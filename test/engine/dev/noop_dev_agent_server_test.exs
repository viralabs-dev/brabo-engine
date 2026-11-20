defmodule Engine.Dev.NoopDevAgentServerTest do
  # DataCase — o server persiste em dev_agent_states. Callbacks exercitados
  # DIRETO no processo de teste (init/1 + handle_cast/2), mesmo idioma do
  # DevAgentServerTest: o fake scriptado por dicionário de processo funciona e
  # o acesso ao banco fica no sandbox do próprio processo.
  use Engine.DataCase, async: false

  alias Engine.Dev.{DevAgentState, FakeWorktreeManager, NoopDevAgentServer}
  alias Engine.Sessions.FakeEngineApiClient

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :worktree_manager, FakeWorktreeManager)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :worktree_manager)
      Application.delete_env(:engine, :test_pid)
    end)

    project_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()

    # RN-502/ADR 0143 — o Noop passa pelo MESMO `AgentIo.try_claim/2`, então a
    # guarda de container vale para ele igual: sem esta linha ele não claima.
    container_running!(project_id)

    {:ok, state} =
      NoopDevAgentServer.init({project_id, "dev-api", "api", session_id, 500_000, 2, nil, nil})

    %{state: state, project_id: project_id, session_id: session_id}
  end

  test "init grava impl=noop (a reidratação sobe o server certo)", %{
    project_id: project_id
  } do
    row = DevAgentState.get(project_id, "dev-api")

    assert row.impl == "noop"
    assert row.task_budget_micros == 500_000
    assert row.max_gate_corrections == 2
  end

  test "sem task pegável: fica idle, sem propor ações", %{state: state} do
    Process.put(:fake_tasks, [])

    assert {:noreply, _} = NoopDevAgentServer.handle_cast(:work, state)

    assert_received {:event_appended, _, _, %{type: "dev.idle"}}
    refute_received {:propose_action, _, _, _}
  end

  test "ciclo completo: worktree, arquivo trivial, commit com identidade, push e PR", %{
    state: state
  } do
    Process.put(:fake_tasks, [
      %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "Cadastro"}
    ])

    assert {:noreply, new_state} = NoopDevAgentServer.handle_cast(:work, state)

    assert_received {:task_claimed, "api", "dev-api"}
    assert_received {:worktree_created, _, "dev-api", "task-aaaa1111"}

    # O arquivo trivial existe no worktree — é o diff que a PR carrega.
    assert File.exists?(Path.join(new_state.worktree, "NOOP-task-aaaa1111.md"))

    assert_received {:propose_action, "git_commit", _, commit}
    assert commit.author == "dev-api[bot]"
    assert commit.authorEmail == "dev-api-bot@brabo.dev"
    assert commit.coAuthor =~ "Brabo User"
    assert commit.branch == "feature/task-aaaa1111"

    assert_received {:propose_action, "git_push", _, push}
    assert push.branch == "feature/task-aaaa1111"

    assert_received {:propose_action, "pr_open", _, pr}
    assert pr.sourceBranch == "feature/task-aaaa1111"
    assert pr.storyTaskId == "aaaa1111-2222-4333-8444-555555555555"

    assert_received {:task_marked, "aaaa1111-2222-4333-8444-555555555555", "in_review", "dev-api"}
    refute_received {:task_blocked, _, _, _, _}

    assert new_state.task_id == "aaaa1111-2222-4333-8444-555555555555"
    assert new_state.branch == "feature/task-aaaa1111"
  end

  test "não chama LLM nenhum (é o ponto do agente burro)", %{state: state} do
    Process.put(:fake_tasks, [
      %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "Cadastro"}
    ])

    assert {:noreply, _} = NoopDevAgentServer.handle_cast(:work, state)

    refute_received {:llm_turn, _, _, _}
    refute_received {:llm_turn_stream, _, _, _}
    # E nem monta o contexto rico da task, que é insumo de prompt.
    refute_received {:dev_context_fetched, _, _}
  end

  test "abre o gate de verdade, e não só entra em awaiting_gate", %{state: state} do
    # O Noop marcava a task `in_review` e parava aí: `tasks.gate_status` ficava
    # NULL e não havia gate para julgar. A validação da Fase 12 travava
    # esperando esse campo — o defeito morava no instrumento de medida.
    Process.put(:fake_tasks, [
      %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "Cadastro"}
    ])

    assert {:noreply, s} = NoopDevAgentServer.handle_cast(:work, state)

    assert s.status == :awaiting_gate
    assert_received {:gate_opened, "aaaa1111-2222-4333-8444-555555555555", "dev-api"}
  end

  test "sem PR (ação pendente) o gate NÃO abre — RN-050", %{state: state} do
    # Sem PR não há o que julgar. Abrir o gate aqui criaria um gate sobre
    # coisa nenhuma, que é justamente o que a RN-050 proíbe.
    Process.put(:fake_tasks, [
      %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "Cadastro"}
    ])

    Process.put(:fake_propose_action, %{"id" => "pa-77", "status" => "pending"})

    assert {:noreply, s} = NoopDevAgentServer.handle_cast(:work, state)

    assert s.status == :awaiting_approval
    refute_received {:gate_opened, _task_id, _agent}
  end

  test "pr_settled com o gate JÁ aberto é ignorado, não derruba o processo", %{state: state} do
    # A mensagem exata que matava o agente: `opened: true` chegando quando ele
    # já está em `:awaiting_gate`. Sem cláusula, o `handle_info/2` estourava
    # FunctionClauseError; como o server é `restart: :temporary`, morria para
    # sempre e a task seguinte nunca era reivindicada.
    state = %{
      state
      | task_id: "aaaa1111-2222-4333-8444-555555555555",
        status: :awaiting_gate
    }

    assert {:noreply, s} =
             NoopDevAgentServer.handle_info(
               {:pr_settled, %{task_id: state.task_id, opened: true}},
               state
             )

    assert s.status == :awaiting_gate
  end

  test "PR aprovada depois de pendente abre o gate", %{state: state} do
    state = %{
      state
      | task_id: "aaaa1111-2222-4333-8444-555555555555",
        status: :awaiting_approval
    }

    assert {:noreply, s} =
             NoopDevAgentServer.handle_info(
               {:pr_settled, %{task_id: state.task_id, opened: true}},
               state
             )

    assert s.status == :awaiting_gate
    assert_received {:gate_opened, "aaaa1111-2222-4333-8444-555555555555", "dev-api"}
  end

  test "pending -> action_settled -> pr_settled: chega a dev.awaiting_gate (AT-839)", %{
    state: state
  } do
    Process.put(:fake_tasks, [
      %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "Cadastro"}
    ])

    Process.put(:fake_propose_action, %{"id" => "pa-77", "status" => "pending"})
    assert {:noreply, s} = NoopDevAgentServer.handle_cast(:work, state)
    assert s.status == :awaiting_approval

    # o desfecho do git_push aprovado: antes da cláusula, FunctionClauseError
    assert {:noreply, s} =
             NoopDevAgentServer.handle_info(
               {:action_settled, %{status: "executed", action_type: "git_push"}},
               s
             )

    assert s.status == :awaiting_approval

    assert {:noreply, s} =
             NoopDevAgentServer.handle_info({:pr_settled, %{task_id: s.task_id, opened: true}}, s)

    assert s.status == :awaiting_gate
    assert_received {:event_appended, _, _, %{type: "dev.awaiting_gate"}}
  end

  describe "reentrega do conflito de merge (AT-1001)" do
    @task_id "aaaa1111-2222-4333-8444-555555555555"
    @arquivo "NOOP-task-aaaa1111.md"

    defmodule IntegrandoFake do
      # Readoção com conflito: o resultado vem do dicionário do teste.
      defdelegate create(p, a, s), to: Engine.Dev.FakeWorktreeManager
      defdelegate preservar(p, w, a, t), to: Engine.Dev.FakeWorktreeManager

      def adopt_integrando(p, a, s) do
        {:ok, wt} = Engine.Dev.FakeWorktreeManager.adopt_integrando(p, a, s)

        case Process.get(:fake_conflito_arquivos) do
          nil -> {:ok, wt}
          arquivos -> {:error, {:conflito_de_integracao, wt, arquivos, "conflito"}}
        end
      end
    end

    setup do
      Application.put_env(:engine, :worktree_manager, IntegrandoFake)
      :ok
    end

    defp conflito, do: {:merge_conflict, %{task_id: @task_id, conflicting_files: [@arquivo]}}

    test "só o arquivo do Noop em conflito: reescreve, commita, e o push pendente espera",
         %{state: state} do
      Process.put(:fake_conflito_arquivos, [@arquivo])

      Process.put(:fake_propose_action_by_type, %{
        "git_push" => %{"id" => "pa-1", "status" => "pending"}
      })

      assert {:noreply, s} = NoopDevAgentServer.handle_info(conflito(), state)

      assert s.status == :awaiting_approval
      assert s.reentrega == true
      assert s.reentrega_push_id == "pa-1"
      assert File.read!(Path.join(s.worktree, @arquivo)) =~ "NoopDevAgent"
      assert_received {:propose_action, "git_commit", _, %{message: msg}}
      assert msg =~ "reentrega"
      assert_received {:propose_action, "git_push", _, _}
      assert_received {:event_appended, _, _, %{type: "dev.awaiting_approval"}}
      refute_received {:task_marked, _, "in_review", _}
      refute_received {:gate_opened, _, _}
    end

    test "AT-1001b: o claim que devolve a task reaberta vira reentrega, não ciclo novo",
         %{state: state} do
      Process.put(:fake_tasks, [%{"id" => @task_id, "title" => "Cadastro"}])
      {:noreply, s} = NoopDevAgentServer.handle_cast(:work, state)
      Process.put(:fake_conflito_arquivos, [@arquivo])

      Process.put(:fake_propose_action_by_type, %{
        "git_push" => %{"id" => "pa-1", "status" => "pending"}
      })

      Process.put(:fake_tasks, [])

      # Gate aprovado: o agente fica ocioso, esperando o merge do dono.
      {:noreply, s} =
        NoopDevAgentServer.handle_info(
          {:gate_resolved, %{task_id: @task_id, next_action: "done"}},
          s
        )

      assert s.status == :idle
      flush()

      # O merge conflitou: a api reabriu a task e o claim ocioso a devolve ANTES do wake.
      Process.put(:fake_tasks, [reaberta()])
      {:noreply, s} = NoopDevAgentServer.handle_info({:wake, :became_claimable}, s)
      assert_received {:merge_conflict, %{task_id: @task_id}} = msg
      refute_received {:event_appended, _, _, %{type: "dev.working", payload: %{cause: nil}}}
      {:noreply, s} = NoopDevAgentServer.handle_info(msg, s)

      assert s.status == :awaiting_approval
      assert s.reentrega == true

      assert_received {:event_appended, _, _,
                       %{type: "dev.working", payload: %{cause: "merge_conflict"}}}

      assert_received {:propose_action, "git_push", _, _}
      refute_received {:propose_action, "pr_open", _, _}

      # O aviso do outbox, que chega depois, é descartado e não reentrega de novo.
      flush()
      assert {:noreply, s2} = NoopDevAgentServer.handle_info(conflito(), s)
      assert s2.status == :awaiting_approval
      refute_received {:propose_action, _, _, _}
    end

    defp reaberta,
      do: %{
        "id" => @task_id,
        "title" => "Cadastro",
        "retomada" => "merge_conflict",
        "conflictingFiles" => [@arquivo]
      }

    # AT-1003: sem marcas em memória (engine reiniciado entre o gate e o conflito),
    # o dado da api no claim basta para reentregar.
    test "AT-1003: restart entre o gate e o conflito: a retomada da api reentrega",
         %{state: state} do
      Process.put(:fake_conflito_arquivos, [@arquivo])

      Process.put(:fake_propose_action_by_type, %{
        "git_push" => %{"id" => "pa-1", "status" => "pending"}
      })

      Process.put(:fake_tasks, [reaberta()])
      s = %{state | status: :idle, task_id: nil}
      refute Map.has_key?(s, :aprovadas)

      {:noreply, s} = NoopDevAgentServer.handle_info({:wake, :became_claimable}, s)
      assert_received {:merge_conflict, %{task_id: @task_id, conflicting_files: [@arquivo]}} = msg
      {:noreply, s} = NoopDevAgentServer.handle_info(msg, s)

      assert s.status == :awaiting_approval
      assert s.reentrega == true
      assert_received {:propose_action, "git_push", _, _}
      refute_received {:propose_action, "pr_open", _, _}
    end

    test "AT-1003: claim sem `retomada` (api velha) segue como trabalho novo", %{state: state} do
      Process.put(:fake_tasks, [%{"id" => @task_id, "title" => "Cadastro"}])

      {:noreply, _} =
        NoopDevAgentServer.handle_info({:wake, :became_claimable}, %{state | status: :idle})

      refute_received {:merge_conflict, _}
    end

    defp flush do
      receive do
        _ -> flush()
      after
        0 -> :ok
      end
    end

    test "push aprovado: in_review ANTES do open_gate e dev.awaiting_gate com a causa",
         %{state: state} do
      s =
        %{state | status: :awaiting_approval, task_id: @task_id}
        |> Map.merge(%{reentrega: true, reentrega_push_id: "push-1"})

      assert {:noreply, s} =
               NoopDevAgentServer.handle_info(
                 {:action_settled, %{action_id: "push-1", status: "executed"}},
                 s
               )

      assert s.status == :awaiting_gate
      assert s.reentrega == false

      assert {:messages, msgs} = Process.info(self(), :messages)

      ordem =
        Enum.flat_map(msgs, fn
          {:task_marked, @task_id, "in_review", _} -> [:in_review]
          {:gate_opened, @task_id, _} -> [:open_gate]
          _ -> []
        end)

      assert ordem == [:in_review, :open_gate]

      assert_received {:event_appended, _, _, %{type: "dev.awaiting_gate", payload: payload}}
      assert payload.cause == "merge_conflict"
    end

    test "action_settled de outra ação (commit) não bloqueia; o do push reabre o gate",
         %{state: state} do
      s = %{state | status: :awaiting_approval, task_id: @task_id}
      s = Map.merge(s, %{reentrega: true, reentrega_push_id: "push-1"})
      Process.put(:fake_tasks, [])

      for status <- ["auto_approved", "executed", "denied"] do
        assert {:noreply, ^s} =
                 NoopDevAgentServer.handle_info(
                   {:action_settled, %{action_id: "commit-1", status: status}},
                   s
                 )
      end

      refute_received {:task_blocked, _, _, _, _}

      assert {:noreply, s2} =
               NoopDevAgentServer.handle_info(
                 {:action_settled, %{action_id: "push-1", status: "executed"}},
                 s
               )

      assert s2.status == :awaiting_gate
      assert_received {:task_marked, @task_id, "in_review", "dev-api"}
      assert_received {:gate_opened, @task_id, "dev-api"}
    end

    test "push executado na hora (modo automático) entrega direto", %{state: state} do
      Process.put(:fake_conflito_arquivos, [@arquivo])

      assert {:noreply, s} = NoopDevAgentServer.handle_info(conflito(), state)

      assert s.status == :awaiting_gate
      assert_received {:task_marked, @task_id, "in_review", "dev-api"}
      assert_received {:gate_opened, @task_id, "dev-api"}
    end

    test "push negado bloqueia com o motivo nomeado", %{state: state} do
      s =
        %{state | status: :awaiting_approval, task_id: @task_id}
        |> Map.merge(%{reentrega: true, reentrega_push_id: "push-1"})

      Process.put(:fake_tasks, [])

      assert {:noreply, _} =
               NoopDevAgentServer.handle_info(
                 {:action_settled, %{action_id: "push-1", status: "denied"}},
                 s
               )

      assert_received {:task_blocked, @task_id, "a reentrega do conflito não foi aprovada", _,
                       "dev-api"}

      refute_received {:gate_opened, _, _}
    end

    test "conflito em outro arquivo bloqueia, sem commit nem push", %{state: state} do
      Process.put(:fake_conflito_arquivos, [@arquivo, "a.ex"])
      Process.put(:fake_tasks, [])

      assert {:noreply, _} = NoopDevAgentServer.handle_info(conflito(), state)

      assert_received {:task_blocked, @task_id,
                       "conflito de merge em arquivo que o NoopDevAgent não resolve", _,
                       "dev-api"}

      refute_received {:propose_action, _, _, _}
    end

    test "ocupado: reagenda em vez de perder o conflito", %{state: state} do
      ocupado = %{state | status: :awaiting_gate, task_id: "bbbb2222-3333-4444-8555-666666666666"}

      assert {:noreply, ^ocupado} = NoopDevAgentServer.handle_info(conflito(), ocupado)
      refute_received {:task_blocked, _, _, _, _}
      assert_receive {:merge_conflict, _}, 31_000
    end

    test "disjuntor aberto bloqueia nomeado, sem cair", %{state: state} do
      state = %{state | status: :idle_tripped}
      assert {:noreply, ^state} = NoopDevAgentServer.handle_info(conflito(), state)

      assert_received {:task_blocked, @task_id,
                       "conflito de merge: o NoopDevAgent não readota a branch" <> _, _,
                       "dev-api"}
    end
  end

  test "mensagem desconhecida não derruba o dublê (AT-844)", %{state: state} do
    assert {:noreply, ^state} = NoopDevAgentServer.handle_info({:evento_novo, 1}, state)
  end

  test "PR negada devolve a task com origem politica", %{state: state} do
    state = %{
      state
      | task_id: "aaaa1111-2222-4333-8444-555555555555",
        status: :awaiting_approval
    }

    assert {:noreply, _} =
             NoopDevAgentServer.handle_info(
               {:pr_settled, %{task_id: state.task_id, opened: false}},
               state
             )

    assert_received {:task_blocked, "aaaa1111-2222-4333-8444-555555555555", "a PR não foi aberta",
                     _, "dev-api"}

    refute_received {:gate_opened, _t, _a}
  end

  test "claim com corpo VAZIO vira idle, não derruba o agente", %{state: state} do
    # O defeito real, achado por execução: com a fila vazia, a rota de claim
    # responde `201` com `content-length: 0`. O `Req` entrega `""` — que não é
    # `nil` — e o `AgentIo.try_claim/2` casava com a cláusula de task
    # encontrada, chamando `run_task("")`: BadMapError, processo
    # `restart: :temporary` morto de vez, estado apagado pelo Monitor.
    #
    # A guarda vive no `AgentIo`, compartilhado com o `DevAgentServer` REAL —
    # o Noop aqui é só o veículo mais barato de exercitá-la.
    Process.put(:fake_tasks, [""])

    assert {:noreply, s} = NoopDevAgentServer.handle_cast(:work, state)

    assert s.status == :idle
    assert_received {:event_appended, _, _, %{type: "dev.idle"}}
    refute_received {:propose_action, _, _, _}
  end

  test "falha no worktree devolve a task em vez de deixá-la órfã", %{state: state} do
    Process.put(:fake_tasks, [
      %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "Cadastro"}
    ])

    Process.put(:fake_worktree_error, :disco_cheio)

    assert {:noreply, _} = NoopDevAgentServer.handle_cast(:work, state)

    assert_received {:event_appended, _, _, %{type: "dev.error"}}

    assert_received {:task_blocked, "aaaa1111-2222-4333-8444-555555555555",
                     "falha ao preparar o worktree", _, "dev-api"}

    refute_received {:propose_action, "pr_open", _, _}
  end

  test "devolução de gate: bloqueia com diagnóstico em vez de derrubar o processo", %{
    state: state
  } do
    # `:awaiting_gate` é o estado REAL de quem acabou de abrir PR (Fase 12d) —
    # e é o único em que uma devolução faz sentido.
    state = %{
      state
      | task_id: "aaaa1111-2222-4333-8444-555555555555",
        status: :awaiting_gate
    }

    assert {:noreply, _} =
             NoopDevAgentServer.handle_cast(
               {:correct, %{gate: "qa", reason: "suite vermelha", diagnosis: "..."}},
               state
             )

    assert_received {:task_blocked, "aaaa1111-2222-4333-8444-555555555555", reason, _, "dev-api"}
    assert reason =~ "não corrige"
  end

  test "devolução de gate ATRASADA, quando o agente já seguiu, é ignorada", %{state: state} do
    # Mesmo guard do agente real (D4): `correct/3` é um cast puro. Uma entrega
    # tardia rodaria a devolução do gate ANTIGO contra o `task_id` ATUAL —
    # bloquearia uma task que não tem nada a ver com o parecer.
    state = %{state | task_id: "bbbb2222-3333-4444-8555-666666666666", status: :working}

    assert {:noreply, ^state} =
             NoopDevAgentServer.handle_cast(
               {:correct, %{gate: "qa", reason: "suite vermelha", diagnosis: "..."}},
               state
             )

    refute_received {:task_blocked, _, _, _, _}
  end

  describe "reagendamento sem restart (Fase 12d — o Noop entra na 12b)" do
    test "três tasks em SEQUÊNCIA, um agente, zero restarts, termina idle", %{
      state: state,
      project_id: project_id
    } do
      # O critério de aceite da Fase 12b, exercitado pelo veículo sem LLM.
      # Antes da 12d isto era impossível: o Noop parava na primeira.
      Process.put(:fake_tasks, [
        %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "t1"},
        %{"id" => "bbbb2222-3333-4444-8555-666666666666", "title" => "t2"},
        %{"id" => "cccc3333-4444-4555-8666-777777777777", "title" => "t3"}
      ])

      assert {:noreply, s1} = NoopDevAgentServer.handle_cast(:work, state)
      assert s1.status == :awaiting_gate
      assert s1.task_id == "aaaa1111-2222-4333-8444-555555555555"

      # Gate aprova → o agente reivindica a PRÓXIMA sozinho.
      assert {:noreply, s2} =
               NoopDevAgentServer.handle_info(
                 {:gate_resolved, %{task_id: s1.task_id, next_action: "done"}},
                 s1
               )

      assert s2.status == :awaiting_gate
      assert s2.task_id == "bbbb2222-3333-4444-8555-666666666666"

      assert {:noreply, s3} =
               NoopDevAgentServer.handle_info(
                 {:gate_resolved, %{task_id: s2.task_id, next_action: "done"}},
                 s2
               )

      assert s3.task_id == "cccc3333-4444-4555-8666-777777777777"

      # Fila vazia: idle EXPLÍCITO, com o processo vivo e a linha durável
      # dizendo a verdade — não um processo morto.
      assert {:noreply, s4} =
               NoopDevAgentServer.handle_info(
                 {:gate_resolved, %{task_id: s3.task_id, next_action: "done"}},
                 s3
               )

      assert s4.status == :idle
      assert s4.task_id == nil
      assert DevAgentState.get(project_id, "dev-api").status == "idle"
    end

    test "task nova fica pegável e acorda quem está idle", %{state: state} do
      Process.put(:fake_tasks, [])
      assert {:noreply, idle} = NoopDevAgentServer.handle_cast(:work, state)
      assert idle.status == :idle

      Process.put(:fake_tasks, [
        %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "nova"}
      ])

      assert {:noreply, trabalhando} =
               NoopDevAgentServer.handle_info({:wake, :became_claimable}, idle)

      assert trabalhando.task_id == "aaaa1111-2222-4333-8444-555555555555"
    end

    test "wake de task pegável NÃO interrompe quem está em awaiting_gate", %{state: state} do
      ocupado = %{state | status: :awaiting_gate, task_id: "aaaa1111-2222-4333-8444-555555555555"}

      assert {:noreply, ^ocupado} =
               NoopDevAgentServer.handle_info({:wake, :became_claimable}, ocupado)

      refute_received {:task_claimed, _, _}
    end

    test "três blocked seguidas travam o agente em idle_tripped", %{
      state: state,
      project_id: project_id
    } do
      state = %{state | max_consecutive_blocked: 3}

      # Cada volta: o agente está em awaiting_gate e o gate bloqueia. A fila
      # tem sempre uma próxima, então só o breaker pode pará-lo.
      travado =
        Enum.reduce(1..3, state, fn i, acc ->
          Process.put(:fake_tasks, [
            %{"id" => "aaaa1111-2222-4333-8444-55555555555#{i}", "title" => "t#{i}"}
          ])

          acc = %{
            acc
            | status: :awaiting_gate,
              task_id: "aaaa1111-2222-4333-8444-55555555555#{i}"
          }

          {:noreply, novo} =
            NoopDevAgentServer.handle_info(
              {:gate_resolved, %{task_id: acc.task_id, next_action: "blocked"}},
              acc
            )

          novo
        end)

      assert travado.status == :idle_tripped
      assert travado.consecutive_blocked == 3
      assert DevAgentState.get(project_id, "dev-api").status == "idle_tripped"
      assert_received {:event_appended, _, _, %{type: "dev.idle_tripped"}}
    end

    test "aprovado no meio de uma sequência zera o contador do breaker", %{state: state} do
      Process.put(:fake_tasks, [])

      travando = %{
        state
        | status: :awaiting_gate,
          task_id: "aaaa1111-2222-4333-8444-555555555555",
          consecutive_blocked: 2,
          max_consecutive_blocked: 3
      }

      assert {:noreply, zerado} =
               NoopDevAgentServer.handle_info(
                 {:gate_resolved, %{task_id: travando.task_id, next_action: "done"}},
                 travando
               )

      assert zerado.consecutive_blocked == 0
      assert zerado.status == :idle
    end

    test "rearm é a única saída de idle_tripped", %{state: state} do
      Process.put(:fake_tasks, [
        %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "depois do rearm"}
      ])

      travado = %{state | status: :idle_tripped, consecutive_blocked: 3}

      assert {:noreply, solto} = NoopDevAgentServer.handle_info(:rearm, travado)
      assert solto.consecutive_blocked == 0
      assert solto.task_id == "aaaa1111-2222-4333-8444-555555555555"
    end

    test "rearm em agente que não está travado não faz nada", %{state: state} do
      idle = %{state | status: :idle}
      assert {:noreply, ^idle} = NoopDevAgentServer.handle_info(:rearm, idle)
      refute_received {:task_claimed, _, _}
    end
  end

  describe "reidratação nos quatro estados (Fase 12d)" do
    setup %{project_id: project_id, session_id: session_id} do
      %{
        subir: fn resume ->
          {:ok, s} =
            NoopDevAgentServer.init(
              {project_id, "dev-web", "web", session_id, 500_000, 2, 3, resume}
            )

          s
        end
      }
    end

    test "idle e idle_tripped voltam sem task, preservando o contador", %{subir: subir} do
      idle = subir.(%{status: "idle", task_id: nil, worktree_path: nil, consecutive_blocked: 1})
      assert idle.status == :idle
      assert idle.task_id == nil
      # O contador PRECISA sobreviver: senão um restart no meio de uma
      # sequência de blocked zeraria o breaker de graça.
      assert idle.consecutive_blocked == 1

      travado =
        subir.(%{
          status: "idle_tripped",
          task_id: nil,
          worktree_path: nil,
          consecutive_blocked: 3
        })

      assert travado.status == :idle_tripped
      assert travado.consecutive_blocked == 3
    end

    test "awaiting_gate retém task e worktree — um gate tardio ainda os encontra", %{
      subir: subir
    } do
      s =
        subir.(%{
          status: "awaiting_gate",
          task_id: "aaaa1111-2222-4333-8444-555555555555",
          worktree_path: "/data/wt/dev-web",
          consecutive_blocked: 0
        })

      assert s.status == :awaiting_gate
      assert s.task_id == "aaaa1111-2222-4333-8444-555555555555"
      assert s.worktree == "/data/wt/dev-web"
      assert s.branch == "feature/task-aaaa1111"
    end
  end

  test "dois agentes do mesmo projeto trabalham em paralelo sem conflito", %{
    project_id: project_id,
    session_id: session_id
  } do
    {:ok, api} =
      NoopDevAgentServer.init({project_id, "dev-api", "api", session_id, nil, nil, nil, nil})

    {:ok, web} =
      NoopDevAgentServer.init({project_id, "dev-web", "web", session_id, nil, nil, nil, nil})

    Process.put(:fake_tasks, [
      %{"id" => "aaaa1111-2222-4333-8444-555555555555", "title" => "Cadastro"},
      %{"id" => "bbbb2222-3333-4444-8555-666666666666", "title" => "Listagem"}
    ])

    {:noreply, api_state} = NoopDevAgentServer.handle_cast(:work, api)
    {:noreply, web_state} = NoopDevAgentServer.handle_cast(:work, web)

    # Cada um pegou a SUA task, no seu worktree, na sua branch.
    assert api_state.task_id != web_state.task_id
    assert api_state.worktree != web_state.worktree
    assert api_state.branch != web_state.branch

    # E cada worktree só tem o arquivo do seu dono.
    assert File.exists?(Path.join(api_state.worktree, "NOOP-task-aaaa1111.md"))
    refute File.exists?(Path.join(api_state.worktree, "NOOP-task-bbbb2222.md"))
    assert File.exists?(Path.join(web_state.worktree, "NOOP-task-bbbb2222.md"))

    # Duas PRs distintas, uma por branch.
    prs =
      for _ <- 1..2 do
        assert_received {:propose_action, "pr_open", _, pr}
        pr.sourceBranch
      end

    assert Enum.uniq(prs) == prs
  end
end
