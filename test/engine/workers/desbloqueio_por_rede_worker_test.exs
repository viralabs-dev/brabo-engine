defmodule Engine.Workers.DesbloqueioPorRedeWorkerTest do
  # RN-1419/RN-1420 (AT-995)
  use Engine.DataCase, async: false
  use Oban.Testing, repo: Engine.Repo, prefix: "engine"

  alias Engine.Sessions.FakeEngineApiClient
  alias Engine.Workers.DesbloqueioPorRedeWorker

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
    end)
  end

  defp tarefa(id, origem, motivo),
    do: %{
      "id" => id,
      "blocked" => true,
      "blockedOrigin" => origem,
      "blockedReason" => motivo,
      "assignedTo" => "dev-api"
    }

  defp backlog do
    Process.put(
      :fake_backlog,
      [
        %{
          "stories" => [
            %{
              "sessionId" => "s1",
              "tasks" => [
                tarefa("rede1", "infra", "falha passageira de rede — desbloqueie à mão"),
                tarefa("rede2", "infra", "npm install: getaddrinfo EAI_AGAIN"),
                tarefa("limite", "infra", "falha passageira de limite de uso do modelo"),
                tarefa("qa", "codigo", "parecer de QA reprovou, sem rede para o teste"),
                %{"id" => "livre", "blocked" => false}
              ]
            }
          ]
        }
      ]
    )
  end

  defp job(payload, id \\ "ev1"),
    do: %Oban.Job{
      args: %{"event_type" => "container.running", "event_id" => id, "payload" => payload}
    }

  test "rede provada retoma só as tarefas bloqueadas por rede, com a orientação" do
    backlog()

    assert :ok =
             DesbloqueioPorRedeWorker.perform(job(%{"projectId" => "p", "redeProvada" => true}))

    assert_received {:task_unblocked, "rede1", "dev-api"}
    assert_received {:task_unblocked_orientacao, "rede1", orientacao}
    assert orientacao =~ "a rede do container voltou"
    assert_received {:task_unblocked, "rede2", "dev-api"}
    refute_received {:task_unblocked, "limite", _}
    refute_received {:task_unblocked, "qa", _}
    refute_received {:task_unblocked, "livre", _}
  end

  test "redeProvada false ou ausente não retoma nada" do
    backlog()

    assert :ok =
             DesbloqueioPorRedeWorker.perform(job(%{"projectId" => "p", "redeProvada" => false}))

    assert :ok = DesbloqueioPorRedeWorker.perform(job(%{"projectId" => "p"}))
    refute_received {:task_unblocked, _, _}
  end

  test "a mesma prova (mesmo evento) não gera dois jobs" do
    args = %{event_type: "container.running", event_id: "ev9", payload: %{}}
    {:ok, a} = args |> DesbloqueioPorRedeWorker.new() |> Oban.insert()
    {:ok, b} = args |> DesbloqueioPorRedeWorker.new() |> Oban.insert()
    assert a.id == b.id

    {:ok, c} = %{args | event_id: "ev10"} |> DesbloqueioPorRedeWorker.new() |> Oban.insert()
    refute c.id == a.id
  end
end
