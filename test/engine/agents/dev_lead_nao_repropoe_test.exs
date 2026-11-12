defmodule Engine.Agents.DevLeadNaoRepropoeTest do
  @moduledoc "AT-910 (RN-1130, RN-1131): com a execução ativa o plano é só das restantes."
  use Engine.DataCase, async: false

  alias Engine.Agents.DevLeadTools
  alias Engine.Dev.DevAgentState
  alias Engine.Sessions.FakeEngineApiClient

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
    end)

    state = %{project_id: Ecto.UUID.generate(), session_id: "s1"}

    Process.put(:fake_backlog, [
      %{
        "stories" => [
          %{
            "title" => "H",
            "moduleIds" => ["api"],
            "tasks" => [
              %{
                "id" => "11111111-aaaa",
                "title" => "Feita",
                "status" => "done",
                "module" => "api"
              },
              %{"id" => "22222222-aaaa", "title" => "Nova 1", "status" => "todo"},
              %{"id" => "33333333-aaaa", "title" => "Nova 2", "status" => "todo"}
            ]
          }
        ]
      }
    ])

    %{state: state}
  end

  defp ativar(state) do
    DevAgentState.upsert!(%{
      project_id: state.project_id,
      agent_id: "dev-api",
      module: "api",
      session_id: "s1",
      status: "working"
    })
  end

  defp plano(tarefas) do
    %{
      "modulos" => [%{"modulo" => "api", "agentes" => 1, "porque" => "x"}],
      "resumo" => "tudo",
      "tarefas" => tarefas
    }
  end

  test "execução ativa e tudo feito: recusa sem propor", %{state: state} do
    ativar(state)

    assert {:error, msg} =
             DevLeadTools.run(plano([%{"taskId" => "11111111-aaaa", "modulo" => "api"}]), state)

    assert msg =~ "NÃO reproponha"
    refute_received {:propose_action, _, _, _}
  end

  test "execução ativa: propõe só as 2 novas", %{state: state} do
    ativar(state)

    tarefas =
      for id <- ["11111111-aaaa", "22222222-aaaa", "33333333-aaaa"],
          do: %{"taskId" => id, "modulo" => "api"}

    assert {:ok, _} = DevLeadTools.run(plano(tarefas), state)
    assert_received {:propose_action, "propose_execution_plan", _, payload}
    assert Enum.map(payload.tarefas, & &1["taskId"]) == ["22222222-aaaa", "33333333-aaaa"]
    assert payload.resumo =~ "plano das tarefas restantes (2)"
  end

  test "sem execução ativa o plano segue inteiro", %{state: state} do
    tarefas = [%{"taskId" => "11111111-aaaa", "modulo" => "api"}]
    assert {:ok, _} = DevLeadTools.run(plano(tarefas), state)
    assert_received {:propose_action, _, _, %{tarefas: [_]}}
  end

  test "o backlog lido mostra o módulo ENTREGUE", %{state: state} do
    texto = DevLeadTools.tarefas_do_backlog(state.project_id)
    assert texto =~ "ENTREGUE: módulo api (1 tarefa(s) done, na main)"
  end
end
