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
  alias Engine.Workers.ReiniciarAppWorker

  @impl true
  def perform(%Oban.Job{
        args: %{"event_type" => "project.trunk_merged", "payload" => %{"projectId" => pid} = p}
      })
      when is_binary(pid) do
    avancar = Application.get_env(:engine, :avancar_pasta_fn, &WorktreeManager.avancar_pasta/1)
    resultado = avancar.(pid)
    registrar(resultado, pid, p["sessionId"])
    # RN-1028: só uma pasta que andou reinicia o app (recusa, em dia e noop não).
    with {:avancou, _, _} <- resultado,
         sid when is_binary(sid) <- p["sessionId"],
         do: ReiniciarAppWorker.agendar(pid, sid)

    :ok
  end

  # RN-1027: o avanço é idempotente, então o runner que entra e o container que
  # chega em `running` reaplicam o MESMO trabalho (sem sessão: sem evento).
  def perform(%Oban.Job{
        args: %{"event_type" => "container.running", "payload" => %{"projectId" => pid}}
      })
      when is_binary(pid),
      do:
        perform(%Oban.Job{
          args: %{"event_type" => "project.trunk_merged", "payload" => %{"projectId" => pid}}
        })

  def perform(%Oban.Job{}), do: :ok

  @doc """
  Reenfileira o avanço de `project_id` (RN-1027), sem sessão. Único por projeto
  enquanto houver um job pendente, para o `join` em rajada não empilhar trabalho.
  """
  def reaplicar(project_id) do
    %{
      event_type: "project.trunk_merged",
      aggregate_id: project_id,
      payload: %{projectId: project_id}
    }
    |> new(unique: [period: 30, keys: [:aggregate_id], states: [:available, :scheduled]])
    |> Oban.insert()
  end

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
