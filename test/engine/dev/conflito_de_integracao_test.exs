defmodule Engine.Dev.GitRealWorktreeManager do
  @moduledoc false
  # O WorktreeManager real sem a resolução do projeto via banco: o `work_dir`
  # vem do env do teste e o git é o de verdade.
  alias Engine.Dev.WorktreeManager

  def create_from(_project_id, agent_id, slug, base),
    do:
      WorktreeManager.add_worktree(
        Application.fetch_env!(:engine, :conflito_work_dir),
        agent_id,
        slug,
        base
      )

  def preservar(_project_id, path, agent_id, task_id),
    do: WorktreeManager.preservar_em(path, agent_id, task_id)

  def sem_diff_contra_a_dev?(path, _project_id), do: WorktreeManager.sem_diff_contra_a_dev?(path)
  defdelegate conflito_nao_resolvido?(path, arquivos), to: WorktreeManager
  defdelegate abortar_merge_em_curso(path), to: WorktreeManager
end

defmodule Engine.Dev.ConflitoDeIntegracaoTest do
  @moduledoc """
  RN-1010 (AT-747): o conflito da `main` integrada no claim vai ao agente. Git
  REAL num diretório temporário; LLM e api scriptados (mesmo idioma de
  `dev_agent_chain_test.exs`, com `handle_cast` chamado no processo do teste).
  """

  use Engine.DataCase, async: false

  alias Engine.Dev.{DevAgentServer, WorktreeManager}
  alias Engine.Sessions.FakeEngineApiClient

  setup do
    root =
      Path.join(System.tmp_dir!(), "brabo-conflito-#{System.unique_integer([:positive])}")

    project_id = Ecto.UUID.generate()
    work_dir = Path.join(root, project_id)
    File.mkdir_p!(work_dir)

    git(work_dir, ["init"])
    git(work_dir, ["config", "user.email", "t@brabo.dev"])
    git(work_dir, ["config", "user.name", "t"])
    File.write!(Path.join(work_dir, "README.md"), "x")
    git(work_dir, ["add", "-A"])
    git(work_dir, ["commit", "-m", "init"])

    bare = Path.join(root, "origem.git")
    git(root, ["init", "--bare", "origem.git"])
    git(work_dir, ["remote", "add", "origin", bare])
    git(work_dir, ["checkout", "-b", "main"])
    git(work_dir, ["push", "origin", "main"])

    # A task anterior mexeu no README; depois a dev andou no mesmo arquivo.
    {:ok, %{path: p, branch: anterior}} =
      WorktreeManager.add_worktree(work_dir, "dev-api", "task-aaaa1111", "main")

    File.write!(Path.join(p, "README.md"), "da task")
    {:ok, _} = WorktreeManager.preservar_em(p, "dev-api", "task-aaaa1111")

    outro = Path.join(root, "outro")
    git(root, ["clone", "-b", "main", bare, "outro"])
    git(outro, ["config", "user.email", "t@brabo.dev"])
    git(outro, ["config", "user.name", "t"])
    File.write!(Path.join(outro, "README.md"), "da main")
    git(outro, ["add", "-A"])
    git(outro, ["commit", "-m", "outra PR"])
    git(outro, ["push", "origin", "main"])
    git(work_dir, ["fetch", "origin"])

    Application.put_env(:engine, :project_workspaces_root, root)
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :worktree_manager, Engine.Dev.GitRealWorktreeManager)
    Application.put_env(:engine, :conflito_work_dir, work_dir)
    Application.put_env(:engine, :gate_dispatcher, Engine.Gates.FakeGateDispatcher)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      for k <- [
            :project_workspaces_root,
            :worktree_manager,
            :conflito_work_dir,
            :engine_api_client,
            :gate_dispatcher,
            :test_pid
          ],
          do: Application.delete_env(:engine, k)

      File.rm_rf!(root)
    end)

    container_running!(project_id)
    session_id = Ecto.UUID.generate()

    {:ok, state} =
      DevAgentServer.init({project_id, "dev-api", "api", session_id, nil, nil, 3, nil})

    task_id = "bbbb2222-0000-4000-8000-000000000000"
    Process.put(:fake_tasks, [%{"id" => task_id, "title" => "Dois"}])

    Process.put(:fake_dev_context, %{
      "task" => %{"id" => "x", "title" => "x", "description" => ""},
      "story" => %{
        "id" => "st-1",
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

    # Faz o `terminal` do agente rodar de verdade no worktree.
    Process.put(:fake_propose_hook, fn
      "terminal", %{command: cmd, cwd: cwd} -> System.cmd("sh", ["-c", cmd], cd: cwd)
      _, _ -> :ok
    end)

    Process.put(:fake_propose_action, %{
      "id" => "pa-1",
      "status" => "executed",
      "executionResult" => %{"exitCode" => 0, "stdout" => "ok"}
    })

    %{state: Map.put(state, :base_preservada, anterior), work_dir: work_dir}
  end

  defp git(cd, args), do: {_, 0} = System.cmd("git", args, cd: cd, stderr_to_stdout: true)

  test "o agente resolve e conclui o merge: chega a awaiting_gate, sem bloqueio",
       %{state: state} do
    Process.put(:fake_llm_turns, [
      FakeEngineApiClient.tool_call_response("terminal", %{
        "command" =>
          "printf resolvido > README.md && git add README.md && " <>
            "git -c user.name=a -c user.email=a@b commit --no-edit"
      }),
      FakeEngineApiClient.tool_call_response("report_done", %{"summary" => "pronta"})
    ])

    assert {:noreply, state} = DevAgentServer.handle_cast(:work, state)
    assert state.status == :awaiting_gate

    assert_received {:event_appended, _, _,
                     %{type: "dev.working", payload: %{cause: "integration_conflict"}}}

    refute_received {:event_appended, _, _, %{type: "dev.blocked"}}

    wt = state.worktree
    assert File.read!(Path.join(wt, "README.md")) == "resolvido"
    refute match?({_, 0}, System.cmd("git", ["rev-parse", "--verify", "MERGE_HEAD"], cd: wt))
  end

  test "report_done sem resolver: bloqueia, aborta o merge e não commita marcador",
       %{state: state, work_dir: work_dir} do
    Process.put(:fake_llm_turns, [
      FakeEngineApiClient.tool_call_response("terminal", %{"command" => "true"}),
      FakeEngineApiClient.tool_call_response("report_done", %{"summary" => "pronta"})
    ])

    assert {:noreply, state} = DevAgentServer.handle_cast(:work, state)
    refute state.status == :awaiting_gate

    assert_received {:event_appended, _, _,
                     %{
                       type: "dev.blocked",
                       payload: %{
                         reason: "conflito ao integrar a main atual" <> _,
                         origem: "codigo"
                       }
                     }}

    {tree, 0} =
      System.cmd("git", ["grep", "-c", "<<<<<<<", "feature/task-bbbb2222"],
        cd: work_dir,
        stderr_to_stdout: true
      )
      |> then(fn
        {_, 1} -> {"", 0}
        r -> r
      end)

    assert tree == ""
  end
end
