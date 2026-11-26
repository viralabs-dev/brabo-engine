defmodule Engine.Dev.NoopDevAgentServer do
  @moduledoc """
  Dev agent BURRO (Fase 4a) — valida a infraestrutura de execução sem LLM:
  reivindica uma task, monta um worktree isolado, escreve um arquivo trivial,
  e propõe commit → push → pr_open pelo pipeline de `proposed_actions`
  (autonomia `auto_approve` executa). Nenhuma chamada de modelo, nenhum gasto
  de token, resultado determinístico.

  Convive com o `Engine.Dev.DevAgentServer` real: mesmo Registry, mesmo
  `agent_id` (`dev-<modulo>`), mesmo estado durável. O modo é escolhido na
  ativação da execução e gravado em `dev_agent_states.impl`, pra que a
  reidratação suba o server certo depois de um restart do nó.

  Tudo que ele exercita — worktree, identidade `dev-<modulo>[bot]`, propostas
  git, e desde a Fase 12d a máquina de estados do reagendamento — vem de
  `Engine.Dev.AgentIo`, o MESMO código do agente real: um Noop que
  reimplementasse essas partes validaria uma cópia, não a infraestrutura.

  **Não JULGA, mas participa do ciclo do gate.** Ele não tem LLM: não corrige
  uma devolução e não emite parecer. Mas abre a PR, fica em `:awaiting_gate`
  retendo o worktree, e reage ao desfecho como o agente real — aprovado,
  reivindica a próxima; bloqueado, conta para o circuit breaker.

  Até a Fase 12d isto não era verdade: o Noop fixava `status: :working`, não
  assinava o `Engine.Dev.Wake` e processava UMA task antes de parar. Ou seja,
  o achado #10 do dogfooding — que a Fase 12b existiu para matar — seguia vivo
  dentro do único veículo capaz de validar a fase sem gastar token. Uma
  validação de ponta a ponta com este agente reprovaria o critério "zero
  restarts" por defeito do próprio instrumento.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Engine.Dev.{AgentIo, ExplicacaoDoBloqueio, Wake}
  alias Engine.Runners.CredencialDeGit
  alias Engine.Sessions.EngineApiClient

  @impl_tag "noop"
  @reentrega_do_conflito_ms 30_000

  def start_link(
        {project_id, agent_id, module, session_id, task_budget_micros, max_gate_corrections,
         max_consecutive_blocked, resume}
      ) do
    GenServer.start_link(
      __MODULE__,
      {project_id, agent_id, module, session_id, task_budget_micros, max_gate_corrections,
       max_consecutive_blocked, resume},
      name: via(project_id, agent_id)
    )
  end

  defdelegate via(project_id, agent_id), to: AgentIo

  @doc "Dispara o ciclo de trabalho (chamado num start FRESCO, não em rehydration)."
  def work(project_id, agent_id), do: GenServer.cast(via(project_id, agent_id), :work)

  # --- Callbacks ---

  @impl true
  def init(
        {project_id, agent_id, module, session_id, task_budget_micros, max_gate_corrections,
         max_consecutive_blocked, resume}
      ) do
    base = %{
      project_id: project_id,
      agent_id: agent_id,
      module: module,
      session_id: session_id,
      impl: @impl_tag,
      # Não gasta token, mas os tetos viajam no estado durável: o subagente
      # extra da paralelização HERDA a linha do agente base, e trocar o modo
      # não pode zerar o que o usuário configurou.
      task_budget_micros: task_budget_micros,
      max_gate_corrections: max_gate_corrections,
      max_consecutive_blocked: max_consecutive_blocked
    }

    state = AgentIo.resume_state(base, resume)
    AgentIo.persist(state)
    :ok = Wake.subscribe(project_id, agent_id)

    # Mesma razão do agente real (D2): a recuperação de um `working`
    # interrompido bloqueia, e feita no `init/1` seguraria o boot inteiro pelo
    # `DevRehydrator`.
    if resume && resume.status == "working" do
      {:ok, state, {:continue, :restart_recovery}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:restart_recovery, state) do
    state =
      AgentIo.block_task(
        state,
        "engine reiniciou durante a task",
        "o trabalho do NoopDevAgent não pôde ser retomado após o restart",
        # Quem derrubou o turno foi o processo reiniciando.
        "infra",
        ExplicacaoDoBloqueio.de(:reinicio_do_engine)
      )

    # SEM passar por `finish_task/3`: reiniciar o engine não é o agente
    # queimando o teto, e não pode contar pro circuit breaker.
    {:noreply,
     state
     |> Map.merge(%{task_id: nil, worktree: nil, branch: nil})
     |> try_claim()}
  end

  @impl true
  def handle_cast(:work, state) do
    AgentIo.emit(state, "dev.started", %{agentId: state.agent_id, module: state.module})
    {:noreply, try_claim(state)}
  end

  @impl true
  def handle_cast({:correct, findings}, %{status: :awaiting_gate} = state) do
    # O Noop não tem LLM: não sabe corrigir. Devolve a task com diagnóstico em
    # vez de derrubar o processo — e o `block_task` conta pro breaker pelo
    # `handle_info` do gate, como no agente real.
    {:noreply,
     AgentIo.block_task(
       state,
       "NoopDevAgent não corrige devolução de gate",
       "gate: #{inspect(Map.get(findings, :gate))}",
       # Limite conhecido do PRODUTO, não falha de execução: o Noop não tem LLM
       # e nunca soube corrigir.
       "codigo",
       ExplicacaoDoBloqueio.de(:generico)
     )}
  end

  # Mesmo guard do agente real (D4): uma devolução que chega tarde, quando o
  # agente já seguiu para outra task, rodaria contra o `task_id` ERRADO.
  def handle_cast({:correct, _findings}, state), do: {:noreply, state}

  # --- Wakes (Fase 12b, entregues ao Noop desde a 12d) ---

  @impl true
  def handle_info(
        {:gate_resolved, %{task_id: task_id, next_action: next_action} = ev},
        %{task_id: task_id, status: :awaiting_gate} = state
      ) do
    desfecho =
      case desfecho(next_action) do
        :blocked ->
          if AgentIo.conta_no_disjuntor?(Map.get(ev, :origin), Map.get(ev, :blocked_by)),
            do: :blocked,
            else: :blocked_infra

        outro ->
          outro
      end

    {:noreply, finish_task(state, desfecho)}
  end

  def handle_info({:gate_resolved, _}, state), do: {:noreply, state}

  def handle_info({:wake, :became_claimable}, %{status: :idle} = state) do
    {:noreply, try_claim(state)}
  end

  def handle_info({:wake, :became_claimable}, state), do: {:noreply, state}

  def handle_info(:rearm, %{status: :idle_tripped} = state) do
    state = %{state | consecutive_blocked: 0}
    AgentIo.persist(state)
    {:noreply, try_claim(state)}
  end

  def handle_info(:rearm, state), do: {:noreply, state}

  # --- `task.pr_settled` (Fase 12e) ---
  #
  # As MESMAS três cláusulas do agente real, e pelo mesmo motivo. O Noop não
  # tinha nenhuma: a mensagem chegava, o `handle_info/2` estourava
  # `FunctionClauseError` e o processo morria — `restart: :temporary`, então
  # para sempre, com o `Monitor` apagando o estado logo atrás. A validação da
  # Fase 12 parava na 2ª task sem dizer por quê.
  #
  # O caso que derrubava era `opened: true` com o agente já em
  # `:awaiting_gate`: no agente real ele cai no catch-all e é IGNORADO, porque
  # o gate já foi aberto na hora da PR.

  # A PR estava pendente de aprovação e foi aprovada: agora há o que julgar.
  def handle_info(
        {:pr_settled, %{task_id: task_id, opened: true}},
        %{task_id: task_id, status: :awaiting_approval} = state
      ) do
    abrir_gate(state, task_id)

    state = %{state | status: :awaiting_gate}
    AgentIo.persist(state)

    AgentIo.emit(state, "dev.awaiting_gate", %{agentId: state.agent_id, taskId: task_id})

    {:noreply, state}
  end

  # Negada, ou a abertura falhou. Devolve com diagnóstico em vez de esperar
  # para sempre por um gate que ninguém vai abrir. Origem `politica`: foi uma
  # DECISÃO, nada quebrou.
  def handle_info(
        {:pr_settled, %{task_id: task_id, opened: false}},
        %{task_id: task_id, status: :awaiting_approval} = state
      ) do
    state =
      AgentIo.block_task(
        state,
        "a PR não foi aberta",
        "as ações git da task não foram aprovadas — o trabalho ficou no worktree e o gate nunca abriu",
        "politica",
        ExplicacaoDoBloqueio.de(:pr_nao_aberta)
      )

    {:noreply,
     state
     |> Map.merge(%{task_id: nil, worktree: nil, branch: nil})
     |> try_claim()}
  end

  def handle_info({:pr_settled, _}, state), do: {:noreply, state}

  # AT-839 (ADR 0052): o `git_push`/`pr_open` pendentes (RN-689) entregam
  # `action_settled` ao serem aprovados. O agente real ignora (dev_agent_server.ex);
  # sem a cláusula o Noop morria com FunctionClauseError antes do `pr_settled`.
  #
  # AT-1001: se o push pendente era o da REENTREGA do conflito, o desfecho dele
  # decide: executado → `in_review` e só então o gate (como o real, AT-983);
  # qualquer outro → bloqueio nomeado. O desfecho casa pelo `action_id` do push
  # (`reentrega_push_id`, como o `correcao_pendente` do real, AT-1002): o do
  # commit auto_approved ou de ação antiga NÃO é o do push e cai no catch-all.
  def handle_info(
        {:action_settled, %{action_id: id, status: "executed"}},
        %{status: :awaiting_approval, reentrega: true, reentrega_push_id: id} = state
      )
      when not is_nil(id),
      do: {:noreply, entregar_reentrega(state)}

  def handle_info(
        {:action_settled, %{action_id: id}},
        %{status: :awaiting_approval, reentrega: true, reentrega_push_id: id} = state
      )
      when not is_nil(id) do
    {:noreply,
     bloquear_reentrega(
       state,
       "a reentrega do conflito não foi aprovada",
       "o push da branch integrada com a main foi negado ou falhou; o gate não reabre",
       "politica",
       ExplicacaoDoBloqueio.de(:push_nao_aprovado)
     )}
  end

  def handle_info({:action_settled, _}, state), do: {:noreply, state}

  # AT-1001b: a reentrega já foi disparada pelo claim (`AgentIo`); este é o
  # aviso do outbox que chegou depois, descartado uma vez.
  def handle_info(
        {:merge_conflict, %{task_id: task_id} = conflito},
        %{conflito_ja_tratado: tratados} = state
      )
      when is_map_key(tratados, task_id) and not is_map_key(conflito, :via_claim),
      do: {:noreply, %{state | conflito_ja_tratado: Map.delete(tratados, task_id)}}

  # AT-844 (RN-715) / AT-1001: o merge da PR foi recusado por conflito e a api
  # devolveu a task (`in_progress`). Livre, o Noop REENTREGA como o agente real,
  # sem LLM: readota a branch e, se o único conflito é o arquivo dele, o reescreve
  # e propõe commit + push (`reentregar_conflito/3`). Sem o guard da AT-907
  # (mensagem atrasada depois de outro merge): aceitável no dublê.
  # Ocupado: tenta de novo, como o real (a entrega do `Wake` é at-most-once).
  def handle_info({:merge_conflict, _} = msg, %{status: status} = state)
      when status in [:working, :awaiting_gate, :awaiting_approval] do
    Process.send_after(self(), msg, @reentrega_do_conflito_ms)
    {:noreply, state}
  end

  def handle_info({:merge_conflict, %{task_id: task_id} = conflito}, %{status: :idle} = state),
    do: {:noreply, reentregar_conflito(state, task_id, conflito)}

  # Disjuntor aberto: não pega trabalho, devolve nomeado. Vai direto à api, sem
  # `block_task/4`: o `task_id` do wake não é o do estado.
  def handle_info({:merge_conflict, %{task_id: task_id} = conflito}, state) do
    _ =
      EngineApiClient.mark_task_blocked(
        state.project_id,
        state.session_id,
        task_id,
        "conflito de merge: o NoopDevAgent não readota a branch",
        "o merge da PR foi recusado por conflito com a main (#{Enum.join(Map.get(conflito, :conflicting_files, []), ", ")}); " <>
          "o agente está com o disjuntor aberto e não reentrega",
        state.agent_id,
        "codigo",
        ExplicacaoDoBloqueio.de(:conflito_de_merge)
      )

    {:noreply, state}
  end

  # Evento novo do `Wake` não derruba o dublê; o agente real ignora o que não conhece.
  def handle_info(msg, state) do
    Logger.debug("NoopDevAgentServer ignorou #{inspect(msg)}")
    {:noreply, state}
  end

  defp reentregar_conflito(state, task_id, conflito) do
    slug = "task-" <> String.slice(to_string(task_id), 0, 8)
    arquivo = "NOOP-#{slug}.md"
    state = %{state | task_id: task_id}

    adotado =
      case AgentIo.worktree_manager().adopt_integrando(state.project_id, state.agent_id, slug) do
        {:error, {:conflito_de_integracao, wt, arquivos, _}} -> {:ok, wt, arquivos}
        {:ok, wt} -> {:ok, wt, []}
        erro -> erro
      end

    case adotado do
      {:ok, %{path: path, branch: branch}, arquivos} ->
        state = %{state | worktree: path, branch: branch}
        AgentIo.persist(state)

        if Enum.all?(arquivos, &(&1 == arquivo)) do
          reentregar_arquivo(state, arquivo, arquivos)
        else
          bloquear_reentrega(
            state,
            "conflito de merge em arquivo que o NoopDevAgent não resolve",
            "o merge da PR foi recusado por conflito com a main (#{Enum.join(arquivos, ", ")}); " <>
              "o Noop só resolve o próprio #{arquivo}. Aviso original: " <>
              Enum.join(Map.get(conflito, :conflicting_files, []), ", "),
            "codigo",
            ExplicacaoDoBloqueio.de(:conflito_de_merge)
          )
        end

      {:error, reason} ->
        bloquear_reentrega(
          state,
          "não foi possível retomar a branch da PR em conflito",
          inspect(reason),
          "infra",
          ExplicacaoDoBloqueio.de(:retomada_da_branch)
        )
    end
  end

  # Só o arquivo do Noop em conflito: reescrever tira os marcadores e o commit
  # (do sistema) conclui o `MERGE_HEAD`. Sem conflito, só o push.
  defp reentregar_arquivo(state, arquivo, arquivos) do
    AgentIo.emit(state, "dev.working", %{
      agentId: state.agent_id,
      taskId: state.task_id,
      branch: state.branch,
      cause: "merge_conflict"
    })

    commit =
      if arquivos == [] do
        :executed
      else
        File.write!(
          Path.join(state.worktree, arquivo),
          noop_file_content(state, %{"id" => state.task_id})
        )

        AgentIo.propose_commit(state, "#{state.agent_id}: reentrega após conflito de merge")
      end

    {push, push_id} =
      if commit == :executed, do: AgentIo.propose_push_com_id(state), else: {commit, nil}

    case push do
      :executed ->
        entregar_reentrega(state)

      :pending when commit == :executed ->
        # O push nasce `pending` fora do modo automático (RN-689): espera o
        # `action_settled` marcado com `reentrega`.
        state =
          %{state | status: :awaiting_approval}
          |> Map.merge(%{reentrega: true, reentrega_push_id: push_id})

        AgentIo.persist(state)

        AgentIo.emit(state, "dev.awaiting_approval", %{
          agentId: state.agent_id,
          taskId: state.task_id
        })

        state

      _ ->
        bloquear_reentrega(
          state,
          "a reentrega do conflito não executou",
          "commit/push propostos: #{inspect({commit, push})}",
          "infra",
          ExplicacaoDoBloqueio.de(:push_falhou)
        )
    end
  end

  # AT-983: `in_review` ANTES do `open_gate`, como `trigger_gate_recheck/2` do real.
  defp entregar_reentrega(state) do
    _ =
      EngineApiClient.mark_task(
        state.project_id,
        state.session_id,
        state.task_id,
        "in_review",
        state.agent_id
      )

    abrir_gate(state, state.task_id)

    state =
      Map.merge(%{state | status: :awaiting_gate}, %{reentrega: false, reentrega_push_id: nil})

    AgentIo.persist(state)

    AgentIo.emit(state, "dev.awaiting_gate", %{
      agentId: state.agent_id,
      taskId: state.task_id,
      cause: "merge_conflict"
    })

    state
  end

  defp bloquear_reentrega(state, motivo, diagnostico, origem, explicacao) do
    state
    |> AgentIo.block_task(motivo, diagnostico, origem, explicacao)
    |> Map.merge(%{
      task_id: nil,
      worktree: nil,
      branch: nil,
      reentrega: false,
      reentrega_push_id: nil
    })
    |> Map.put(:status, :idle)
    |> try_claim()
  end

  defp abrir_gate(state, task_id) do
    # Sem o `Dispatcher.run_qa/2` do agente real: na validação quem emite o
    # veredito é o script, pelo `RecordGateVerdict` (ADR 0020).
    _ = EngineApiClient.open_gate(state.project_id, state.session_id, task_id, state.agent_id)
    :ok
  end

  defp desfecho("done"), do: :approved
  defp desfecho(:done), do: :approved
  defp desfecho(_), do: :blocked

  # A máquina é a MESMA do agente real (`AgentIo`); só o `run_task/2` difere.
  defp try_claim(state), do: AgentIo.try_claim(state, &run_task/2)

  defp finish_task(state, desfecho), do: AgentIo.finish_task(state, desfecho, &run_task/2)

  # --- Ciclo do NoopDevAgent ---

  defp run_task(state, task) do
    task_id = Map.get(task, "id")
    slug = "task-" <> String.slice(to_string(task_id), 0, 8)

    # task_id entra no state ANTES de montar o worktree: se a criação
    # falhar, a task já foi reivindicada (está `in_progress` na api) e
    # block_task precisa saber qual devolver — senão ela fica órfã, sem
    # dono vivo e invisível pro claim (que só pega `todo`).
    state = Map.put(%{state | task_id: task_id}, :reentrega, false)

    {criado, state} = AgentIo.criar_worktree(state, slug)

    case criado do
      {:ok, %{path: path, branch: branch}} ->
        # Conteúdo trivial (sem LLM) só pra ter um diff.
        File.write!(Path.join(path, "NOOP-#{slug}.md"), noop_file_content(state, task))

        state = %{state | worktree: path, branch: branch}
        AgentIo.persist(state)

        AgentIo.emit(state, "dev.working", %{
          agentId: state.agent_id,
          taskId: task_id,
          branch: branch
        })

        desfechos = [
          AgentIo.propose_commit(state, "#{state.agent_id}: #{task_title(task)}"),
          AgentIo.propose_push(state),
          AgentIo.propose_pr(
            state,
            "#{state.agent_id}: #{task_title(task)}",
            pr_body(state, task)
          )
        ]

        _ =
          EngineApiClient.mark_task(
            state.project_id,
            state.session_id,
            task_id,
            "in_review",
            state.agent_id
          )

        # PR aberta NÃO libera o agente (Fase 12b): o worktree é por AGENTE,
        # não por task, e reivindicar a próxima agora apagaria fisicamente o
        # que o gate ainda precisa ler. Fica retido até o desfecho terminal.
        #
        # Fase 12e: com ação git pendente de aprovação, o estado é
        # `awaiting_approval` — não há PR para gate nenhum julgar.
        status =
          if Enum.all?(desfechos, &(&1 == :executed)),
            do: :awaiting_gate,
            else: :awaiting_approval

        # ABRIR o gate, e não só entrar em `awaiting_gate`. O agente real faz
        # isto em `DevAgentServer.abrir_gate/1`; o Noop marcava a task como
        # `in_review` e parava aí, então `tasks.gate_status` ficava NULL e não
        # havia gate para julgar — `awaiting_gate` sem gate aberto.
        #
        # É a armadilha do achado #10 outra vez, e no mesmo lugar: um defeito
        # sobrevivendo DENTRO do instrumento de medida. A validação da Fase 12
        # travava aqui, esperando um `gate_status` que nunca ia existir.
        #
        # O que NÃO vem junto é o `Dispatcher.run_qa/2` do agente real: quem
        # emite o veredito na validação é o script, pelo `RecordGateVerdict`,
        # justamente para não depender de julgamento de LLM (ADR 0020).
        if status == :awaiting_gate, do: abrir_gate(state, task_id)

        state = %{state | status: status}
        AgentIo.persist(state)

        AgentIo.emit(state, "dev.#{status}", %{
          agentId: state.agent_id,
          taskId: task_id
        })

        state

      {:error, reason} ->
        AgentIo.emit(state, "dev.error", %{agentId: state.agent_id, reason: inspect(reason)})
        # O achado P: saía com `origin: null`. A origem é `codigo` — provider
        # não suportado é limite conhecido do produto, não falha de infra.
        #
        # RN-558 acrescenta UM caso a essa leitura, sem mexer nos outros: a
        # recusa da credencial no runner é `politica`, não `codigo`. Mesmo
        # classificador do `DevAgentServer` — o Noop existe para exercitar ESTE
        # caminho, não uma cópia dele.
        {motivo, origem} = CredencialDeGit.desfecho(reason)

        explicacao =
          if CredencialDeGit.recusada?(reason),
            do: ExplicacaoDoBloqueio.de(:credencial_de_git),
            else: ExplicacaoDoBloqueio.de(:falha_no_worktree)

        AgentIo.block_task(state, motivo, inspect(reason), origem, explicacao)
    end
  end

  defp task_title(task), do: Map.get(task, "title") || Map.get(task, "id")

  defp noop_file_content(state, task) do
    """
    # #{task_title(task)}

    Trabalho do #{state.agent_id} (módulo #{state.module}).

    Arquivo gerado pelo NoopDevAgent — validação da infraestrutura de execução
    (worktree isolado, identidade de commit, pipeline de proposed_actions).
    Sem LLM: o conteúdo é fixo de propósito.
    """
  end

  defp pr_body(state, task) do
    """
    PR aberta pelo **NoopDevAgent** (`#{state.agent_id}`), sem LLM.

    Task: #{task_title(task)} (`#{state.task_id}`)
    Branch: `#{state.branch}`

    Valida worktree isolado, identidade `#{state.agent_id}[bot]` e o pipeline
    de proposed_actions de ponta a ponta. Não passa pelos gates de QA/SecOps.
    """
  end
end
