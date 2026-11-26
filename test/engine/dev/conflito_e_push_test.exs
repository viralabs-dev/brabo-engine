defmodule Engine.Dev.ConflitoEPushTest do
  @moduledoc """
  AT-907 e AT-911 no `DevAgentServer` (api e worktree falsos): o conflito de merge
  que chega com a task já `done` é descartado, e push recusado nunca abre o gate.
  A corrente com git real (troca de agente, bare, `wip`) está em
  `worktree_manager_test.exs` e `git_executor_test.exs`.
  """
  use Engine.DataCase, async: false

  alias Engine.Dev.{DevAgentServer, FakeWorktreeManager}
  alias Engine.Gates.FakeGateDispatcher
  alias Engine.Sessions.FakeEngineApiClient

  @conflito %{
    task_id: "task-abc12345",
    pull_request_id: "pr-6",
    conflicting_files: ["package.json"]
  }

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
    session_id = Ecto.UUID.generate()
    container_running!(project_id)

    {:ok, state} =
      DevAgentServer.init({project_id, "dev-api", "api", session_id, nil, nil, nil, nil})

    %{state: state}
  end

  defp contexto(task_extra) do
    base = %{"id" => "task-abc12345", "title" => "Cadastro", "description" => ""}

    %{
      "task" => Map.merge(base, task_extra),
      "story" => %{
        "id" => "st-1",
        "title" => "Cadastro",
        "description" => "",
        "rf" => [],
        "rnf" => [],
        "dod" => [],
        "dor" => []
      },
      "businessRules" => [],
      "adrs" => []
    }
  end

  defp executada,
    do: %{"id" => "pa-1", "status" => "executed", "executionResult" => %{"exitCode" => 0}}

  defp turnos(resumo) do
    [
      FakeEngineApiClient.tool_call_response("terminal", %{"command" => "npm test"}),
      FakeEngineApiClient.tool_call_response("report_done", %{"summary" => resumo})
    ]
  end

  defp em_correcao(state) do
    %{
      state
      | task_id: "task-abc12345",
        worktree: "/tmp/brabo-fake-existing-worktree",
        branch: "feature/task-abc12345",
        status: :awaiting_gate
    }
  end

  describe "AT-907: o conflito reentregue com a task já done" do
    test "a corrente: ocupado adia, a PR entra, e a reentrega é descartada", %{state: state} do
      Process.put(:fake_tasks, [])

      Process.put(
        :fake_dev_context,
        contexto(%{"status" => "in_progress", "assignedTo" => "dev-api"})
      )

      # Ocupado: a mensagem fica para a reentrega, sem tocar a branch.
      ocupado = %{state | status: :working, task_id: "outra"}

      assert {:noreply, ^ocupado} =
               DevAgentServer.handle_info({:merge_conflict, @conflito}, ocupado)

      refute_received {:worktree_adopted, _, _, _}

      # O dono mergeou de novo e a api fechou a task; o agente ficou livre.
      Process.put(:fake_dev_context, contexto(%{"status" => "done", "assignedTo" => "dev-api"}))

      assert {:noreply, livre} =
               DevAgentServer.handle_info({:merge_conflict, @conflito}, %{state | status: :idle})

      refute_received {:worktree_adopted, _, _, _}

      refute_received {:event_appended, _, _,
                       %{type: "dev.working", payload: %{cause: "merge_conflict"}}}

      assert_received {:event_appended, _, _,
                       %{
                         type: "dev.conflict_rework_dropped",
                         payload: %{taskId: "task-abc12345", motivo: "a PR já entrou"}
                       }}

      assert livre.status == :idle
      assert livre.task_id == nil
    end

    test "descartado, o agente reivindica a próxima da fila", %{state: state} do
      Process.put(:fake_tasks, [%{"id" => "task-next", "title" => "T2"}])
      Process.put(:fake_dev_context, contexto(%{"status" => "done"}))
      Process.put(:fake_propose_action, executada())
      Process.put(:fake_llm_turns, turnos("ok"))

      assert {:noreply, novo} =
               DevAgentServer.handle_info({:merge_conflict, @conflito}, %{state | status: :idle})

      refute_received {:worktree_adopted, _, _, _}
      assert novo.task_id == "task-next"
    end

    test "a task passou para outro dono: descarta", %{state: state} do
      Process.put(:fake_tasks, [])

      Process.put(
        :fake_dev_context,
        contexto(%{"status" => "in_progress", "assignedTo" => "dev-api-2"})
      )

      assert {:noreply, _} =
               DevAgentServer.handle_info({:merge_conflict, @conflito}, %{state | status: :idle})

      refute_received {:worktree_adopted, _, _, _}

      assert_received {:event_appended, _, _,
                       %{type: "dev.conflict_rework_dropped", payload: %{motivo: motivo}}}

      assert motivo =~ "dono"
    end

    test "in_progress com este agente mantém o retrabalho (regressão)", %{state: state} do
      Process.put(:fake_tasks, [])

      Process.put(
        :fake_dev_context,
        contexto(%{"status" => "in_progress", "assignedTo" => "dev-api"})
      )

      Process.put(:fake_propose_action, executada())
      Process.put(:fake_llm_turns, turnos("resolvido"))

      assert {:noreply, novo} =
               DevAgentServer.handle_info({:merge_conflict, @conflito}, %{state | status: :idle})

      assert_received {:worktree_adopted, _, "dev-api", "task-task-abc"}
      refute_received {:event_appended, _, _, %{type: "dev.conflict_rework_dropped"}}

      # AT-983: a reentrega volta a `in_review` ANTES de reabrir o gate.
      {:messages, msgs} = Process.info(self(), :messages)
      idx = fn alvo -> Enum.find_index(msgs, &(elem(&1, 0) == alvo)) end
      assert idx.(:task_marked) != nil
      assert idx.(:task_marked) < idx.(:gate_opened)
      assert_received {:task_marked, "task-abc12345", "in_review", "dev-api"}
      assert novo.status == :awaiting_gate
    end

    test "disjuntor aberto com a task done: não bloqueia", %{state: state} do
      Process.put(:fake_dev_context, contexto(%{"status" => "done"}))

      assert {:noreply, _} =
               DevAgentServer.handle_info(
                 {:merge_conflict, @conflito},
                 %{state | status: :idle_tripped}
               )

      refute_received {:task_blocked, _, _, _, _}
      assert_received {:event_appended, _, _, %{type: "dev.conflict_rework_dropped"}}
    end
  end

  describe "AT-911: push recusado não abre o gate" do
    test "entrega: push recusado bloqueia nomeado (infra), sem PR e sem QA", %{state: state} do
      Process.put(:fake_tasks, [%{"id" => "task-abc12345", "title" => "Cadastro"}])
      Process.put(:fake_dev_context, contexto(%{}))
      Process.put(:fake_propose_action, executada())

      Process.put(:fake_propose_action_by_type, %{
        "git_push" => %{"id" => "p", "status" => "failed"}
      })

      Process.put(:fake_llm_turns, turnos("pronta"))

      assert {:noreply, _} = DevAgentServer.handle_cast(:work, state)

      assert_received {:task_blocked, "task-abc12345", "o push da branch foi recusado", _,
                       "dev-api"}

      assert_received {:task_blocked_origin, "task-abc12345", "infra"}
      refute_received {:propose_action, "pr_open", _, _}
      refute_received {:gate_dispatch, _, _, _}
    end

    test "correção: push recusado bloqueia e não reabre o gate", %{state: state} do
      Process.put(:fake_tasks, [])
      Process.put(:fake_dev_context, contexto(%{}))
      Process.put(:fake_propose_action, executada())

      Process.put(:fake_propose_action_by_type, %{
        "git_push" => %{"id" => "p", "status" => "denied"}
      })

      Process.put(:fake_llm_turns, turnos("corrigido"))

      findings = %{gate: "qa", reason: "x", diagnosis: "y"}
      assert {:noreply, _} = DevAgentServer.handle_cast({:correct, findings}, em_correcao(state))

      assert_received {:task_blocked, "task-abc12345", motivo, _, "dev-api"}
      assert motivo =~ "Não consegui enviar a correção"
      assert_received {:task_blocked_origin, "task-abc12345", "infra"}
      refute_received {:gate_dispatch, _, _, _}
    end

    test "correção: worktree limpo conta como commit feito, publica e reabre o gate (RN-1506)", %{
      state: state
    } do
      dir = Path.join(System.tmp_dir!(), "brabo-limpo-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      for a <- [
            ["init", "-q", "-b", "main", "."],
            ["config", "user.email", "t@t"],
            ["config", "user.name", "t"],
            ["commit", "-q", "--allow-empty", "-m", "base"]
          ],
          do: {_, 0} = System.cmd("git", a, cd: dir, stderr_to_stdout: true)

      # o cartão do módulo (RN-1112) é escrito antes do commit; aqui já estaria versionado.
      File.write!(Path.join(dir, ".git/info/exclude"), ".brabo/\nAGENTS.md\n")

      Process.put(:fake_tasks, [])
      Process.put(:fake_dev_context, contexto(%{}))
      Process.put(:fake_propose_action, executada())
      Process.put(:fake_llm_turns, turnos("corrigido"))

      findings = %{gate: "qa", reason: "x", diagnosis: "y"}
      limpo = %{em_correcao(state) | worktree: dir}
      assert {:noreply, _} = DevAgentServer.handle_cast({:correct, findings}, limpo)

      refute_received {:propose_action, "git_commit", _, _}
      assert_received {:propose_action, "git_push", _, _}
      assert_received {:gate_dispatch, _, _, _}
      refute_received {:task_blocked, _, _, _, _}
    end

    test "correção: commit recusado bloqueia em linguagem simples, sem átomo", %{state: state} do
      Process.put(:fake_tasks, [])
      Process.put(:fake_dev_context, contexto(%{}))
      Process.put(:fake_propose_action, executada())

      Process.put(:fake_propose_action_by_type, %{
        "git_commit" => %{"id" => "c", "status" => "denied"}
      })

      Process.put(:fake_llm_turns, turnos("corrigido"))

      findings = %{gate: "qa", reason: "x", diagnosis: "y"}
      assert {:noreply, _} = DevAgentServer.handle_cast({:correct, findings}, em_correcao(state))

      assert_received {:task_blocked, "task-abc12345", motivo, diag, "dev-api"}
      assert motivo == "Não consegui salvar a correção no repositório do projeto"
      refute motivo =~ ":refused"
      assert diag =~ "commit"
      assert_received {:task_blocked_origin, "task-abc12345", "infra"}
    end

    defp push_pendente do
      Process.put(:fake_tasks, [])
      Process.put(:fake_dev_context, contexto(%{}))
      Process.put(:fake_propose_action, executada())

      Process.put(:fake_propose_action_by_type, %{
        "git_push" => %{"id" => "p", "status" => "pending"}
      })

      Process.put(:fake_llm_turns, turnos("corrigido"))
    end

    defp esperando_push(state, gate) do
      push_pendente()
      findings = %{gate: gate, reason: "x", diagnosis: "y"}

      assert {:noreply, novo} =
               DevAgentServer.handle_cast({:correct, findings}, em_correcao(state))

      assert novo.status == :awaiting_approval
      assert novo.correcao_pendente.action_id == "p"
      refute_received {:gate_dispatch, _, _, _}
      novo
    end

    test "correção: push pendente espera e o `executed` reabre o gate", %{state: state} do
      novo = esperando_push(state, "qa")

      assert {:noreply, depois} =
               DevAgentServer.handle_info(
                 {:action_settled, %{action_id: "p", status: "executed"}},
                 novo
               )

      assert depois.status == :awaiting_gate
      assert depois.correcao_pendente == nil
      assert_received {:gate_dispatch, _, _, _}
    end

    test "conflito: push pendente + `executed` marca in_review antes do gate", %{state: state} do
      novo = esperando_push(state, "conflito_de_merge")

      {:noreply, depois} =
        DevAgentServer.handle_info({:action_settled, %{action_id: "p", status: "executed"}}, novo)

      assert depois.status == :awaiting_gate
      {:messages, msgs} = Process.info(self(), :messages)
      idx = fn alvo -> Enum.find_index(msgs, &(elem(&1, 0) == alvo)) end
      assert idx.(:task_marked) != nil
      assert idx.(:task_marked) < idx.(:gate_opened)
      assert_received {:gate_dispatch, _, _, _}
    end

    test "push `denied`: bloqueia (politica), sem gate e sem contar no disjuntor", %{
      state: state
    } do
      novo = esperando_push(state, "qa")

      assert {:noreply, depois} =
               DevAgentServer.handle_info(
                 {:action_settled, %{action_id: "p", status: "denied"}},
                 novo
               )

      assert_received {:task_blocked, "task-abc12345", "o push da correção não foi aprovado", _,
                       _}

      assert_received {:task_blocked_origin, "task-abc12345", "politica"}
      refute_received {:gate_dispatch, _, _, _}
      assert depois.consecutive_blocked == novo.consecutive_blocked
      assert depois.correcao_pendente == nil
      assert depois.task_id == nil
    end

    test "push `failed`: bloqueia (infra), sem gate e sem contar no disjuntor", %{state: state} do
      novo = esperando_push(state, "qa")

      assert {:noreply, depois} =
               DevAgentServer.handle_info(
                 {:action_settled, %{action_id: "p", status: "failed"}},
                 novo
               )

      assert_received {:task_blocked, "task-abc12345", "o push da correção falhou", _, _}
      assert_received {:task_blocked_origin, "task-abc12345", "infra"}
      refute_received {:gate_dispatch, _, _, _}
      assert depois.consecutive_blocked == novo.consecutive_blocked
    end

    test "`action_settled` de outro action_id é ignorado", %{state: state} do
      novo = esperando_push(state, "qa")

      assert {:noreply, ^novo} =
               DevAgentServer.handle_info(
                 {:action_settled, %{action_id: "outra", status: "executed"}},
                 novo
               )

      refute_received {:gate_dispatch, _, _, _}
    end
  end
end
