---
id: rn-engine-parte-07
title: 'Regras de negócio — Engine — parte 7 (desde RN-1076)'
sidebar_label: 'Engine — parte 7 (desde RN-1076)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

# Engine — parte 7 (desde RN-1076)

<a id="rn-1076"></a>

### RN-1076 — As Percepções olham o produto do usuário; a falha da plataforma é sinal interno só no TP-01 {#rn-1076}

> **Revoga a [RN-717](parte-04.md#rn-717)** (a Anamnese não registra mais desvio de agente) e **revisa a [RN-079](parte-01.md#rn-079)** (o material analisável ganha escopo).

- **Regra:** o Psicólogo só emite hipótese sobre o que está sendo construído com o usuário e está errado em relação ao pedido (requisito mal entendido, entrega fora do pedido, regra de negócio do projeto quebrada). Cada item da `emit_hypotheses` traz `escopo` obrigatório (`produto` | `plataforma`). `produto` vira hipótese em Percepções, como antes. `plataforma` (agente ocioso, teto estourado, worktree, validador, ordem de início) nunca vira hipótese: com `sessaoDeTeste` verdadeiro vira `psychologist.platform_signal` no log da sessão (gravado pela api, fora do grafo e da fila da Anamnese); com `sessaoDeTeste` falso o prompt manda ignorá-lo e a api o descarta sem evento. O engine lê `sessaoDeTeste` (booleano) do contexto que a api devolve (`projects.sessao_de_teste`; ausente vale `false`), não cria flag de ambiente e o repassa no corpo do POST das hipóteses. Lote vazio é válido. `terminationAnalysis` só é exigida em sessão de teste com término anormal; fora dela o bloco de término some do prompt. O kickoff do Psicólogo vai à v4 e o inline do worker segue byte a byte igual ao template.
- **Por quê:** TP-01 28ª (10/11): as 8 hipóteses do Psicólogo foram todas sobre a plataforma e nenhuma disse se o app do usuário estava sendo construído errado (achado 34). A falha técnica é do TP-01, não da Anamnese nem do Psicólogo.
- **Onde:** `prompts/psychologist-kickoff.md` (v4), `apps/engine/lib/engine/workers/psychologist_worker.ex:311` (`render_inline`), `apps/engine/lib/engine/workers/psychologist_worker.ex:299` (`render_template`), `apps/engine/lib/engine/workers/psychologist_worker.ex:356` (`escopo_instruction`), `apps/engine/lib/engine/workers/psychologist_worker.ex:367` (`termination_instruction`), `apps/engine/lib/engine/workers/psychologist_worker.ex:230` (`build_ctx`), `apps/engine/lib/engine/psychologist/context_builder.ex:83` (`build`), `apps/engine/lib/engine/psychologist/tools/emit_hypotheses.ex:22` (`spec`), `apps/engine/lib/engine/psychologist/tools/emit_hypotheses.ex:99` (`run`), `apps/engine/lib/engine/sessions/engine_api_client.ex:1858` (`propose_hypotheses`); a regra de lote e o evento ficam na api, em [`propose-hypotheses.use-case.ts`](https://github.com/viralabs-dev/brabo-api/blob/dev/src/application/use-cases/execution/propose-hypotheses.use-case.ts) ([ADR 0288](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0288-link-entre-repos-nas-rns-e-url-do-repo-dono.md)).
- **Teste:** `apps/engine/test/engine/psychologist/tools/emit_hypotheses_test.exs` ("`escopo` é obrigatório e só aceita produto ou plataforma", "lista vazia é aceita", "sessaoDeTeste do ctx é repassado"), `apps/engine/test/engine/workers/psychologist_worker_test.exs` (describe "RN-1076": critério de produto, sinal ligado, sinal desligado, "template do repo e inline renderizam o MESMO texto"), `apps/engine/test/engine/anamnese/tools_test.exs` (`refute "report_agent_deviation"`), `apps/engine/test/engine/workers/anamnese_worker_test.exs` ("o kickoff (inline e template v5) não manda mais registrar desvio do agente").
- **Origem:** AT-898, decisões do dono de 10/11/2026 (achado 34 do TP-01 28ª) e escolha da marcação por flag no projeto (11/11). Revoga a RN-717 e revisa a RN-079 (ADR 0291).

<a id="rn-1077"></a>

### RN-1077 — A task reivindicada parte da PRÓPRIA branch quando ela tem trabalho fora da `main` {#rn-1077}

> **Revisa a [RN-760](parte-05.md#rn-760)** (a `base_preservada` de outra task só vale quando a task não tem branch própria) e **estende a [RN-779](parte-05.md#rn-779)** (o caso "própria branch" deixa de exigir `base == main`).

- **Regra:** a task que o agente reivindica parte da PRÓPRIA branch `feature/<slug>`, local ou em `origin/`, sempre que ela não é ancestral da ponta da `main`, mesmo quando o agente traz a branch preservada de OUTRA task (`base_preservada`, RN-743). Antes o `worktree add -B` redefinia a branch própria em cima da base alheia e o commit já enviado ao bare saía do histórico local: o push seguinte era recusado (non-fast-forward) e o gate julgava um commit diferente do que o merge usaria.
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:464` (`retomada`), `apps/engine/lib/engine/dev/worktree_manager.ex:338` (`add_worktree`)
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs` ("a branch própria com commit no remoto vence a base_preservada de outra task, e o push segue"); mutação provada: voltar a condição para `base == main` reprova o teste.
- **Origem:** AT-911 (TP-01 28ª, achado 21), Rodada 365, lane X1.

<a id="rn-1078"></a>

### RN-1078 — O gate só abre com commit e push executados e o HEAD igual ao do remoto {#rn-1078}

> **Revisa a [RN-664](parte-04.md#rn-664)** (o gate julga o diff da PR: agora a PR é o que está no remoto) e **a [RN-715](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-715)** (a correção pós-conflito não reabre o gate às cegas).

- **Regra:** na entrega e na correção, o gate (QA, ou o recomeço da RN-715) só abre depois de `git_commit` e `git_push` com desfecho `executed` e com o HEAD do worktree igual a `origin/<branch>` (`head_igual_ao_remoto/2`, sem `fetch`: o push atualiza a ref e o push recusado a deixa velha). Push `refused` bloqueia a task com o motivo nomeado e origem `infra`, sem abrir PR nem gate; `pending` espera a aprovação (`awaiting_approval`); HEAD diferente do remoto bloqueia "o worktree e a branch do remoto divergem" com os dois SHAs. Sem a ref do remoto (branch nunca enviada) ou sem worktree local (modo `runner`) a guarda não bloqueia: quem recusa é o desfecho da ação.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:939` (`handle_correction_outcome`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1313` (`with_head_no_remoto`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1331` (`entregar`), `apps/engine/lib/engine/dev/worktree_manager.ex:511` (`head_igual_ao_remoto`)
- **Teste:** `apps/engine/test/engine/dev/conflito_e_push_test.exs` (push recusado na entrega e na correção bloqueia e não chama o QA; pendente espera), `apps/engine/test/engine/dev/worktree_manager_test.exs` ("a guarda: HEAD à frente do remoto diverge"); mutação provada: tirar o `:refused` do bloqueio reprova o teste.
- **Origem:** AT-911, Rodada 365, lane X1.

<a id="rn-1079"></a>

### RN-1079 — O `wip` de preservação não enviado é absorvido pelo commit da task {#rn-1079}

> **Estende a [RN-743](parte-05.md#rn-743)** (o commit `wip` continua sendo como o trabalho sobrevive ao bloqueio).

- **Regra:** o commit `wip(<agente>): trabalho preservado…` que ainda não está em `origin/<branch>` é desfeito (`reset --soft HEAD~1`, em laço, só no topo e sem merge em curso) antes do `GitExecutor.commit/1`; o trabalho entra no commit real da task e o `wip` não chega à PR nem à `main`. Um `wip` já enviado fica: tirá-lo exigiria push forçado.
- **Onde:** `apps/engine/lib/engine/actions/git_executor.ex:18` (`commit`), `apps/engine/lib/engine/actions/git_executor.ex:53` (`absorver_wip_nao_enviado`)
- **Teste:** `apps/engine/test/engine/actions/git_executor_test.exs` ("o wip não enviado é absorvido: um commit só…", "o wip já enviado fica"); mutação provada: remover a chamada reprova o teste.
- **Origem:** AT-911 (o `wip` entrou na `main` pela PR #12), Rodada 365, lane X1.

<a id="rn-1080"></a>

### RN-1080 — A branch presa no worktree de outro dev agent é liberada, e o conflito reentregue só retrabalha task viva {#rn-1080}

> **Revisa a [RN-715](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-715)** (a reentrega do conflito confere a task antes de readotar) e **estende a [RN-743](parte-05.md#rn-743)** (a preservação também vale para o worktree de OUTRO agente).

- **Regra (AT-915):** quando `feature/<slug>` da task reivindicada está presa no worktree de outro dev agent em `.worktrees/<outro>`, o engine preserva o que esse worktree tem sem commit (`wip`, RN-743) e o remove antes de criar o próprio. A task desbloqueada nunca bloqueia por "branch em uso". A branch presa fora de `.worktrees/` (o checkout do usuário) segue recusada pelo git, com a branch no motivo. Declarado: no modo `runner` a regra não roda.
- **Regra (AT-907):** o `{:merge_conflict, _}` só inicia o retrabalho se a task, lida na api no momento da entrega, ainda está `in_progress` com este agente. Se a PR entrou por outro merge (`done`), ou a task mudou de estado ou de dono, o conflito é descartado com `dev.conflict_rework_dropped` (`taskId`, `motivo`) e o agente segue para a fila. Vale também para o agente com disjuntor aberto, que não bloqueia mais task `done`.
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:482` (`liberar_branch_presa`), `apps/engine/lib/engine/dev/dev_agent_server.ex:354` (`handle_info`), `apps/engine/lib/engine/dev/dev_agent_server.ex:451` (`motivo_do_descarte`), `apps/engine/lib/engine/dev/dev_agent_server.ex:474` (`retrabalhar_conflito`)
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs` ("AT-915: a branch presa no worktree de outro agente é preservada…", "…fora de .worktrees segue recusada"), `apps/engine/test/engine/dev/conflito_e_push_test.exs` (a corrente: ocupado adia, a PR entra, a reentrega é descartada; outro dono; regressão in_progress; disjuntor); mutação provada: tirar a liberação ou o descarte reprova um teste cada.
- **Origem:** AT-915 (achado 27) e AT-907 (achado 16), Rodada 365, lane X1.

<a id="rn-1099"></a>

### RN-1099 — O merge da PR de infra faz a Infra propor de novo a subida do container {#rn-1099}

> **Estende a [RN-671](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-671)** (a subida pelo servidor deixa de existir só no kickoff) **e a [RN-672](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-672)** (o Dev Lead é oferecido também depois desse merge).

- **Regra (AT-899):** o `project.trunk_merged` ganha um segundo consumidor, o `InfraOfereceDevLeadWorker`, que avisa `{:trunk_merged, project_id}` no tópico do projeto. O Infra Lead vivo, sem turno em curso, lê o container registrado: `running` oferece o Dev Lead (`if_absent`); `provisioning` não faz nada; qualquer outro estado repete o passo `subir_no_aceite/2` (mesma `propor_container_start/2`, mesmas recusas). Se a proposta não nasce (sem roteamento, modo `runner`, recusa), o fio diz o próximo passo (pedir a subida ou usar a página Containers). Com turno em curso nada é feito: o fecho do turno já pergunta. Entrega at-most-once, como a RN-672.
- **Por quê:** TP-01 28ª (achados 3 e 4): a PR de infra entrou sem subida e a corrente parou até o usuário escrever; o "aguardando" ficou sem pergunta nem botão.
- **Onde:** `lib/engine/outbox/drain.ex:116` (`handlers_for`), `lib/engine/workers/infra_oferece_dev_lead_worker.ex:29` (`perform`), `lib/engine/infra/infra_lead_server.ex` (`handle_info({:trunk_merged, _}, _)`, `ao_merge_da_pr_de_infra`).
- **Teste:** `test/engine/infra/infra_lead_server_test.exs` (três casos "RN-1099"), `test/engine/workers/infra_oferece_dev_lead_worker_test.exs`, `test/engine/outbox/drain_test.exs` ("project.trunk_merged enfileira o TrunkMergedWorker e o aviso à Infra").
- **Origem:** AT-899 (parte do engine), Rodada 366, lane EB.

<a id="rn-1100"></a>

### RN-1100 — A Infra escreve na raiz o índice "Módulos" {#rn-1100}

> **Estende a [RN-846](parte-05.md#rn-846)** (a rota de negócio mora no README do módulo, regra do kickoff do dev, na lane EA).

- **Regra (AT-903):** o kickoff da Infra manda escrever no `README.md` da raiz, além de "Rodar na sua máquina", uma seção "Módulos" com um link para o `modules/<m>/README.md` de cada módulo do `module_map`. A raiz deixa de ser tocada pelas tarefas, o que evita o conflito de merge entre módulos paralelos. Sem gerador: o índice é escrito uma vez, na PR de infra.
- **Onde:** `lib/engine/infra/infra_lead_server.ex` (`build_kickoff`, item 3).
- **Teste:** `test/engine/infra/infra_lead_server_test.exs` ("o kickoff pede o índice Módulos").
- **Origem:** AT-903 (parte da Infra), Rodada 366, lane EB.

<a id="rn-1086"></a>

### RN-1086 — O dev ocioso volta a procurar tarefa sozinho, e a execução parada tenta o claim de novo {#rn-1086}

> **Generaliza a [RN-1009](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-1009)** (todo `done`, não só o merge, acorda os dependentes: a api grava `task.became_claimable` com `cause` `dependency_done` ou `plan_applied`, e o `DevAgentWakeWorker` já o entrega) e **a [RN-047](parte-01.md#rn-047)** (o rearm de agente fora de `idle_tripped` segue 409).

- **Regra:** o claim vazio deixa o agente `:idle` e agenda a PRÓXIMA procura em `procura_ociosa_ms/0` (60 s, configurável), pela mesma mensagem do wake (`{:wake, :became_claimable}`); um timer por agente, que o wake externo substitui. Na re-tentativa o agente já está anunciado (`idle_anunciado`): sem `dev.idle`, sem persist e sem reagendar a checagem da parada, para não inundar o fio. O `ExecucaoParadaWorker` entrega o mesmo wake a todo agente `idle` da sessão antes de avaliar (re-tentar é inofensivo: o guard em processo decide). `POST /internal/sessions/:sessionId/dev-agents/:agentId/wake` responde 202 com o agente `idle`, 409 nomeado nos outros status e 404 se não existe (a api repassa o 409 e grava `dev.wake_requested`, que entra no `@movimento` da parada). O Dev Lead ganha `procurar_tarefa(agent_id)`: wake direto se `idle`, senão diz o status.
- **Onde:** `apps/engine/lib/engine/dev/agent_io.ex:219` (`sem_task_pegavel`), `apps/engine/lib/engine/dev/agent_io.ex:241` (`procura_ociosa_ms`), `apps/engine/lib/engine_web/controllers/execution_command_controller.ex:121` (`wake`), `apps/engine/lib/engine/workers/execucao_parada_worker.ex:124` (`reprocurar`), `apps/engine/lib/engine/agents/dev_lead_tools.ex:503` (`run_procurar_tarefa`)
- **Teste:** `apps/engine/test/engine/dev/dev_agent_chain_test.exs` (a corrente: dependência aberta → ocioso → `mark_task done` → outbox `task.became_claimable` → drain → wake → claim; e o timer sozinho, sem `dev.idle` repetido), `apps/engine/test/engine_web/controllers/execution_command_controller_test.exs` (wake 202/409/404), `apps/engine/test/engine/workers/execucao_parada_worker_test.exs`, `apps/engine/test/engine/agents/dev_lead_tools_test.exs`; mutação provada: tirar o `agendar_procura` reprova o teste do timer.
- **Origem:** AT-906 (TP-01 28ª, achados 15, 17 e 25), Rodada 366, lane X2a.

<a id="rn-1087"></a>

### RN-1087 — A tarefa nasce com o módulo, e o Dev Lead arquiva a tarefa `todo` que ele criou {#rn-1087}

> **Estende a [RN-1006](parte-06.md#rn-1006)** (o `module` do Dev Lead passa a ser gravado) e **a RN-727** (`archive_story`, na api) (arquivar, agora também a tarefa).

- **Regra:** o `Engine.Harness.Tools.CreateTask.run/2` envia `fields.module` quando o `module` vem nos argumentos (antes o descartava e a tarefa nascia órfã). A ferramenta `arquivar_tarefa(task_id, motivo)` do Dev Lead chama `POST /internal/sessions/:sessionId/tasks/:taskId/archive` com `{projectId, reason}`; o motivo é obrigatório (vazio é recusado sem chamar a api) e a api só arquiva `todo` criada por ele (409 nomeado `tarefa_em_execucao`, `tarefa_arquivada` ou `tarefa_de_outro_autor`, que volta ao modelo). `ExecucaoParadaWorker.pendentes/1` ignora tarefa com `archivedAt`.
- **Onde:** `apps/engine/lib/engine/harness/tools/create_task.ex:52` (`put_module`), `apps/engine/lib/engine/agents/dev_lead_tools.ex:464` (`run_arquivar_tarefa`), `apps/engine/lib/engine/sessions/engine_api_client.ex:1428` (`archive_task`), `apps/engine/lib/engine/workers/execucao_parada_worker.ex:112` (`pendentes`)
- **Teste:** `apps/engine/test/engine/agents/dev_lead_tools_test.exs` (o `create_task` envia `module`; arquivar com motivo, sem motivo e com recusa nomeada), `apps/engine/test/engine/workers/execucao_parada_worker_test.exs` (a parada não conta tarefa arquivada); mutação provada: tirar o `put_module` reprova o teste.
- **Origem:** AT-912 (TP-01 28ª, achado 22), Rodada 366, lane X2a.

<a id="rn-1088"></a>

### RN-1088 — A execução parada nomeia o ciclo entre o bloqueio e o `dependsOn` {#rn-1088}

> **Estende a [RN-1059](parte-06.md#rn-1059)** (motivo novo da parada) e **a [RN-1012](parte-06.md#rn-1012)** (o caminho até o Arquiteto é o `pedir_ao_arquiteto`).

- **Regra:** quando uma tarefa bloqueada do módulo Y cita, no `blockedReason`, um módulo X que depende de Y (direta ou transitivamente, pelo `module_map` vigente lido em `get_infra_context`), o `execution.stalled` traz `ciclosDeDependencia: [{taskId, modulo: Y, esperaPor: X}]`. A citação é `modules/X`, `dev-X` ou `X` com borda (`x-y` não cita `x`). O aviso ao Dev Lead diz "IMPASSE de dependência" e que só o contrato ou o `dependsOn` mudando destrava: leve ao Arquiteto com `pedir_ao_arquiteto`, em vez de repropor o plano. Sem canal novo.
- **Onde:** `apps/engine/lib/engine/workers/execucao_parada_worker.ex:136` (`ciclos_de_dependencia`), `apps/engine/lib/engine/workers/execucao_parada_worker.ex:165` (`ciclos`), `apps/engine/lib/engine/agents/dev_lead_server.ex:381` (`aviso_de_ciclo`)
- **Teste:** `apps/engine/test/engine/workers/execucao_parada_worker_test.exs` (ciclo direto, transitivo, sem ciclo, e a corrente até o Dev Lead), `apps/engine/test/engine/agents/dev_lead_server_test.exs` (o aviso manda `pedir_ao_arquiteto`).
- **Origem:** AT-913 (TP-01 28ª, achado 25), Rodada 366, lane X2a. O id de tarefa como citação ficou fora: só o nome do módulo.

<a id="rn-1089"></a>

### RN-1089 — A falha de reinício da app depois do merge avisa o Dev Lead com motivo, código e o caminho do log {#rn-1089}

> **Estende a [RN-1028](parte-06.md#rn-1028)** (o desfecho do reinício vai à linha do tempo, sem trecho de log).

- **Regra:** `app.restart_failed` continua com `motivo` e `exitCode` (allowlist) e ganha `log: "/tmp/brabo-app.log"` (o caminho no container); o TEXTO do log nunca entra no evento nem no aviso, porque o comando do app pode carregar segredo. A falha também entrega `{:app_falhou, %{motivo, exitCode}}` ao Dev Lead, que abre turno com "[Aviso do sistema]" mandando criar a tarefa de correção no módulo dono e pedir ao dev que leia o log no container. O reinício bem-sucedido não acorda ninguém.
- **Onde:** `apps/engine/lib/engine/workers/reiniciar_app_worker.ex:62` (`falhou`), `apps/engine/lib/engine/agents/dev_lead_server.ex:372` (`aviso_de_app`), `apps/engine/lib/engine/agents/dev_lead_server.ex:416` (`handle_info`)
- **Teste:** `apps/engine/test/engine/workers/reiniciar_app_worker_test.exs` (a falha acorda o Dev Lead e o payload não tem o texto do log; o sucesso não acorda), `apps/engine/test/engine/agents/dev_lead_server_test.exs` (o aviso abre turno com motivo, código e caminho).
- **Origem:** AT-914 (TP-01 28ª, achado 24), Rodada 366, lane X2a. Troca o "fim do stderr" por "onde ler" (regra transversal de segredo).

<a id="rn-1090"></a>

### RN-1090 — O teto de gasto por tarefa vale para os dev agents vivos, e a memória nunca sobrescreve um teto mais novo {#rn-1090}

> **Estende a [RN-036](parte-01.md#rn-036)** (o teto por tarefa do agente); o campo na tela e o `PATCH` do projeto são da api e do web.

- **Regra:** `POST /internal/projects/:projectId/execution/task-budget` com `{taskBudgetMicros}` (inteiro positivo, senão 400) grava o teto em toda linha `dev_agent_states` do projeto e troca `task_budget_micros` na memória de cada agente vivo (`DevAgentSupervisor.atualizar_teto/2`, por `:sys.replace_state`, sem handler novo no server real nem no Noop). O `start` sobre agente já vivo (`:existing`) com `taskBudgetMicros` faz o mesmo. A tarefa em curso mantém o teto com que o laço começou; o novo vale a partir da próxima volta (desbloqueio, correção ou tarefa nova), e o `persist` seguinte não devolve o valor velho ao banco. Quem chama é a api, ao mudar o teto do projeto.
- **Onde:** `apps/engine/lib/engine_web/controllers/execution_command_controller.ex:140` (`task_budget`), `apps/engine/lib/engine/dev/dev_agent_supervisor.ex:75` (`atualizar_teto`), `apps/engine/lib/engine/dev/dev_agent_state.ex:83` (`set_teto`)
- **Teste:** `apps/engine/test/engine_web/controllers/execution_command_controller_test.exs` (o teto vai ao banco e à memória, e o `persist` seguinte o mantém; 400; o `start` sobre agente vivo); mutação provada: tirar o `trocar_na_memoria` reprova o teste do `persist`.
- **Origem:** AT-917 (TP-01 28ª, achado 29), Rodada 366, lane X2a. Parte do engine; a api chama a rota depois (lane posterior).

<a id="rn-1093"></a>
### RN-1093 — O Arquiteto lê a `main` antes de declarar o contrato, e `declare_module_contracts` a confere {#rn-1093}

- **Regra (AT-918):** o Arquiteto tem `read_file` e `search_workspace`, que sem `workspace_root` leem a pasta do projeto, isto é, a `main` mergeada (RN-1021), e o prompt manda lê-la antes de declarar. `declare_module_contracts` confere cada item `funcao` contra essa pasta e devolve, no resultado, as funções que a `main` não tem hoje. Não recusa (contrato pode declarar interface futura). Pasta invisível ao engine (modo `runner`) devolve "Não conferi o código".
- **Onde:** `lib/engine/harness/contrato_contra_o_codigo.ex` (`texto_do_codigo`), `lib/engine/harness/tools/declare_module_contracts.ex` (`conferencia_com_codigo`), `lib/engine/agents/arquiteto_server.ex` (`tool_specs`, `run_tool`)
- **Teste:** `test/engine/harness/tools/declare_module_contracts_test.exs` ("função que a main não tem volta nomeada…", "pasta invisível…"), `test/engine/agents/arquiteto_server_test.exs` (catálogo)
- **Origem:** AT-918 (achado 31 do TP-01 28ª), Rodada 366, lane X2b.

<a id="rn-1094"></a>
### RN-1094 — Mudar o contrato lista as tarefas afetadas, e o Arquiteto as corrige no mesmo turno {#rn-1094}

- **Regra (AT-918):** ao declarar uma versão nova, o resultado lista as tarefas não concluídas (`todo`/em curso, não arquivadas) cujo título ou descrição cita função ou rota que a versão anterior tinha e a nova tirou ou mudou. O Arquiteto as corrige com `update_task` (RN-1068, que recusa tarefa em execução). Arquivar a que perdeu o sentido depende da ferramenta da AT-912; o texto só a oferece "quando houver no catálogo".
- **Onde:** `lib/engine/harness/contrato_contra_o_codigo.ex` (`texto_das_tarefas`), `lib/engine/harness/tools/declare_module_contracts.ex` (`versao_anterior`)
- **Teste:** `test/engine/harness/tools/declare_module_contracts_test.exs` ("tarefa não concluída que cita interface retirada…")
- **Origem:** AT-918, Rodada 366, lane X2b.

<a id="rn-1116"></a>
### RN-1116 — O parecer do QA separa `itens` (bloqueia) de `melhorias` (não bloqueia) {#rn-1116}

> **Estende a [RN-944](parte-06.md#rn-944)** (o QA não move a régua) e a RN-015 (a contagem de correção só considera `itens`).

- **Regra (AT-905):** `emit_qa_verdict` ganha `melhorias` (lista de texto, opcional). `itens` é SÓ o que viola regra da história, critério da tarefa ou regra do recorte; o resto é melhoria e não reprova nem conta correção. O campo atravessa o hook de término, o consolidador (`QaLead`), o artefato `qa_verdict` e a chamada `gates/verdict` (só quando não vazio, no corpo como `melhorias`, para a api publicá-las no comentário da PR). O prompt da Automação e o recorte dizem a separação.
- **Onde:** `lib/engine/gates/tools/emit_qa_verdict.ex` (`spec`), `lib/engine/gates/hooks/termination.ex` (`call`), `lib/engine/gates/qa_lead.ex` (`melhorias_de`), `lib/engine/gates/qa_lead_server.ex` (`extras_de_melhorias`), `lib/engine/gates/qa_automacao_agent.ex` (`initial_message`)
- **Teste:** `test/engine/gates/qa_lead_test.exs` ("melhorias acompanham…"), `test/engine/gates/tools/emit_qa_verdict_test.exs`
- **Origem:** AT-905 (achados 14 e 30 do TP-01 28ª), Rodada 367, lane gates.

<a id="rn-1117"></a>
### RN-1117 — `changes_requested` sem item bloqueante é recusado {#rn-1117}

- **Regra (AT-905):** a ferramenta recusa `changes_requested` com `itens` vazio ("aprove e liste as melhorias"). A recusa é resultado de ferramenta, entrada do laço (RN-163).
- **Onde:** `lib/engine/gates/tools/emit_qa_verdict.ex` (`run`)
- **Teste:** `test/engine/gates/tools/emit_qa_verdict_test.exs` ("recusa changes_requested sem itens")
- **Origem:** AT-905, Rodada 367, lane gates.

<a id="rn-1118"></a>
### RN-1118 — Numa volta nova, item novo só reprova se trata de arquivo do diff da volta {#rn-1118}

> **Estende a [RN-944](parte-06.md#rn-944)**: a régua que era só de prompt passa a ser conferida por código.

- **Regra (AT-905):** `itens` aceita texto ou `{texto, origem}` (`anterior` | `regressao_no_diff`). Com pedido anterior, o `QaLeadServer` confere cada item `regressao_no_diff` contra os arquivos alterados desde o `headAvaliado` da volta anterior (gravado no `qa_verdict`, `git diff --name-only <head>..HEAD`). Item sem arquivo do diff vai para `melhorias`, com aviso no `resumo`, e não reprova; se todos os itens saem, o parecer vira `approved`. Sem head conhecido, nada é conferido.
- **Onde:** `lib/engine/gates/itens_do_parecer.ex` (`aplicar`), `lib/engine/gates/qa_lead_server.ex` (`tratar_resultado`, `arquivos_da_volta`, `pedido_anterior`)
- **Teste:** `test/engine/gates/itens_do_parecer_test.exs`, `test/engine/gates/qa_lead_server_test.exs` ("a volta nova não move a régua")
- **Origem:** AT-905, Rodada 367, lane gates.

<a id="rn-1119"></a>
### RN-1119 — Requisito de execução que contradiz o contrato é observação, e o ponto de entrada é o da aplicação {#rn-1119}

> **Revisa a [RN-786](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-786)** (a divergência de nome já era observação; passa a valer para a execução) e a [RN-813](parte-05.md#rn-813).

- **Regra (AT-909):** o recorte exige que o ponto de entrada REAL que sobe seja o da APLICAÇÃO (o `run.app`/compose), não o `start` de cada módulo. Módulo que o contrato diz ser composto por outro (dependência injetada) não precisa subir sozinho: exigir isso é observação no `resumo`, nunca item.
- **Onde:** `lib/engine/gates/recorte_da_tarefa.ex` (`secao_do_ponto_de_entrada`, `secao_do_contrato`)
- **Teste:** `test/engine/gates/recorte_da_tarefa_test.exs` ("AT-909: o ponto de entrada é o da aplicação…")
- **Origem:** AT-909 (achado 19), Rodada 367, lane gates.

<a id="rn-1120"></a>
### RN-1120 — O parecer de QA que a api guarda no bloqueio por teto leva os itens {#rn-1120}

- **Regra (AT-909):** o engine sempre manda à api os `itens` como lista de texto (nunca objetos) e grava no `artifact.qa_verdict` os campos `itens`, `melhorias` e `headAvaliado`, que são a fonte do Dev Lead e da orientação do Desbloquear. O bloqueio por "ciclo de correção esgotado" grava como diagnóstico o `resumo` mais os `itens` (parte da api, outra lane).
- **Onde:** `lib/engine/gates/qa_lead_server.ex` (`aplicar`, `emit_parecer_interno`), `lib/engine/gates/itens_do_parecer.ex` (`textos`)
- **Teste:** `test/engine/gates/qa_lead_server_test.exs` ("o artefato qa_verdict leva itens, melhorias e headAvaliado")
- **Origem:** AT-909, Rodada 367, lane gates.

<a id="rn-1121"></a>
### RN-1121 — Entrega que toca manifesto ou build, ou a última tarefa, é provada num clone limpo {#rn-1121}

> **Revisa a [RN-817](parte-05.md#rn-817)** (o ambiente limpo limpava processos, não artefatos de build) e a [RN-935](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-935).

- **Regra (AT-921):** quando a entrega altera `package.json`, lockfile, `Dockerfile`, `docker-compose*.yml` ou `tsconfig*.json`, ou é a última tarefa pendente (irmãs `done` e nenhuma tarefa aberta no módulo), o `QaLeadServer` prepara `.brabo-qa/clone-limpo/` com `git archive HEAD` (sem `node_modules`, `dist` nem arquivo não versionado), sem Docker e sem LLM extra. O recorte manda instalar, compilar, testar e subir o app ali, conferindo `/docs` e `/openapi.json`. Nas demais tarefas nada muda. Se o clone não puder ser preparado, o recorte diz e isso não reprova.
- **Onde:** `lib/engine/gates/clone_limpo.ex` (`disparar?`, `preparar`), `lib/engine/gates/qa_lead_server.ex` (`clone_limpo`), `lib/engine/gates/recorte_da_tarefa.ex` (`secao_do_clone_limpo`)
- **Teste:** `test/engine/gates/clone_limpo_test.exs` (corrente com git de verdade), `test/engine/gates/recorte_da_tarefa_test.exs`
- **Origem:** AT-921 (achado 35), Rodada 367, lane gates.

<a id="rn-1122"></a>
### RN-1122 — O QA confere a rota no README do módulo, não no da raiz {#rn-1122}

> **Revisa a [RN-850](parte-05.md#rn-850) e a [RN-854](parte-05.md#rn-854)** no lado do recorte.

- **Regra (AT-903):** o recorte confere a seção "Rotas HTTP" do README da pasta do módulo da tarefa, e cada rota dela precisa estar no `/openapi.json` servido. Rota que só está no README da raiz não é exigida e não reprova. O kickoff do dev que manda a rota para o README do módulo é de outra lane.
- **Onde:** `lib/engine/gates/recorte_da_tarefa.ex` (`texto`, `secao_do_ponto_de_entrada`)
- **Teste:** `test/engine/gates/recorte_da_tarefa_test.exs` ("AT-903: o QA confere o README do módulo")
- **Origem:** AT-903 (achado 11), Rodada 367, lane gates.

<a id="rn-1123"></a>
### RN-1123 — No clone limpo, falha de passo é item, falha de rede é `infra`, e o compose real segue observação {#rn-1123}

> **Revisa a [RN-813](parte-05.md#rn-813) e a [RN-854](parte-05.md#rn-854)** (o compose como observação).

- **Regra (AT-921):** instalação, build, suíte e subida a partir do clone limpo que falham são `itens`. Falha de REDE (registry inacessível) tem origem `infra` e vai ao `resumo`, não reprova. O build da imagem e o `docker compose up` real continuam observação ("provado só na máquina do usuário"): a instância de QA não tem Docker e o broker não faz build.
- **Onde:** `lib/engine/gates/recorte_da_tarefa.ex` (`secao_do_ponto_de_entrada`, `secao_do_clone_limpo`)
- **Teste:** `test/engine/gates/recorte_da_tarefa_test.exs` ("AT-921: a seção do clone limpo…")
- **Origem:** AT-921, Rodada 367, lane gates.

<a id="rn-1130"></a>
### RN-1130 — Com a execução ativa, `propose_execution_plan` propõe só as tarefas restantes {#rn-1130}

- **Regra (AT-910):** com agentes do projeto vivos (`dev_agent_states`), a ferramenta descarta de `tarefas` as que o backlog diz `done`, `in_progress` ou `in_review` e as que já têm o mesmo módulo. Sobrando alguma, propõe só essas, com o `resumo` "plano das tarefas restantes (N)". Sem sobra, recusa com "NÃO reproponha: diga ao usuário o que destrava". Falha de leitura (banco ou backlog) não recusa, como a RN-792. Estende as RN-677 e RN-678.
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`restantes_e_conferir`, `execucao_ativa?`, `ja_resolvida?`)
- **Teste:** `test/engine/agents/dev_lead_nao_repropoe_test.exs`
- **Origem:** AT-910, Rodada 368, lane Dev Lead.

<a id="rn-1131"></a>
### RN-1131 — O backlog lido pelo Dev Lead lista os módulos entregues {#rn-1131}

- **Regra (AT-910):** o `tarefas_do_backlog` (kickoff e `read_backlog`) acrescenta "ENTREGUE: módulo X (n tarefa(s) done, na main)" para o módulo cujas tarefas estão todas `done`, sem listá-las, para ele não recriar fundação.
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`modulos_entregues`)
- **Teste:** `test/engine/agents/dev_lead_nao_repropoe_test.exs` ("ENTREGUE")
- **Origem:** AT-910, Rodada 368, lane Dev Lead.

<a id="rn-1132"></a>
### RN-1132 — O contrato novo e a parada não pedem replano, e a recusa sem motivo gera uma pergunta {#rn-1132}

- **Regra (AT-910):** o aviso de contrato (RN-1012) manda criar a tarefa no módulo dono e NÃO repropor o plano com a execução ativa; o aviso de parada (RN-1059) também proíbe repropor. A recusa do plano SEM motivo volta ao Dev Lead com "pergunte UMA vez ao usuário o que mudar antes de propor de novo". Com motivo, o texto segue como antes.
- **Onde:** `lib/engine/agents/dev_lead_server.ex` (`aviso_de_contrato`, `aviso_de_parada`, `texto_do_desfecho`, `pergunta_apos_recusa`)
- **Teste:** `test/engine/agents/dev_lead_server_test.exs` ("contrato_publicado…", o kickoff)
- **Origem:** AT-910, Rodada 368, lane Dev Lead.

<a id="rn-1133"></a>
### RN-1133 — A fundação do primeiro módulo cria a raiz do workspace {#rn-1133}

- **Regra (AT-921):** com mais de um módulo no mesmo runtime, o kickoff manda a fundação do primeiro módulo pegável (sem `dependsOn`) criar também a raiz do workspace: `package.json` com `workspaces`, lockfile, raiz do compose e script de build na ordem do grafo; cada módulo tem `package.json` próprio. Estende a RN-1006.
- **Onde:** `lib/engine/agents/dev_lead_server.ex` (texto da FUNDAÇÃO no kickoff)
- **Teste:** `test/engine/agents/dev_lead_server_test.exs` (kickoff com a "RAIZ do workspace")
- **Origem:** AT-921, Rodada 368, lane Dev Lead.

<a id="rn-1095"></a>

### RN-1095 — A retentativa por corte pelo teto de saída dobra o teto, em vez de repetir o pedido {#rn-1095}

> **Revisa a [RN-780](parte-05.md#rn-780)** (a volta retentada deixa de ser idêntica à primeira).

- **Regra (AT-920):** a volta retentada de uma resposta só de raciocínio cortada pelo teto (`truncated`) marca `saida_ampliada` e chama o `llm_turn` com `saida_ampliada: true`; a fachada leva `saidaAmpliada: true` no corpo para a api, que dobra o teto de saída do turno. A primeira chamada e as seguintes (uma chamada de ferramenta zera a marca) saem sem a opção.
- **Onde:** `apps/engine/lib/engine/harness/tool_loop.ex:256` (`parada_sem_chamada`), `apps/engine/lib/engine/harness/tool_loop.ex:287` (`llm_turn_com_retentativa`), `apps/engine/lib/engine/sessions/engine_api_client.ex:2012` (`com_catalogo_completo`)
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs` ("RN-1095: só a volta retentada pede o teto de saída dobrado")
- **Declarado:** a parte da api (dobrar `maxTokens` e o mapa de raciocínio do `claude-sonnet-5`) é de outra lane; até ela entrar, a api ignora o campo.
- **Origem:** AT-920 (achado 33 da 28ª), Rodada 366, lane EA.

<a id="rn-1096"></a>

### RN-1096 — O bloqueio por corte repetido diz o que mudar {#rn-1096}

- **Regra (AT-920):** repetido o corte, o diagnóstico do bloqueio diz que a retentativa já dobrou o teto de saída e que o próximo passo é trocar o modelo do agente ou desligar o raciocínio daquele modelo.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:1456` (`stop_diagnosis`)
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs` (corte repetido marca `corte_pelo_teto`, que escolhe o diagnóstico)
- **Origem:** AT-920, Rodada 366, lane EA.

<a id="rn-1097"></a>

### RN-1097 — O kickoff do dev ensina a provar a rota com o app de pé, e o teto do terminal é dito como teto {#rn-1097}

> **Estende a [RN-846](parte-05.md#rn-846)** e espelha a [RN-854](parte-05.md#rn-854).

- **Regra (AT-904):** o `initial_message` do dev traz a receita: subida em segundo plano (`nohup`), espera da porta, `curl` e encerramento do grupo de processos, sem nunca subir o app em primeiro plano. O resultado do estouro do teto do terminal diz que é teto de tempo, não recusa de permissão. A causa do "negado pelo sistema" da 28ª foi lida como o teto de 120 s com o servidor em primeiro plano (hipótese do levantamento, sem o log da 28ª).
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:715` (`@receita_de_subir_o_app`), `apps/engine/lib/engine/dev/dev_agent_server.ex:820` (`initial_message`), `apps/engine/lib/engine/harness/hooks/action_pipeline.ex:85` (`resultado_de_teto_do_terminal`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs` ("RN-1097…"), `apps/engine/test/engine/sessions/engine_api_client_propose_terminal_test.exs` ("o estouro da espera chega ao modelo…")
- **Origem:** AT-904 (achado 13), Rodada 366, lane EA.

<a id="rn-1098"></a>

### RN-1098 — A rota HTTP entra no README do módulo, nunca no da raiz {#rn-1098}

> **Revisa a [RN-846](parte-05.md#rn-846)** e a [RN-850](parte-05.md#rn-850) (o destino da seção "Rotas HTTP").

- **Regra (AT-903):** o kickoff do dev manda a rota criada ou mudada para a seção "Rotas HTTP" do `README.md` da PASTA DO SEU MÓDULO; o README da raiz é da Infra (uso e índice de módulos) e da tarefa de integração. Dependências de outras lanes, não feitas aqui: o índice "Módulos" da raiz (`infra_lead_server.ex`) e a conferência do recorte do QA (`recorte_da_tarefa.ex`, que ainda exige a rota na raiz).
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:820` (`initial_message`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs` ("RN-846: kickoff pede a rota no README…")
- **Origem:** AT-903 (achado 11), Rodada 366, lane EA.

<a id="rn-1110"></a>

### RN-1110 — O kickoff do dev leva, fixada, a memória do módulo da tarefa e a dos módulos de que ele depende {#rn-1110}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)).

- **Regra (AT-923):** o kickoff do dev agent traz uma mensagem FIXADA (`:pinned`, que o `ContextManager` não compacta), "Memória dos módulos", entre o enunciado e o retrato do worktree. Ela tem o cartão do módulo da tarefa por inteiro e, dos módulos de `dependeDe`, só as seções Expõe e Como usar, mais o contrato declarado de cada um (lido do banco, a fonte única). São no máximo 8 000 tokens estimados: o módulo próprio é o último a ser cortado (pela cauda, com marcador) e as seções de dependência que não cabem são omitidas e contadas; o total real é dito (ADR 0060). Os outros módulos ficam a um `read_file`, e a mensagem diz o caminho. Cartão ausente ou pasta que o engine não vê (modo `runner`) não quebra: a mensagem diz isso.
- **Onde:** `lib/engine/dev/memoria_do_projeto.ex:55` (`mensagem`), `lib/engine/dev/dev_agent_server.ex:709` (`memoria_message`)
- **Teste:** `test/engine/dev/memoria_do_projeto_test.exs`, `test/engine/dev/memoria_corrente_test.exs` ("report_done → cartão → kickoff da próxima tarefa…")
- **Origem:** AT-923 (EP-036), Rodada 372, lane L4 (A1 e A2).

<a id="rn-1111"></a>

### RN-1111 — A correção pedida por um gate começa com a mesma memória, o retrato e o resumo anterior {#rn-1111}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)).

- **Regra (AT-923):** a volta de correção (`implement_correction`) não recomeça só com o enunciado: monta enunciado, a mesma mensagem fixada da RN-1110, o retrato do worktree, o resumo do `report_done` anterior (guardado no estado do agente) e, por último, o parecer do gate.
- **Onde:** `lib/engine/dev/dev_agent_server.ex:900` (`implement_correction`), `lib/engine/dev/dev_agent_server.ex:768` (`resumo_anterior`)
- **Teste:** `test/engine/dev/memoria_corrente_test.exs` ("a correção de gate leva a memória…")
- **Origem:** AT-923 (EP-036), Rodada 372, lane L4 (A1 e A2).

<a id="rn-1112"></a>

### RN-1112 — No `report_done`, o sistema regenera o cartão do módulo, sem LLM, e ele entra no mesmo commit {#rn-1112}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)).

- **Regra (AT-923):** antes do `propose_commit` (entrega e correção), o engine regenera `.brabo/memoria/modulos/<m>.md` do módulo da tarefa a partir do código do worktree: `package.json` (scripts, dependência irmã), exports do ponto de entrada (com `export *` seguido um nível), rotas por regex ou `openapi.json`, pasta de migrações. Sem LLM, sem rede, sem timestamp (o mesmo código gera o mesmo arquivo). Linguagem desconhecida sai só com a lista de arquivos e a seção humana. O `AGENTS.md` da raiz ganha uma linha de ponteiro. Falha na geração não derruba a entrega, e pasta fora do alcance do engine (modo `runner`) é ignorada. Limite: a rota é o caminho como escrito no arquivo, sem o prefixo de `app.use`.
- **Onde:** `lib/engine/dev/memoria_extrator.ex:71` (`escrever`), `lib/engine/dev/dev_agent_server.ex:784` (`escrever_memoria`)
- **Teste:** `test/engine/dev/memoria_extrator_test.exs`, `test/engine/dev/memoria_corrente_test.exs`
- **Origem:** AT-923 (EP-036), Rodada 372, lane L4 (A1 e A2).

<a id="rn-1113"></a>

### RN-1113 — A seção humana "Como usar" só muda pelo `como_usar` do dev daquele módulo {#rn-1113}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)).

- **Regra (AT-923):** o `report_done` ganha o parâmetro opcional `como_usar` (texto curto, teto de 4 000 bytes com o total dito quando corta). Ele substitui só a seção "Como usar" do cartão do PRÓPRIO módulo; sem ele, o que estava lá (inclusive edição do usuário) fica, e a parte gerada, entre `<!-- brabo:gerado -->` e `<!-- /brabo:gerado -->`, é sobrescrita. O kickoff pede o parâmetro quando a tarefa muda o que o módulo expõe ou como sobe e testa.
- **Onde:** `lib/engine/dev/memoria_extrator.ex:495` (`humana`), `lib/engine/dev/tools/report_done.ex:33` (`como_usar`)
- **Teste:** `test/engine/dev/memoria_extrator_test.exs` ("como_usar troca só a seção humana…")
- **Origem:** AT-923 (EP-036), Rodada 372, lane L4 (A1 e A2).

<a id="rn-1114"></a>

### RN-1114 — O cartão diz o que o contrato declara e o código não expõe, e o contrário {#rn-1114}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)). Relaciona-se com a [RN-1093](parte-06.md#rn-1093) (o Arquiteto confere o código).

- **Regra (AT-923):** o contrato declarado (versão e itens, do banco) é renderizado no cartão, com a seção "Divergência contrato × código": função ou rota declarada que o código não tem, e função exportada ou rota servida que o contrato não declara. A divergência é dita, nunca corrigida em silêncio, e a fonte do contrato continua no banco (RN-684).
- **Onde:** `lib/engine/dev/memoria_extrator.ex:420` (`divergencia`)
- **Teste:** `test/engine/dev/memoria_extrator_test.exs` ("RN-1114…")
- **Origem:** AT-923 (EP-036), Rodada 372, lane L4 (A1 e A2).

<a id="rn-1115"></a>

### RN-1115 — A varredura do workspace e a leitura de `AGENTS.md` não descem em `node_modules` {#rn-1115}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)).

- **Regra (AT-923):** `WorkspaceFiles.search`/`count` pulam `.git` e `node_modules`; o `InstructionFiles` pula também `.brabo` (a memória não é instrução). Descer em `node_modules` custava segundos e enchia a busca do dev de código de terceiro.
- **Onde:** `lib/engine/harness/workspace_files.ex:137` (`walk`), `lib/engine/harness/instruction_files.ex:241` (`collect`)
- **Teste:** `test/engine/harness/workspace_files_test.exs`, `test/engine/harness/instruction_files_test.exs` ("AT-923…")
- **Origem:** AT-923 (EP-036), Rodada 372, lane L4 (A1 e A2).

<a id="rn-1158"></a>

### RN-1158 — O fecho do turno grava o que foi gravado como CAMPO {#rn-1158}

> **Estende a [RN-731](parte-05.md#rn-731).**

- **Regra (AT-933):** o `agent.response` de fecho dos agentes conversacionais leva `gravadoNoTurno: %{itens: [%{tipo, total}], recusadas}` (`tipo` é a classe da RN-731, ex. `"regra"`, `"adr"`, na ordem fixa da linha), além da linha "Gravado neste turno: …" no `content`, que segue igual por compatibilidade. Turno sem escrita não leva o campo.
- **Onde:** `lib/engine/agents/gravado_no_turno.ex` (`descarregar_com_campos`), `lib/engine/agents/texto_do_turno.ex` (`payload_do_turno`)
- **Teste:** `test/engine/agents/metricas_do_turno_test.exs` ("RN-1158/1160…")
- **Origem:** AT-933, Rodada 374, lane F1-engine.

<a id="rn-1159"></a>

### RN-1159 — O fecho do turno grava custo, chamadas, raciocínio e duração {#rn-1159}

- **Regra (AT-933):** a cada chamada de LLM concluída o engine soma o `usage` do turno; o fecho leva `custoMicros` (chat mais Jev), `chamadasLlm`, `raciocinioTokens` (só se algum `usage` trouxe `reasoningTokens`, que a api passa a devolver em outra lane da AT-933) e `duracaoMs` (da primeira chamada ao fecho).
- **Onde:** `lib/engine/agents/metricas_do_turno.ex` (`registrar`), `lib/engine/sessions/engine_api_client.ex` (`registrar_raciocinio`)
- **Teste:** `test/engine/agents/metricas_do_turno_test.exs` ("RN-1159…")
- **Origem:** AT-933, Rodada 374, lane F1-engine.

<a id="rn-1160"></a>

### RN-1160 — O texto do fecho não muda {#rn-1160}

- **Regra (AT-933):** os campos das RN-1158 e RN-1159 são acrescentados FORA do `content`; o texto da resposta e a linha da RN-731 ficam como eram, e quem não conhece os campos os ignora.
- **Onde:** `lib/engine/agents/texto_do_turno.ex` (`payload_do_turno`)
- **Teste:** `test/engine/agents/metricas_do_turno_test.exs` ("RN-1158/1160…")
- **Origem:** AT-933, Rodada 374, lane F1-engine.

<a id="rn-1161"></a>

### RN-1161 — Sem fato, sem campo {#rn-1161}

- **Regra (AT-933):** turno sem escrita não leva `gravadoNoTurno`; turno sem chamada de LLM não leva os campos de métrica; turno sem texto algum (`payload_do_turno` nulo) descarta o acúmulo. O `ToolLoop` (dev, QA, gates) não entra nesta regra: ele já grava `tokensSpentMicros` por iteração.
- **Onde:** `lib/engine/agents/metricas_do_turno.ex` (`descarregar`)
- **Teste:** `test/engine/agents/metricas_do_turno_test.exs` ("RN-1161…")
- **Origem:** AT-933, Rodada 374, lane F1-engine.

<a id="rn-1167"></a>

### RN-1167 — O dev consulta o impacto de um módulo pelo grafo, e grafo desligado nunca vira lista vazia {#rn-1167}

- **Regra (AT-924):** o dev agent ganha a ferramenta `consultar_impacto_do_modulo` (`:direct`, leitura contida, ADR 0060): o projeto vem do contexto, o único parâmetro é o nome do módulo, e cada lista tem teto de 40 com o total dito. Responde quem depende do módulo, o que ele expõe, as decisões que o citam e a versão do contrato. 503 da api (grafo desligado) volta como `ok: false` "grafo desligado", nunca como lista vazia; 404 diz que o módulo não tem nó.
- **Onde:** `lib/engine/harness/tools/consultar_impacto_do_modulo.ex:42` (`run`), `lib/engine/sessions/engine_api_client.ex` (`consultar_impacto_do_modulo`), `lib/engine/dev/tools.ex` (`registry`)
- **Teste:** `test/engine/harness/tools/consultar_impacto_do_modulo_test.exs`
- **Origem:** AT-924, lane E1-engine; estende a RN-1166 da api.

<a id="rn-1134"></a>
### RN-1134 — O dev recebe os mesmos critérios da entrega que o QA, antes de codar {#rn-1134}

- **Regra (AT-905):** o kickoff e a volta de correção do dev levam uma mensagem fixada com os critérios da entrega (forma da resposta, ponto de entrada, contrato), os mesmos do recorte do QA, sem a régua do veredito. Uma função só, `criterios_da_entrega/1`, gera os dois textos.
- **Onde:** `lib/engine/gates/recorte_da_tarefa.ex` (`criterios_da_entrega`), `lib/engine/dev/dev_agent_server.ex` (`criterios_message`)
- **Teste:** `test/engine/gates/recorte_da_tarefa_test.exs` ("AT-905: criterios_da_entrega")
- **Origem:** AT-905, Rodada 369, lane engine.

<a id="rn-1135"></a>
### RN-1135 — O Desbloquear leva orientação e o último parecer ao dev, e a orientação prevalece {#rn-1135}

- **Regra (AT-909):** o `dev-context` traz `desbloqueio` e `ultimoParecer` (api#105); quando há orientação, o dev recebe uma mensagem fixada com o parecer e a orientação, que prevalece sobre o parecer.
- **Onde:** `lib/engine/dev/context_builder.ex` (`build`), `lib/engine/dev/dev_agent_server.ex` (`desbloqueio_message`)
- **Teste:** `test/engine/dev/context_builder_test.exs` ("RN-1135")
- **Origem:** AT-909, Rodada 369, lane engine.

<a id="rn-1136"></a>
### RN-1136 — O Dev Lead lê o último parecer de gate de uma tarefa {#rn-1136}

- **Regra (AT-909):** a ferramenta `ler_parecer_da_tarefa(task_id)` devolve veredito, resumo, itens e melhorias do último parecer, lidos pelo `dev-context`; tarefa sem parecer e falha de leitura têm resposta nomeada.
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`run_ler_parecer_da_tarefa`), `lib/engine/agents/dev_lead_server.ex` (`tool_specs`)
- **Teste:** `test/engine/agents/dev_lead_tools_test.exs` ("RN-1136")
- **Origem:** AT-909, Rodada 369, lane engine.

<a id="rn-1137"></a>
### RN-1137 — O `update_task` do Arquiteto vai com o autor `arquiteto` {#rn-1137}

- **Regra (AT-918):** a ferramenta manda `agentId: "arquiteto"` quando chamada pelo Arquiteto (a api aceita o autor desde a api#105); PO continua `po` e Dev Lead `dev-lead`.
- **Onde:** `lib/engine/harness/tools/update_task.ex` (`run`), `lib/engine/agents/arquiteto_server.ex` (`run_tool`)
- **Teste:** `test/engine/harness/tools/update_task_test.exs` ("o Arquiteto manda agentId arquiteto")
- **Origem:** AT-918, Rodada 369, lane engine.

<a id="rn-1190"></a>
### RN-1190 — O gate de QA esgotado avisa o Dev Lead com os itens {#rn-1190}

- **Regra (AT-909):** quando a api devolve `nextAction: blocked` ao veredito do QA, o `QaLeadServer` entrega ao Dev Lead um `:tarefa_bloqueada` com o motivo "ciclo de correção esgotado (gate qa)" e os itens no diagnóstico. A exclusão da RN-1012 cai só para este caso; o gate de SecOps segue fora.
- **Onde:** `lib/engine/gates/qa_lead_server.ex` (`avisar_ciclo`)
- **Teste:** `test/engine/gates/qa_lead_server_test.exs` ("RN-1190")
- **Origem:** AT-909, Rodada 369, lane avisos.

<a id="rn-1191"></a>
### RN-1191 — Na penúltima correção permitida o Dev Lead é avisado com os itens {#rn-1191}

- **Regra (AT-909):** quando o veredito do QA pede correção e `gateCorrectionCount == max_gate_corrections - 1`, o Dev Lead recebe `:ciclo_quase_esgotado` com os itens da volta e o caminho (`ler_parecer_da_tarefa`, `pedir_ao_arquiteto`). São os itens desta volta, sem diferença contra a anterior.
- **Onde:** `lib/engine/gates/qa_lead_server.ex` (`avisar_ciclo`), `lib/engine/agents/dev_lead_server.ex` (`aviso_de_ciclo_quase_esgotado`)
- **Teste:** `test/engine/gates/qa_lead_server_test.exs` ("RN-1191"), `test/engine/agents/dev_lead_server_test.exs` ("ciclo_quase_esgotado")
- **Origem:** AT-909, Rodada 369, lane avisos.

<a id="rn-1320"></a>
### RN-1320 — O gate resolvido aciona o merge automático e o desfecho tem origem nomeada {#rn-1320}

- **Regra (AT-902):** `task.gate_resolved` (`nextAction: done`) vai também ao `MergeAutomaticoWorker`, que chama `POST /internal/projects/:projectId/tasks/:taskId/auto-merge` (RN-1316). O engine não decide merge: chave, gates, PR e duplicidade são da api. Recusa 409 `chave_desligada`, `gate_pendente`, `pr_ja_mergeado` e `merge_ja_proposto` é o caminho normal (`:ok`, só log). `sem_pr` ou código desconhecido grava `merge_automatico.recusado` (origem `politica`). Proposta `failed` grava `merge_automatico.falhou` com origem `codigo` (conflito, com os arquivos; o dev acorda pela RN-715) ou `infra` (provider). 5xx e queda de rede tentam de novo (5 tentativas) e, esgotadas, gravam `merge_automatico.falhou` com origem `infra` (só o status, nunca o corpo); outro 4xx grava na hora. A PR sempre fica pronta para o clique manual.
- **Onde:** `lib/engine/workers/merge_automatico_worker.ex`, `lib/engine/outbox/drain.ex` (`handlers_for`), `Engine.Sessions.EngineApiClient.acionar_merge_automatico/3`
- **Teste:** `test/engine/workers/merge_automatico_worker_test.exs`, `test/engine/outbox/drain_test.exs`
- **Origem:** AT-902 (EP-036), decisão do dono de 12/11/2026; espelha a RN-1316 da api.
