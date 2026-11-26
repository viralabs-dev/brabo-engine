defmodule Engine.Agents.DevLeadToolsLerPlanoTest do
  @moduledoc """
  RN-1505 (AT-1018): `ler_plano` dá execução ativa quando há dev agent do projeto, mesmo
  sem `execution.activated` na sessão do Dev Lead (o evento mora na sessão de execução).
  """
  use Engine.DataCase, async: false

  alias Engine.Agents.DevLeadTools
  alias Engine.Dev.DevAgentState
  alias Engine.Sessions.FakeEngineApiClient

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    on_exit(fn -> Application.delete_env(:engine, :engine_api_client) end)
  end

  test "só proposed_action.approved na sessão, com dev agent no projeto: ativa sim" do
    project_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    agora = DateTime.utc_now() |> DateTime.truncate(:second)

    Engine.Repo.insert_all("projects", [
      %{
        id: Ecto.UUID.dump!(project_id),
        name: "cobaia",
        slug: "cobaia-#{System.unique_integer([:positive])}",
        created_at: agora,
        updated_at: agora
      }
    ])

    Engine.Repo.insert_all("sessions", [
      %{
        id: Ecto.UUID.dump!(session_id),
        project_id: Ecto.UUID.dump!(project_id),
        created_at: agora
      }
    ])

    Process.put(:fake_events, [
      %{
        "type" => "proposed_action.created",
        "payload" => %{"actionType" => "propose_execution_plan", "actionId" => "p1"}
      },
      %{"type" => "proposed_action.approved", "payload" => %{"actionId" => "p1"}}
    ])

    ctx = %{project_id: project_id, session_id: session_id}
    assert {:ok, "plano: aprovado; execucao ativa: nao."} = DevLeadTools.run_ler_plano(%{}, ctx)

    DevAgentState.upsert!(%{
      project_id: project_id,
      agent_id: "dev-api",
      module: "api",
      session_id: Ecto.UUID.generate(),
      task_id: Ecto.UUID.generate(),
      worktree_path: System.tmp_dir!(),
      status: "idle"
    })

    assert {:ok, "plano: aprovado; execucao ativa: sim."} = DevLeadTools.run_ler_plano(%{}, ctx)
  end
end
