defmodule Engine.Dev.BloqueioContaSoODevTest do
  @moduledoc """
  AT-984 (RN-047/RN-810): o disjuntor do dev só conta bloqueio atribuível a ele.
  """
  use Engine.DataCase, async: false

  alias Engine.Dev.{AgentIo, DevAgentServer, FakeWorktreeManager}
  alias Engine.Gates.FakeGateDispatcher
  alias Engine.Sessions.FakeEngineApiClient

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :worktree_manager, FakeWorktreeManager)
    Application.put_env(:engine, :gate_dispatcher, FakeGateDispatcher)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      for k <- [:engine_api_client, :worktree_manager, :gate_dispatcher, :test_pid],
          do: Application.delete_env(:engine, k)
    end)

    project_id = Ecto.UUID.generate()
    container_running!(project_id)

    {:ok, state} =
      DevAgentServer.init(
        {project_id, "dev-api", "api", Ecto.UUID.generate(), nil, nil, nil, nil}
      )

    Process.put(:fake_tasks, [])

    %{state: %{state | max_consecutive_blocked: 3, task_id: "t1", status: :awaiting_gate}}
  end

  defp resolve(state, ev),
    do:
      DevAgentServer.handle_info(
        {:gate_resolved, Map.merge(%{task_id: "t1", next_action: "blocked"}, ev)},
        state
      )

  test "conta_no_disjuntor?/2" do
    refute AgentIo.conta_no_disjuntor?("infra", "qa-lead")
    refute AgentIo.conta_no_disjuntor?("infra", nil)
    refute AgentIo.conta_no_disjuntor?("modelo", "qa-lead")
    refute AgentIo.conta_no_disjuntor?("codigo", "secops-lead")
    assert AgentIo.conta_no_disjuntor?("politica", "qa-agent")
    assert AgentIo.conta_no_disjuntor?("politica", "qa-lead")
    assert AgentIo.conta_no_disjuntor?(nil, nil)
    assert AgentIo.conta_no_disjuntor?("modelo", "dev-api")
  end

  test "gate_resolved bloqueado por infra do qa-lead não conta; payload antigo conta", %{
    state: state
  } do
    {:noreply, a} = resolve(state, %{origin: "infra", blocked_by: "qa-lead"})
    assert a.consecutive_blocked == 0

    {:noreply, b} = resolve(state, %{origin: "politica", blocked_by: "qa-agent"})
    assert b.consecutive_blocked == 1

    {:noreply, c} = resolve(state, %{})
    assert c.consecutive_blocked == 1
  end

  test "block_task com origem infra + finish_task(:blocked) não conta; modelo conta", %{
    state: state
  } do
    a = state |> AgentIo.block_task("x", "y", "infra") |> AgentIo.finish_task(:blocked, &run/2)
    assert a.consecutive_blocked == 0

    b = state |> AgentIo.block_task("x", "y", "modelo") |> AgentIo.finish_task(:blocked, &run/2)
    assert b.consecutive_blocked == 1
  end

  defp run(state, _task), do: state

  defp bloqueia(state, args) do
    Process.put(:fake_tasks, [%{"id" => "t1", "title" => "T"}])

    Process.put(:fake_dev_context, %{
      "task" => %{"id" => "t1", "title" => "x", "description" => ""},
      "story" => %{
        "id" => "s",
        "title" => "x",
        "description" => "",
        "rf" => [],
        "rnf" => [],
        "dod" => [],
        "dor" => []
      },
      "businessRules" => [],
      "adrs" => []
    })

    Process.put(
      :fake_llm_turns,
      [
        FakeEngineApiClient.tool_call_response(
          "report_blocked",
          Map.merge(%{"reason" => "r", "diagnosis" => "d"}, args)
        )
      ]
    )

    {:noreply, novo} = DevAgentServer.handle_cast(:work, %{state | task_id: nil, status: :idle})
    novo
  end

  test "report_blocked com causa depende_de_outra_tarefa avisa o Dev Lead e não conta", %{
    state: state
  } do
    :ok = Engine.Dev.Wake.subscribe(state.project_id, "dev-lead")
    novo = bloqueia(state, %{"causa" => "depende_de_outra_tarefa"})
    assert_received {:tarefa_bloqueada, %{task_id: "t1"}}
    assert novo.consecutive_blocked == 0
  end

  test "report_blocked sem causa conta como antes", %{state: state} do
    assert bloqueia(state, %{}).consecutive_blocked == 1
  end

  defmodule FakeArquiteto do
    use GenServer

    def start_link({sid, test_pid}),
      do: GenServer.start_link(__MODULE__, test_pid, name: Engine.Agents.ArquitetoServer.via(sid))

    def init(test_pid), do: {:ok, test_pid}

    def handle_call({:user_message, texto, _, _}, _from, test_pid) do
      send(test_pid, {:arquiteto_recebeu, texto})
      {:reply, :ok, test_pid}
    end
  end

  test "report_blocked com precisa_de arquiteto entrega o pedido ao Arquiteto e avisa o Dev Lead (AT-981 C2)",
       %{state: state} do
    start_supervised!({FakeArquiteto, {state.session_id, self()}})
    :ok = Engine.Dev.Wake.subscribe(state.project_id, "dev-lead")

    bloqueia(state, %{"causa" => "depende_de_outra_tarefa", "precisa_de" => "arquiteto"})

    assert_received {:arquiteto_recebeu, "[Pedido do Dev Lead] " <> pedido}
    assert pedido =~ "t1"
    assert_received {:tarefa_bloqueada, %{pedido_ao_arquiteto: true}}
  end

  test "sem precisa_de o Arquiteto não recebe nada", %{state: state} do
    start_supervised!({FakeArquiteto, {state.session_id, self()}})
    :ok = Engine.Dev.Wake.subscribe(state.project_id, "dev-lead")
    bloqueia(state, %{})
    refute_received {:arquiteto_recebeu, _}
    assert_received {:tarefa_bloqueada, %{pedido_ao_arquiteto: false}}
  end
end
