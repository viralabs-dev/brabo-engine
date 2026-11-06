defmodule Engine.Workers.TrunkMergedWorker do
  @moduledoc """
  Consumidor de `project.trunk_merged` (RN-1021, AT-617): a api mergeou uma PR
  na `main` do projeto (`settleMerge`), e a pasta do projeto avança até ela por
  `Engine.Dev.WorktreeManager.avancar_pasta/1`. Payload: `{projectId, sessionId, mergedSha}`
  (`sessionId` é a da tarefa mergeada e recebe o evento do resultado).

  Recusa não é falha do job: a pasta é do usuário e fica como está, com um
  evento `workspace.checkout_not_advanced` que nomeia o motivo.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Engine.Dev.WorktreeManager
  alias Engine.Sessions.EngineApiClient

  @impl true
  def perform(%Oban.Job{
        args: %{"event_type" => "project.trunk_merged", "payload" => %{"projectId" => pid} = p}
      })
      when is_binary(pid) do
    avancar = Application.get_env(:engine, :avancar_pasta_fn, &WorktreeManager.avancar_pasta/1)
    pid |> avancar.() |> registrar(pid, p["sessionId"])
    :ok
  end

  def perform(%Oban.Job{}), do: :ok

  defp registrar({:avancou, de, para}, pid, sid),
    do: evento(pid, sid, "workspace.checkout_advanced", %{from: de, to: para})

  defp registrar({:recusado, motivo, branch}, pid, sid) do
    {reason, detalhe} = if is_tuple(motivo), do: motivo, else: {motivo, nil}
    Logger.warning("pasta do projeto #{pid} não avançou: #{reason} #{detalhe}")

    evento(pid, sid, "workspace.checkout_not_advanced", %{
      reason: to_string(reason),
      branch: branch,
      detail: detalhe
    })
  end

  defp registrar(_, _, _), do: :ok

  defp evento(pid, sid, type, payload) when is_binary(sid),
    do:
      EngineApiClient.append_event(pid, sid, %{
        type: type,
        actorKind: "system",
        actorId: "engine",
        payload: payload
      })

  defp evento(_, _, _, _), do: :ok
end
