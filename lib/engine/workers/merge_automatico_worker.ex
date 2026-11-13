defmodule Engine.Workers.MergeAutomaticoWorker do
  @moduledoc """
  RN-1320 (AT-902): consumidor de `task.gate_resolved` que aciona o merge
  automático da PR da tarefa (`POST /internal/projects/:projectId/tasks/:taskId/auto-merge`).

  O engine NÃO decide merge: chave, gates, PR e duplicidade são conferidos na
  api (RN-1316). O worker repassa `projectId`, `sessionId` e `taskId` e trata o
  desfecho, sempre com origem nomeada (RN-059), nunca por eliminação:

  - 409 `chave_desligada`, `gate_pendente`, `pr_ja_mergeado`, `merge_ja_proposto`:
    caminho normal, `:ok` só com log (o gate seguinte reemite o evento).
  - 409 `sem_pr` ou código desconhecido: evento `merge_automatico.recusado`
    (origem `politica`), sem retry.
  - 200 com a proposta `failed` (conflito, proteção do provider ou infra): evento
    `merge_automatico.falhou` com o motivo; o conflito acorda o dev pelo caminho
    da RN-715 e o resto vira clique manual.
  - 5xx, timeout ou queda: retry do Oban; esgotadas as tentativas, evento
    `merge_automatico.falhou` com origem `infra`. Outro 4xx: evento na hora.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  require Logger

  alias Engine.Sessions.EngineApiClient

  @normais ~w(chave_desligada gate_pendente pr_ja_mergeado merge_ja_proposto)

  @impl true
  def perform(%Oban.Job{
        args: %{
          "event_type" => "task.gate_resolved",
          "payload" => %{"projectId" => pid, "sessionId" => sid, "taskId" => tid}
        },
        attempt: attempt,
        max_attempts: max
      })
      when is_binary(pid) and is_binary(sid) and is_binary(tid) do
    case EngineApiClient.acionar_merge_automatico(pid, sid, tid) do
      {:ok, %{"status" => "failed"} = acao} ->
        {origem, detalhe} = motivo(acao)
        evento(pid, sid, "merge_automatico.falhou", tid, origem, detalhe)

      {:ok, _} ->
        :ok

      {:error, {409, %{"code" => code}}} when code in @normais ->
        Logger.info("merge automático não acionado (#{code}) na tarefa #{tid}")

      {:error, {409, corpo}} ->
        evento(pid, sid, "merge_automatico.recusado", tid, "politica", recusa(corpo))

      {:error, {status, _}} when status in 400..499 ->
        evento(pid, sid, "merge_automatico.falhou", tid, "infra", "a api respondeu #{status}")

      {:error, erro} when attempt >= max ->
        evento(pid, sid, "merge_automatico.falhou", tid, "infra", falha(erro))

      {:error, erro} ->
        {:error, falha(erro)}
    end
  end

  def perform(%Oban.Job{}), do: :ok

  # Conflito é do código (a api o nomeia com os arquivos); o resto é do provider.
  defp motivo(%{"executionResult" => %{"conflictingFiles" => [_ | _] = f}}),
    do: {"codigo", "conflito de merge em #{Enum.join(f, ", ")}"}

  defp motivo(%{"executionResult" => %{"error" => e}}) when is_binary(e),
    do: {"infra", String.slice(e, 0, 300)}

  defp motivo(_), do: {"infra", "o provider recusou o merge"}

  defp recusa(%{"code" => c}) when is_binary(c), do: c
  defp recusa(_), do: "recusa sem código"

  # Só o status ou a classe do erro: o corpo pode carregar dado que não vai para o fio.
  defp falha({status, _}) when is_integer(status), do: "a api respondeu #{status}"
  defp falha(erro) when is_atom(erro), do: "falha de rede (#{erro})"
  defp falha(_), do: "falha de rede ao acionar a api"

  defp evento(pid, sid, type, tid, origem, detalhe) do
    Logger.warning("#{type} na tarefa #{tid}: #{detalhe}")

    EngineApiClient.append_event(pid, sid, %{
      type: type,
      actorKind: "system",
      actorId: "engine",
      payload: %{taskId: tid, origem: origem, motivo: detalhe}
    })

    :ok
  end
end
