defmodule Engine.Workers.ExecucaoParadaWorkerTest do
  @moduledoc "AT-800 (RN-1059): a execução parada atrás de bloqueio ou disjuntor avisa a sessão."
  use Engine.DataCase, async: false

  alias Engine.Dev.{DevAgentState, Wake}
  alias Engine.Sessions.FakeEngineApiClient
  alias Engine.Workers.ExecucaoParadaWorker

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
    end)

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

    Wake.subscribe(project_id, "dev-lead")
    %{p: project_id, s: session_id}
  end

  defp agente!(p, s, id, status) do
    DevAgentState.upsert!(%{
      project_id: p,
      agent_id: id,
      module: String.replace_prefix(id, "dev-", ""),
      session_id: s,
      status: status
    })
  end

  defp tarefa(id, extra \\ %{}),
    do:
      Map.merge(
        %{"id" => id, "title" => "t #{id}", "status" => "todo", "module" => "catalogo"},
        extra
      )

  defp backlog(tarefas), do: [%{"id" => "ep", "stories" => [%{"id" => "st", "tasks" => tarefas}]}]

  defp evento!(s, seq, type, payload) do
    Engine.Repo.insert_all("session_events", [
      %{
        id: "evt-#{System.unique_integer([:positive])}",
        session_id: Ecto.UUID.dump!(s),
        seq: seq,
        type: type,
        actor_kind: "system",
        actor_id: "execucao",
        payload: payload,
        created_at: DateTime.add(DateTime.utc_now(), seq, :millisecond)
      }
    ])
  end

  defp rodar(p, s),
    do: ExecucaoParadaWorker.perform(%Oban.Job{args: %{"projectId" => p, "sessionId" => s}})

  # O cenário do TP-01 27ª: 4 idle, 1 idle_tripped, 3 bloqueadas do catálogo e 7 pendentes.
  defp cenario_tp01(p, s) do
    for a <- ~w(dev-auth dev-api-http dev-agenda dev-config), do: agente!(p, s, a, "idle")
    agente!(p, s, "dev-catalogo", "idle_tripped")

    bloqueadas =
      for id <- ~w(f9c6c48f ad157be7 d5df00dd),
          do: tarefa(id, %{"blocked" => true, "blockedReason" => "conflito ao integrar a main"})

    Process.put(:fake_backlog, backlog(bloqueadas ++ for(n <- 1..7, do: tarefa("t#{n}"))))
  end

  test "o cenário do TP-01: grava execution.stalled e acorda o Dev Lead", %{p: p, s: s} do
    cenario_tp01(p, s)
    assert :ok = rodar(p, s)

    assert_received {:event_appended, ^p, ^s,
                     %{type: "execution.stalled", actorKind: "system", payload: payload}}

    assert [%{agentId: "dev-catalogo", module: "catalogo"}] = payload.agentesTravados
    assert Enum.map(payload.tarefasBloqueadas, & &1.taskId) == ~w(f9c6c48f ad157be7 d5df00dd)
    assert payload.tarefasPendentes == 10
    assert length(payload.agentesOciosos) == 4
    assert_received {:execucao_parada, ^payload}
  end

  test "agente trabalhando: nada é gravado", %{p: p, s: s} do
    cenario_tp01(p, s)
    agente!(p, s, "dev-auth", "working")
    assert :ok = rodar(p, s)
    refute_received {:event_appended, _, _, _}
    refute_received {:execucao_parada, _}
  end

  test "nada pendente: nada é gravado", %{p: p, s: s} do
    cenario_tp01(p, s)
    Process.put(:fake_backlog, backlog([tarefa("a", %{"status" => "done"})]))
    assert :ok = rodar(p, s)
    refute_received {:event_appended, _, _, _}
  end

  test "só PR esperando merge, sem bloqueio nem disjuntor: nada (AT-810)", %{p: p, s: s} do
    agente!(p, s, "dev-auth", "idle")
    Process.put(:fake_backlog, backlog([tarefa("a", %{"status" => "in_review"})]))
    assert :ok = rodar(p, s)
    refute_received {:event_appended, _, _, _}
  end

  test "não repete sem mudança; depois de dev.working grava de novo", %{p: p, s: s} do
    cenario_tp01(p, s)

    evento!(s, 1, "execution.stalled", %{
      "tarefasBloqueadas" => for(id <- ~w(f9c6c48f ad157be7 d5df00dd), do: %{"taskId" => id}),
      "agentesTravados" => [%{"agentId" => "dev-catalogo"}]
    })

    assert :ok = rodar(p, s)
    refute_received {:event_appended, _, _, _}

    evento!(s, 2, "dev.working", %{})
    assert :ok = rodar(p, s)
    assert_received {:event_appended, ^p, ^s, %{type: "execution.stalled"}}
  end
end
