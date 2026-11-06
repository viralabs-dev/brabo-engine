defmodule Engine.Workers.TrunkMergedWorkerTest do
  use Engine.DataCase, async: false
  use Oban.Testing, repo: Engine.Repo, prefix: "engine"

  alias Engine.Sessions.FakeEngineApiClient
  alias Engine.Workers.TrunkMergedWorker

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
      Application.delete_env(:engine, :avancar_pasta_fn)
    end)
  end

  defp job(payload),
    do: %Oban.Job{args: %{"event_type" => "project.trunk_merged", "payload" => payload}}

  defp com_resultado(r), do: Application.put_env(:engine, :avancar_pasta_fn, fn _ -> r end)

  test "avanço grava workspace.checkout_advanced na sessão do payload" do
    com_resultado({:avancou, "aaa", "bbb"})

    assert :ok =
             TrunkMergedWorker.perform(
               job(%{"projectId" => "p1", "sessionId" => "s1", "mergedSha" => "bbb"})
             )

    assert_received {:event_appended, "p1", "s1",
                     %{type: "workspace.checkout_advanced", payload: %{from: "aaa", to: "bbb"}}}
  end

  test "recusa grava workspace.checkout_not_advanced com o motivo" do
    com_resultado({:recusado, :dirty_tree, "main"})

    assert :ok =
             TrunkMergedWorker.perform(
               job(%{"projectId" => "p1", "sessionId" => "s1", "mergedSha" => "x"})
             )

    assert_received {:event_appended, "p1", "s1",
                     %{
                       type: "workspace.checkout_not_advanced",
                       payload: %{reason: "dirty_tree", branch: "main"}
                     }}
  end

  test "no-op e em dia não gravam nada" do
    for r <- [:noop, :em_dia] do
      com_resultado(r)
      assert :ok = TrunkMergedWorker.perform(job(%{"projectId" => "p1", "sessionId" => "s1"}))
    end

    refute_received {:event_appended, _, _, _}
  end

  test "container.running reaplica o avanço (RN-1027), sem sessão: sem evento" do
    pai = self()
    Application.put_env(:engine, :avancar_pasta_fn, fn "p1" -> send(pai, :avancou) && :em_dia end)

    assert :ok =
             TrunkMergedWorker.perform(%Oban.Job{
               args: %{"event_type" => "container.running", "payload" => %{"projectId" => "p1"}}
             })

    assert_received :avancou
  end

  test "runner_offline grava o evento com o motivo" do
    com_resultado({:recusado, :runner_offline, nil})

    TrunkMergedWorker.perform(
      job(%{"projectId" => "p1", "sessionId" => "s1", "mergedSha" => "x"})
    )

    assert_received {:event_appended, "p1", "s1",
                     %{
                       type: "workspace.checkout_not_advanced",
                       payload: %{reason: "runner_offline"}
                     }}
  end

  test "reaplicar enfileira um job por projeto, sem empilhar" do
    {:ok, _} = TrunkMergedWorker.reaplicar("p9")
    {:ok, _} = TrunkMergedWorker.reaplicar("p9")
    assert [_] = all_enqueued(worker: TrunkMergedWorker)
  end
end
