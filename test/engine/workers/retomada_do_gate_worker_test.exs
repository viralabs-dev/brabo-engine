defmodule Engine.Workers.RetomadaDoGateWorkerTest do
  use Engine.DataCase, async: false
  use Oban.Testing, repo: Engine.Repo, prefix: "engine"

  alias Engine.Workers.RetomadaDoGateWorker

  test "agenda a 1ª, 2ª e 3ª retomada em 1, 3 e 10 min e esgota na 4ª (RN-864)" do
    for {feitas, minutos} <- [{0, 1}, {1, 3}, {2, 10}] do
      assert {:ok, ^minutos} = RetomadaDoGateWorker.agendar("p-1", "t-1", feitas)
    end

    assert :esgotado = RetomadaDoGateWorker.agendar("p-1", "t-1", 3)
    assert_enqueued(worker: RetomadaDoGateWorker, args: %{"taskId" => "t-1", "tentativa" => 3})
  end

  test "perform roda o gate de QA de novo" do
    Application.put_env(:engine, :gate_dispatcher, Engine.Gates.FakeGateDispatcher)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :gate_dispatcher)
      Application.delete_env(:engine, :test_pid)
    end)

    assert :ok = perform_job(RetomadaDoGateWorker, %{"projectId" => "p-1", "taskId" => "t-1"})
    assert_received {:gate_dispatch, :qa, "p-1", "t-1"}
  end
end
