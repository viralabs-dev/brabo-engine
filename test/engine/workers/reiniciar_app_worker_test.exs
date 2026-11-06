defmodule Engine.Workers.ReiniciarAppWorkerTest do
  use Engine.DataCase, async: false
  use Oban.Testing, repo: Engine.Repo, prefix: "engine"

  alias Engine.Sessions.FakeEngineApiClient
  alias Engine.Workers.{ReiniciarAppWorker, TrunkMergedWorker}

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
      Application.delete_env(:engine, :avancar_pasta_fn)
    end)
  end

  defp mergear(resultado, sid \\ "s1") do
    Application.put_env(:engine, :avancar_pasta_fn, fn _ -> resultado end)

    TrunkMergedWorker.perform(%Oban.Job{
      args: %{
        "event_type" => "project.trunk_merged",
        "payload" => %{"projectId" => "p1", "sessionId" => sid, "mergedSha" => "x"}
      }
    })
  end

  defp reiniciar(resposta) do
    Process.put(:fake_app_restart, resposta)
    ReiniciarAppWorker.perform(%Oban.Job{args: %{"projectId" => "p1", "sessionId" => "s1"}})
  end

  test "pasta que avançou agenda o reinício" do
    mergear({:avancou, "a", "b"})
    assert_enqueued(worker: ReiniciarAppWorker, args: %{"projectId" => "p1", "sessionId" => "s1"})
  end

  test "recusa, em dia, noop e merge sem sessão não agendam reinício" do
    for r <- [{:recusado, :dirty_tree, "main"}, :em_dia, :noop], do: mergear(r)
    mergear({:avancou, "a", "b"}, nil)
    refute_enqueued(worker: ReiniciarAppWorker)
  end

  test "dois merges seguidos dão um reinício só" do
    mergear({:avancou, "a", "b"})
    mergear({:avancou, "b", "c"}, "s2")
    assert [_] = all_enqueued(worker: ReiniciarAppWorker)
  end

  test "reinício ok grava app.restarted" do
    assert :ok = reiniciar({:ok, %{"reiniciou" => true}})
    assert_received {:app_restart, "p1"}
    assert_received {:event_appended, "p1", "s1", %{type: "app.restarted"}}
  end

  test "sem_app vira app.restart_skipped" do
    reiniciar({:ok, %{"reiniciou" => false, "motivo" => "sem_app"}})

    assert_received {:event_appended, "p1", "s1",
                     %{type: "app.restart_skipped", payload: %{motivo: "sem_app"}}}
  end

  test "falha leva só motivo e exitCode, nunca texto livre" do
    reiniciar(
      {:ok,
       %{"reiniciou" => false, "motivo" => "app_saiu", "exitCode" => 3, "log" => "JWT_SECRET=x"}}
    )

    assert_received {:event_appended, "p1", "s1", %{type: "app.restart_failed", payload: payload}}

    assert payload == %{motivo: "app_saiu", exitCode: 3}

    reiniciar({:ok, %{"reiniciou" => false, "motivo" => "segredo=abc"}})
    assert_received {:event_appended, _, _, %{payload: %{motivo: "desconhecido"}}}
  end

  test "erro de chamada vira app.restart_failed" do
    reiniciar({:error, :timeout})

    assert_received {:event_appended, "p1", "s1",
                     %{type: "app.restart_failed", payload: %{motivo: "falha_na_chamada"}}}
  end
end
