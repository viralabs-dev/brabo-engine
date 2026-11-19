defmodule Engine.Workers.DesbloqueioPorRedeWorker do
  @moduledoc """
  RN-1419 (AT-995): o container do projeto subiu com a REDE PROVADA
  (`container.running` com `redeProvada: true`) — as tarefas do projeto
  bloqueadas por falta de rede voltam sozinhas, pelo MESMO desbloqueio da
  retomada automática (RN-864, `EngineApiClient.unblock_task/5`, ator `system`),
  com a orientação visível no chat. `redeProvada` ausente vale `false`.

  Só a causa de rede: `blockedOrigin == "infra"` e o motivo casando
  `@motivo_de_rede`. Bloqueio de infra de outra causa (limite de uso, PR
  divergente...) fica para a pessoa.

  Anti-laço (RN-1420): uma retomada por PROVA por tarefa. O job é único pelo
  id do evento (a mesma prova nunca roda duas vezes) e sem retentativa
  (`max_attempts: 1`); a tarefa que voltar a bloquear pela rede só é retomada
  por uma prova NOVA (outro evento).
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: :infinity, keys: [:event_id], states: :all]

  alias Engine.Sessions.EngineApiClient

  require Logger

  @motivo_de_rede ~r/falha passageira de rede|sem rede|EAI_AGAIN|ENOTFOUND|getaddrinfo|npm install/i

  @impl true
  def perform(%Oban.Job{
        args: %{"event_type" => "container.running", "payload" => %{"redeProvada" => true} = p}
      }) do
    project_id = Map.get(p, "projectId")

    with true <- is_binary(project_id),
         {:ok, epicos} when is_list(epicos) <- EngineApiClient.list_backlog(project_id) do
      hora = Calendar.strftime(DateTime.utc_now(), "%H:%M")

      orientacao =
        "a rede do container voltou (provada às #{hora} UTC); parta do último commit do worktree"

      for historia <- Enum.flat_map(epicos, &Map.get(&1, "stories", [])),
          tarefa <- Map.get(historia, "tasks", []),
          sem_rede?(tarefa) do
        EngineApiClient.unblock_task(
          project_id,
          Map.get(historia, "sessionId"),
          Map.get(tarefa, "id"),
          Map.get(tarefa, "assignedTo") || "system",
          orientacao
        )
      end
    else
      outro -> Logger.warning("DesbloqueioPorRede: backlog indisponível: #{inspect(outro)}")
    end

    :ok
  end

  def perform(%Oban.Job{}), do: :ok

  defp sem_rede?(t),
    do:
      Map.get(t, "blocked") == true and Map.get(t, "blockedOrigin") == "infra" and
        is_nil(Map.get(t, "archivedAt")) and
        to_string(Map.get(t, "blockedReason")) =~ @motivo_de_rede and
        not (to_string(Map.get(t, "blockedReason")) =~ ~r/limite de uso/i)
end
