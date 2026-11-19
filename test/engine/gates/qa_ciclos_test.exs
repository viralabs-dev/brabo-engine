defmodule Engine.Gates.QaCiclosTest.CicloFalso do
  @moduledoc false
  # Um ciclo que avisa o teste que começou e só termina quando mandarem.
  def start_link({project_id, task_id, _feitas, ciclos}) do
    teste = Application.fetch_env!(:engine, :qa_ciclos_teste_pid)

    {:ok,
     spawn_link(fn ->
       send(teste, {:iniciou, project_id, task_id, System.monotonic_time(:millisecond)})

       receive do
         :terminar -> send(ciclos, {:ciclo_terminado, task_id, nil})
       end
     end)}
  end
end

defmodule Engine.Gates.QaCiclosTest do
  # Chaves de Application: não pode ser async.
  use ExUnit.Case, async: false

  alias Engine.Gates.{QaCiclos, QaLeadServer}
  alias Engine.Gates.QaCiclosTest.CicloFalso

  setup do
    project_id = "proj-ciclos-#{System.unique_integer([:positive])}"
    Application.put_env(:engine, :qa_ciclos_teste_pid, self())
    Application.put_env(:engine, :qa_ciclo_server, CicloFalso)
    Application.put_env(:engine, :qa_ciclos_por_projeto, 2)

    on_exit(fn ->
      Enum.each(
        [:qa_ciclos_teste_pid, :qa_ciclo_server, :qa_ciclos_por_projeto],
        &Application.delete_env(:engine, &1)
      )
    end)

    {:ok, router} = QaCiclos.start_link(project_id)
    %{project_id: project_id, router: router}
  end

  test "duas tasks do mesmo projeto abrem dois ciclos ao mesmo tempo (RN-1401)", %{
    project_id: p,
    router: router
  } do
    QaLeadServer.run(p, "t1")
    QaLeadServer.run(p, "t2")

    # os dois COMEÇARAM sem nenhum ter terminado
    assert_receive {:iniciou, ^p, "t1", _}, 1_000
    assert_receive {:iniciou, ^p, "t2", _}, 1_000
    assert GenServer.call(router, {:em_voo?, "t1"})
    assert GenServer.call(router, {:em_voo?, "t2"})
  end

  test "a N+1ª task espera uma vaga (RN-1402)", %{project_id: p, router: router} do
    for t <- ~w(t1 t2 t3), do: QaLeadServer.run(p, t)

    assert_receive {:iniciou, ^p, "t1", _}, 1_000
    assert_receive {:iniciou, ^p, "t2", _}, 1_000
    refute_receive {:iniciou, ^p, "t3", _}, 200
    assert GenServer.call(router, {:em_voo?, "t3"}), "na fila conta como em voo"

    %{ciclos: ciclos} = :sys.get_state(router)
    send(ciclos["t1"].pid, :terminar)

    assert_receive {:iniciou, ^p, "t3", _}, 1_000
  end

  test "pedido repetido de task em voo não abre outro ciclo", %{project_id: p} do
    QaLeadServer.run(p, "t1")
    QaLeadServer.run(p, "t1")
    assert_receive {:iniciou, ^p, "t1", _}, 1_000
    refute_receive {:iniciou, ^p, "t1", _}, 200
  end

  test "o teto sem configuração é o número de dev agents ativos, no mínimo 1" do
    Application.delete_env(:engine, :qa_ciclos_por_projeto)
    assert QaCiclos.teto("projeto-sem-devs") == 1
  end
end
