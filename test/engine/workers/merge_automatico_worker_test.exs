defmodule Engine.Workers.MergeAutomaticoWorkerTest do
  use Engine.DataCase, async: false

  alias Engine.Sessions.FakeEngineApiClient
  alias Engine.Workers.MergeAutomaticoWorker

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
    end)
  end

  defp rodar(resposta, attempt \\ 1) do
    Process.put(:fake_merge_automatico, resposta)

    MergeAutomaticoWorker.perform(%Oban.Job{
      attempt: attempt,
      max_attempts: 5,
      args: %{
        "event_type" => "task.gate_resolved",
        "payload" => %{"projectId" => "p1", "sessionId" => "s1", "taskId" => "t1"}
      }
    })
  end

  test "repassa projeto, sessão e tarefa e não grava nada quando a proposta passa" do
    assert :ok = rodar({:ok, %{"status" => "executed"}})
    assert_received {:merge_automatico, "p1", "s1", "t1"}
    refute_received {:event_appended, _, _, _}
  end

  test "recusa normal (chave desligada e afins) é :ok sem evento" do
    for code <- ~w(chave_desligada gate_pendente pr_ja_mergeado merge_ja_proposto) do
      assert :ok = rodar({:error, {409, %{"code" => code}}})
    end

    refute_received {:event_appended, _, _, _}
  end

  test "sem_pr vira evento nomeado, sem retry" do
    assert :ok = rodar({:error, {409, %{"code" => "sem_pr"}}})

    assert_received {:event_appended, "p1", "s1",
                     %{
                       type: "merge_automatico.recusado",
                       payload: %{origem: "politica", motivo: "sem_pr"}
                     }}
  end

  test "merge failed por conflito grava origem codigo com os arquivos" do
    acao = %{"status" => "failed", "executionResult" => %{"conflictingFiles" => ["a.ts"]}}
    assert :ok = rodar({:ok, acao})

    assert_received {:event_appended, _, _,
                     %{
                       type: "merge_automatico.falhou",
                       payload: %{origem: "codigo", motivo: "conflito de merge em a.ts"}
                     }}
  end

  test "merge failed do provider grava origem infra com o erro" do
    acao = %{"status" => "failed", "executionResult" => %{"error" => "branch protegida"}}
    assert :ok = rodar({:ok, acao})

    assert_received {:event_appended, _, _,
                     %{payload: %{origem: "infra", motivo: "branch protegida"}}}
  end

  test "5xx tenta de novo; na última tentativa grava evento infra sem o corpo" do
    assert {:error, _} = rodar({:error, {503, %{"segredo" => "x"}}})
    refute_received {:event_appended, _, _, _}

    assert :ok = rodar({:error, {503, %{"segredo" => "x"}}}, 5)

    assert_received {:event_appended, _, _,
                     %{
                       type: "merge_automatico.falhou",
                       payload: %{origem: "infra", motivo: "a api respondeu 503"}
                     }}
  end

  test "outro 4xx grava evento na hora" do
    assert :ok = rodar({:error, {404, %{}}})
    assert_received {:event_appended, _, _, %{type: "merge_automatico.falhou"}}
  end
end
