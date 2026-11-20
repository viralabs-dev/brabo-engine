defmodule Engine.Workers.ReiniciarAppWorker do
  @moduledoc """
  RN-1028 (AT-617): depois que a pasta do projeto avançou até a `main`, o processo
  do app declarado (`run.app`) é reiniciado no lugar pela api. O job é único por
  projeto e atrasado (`@atraso_s`), então merges em sequência viram UM reinício,
  feito com a pasta já na última `main`.

  O desfecho vai para a linha do tempo da sessão que agendou, sem trecho de log
  (o comando do app pode carregar segredo): `app.restarted`, `app.restart_failed`
  ou `app.restart_skipped`. Falha só avisa; a pasta nunca volta.

  AT-914 (RN-1089): a falha também acorda o Dev Lead (`{:app_falhou, ...}`) com motivo,
  código de saída e o caminho do log no container (`@log_no_container`); o TEXTO do log
  nunca entra no evento nem no aviso.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Engine.Sessions.EngineApiClient

  @atraso_s 20

  @doc "Agenda o reinício de `project_id`; já agendado dentro da janela, não duplica."
  def agendar(project_id, session_id) do
    %{"projectId" => project_id, "sessionId" => session_id}
    |> new(
      schedule_in: @atraso_s,
      unique: [period: 60, keys: [:projectId], states: [:available, :scheduled]]
    )
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"projectId" => pid, "sessionId" => sid}}) do
    case EngineApiClient.reiniciar_app(pid) do
      {:ok, %{"reiniciou" => true}} ->
        evento(pid, sid, "app.restarted", %{})

      {:ok, %{"reiniciou" => false, "motivo" => "sem_app"}} ->
        evento(pid, sid, "app.restart_skipped", %{motivo: "sem_app"})

      # AT-985 (RN-1334): o módulo que o comando do app cita ainda não entregou nada.
      {:ok, %{"reiniciou" => false, "motivo" => "alvo_pendente"}} ->
        evento(pid, sid, "app.restart_skipped", %{motivo: "alvo_pendente"})

      {:ok, %{"reiniciou" => false} = r} ->
        falhou(pid, sid, falha(r))

      {:error, _} ->
        falhou(pid, sid, %{motivo: "falha_na_chamada"})
    end

    :ok
  end

  @motivos ~w(sem_container tempo_esgotado falha_no_exec app_saiu)

  # Allowlist: só motivo conhecido e exitCode saem; nenhum texto livre da resposta.
  defp falha(r) do
    %{motivo: if(r["motivo"] in @motivos, do: r["motivo"], else: "desconhecido")}
    |> then(&if is_integer(r["exitCode"]), do: Map.put(&1, :exitCode, r["exitCode"]), else: &1)
  end

  @log_no_container "/tmp/brabo-app.log"

  # AT-985 (RN-1334): a mesma falha (motivo e exitCode) logo depois da anterior grava o
  # evento mas não acorda o Dev Lead de novo; um `app.restarted` no meio rearma o aviso.
  defp falhou(pid, sid, info) do
    repetida = repetida?(pid, sid, info)
    evento(pid, sid, "app.restart_failed", Map.put(info, :log, @log_no_container))
    unless repetida, do: Engine.Dev.Wake.deliver(pid, "dev-lead", {:app_falhou, info})
  end

  defp repetida?(pid, sid, info) do
    case EngineApiClient.list_events(pid, sid,
           latest: true,
           limit: 1,
           types: ["app.restarted", "app.restart_failed"]
         ) do
      {:ok, [%{"type" => "app.restart_failed", "payload" => p}]} ->
        p["motivo"] == info.motivo and p["exitCode"] == Map.get(info, :exitCode)

      _ ->
        false
    end
  end

  defp evento(pid, sid, type, payload) do
    EngineApiClient.append_event(pid, sid, %{
      type: type,
      actorKind: "system",
      actorId: "engine",
      payload: payload
    })
  end
end
