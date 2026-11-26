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
- **Onde:** `prompts/psychologist-kickoff.md` (v4), `apps/engine/lib/engine/workers/psychologist_worker.ex:311` (`render_inline`), `apps/engine/lib/engine/workers/psychologist_worker.ex:299` (`render_template`), `apps/engine/lib/engine/workers/psychologist_worker.ex:356` (`escopo_instruction`), `apps/engine/lib/engine/workers/psychologist_worker.ex:367` (`termination_instruction`), `apps/engine/lib/engine/workers/psychologist_worker.ex:230` (`build_ctx`), `apps/engine/lib/engine/psychologist/context_builder.ex:83` (`build`), `apps/engine/lib/engine/psychologist/tools/emit_hypotheses.ex:22` (`spec`), `apps/engine/lib/engine/psychologist/tools/emit_hypotheses.ex:99` (`run`), `apps/engine/lib/engine/sessions/engine_api_client.ex:1896` (`propose_hypotheses`); a regra de lote e o evento ficam na api, em [`propose-hypotheses.use-case.ts`](https://github.com/viralabs-dev/brabo-api/blob/dev/src/application/use-cases/execution/propose-hypotheses.use-case.ts) ([ADR 0288](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0288-link-entre-repos-nas-rns-e-url-do-repo-dono.md)).
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

- **Regra:** na entrega e na correção, o gate (QA, ou o recomeço da RN-715) só abre depois de `git_commit` e `git_push` com desfecho `executed` e com o HEAD do worktree igual a `origin/<branch>` (`head_igual_ao_remoto/2`, sem `fetch`: o push atualiza a ref e o push recusado a deixa velha). Push `refused` bloqueia a task com o motivo nomeado e origem `infra`, sem abrir PR nem gate; `pending` espera a aprovação (`awaiting_approval`) e na correção o agente guarda o id do push (`correcao_pendente`, AT-1002): o `action_settled` dele `executed` reabre o gate pelo mesmo caminho (no conflito, `in_review` antes do `open_gate`), `denied` bloqueia com origem `politica` e `failed` com origem `infra`, nenhum dos dois conta no disjuntor (RN-1345), e o de outro `action_id` é ignorado; HEAD diferente do remoto bloqueia "o worktree e a branch do remoto divergem" com os dois SHAs. Sem a ref do remoto (branch nunca enviada) ou sem worktree local (modo `runner`) a guarda não bloqueia: quem recusa é o desfecho da ação.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:1109` (`handle_correction_outcome`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1468` (`with_head_no_remoto`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1486` (`entregar`), `apps/engine/lib/engine/dev/worktree_manager.ex:511` (`head_igual_ao_remoto`)
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
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:482` (`liberar_branch_presa`), `apps/engine/lib/engine/dev/dev_agent_server.ex:360` (`handle_info`), `apps/engine/lib/engine/dev/dev_agent_server.ex:456` (`motivo_do_descarte`), `apps/engine/lib/engine/dev/dev_agent_server.ex:535` (`retrabalhar_conflito`)
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs` ("AT-915: a branch presa no worktree de outro agente é preservada…", "…fora de .worktrees segue recusada"), `apps/engine/test/engine/dev/conflito_e_push_test.exs` (a corrente: ocupado adia, a PR entra, a reentrega é descartada; outro dono; regressão in_progress; disjuntor); mutação provada: tirar a liberação ou o descarte reprova um teste cada.
- **Origem:** AT-915 (achado 27) e AT-907 (achado 16), Rodada 365, lane X1.

<a id="rn-1099"></a>

### RN-1099 — O merge da PR de infra faz a Infra propor de novo a subida do container {#rn-1099}

> **Estende a [RN-671](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-671)** (a subida pelo servidor deixa de existir só no kickoff) **e a [RN-672](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-672)** (o Dev Lead é oferecido também depois desse merge).

- **Regra (AT-899):** o `project.trunk_merged` ganha um segundo consumidor, o `InfraOfereceDevLeadWorker`, que avisa `{:trunk_merged, project_id}` no tópico do projeto. O Infra Lead vivo, sem turno em curso, lê o container registrado: `running` oferece o Dev Lead (`if_absent`); `provisioning` não faz nada; qualquer outro estado repete o passo `subir_no_aceite/2` (mesma `propor_container_start/2`, mesmas recusas). Se a proposta não nasce (sem roteamento, modo `runner`, recusa), o fio diz o próximo passo (pedir a subida ou usar a página Containers). Com turno em curso nada é feito: o fecho do turno já pergunta. Entrega at-most-once, como a RN-672.
- **Por quê:** TP-01 28ª (achados 3 e 4): a PR de infra entrou sem subida e a corrente parou até o usuário escrever; o "aguardando" ficou sem pergunta nem botão.
- **Onde:** `lib/engine/outbox/drain.ex:111` (`handlers_for`), `lib/engine/workers/infra_oferece_dev_lead_worker.ex:29` (`perform`), `lib/engine/infra/infra_lead_server.ex` (`handle_info({:trunk_merged, _}, _)`, `ao_merge_da_pr_de_infra`).
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
- **Onde:** `apps/engine/lib/engine/dev/agent_io.ex:238` (`sem_task_pegavel`), `apps/engine/lib/engine/dev/agent_io.ex:234` (`procura_ociosa_ms`), `apps/engine/lib/engine_web/controllers/execution_command_controller.ex:121` (`wake`), `apps/engine/lib/engine/workers/execucao_parada_worker.ex:124` (`reprocurar`), `apps/engine/lib/engine/agents/dev_lead_tools.ex:664` (`run_procurar_tarefa`)
- **Teste:** `apps/engine/test/engine/dev/dev_agent_chain_test.exs` (a corrente: dependência aberta → ocioso → `mark_task done` → outbox `task.became_claimable` → drain → wake → claim; e o timer sozinho, sem `dev.idle` repetido), `apps/engine/test/engine_web/controllers/execution_command_controller_test.exs` (wake 202/409/404), `apps/engine/test/engine/workers/execucao_parada_worker_test.exs`, `apps/engine/test/engine/agents/dev_lead_tools_test.exs`; mutação provada: tirar o `agendar_procura` reprova o teste do timer.
- **Origem:** AT-906 (TP-01 28ª, achados 15, 17 e 25), Rodada 366, lane X2a.

<a id="rn-1087"></a>

### RN-1087 — A tarefa nasce com o módulo, e o Dev Lead arquiva a tarefa `todo` que ele criou {#rn-1087}

> **Estende a [RN-1006](parte-06.md#rn-1006)** (o `module` do Dev Lead passa a ser gravado) e **a RN-727** (`archive_story`, na api) (arquivar, agora também a tarefa).

- **Regra:** o `Engine.Harness.Tools.CreateTask.run/2` envia `fields.module` quando o `module` vem nos argumentos (antes o descartava e a tarefa nascia órfã). A ferramenta `arquivar_tarefa(task_id, motivo)` do Dev Lead chama `POST /internal/sessions/:sessionId/tasks/:taskId/archive` com `{projectId, reason}`; o motivo é obrigatório (vazio é recusado sem chamar a api) e a api só arquiva `todo` criada por ele (409 nomeado `tarefa_em_execucao`, `tarefa_arquivada` ou `tarefa_de_outro_autor`, que volta ao modelo). `ExecucaoParadaWorker.pendentes/1` ignora tarefa com `archivedAt`.
- **Onde:** `apps/engine/lib/engine/harness/tools/create_task.ex:52` (`put_module`), `apps/engine/lib/engine/agents/dev_lead_tools.ex:558` (`run_arquivar_tarefa`), `apps/engine/lib/engine/sessions/engine_api_client.ex:1451` (`archive_task`), `apps/engine/lib/engine/workers/execucao_parada_worker.ex:112` (`pendentes`)
- **Teste:** `apps/engine/test/engine/agents/dev_lead_tools_test.exs` (o `create_task` envia `module`; arquivar com motivo, sem motivo e com recusa nomeada), `apps/engine/test/engine/workers/execucao_parada_worker_test.exs` (a parada não conta tarefa arquivada); mutação provada: tirar o `put_module` reprova o teste.
- **Origem:** AT-912 (TP-01 28ª, achado 22), Rodada 366, lane X2a.

<a id="rn-1088"></a>

### RN-1088 — A execução parada nomeia o ciclo entre o bloqueio e o `dependsOn` {#rn-1088}

> **Estende a [RN-1059](parte-06.md#rn-1059)** (motivo novo da parada) e **a [RN-1012](parte-06.md#rn-1012)** (o caminho até o Arquiteto é o `pedir_ao_arquiteto`).

- **Regra:** quando uma tarefa bloqueada do módulo Y cita, no `blockedReason`, um módulo X que depende de Y (direta ou transitivamente, pelo `module_map` vigente lido em `get_infra_context`), o `execution.stalled` traz `ciclosDeDependencia: [{taskId, modulo: Y, esperaPor: X}]`. A citação é `modules/X`, `dev-X` ou `X` com borda (`x-y` não cita `x`). O aviso ao Dev Lead diz "IMPASSE de dependência" e que só o contrato ou o `dependsOn` mudando destrava: leve ao Arquiteto com `pedir_ao_arquiteto`, em vez de repropor o plano. Sem canal novo.
- **Onde:** `apps/engine/lib/engine/workers/execucao_parada_worker.ex:136` (`ciclos_de_dependencia`), `apps/engine/lib/engine/workers/execucao_parada_worker.ex:165` (`ciclos`), `apps/engine/lib/engine/agents/dev_lead_server.ex:419` (`aviso_de_ciclo`)
- **Teste:** `apps/engine/test/engine/workers/execucao_parada_worker_test.exs` (ciclo direto, transitivo, sem ciclo, e a corrente até o Dev Lead), `apps/engine/test/engine/agents/dev_lead_server_test.exs` (o aviso manda `pedir_ao_arquiteto`).
- **Origem:** AT-913 (TP-01 28ª, achado 25), Rodada 366, lane X2a. O id de tarefa como citação ficou fora: só o nome do módulo.

<a id="rn-1089"></a>

### RN-1089 — A falha de reinício da app depois do merge avisa o Dev Lead com motivo, código e o caminho do log {#rn-1089}

> **Estende a [RN-1028](parte-06.md#rn-1028)** (o desfecho do reinício vai à linha do tempo, sem trecho de log).

- **Regra:** `app.restart_failed` continua com `motivo` e `exitCode` (allowlist) e ganha `log: "/tmp/brabo-app.log"` (o caminho no container); o TEXTO do log nunca entra no evento nem no aviso, porque o comando do app pode carregar segredo. A falha também entrega `{:app_falhou, %{motivo, exitCode}}` ao Dev Lead, que abre turno com "[Aviso do sistema]" mandando criar a tarefa de correção no módulo dono e pedir ao dev que leia o log no container. O reinício bem-sucedido não acorda ninguém.
- **Onde:** `apps/engine/lib/engine/workers/reiniciar_app_worker.ex:75` (`falhou`), `apps/engine/lib/engine/agents/dev_lead_server.ex:396` (`aviso_de_app`), `apps/engine/lib/engine/agents/dev_lead_server.ex:454` (`handle_info`)
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
- **Regra (AT-981, revisa a leitura prévia):** no kickoff a `main` está vazia, então o contrato é declarado AGORA, como interface futura, e o prompt proíbe propor "contrato só depois do código". A `main` só é lida quando já tem código do módulo. O contrato traz, obrigatoriamente, (a) a forma de exposição (plugin, nunca app completa), (b) o dono de cada tabela e (c) os vínculos de identidade entre módulos. Os tipos `tabela` e `identidade` (aceitos pela api, RN-1351) vão sempre ao modelo; a trava `:contrato_com_tabela_e_identidade` foi removida.
- **Onde:** `lib/engine/harness/contrato_contra_o_codigo.ex` (`texto_do_codigo`), `lib/engine/harness/tools/declare_module_contracts.ex` (`conferencia_com_codigo`), `lib/engine/agents/arquiteto_server.ex` (`tool_specs`, `run_tool`)
- **Teste:** `test/engine/harness/tools/declare_module_contracts_test.exs` ("função que a main não tem volta nomeada…", "pasta invisível…", "tabela e identidade só entram no enum…"), `test/engine/agents/arquiteto_server_test.exs` (catálogo, "kickoff manda declarar o contrato antes do código…")
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

- **Regra (AT-921):** quando a entrega altera `package.json`, lockfile, `Dockerfile`, `docker-compose*.yml` ou `tsconfig*.json`, ou é a última tarefa do projeto (`ultimaDoProjeto`, [RN-1350](parte-07.md#rn-1350); a régua por irmãs da história caiu), o `QaLeadServer` prepara `.brabo-qa/clone-limpo/` com `git archive HEAD` (sem `node_modules`, `dist` nem arquivo não versionado), sem Docker e sem LLM extra. O recorte manda instalar, compilar, testar e subir o app ali, conferindo `/docs` e `/openapi.json`. Nas demais tarefas nada muda. Se o clone não puder ser preparado, o recorte diz e isso não reprova.
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

- **Regra (AT-921):** com mais de um módulo no mesmo runtime, o kickoff manda a fundação do primeiro módulo pegável (sem `dependsOn`) criar também a raiz do workspace: `package.json` com `workspaces`, lockfile, raiz do compose e script de build na ordem do grafo; cada módulo tem `package.json` próprio. Estende a RN-1006. A [RN-1415](parte-07.md#rn-1415) a completa: todos os workspaces e as dependências npm, numa tacada só.
- **Onde:** `lib/engine/agents/dev_lead_server.ex` (texto da FUNDAÇÃO no kickoff)
- **Teste:** `test/engine/agents/dev_lead_server_test.exs` (kickoff com a "RAIZ do workspace")
- **Origem:** AT-921, Rodada 368, lane Dev Lead.

<a id="rn-1095"></a>

### RN-1095 — A retentativa por corte pelo teto de saída dobra o teto, em vez de repetir o pedido {#rn-1095}

> **Revisa a [RN-780](parte-05.md#rn-780)** (a volta retentada deixa de ser idêntica à primeira).

- **Regra (AT-920):** a volta retentada de uma resposta só de raciocínio cortada pelo teto (`truncated`) marca `saida_ampliada` e chama o `llm_turn` com `saida_ampliada: true`; a fachada leva `saidaAmpliada: true` no corpo para a api, que dobra o teto de saída do turno. A primeira chamada e as seguintes (uma chamada de ferramenta zera a marca) saem sem a opção.
- **Onde:** `apps/engine/lib/engine/harness/tool_loop.ex:243` (`parada_sem_chamada`), `apps/engine/lib/engine/harness/tool_loop.ex:312` (`llm_turn_com_retentativa`), `apps/engine/lib/engine/sessions/engine_api_client.ex:2050` (`com_catalogo_completo`)
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs` ("RN-1095: só a volta retentada pede o teto de saída dobrado")
- **Declarado:** a parte da api (dobrar `maxTokens` e o mapa de raciocínio do `claude-sonnet-5`) é de outra lane; até ela entrar, a api ignora o campo.
- **Origem:** AT-920 (achado 33 da 28ª), Rodada 366, lane EA.

<a id="rn-1096"></a>

### RN-1096 — O bloqueio por corte repetido diz o que mudar {#rn-1096}

- **Regra (AT-920):** repetido o corte, o diagnóstico do bloqueio diz que a retentativa já dobrou o teto de saída e que o próximo passo é trocar o modelo do agente ou desligar o raciocínio daquele modelo.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:1611` (`stop_diagnosis`)
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs` (corte repetido marca `corte_pelo_teto`, que escolhe o diagnóstico)
- **Origem:** AT-920, Rodada 366, lane EA.

<a id="rn-1097"></a>

### RN-1097 — O kickoff do dev ensina a provar a rota com o app de pé, e o teto do terminal é dito como teto {#rn-1097}

> **Estende a [RN-846](parte-05.md#rn-846)** e espelha a [RN-854](parte-05.md#rn-854).

- **Regra (AT-904):** o `initial_message` do dev traz a receita: subida em segundo plano (`nohup`), espera da porta, `curl` e encerramento do grupo de processos, sem nunca subir o app em primeiro plano. O resultado do estouro do teto do terminal diz que é teto de tempo, não recusa de permissão. A causa do "negado pelo sistema" da 28ª foi lida como o teto de 120 s com o servidor em primeiro plano (hipótese do levantamento, sem o log da 28ª).
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:715` (`@receita_de_subir_o_app`), `apps/engine/lib/engine/dev/dev_agent_server.ex:893` (`initial_message`), `apps/engine/lib/engine/harness/hooks/action_pipeline.ex:85` (`resultado_de_teto_do_terminal`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs` ("RN-1097…"), `apps/engine/test/engine/sessions/engine_api_client_propose_terminal_test.exs` ("o estouro da espera chega ao modelo…")
- **Origem:** AT-904 (achado 13), Rodada 366, lane EA.

<a id="rn-1098"></a>

### RN-1098 — A rota HTTP entra no README do módulo, nunca no da raiz {#rn-1098}

> **Revisa a [RN-846](parte-05.md#rn-846)** e a [RN-850](parte-05.md#rn-850) (o destino da seção "Rotas HTTP").

- **Regra (AT-903):** o kickoff do dev manda a rota criada ou mudada para a seção "Rotas HTTP" do `README.md` da PASTA DO SEU MÓDULO; o README da raiz é da Infra (uso e índice de módulos) e da tarefa de integração. Dependências de outras lanes, não feitas aqui: o índice "Módulos" da raiz (`infra_lead_server.ex`) e a conferência do recorte do QA (`recorte_da_tarefa.ex`, que ainda exige a rota na raiz).
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:893` (`initial_message`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs` ("RN-846: kickoff pede a rota no README…")
- **Origem:** AT-903 (achado 11), Rodada 366, lane EA.

<a id="rn-1110"></a>

### RN-1110 — O kickoff do dev leva, fixada, a memória do módulo da tarefa e a dos módulos de que ele depende {#rn-1110}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)).

- **Regra (AT-923):** o kickoff do dev agent traz uma mensagem FIXADA (`:pinned`, que o `ContextManager` não compacta), "Memória dos módulos", entre o enunciado e o retrato do worktree. Ela tem o cartão do módulo da tarefa por inteiro e, dos módulos de `dependeDe`, só as seções Expõe e Como usar, mais o contrato declarado de cada um (lido do banco, a fonte única). São no máximo 8 000 tokens estimados: o módulo próprio é o último a ser cortado (pela cauda, com marcador) e as seções de dependência que não cabem são omitidas e contadas; o total real é dito (ADR 0060). Os outros módulos ficam a um `read_file`, e a mensagem diz o caminho. Cartão ausente ou pasta que o engine não vê (modo `runner`) não quebra: a mensagem diz isso.
- **Onde:** `lib/engine/dev/memoria_do_projeto.ex:55` (`mensagem`), `lib/engine/dev/dev_agent_server.ex:707` (`memoria_message`)
- **Teste:** `test/engine/dev/memoria_do_projeto_test.exs`, `test/engine/dev/memoria_corrente_test.exs` ("report_done → cartão → kickoff da próxima tarefa…")
- **Origem:** AT-923 (EP-036), Rodada 372, lane L4 (A1 e A2).

<a id="rn-1111"></a>

### RN-1111 — A correção pedida por um gate começa com a mesma memória, o retrato e o resumo anterior {#rn-1111}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)).

- **Regra (AT-923):** a volta de correção (`implement_correction`) não recomeça só com o enunciado: monta enunciado, a mesma mensagem fixada da RN-1110, o retrato do worktree, o resumo do `report_done` anterior (guardado no estado do agente) e, por último, o parecer do gate.
- **Onde:** `lib/engine/dev/dev_agent_server.ex:973` (`implement_correction`), `lib/engine/dev/dev_agent_server.ex:828` (`resumo_anterior`)
- **Teste:** `test/engine/dev/memoria_corrente_test.exs` ("a correção de gate leva a memória…")
- **Origem:** AT-923 (EP-036), Rodada 372, lane L4 (A1 e A2).

<a id="rn-1112"></a>

### RN-1112 — No `report_done`, o sistema regenera o cartão do módulo, sem LLM, e ele entra no mesmo commit {#rn-1112}

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)).

- **Regra (AT-923):** antes do `propose_commit` (entrega e correção), o engine regenera `.brabo/memoria/modulos/<m>.md` do módulo da tarefa a partir do código do worktree: `package.json` (scripts, dependência irmã), exports do ponto de entrada (com `export *` seguido um nível), rotas por regex ou `openapi.json`, pasta de migrações. Sem LLM, sem rede, sem timestamp (o mesmo código gera o mesmo arquivo). Linguagem desconhecida sai só com a lista de arquivos e a seção humana. O `AGENTS.md` da raiz ganha uma linha de ponteiro. Falha na geração não derruba a entrega, e pasta fora do alcance do engine (modo `runner`) é ignorada. Limite: a rota é o caminho como escrito no arquivo, sem o prefixo de `app.use`.
- **Onde:** `lib/engine/dev/memoria_extrator.ex:71` (`escrever`), `lib/engine/dev/dev_agent_server.ex:844` (`escrever_memoria`)
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

> **ADR 0293** ([a memória do projeto é markdown versionado](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0293-a-memoria-do-projeto-e-markdown-versionado-e-o-grafo-e-o-rag-sao-indices.md)). Relaciona-se com a [RN-1093](parte-07.md#rn-1093) (o Arquiteto confere o código).

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

<a id="rn-1330"></a>
### RN-1330 — O QA da última tarefa pede a prova do compose real e o desfecho tem origem nomeada {#rn-1330}

> **Revisa a [RN-1121](parte-07.md#rn-1121)** no ponto "o compose real segue observação".

- **Regra (AT-922):** na ÚLTIMA tarefa do projeto (o campo `ultimaDoProjeto` do dev-context, lido por `CloneLimpo.ultima_tarefa?/1`, [RN-1350](parte-07.md#rn-1350)), e só nela, o `QaLeadServer` chama `POST /internal/projects/:projectId/qa-environments/:taskId/compose` pela fachada `EngineApiClient.provar_compose_de_qa/2`. `provou` aprova e o resumo registra a prova; `falhou` reprova com o motivo e as `recusas` (origem `codigo`: o projeto); `aprova_com_aviso` aprova e escreve o aviso no parecer, em `melhorias` (origem `infra`, por exemplo "sem prova de compose" sem broker, teto de 10 min/4 GB estourado); erro de transporte, status fora do contrato ou veredito desconhecido vira bloqueio nomeado com origem `infra` (RN-059), nunca silêncio. O engine não toca Docker. Cadeia de tetos: broker < api (645 s, RN-1328) < engine (735 s = 645 s + 90 s de folga).
- **Onde:** `lib/engine/gates/prova_de_compose.ex`, `lib/engine/gates/qa_lead_server.ex` (`prova_de_compose`), `lib/engine/sessions/engine_api_client.ex` (`provar_compose_de_qa`)
- **Teste:** `test/engine/gates/prova_de_compose_test.exs`
- **Origem:** AT-922 (EP-036), decisões do dono de 12/11/2026; espelha a RN-1328 da api.

<a id="rn-1345"></a>
### RN-1345 — O disjuntor do dev só conta bloqueio atribuível a ele, e o `report_blocked` diz a causa {#rn-1345}

> **Revisa a [RN-047](parte-01.md#rn-047) e a [RN-810](parte-05.md#rn-810)** nos pontos "todo bloqueio conta" e "só a rede não conta".

- **Regra (AT-984):** não incrementa `consecutive_blocked` (o dev termina a tarefa como `:blocked_infra` e segue reivindicando): (a) o `gate_resolved` bloqueado com `origin: infra`, ou com `blockedBy` sendo o próprio gate falhando (`qa-lead`, `secops*`) e origem diferente de `politica`; (b) todo `block_task/4` do dev com origem `infra`; (c) o `report_blocked` com `causa` `depende_de_outra_tarefa` ou `precisa_de_decisao` (o Dev Lead continua avisado). CONTA: o ciclo de correção esgotado (`politica`, agente `<gate>-agent`), o `report_blocked` com `causa` `nao_consegui` (padrão) e o `gate_resolved` sem `origin`/`blockedBy` (payload antigo). O wake repassa `origin` e `blockedBy` do payload do outbox quando existem.
- **Regra (AT-983):** a reentrega depois de conflito de merge marca a tarefa `in_review` antes de reabrir o gate, como a entrega normal.
- **Regra (AT-982):** a receita de provar rota do kickoff do dev usa `node -e "fetch(...)"`; a imagem não tem `curl`.
- **Onde:** `lib/engine/dev/agent_io.ex` (`conta_no_disjuntor?/2`, `block_task/4`, `finish_task/3`), `lib/engine/dev/dev_agent_server.ex` (`gate_resolved`, `sem_conta_pela_causa`, `trigger_gate_recheck`), `lib/engine/dev/noop_dev_agent_server.ex`, `lib/engine/dev/tools/report_blocked.ex`, `lib/engine/dev/hooks/termination.ex`, `lib/engine/workers/dev_agent_wake_worker.ex`
- **Teste:** `test/engine/dev/bloqueio_conta_so_o_dev_test.exs`, `test/engine/dev/conflito_e_push_test.exs`, `test/engine/dev/report_done_instrucao_test.exs`
- **Origem:** AT-984, AT-983, AT-982 (EP-036), Rodada 382, lane EN1. O E2E `execucao-parada` segue valendo: bloqueio do dono com origem `politica` conta.

<a id="rn-1349"></a>
### RN-1349 — O gate de QA repete a falha passageira do provedor antes de bloquear {#rn-1349}

> **Complementa a [RN-864](parte-05.md#rn-864)** (a retomada do dev) e a [RN-810](parte-05.md#rn-810), e **revisa a [RN-897](parte-06.md#rn-897)** no ponto da origem da "falha repetida de ferramenta".

- **Regra (AT-984):** quando um subagente do gate de QA para por falha PASSAGEIRA do provedor (origem `infra` e diagnóstico de rede, 5xx, 429 ou "Connection error."; crédito esgotado nunca), o `QaLeadServer` NÃO chama `mark_task_blocked` (o bloqueio devolvia a tarefa ao dev, que o contava no disjuntor). Ele agenda o `RetomadaDoGateWorker`, que roda o gate de novo (`Dispatcher.run_qa/2`) depois de 1, 3 e 10 min, até 3 retomadas, as mesmas esperas da RN-864, e grava `gate.retry_scheduled` (`taskId`, `tentativa`, `minutos`). Repetir o gate é seguro: a api recusa veredito em duplicata. Esgotadas as 3, bloqueia como antes (origem `infra`) com o diagnóstico terminando em "3 retomadas do gate já tentadas". O contador é da tarefa, em memória do `QaLeadServer` (reiniciar o engine o zera, como na RN-864), e qualquer outro desfecho o zera. A "falha repetida de ferramenta" (RN-913) passa a ter origem `modelo` (`OrigemDoErro.de_llm/1`): é o laço do próprio QA, não a rede.
- **Onde:** `lib/engine/gates/qa_lead_server.ex` (`retomar_o_gate`), `lib/engine/workers/retomada_do_gate_worker.ex`, `lib/engine/gates/origem_do_erro.ex` (`passageira?`, `de_llm`)
- **Teste:** `test/engine/gates/qa_lead_server_test.exs` ("AT-984"), `test/engine/workers/retomada_do_gate_worker_test.exs`, `test/engine/gates/origem_do_erro_test.exs`
- **Origem:** AT-984 (EP-036), lane L3 (lado do gate), Rodada 382.

<a id="rn-1350"></a>
### RN-1350 — A prova do entregável acontece na última tarefa do PROJETO, num clone que o broker acha {#rn-1350}

> **Revisa a [RN-1330](parte-07.md#rn-1330) e a [RN-1121](parte-07.md#rn-1121)** (a régua da última tarefa e o lugar do clone) e **estende a [RN-854](parte-05.md#rn-854)** com o fluxo das regras por HTTP.

- **Regra (AT-982):** (1) "última tarefa" é o campo `ultimaDoProjeto` do dev-context (`ContextBuilder`), calculado pela api com todas as tarefas do projeto; sem o campo (api antiga), é falso. A régua por irmãs da história saiu: história de uma tarefa nunca disparava e a de vários módulos disparava no meio. (2) Antes de pedir a prova, o `QaLeadServer` materializa o clone do HEAD sob revisão TAMBÉM em `<raiz do projeto>/.brabo-qa/clone-limpo`, onde o broker o procura (`CloneLimpo.preparar/2`); sem raiz visível ao engine (modo `runner`), não prepara e a api devolve o aviso. A raiz ganha `.brabo-qa/` no `.git/info/exclude`. (3) O clone recebe `.env` copiado do `.env.example` quando não tem `.env` (o passo 1 do README), no do worktree e no da raiz. (4) Na última tarefa, com clone limpo, o recorte do QA ganha a seção "Prova do entregável": seguir o README e exercitar POR HTTP cada regra de `regrasDoProjeto` (caminho feliz e recusa, com o status esperado); rota 404, resposta 500 ou regra violada é item. (5) O recorte não manda mais usar `curl`, que a imagem não traz (achado 30): usa `node -e "fetch(...)"`, e o preflight de CORS vira `fetch` com `method: 'OPTIONS'` e o header `Origin`, que o `fetch` do Node 22 envia (o undici não o filtra como o navegador). A troca do `curl` no kickoff do dev é da AT-982 no `DevAgentServer`, em outra mudança.
- **Onde:** `lib/engine/gates/clone_limpo.ex` (`ultima_tarefa?`, `preparar`), `lib/engine/gates/qa_lead_server.ex` (`prova_de_compose`, `raiz_do_projeto`), `lib/engine/dev/context_builder.ex` (`build`), `lib/engine/gates/recorte_da_tarefa.ex` (`secao_da_prova_do_entregavel`)
- **Teste:** `test/engine/gates/clone_limpo_test.exs`, `test/engine/gates/qa_lead_server_test.exs` ("AT-982"), `test/engine/gates/recorte_da_tarefa_test.exs` ("AT-982", o caso do `Origin` no Node), `test/engine/dev/context_builder_test.exs`
- **Origem:** AT-982 (EP-036), lane B, Rodada 382. Os campos `ultimaDoProjeto` e `regrasDoProjeto` são da api (lane AP1).

<a id="rn-1334"></a>
### RN-1334 — O reinício do app não falha por alvo pendente, e a mesma falha seguida acorda o Dev Lead uma vez {#rn-1334}

> **Estende a [RN-1028](parte-06.md#rn-1028) e a [RN-1089](parte-07.md#rn-1089).**

- **Regra (AT-985):** o `ReiniciarAppWorker` aceita da api o motivo `alvo_pendente` (o módulo que o comando do app cita ainda não entregou nada) como `app.restart_skipped` com `{motivo: "alvo_pendente"}`, sem acordar o Dev Lead; a resposta sem o motivo segue como antes. Antes de avisar uma falha, o worker lê o último `app.restarted`/`app.restart_failed` da sessão: se foi um `app.restart_failed` com o MESMO `motivo` e `exitCode`, grava o evento e NÃO acorda o Dev Lead; um `app.restarted` no meio rearma o aviso. O aviso do Dev Lead (`aviso_de_app`) manda ler `read_backlog` e não criar outra tarefa de correção se já há uma aberta no módulo.
- **Por quê:** TP-01 29ª, achado 17: 13 `app.restart_failed` iguais viraram tarefas "Corrigir a app" duplicadas.
- **Onde:** `lib/engine/workers/reiniciar_app_worker.ex` (`perform`, `falhou`, `repetida?`), `lib/engine/agents/dev_lead_server.ex` (`aviso_de_app`)
- **Teste:** `test/engine/workers/reiniciar_app_worker_test.exs` (AT-985), `test/engine/agents/dev_lead_server_test.exs` (AT-985)
- **Origem:** AT-985 (EP-036), Rodada 382, lane EN3; o motivo `alvo_pendente` nasce na api (lane AP1).

<a id="rn-1335"></a>
### RN-1335 — O Dev Lead consulta e age em vez de perguntar: lê a PR e o plano e pede à Infra {#rn-1335}

> **Estende a [RN-1059](parte-06.md#rn-1059) e a [RN-1012](parte-06.md#rn-1012).**

- **Regra (AT-996):** o Dev Lead ganha `ler_estado_da_pr(task_id)` (status, gate, bloqueio e `git_merge` pendente na sessão, lidos do backlog e do log), `ler_plano` (plano proposto, aprovado, recusado e execução ativa, lidos do log) e `pedir_a_infra(mensagem)` (chat.message do `dev-lead` entregue ao `InfraLeadServer` com o prefixo "[Pedido do Dev Lead]"; a última fala da Infra volta como `{:resposta_da_infra, texto}`, aviso do sistema). O aviso de parada (RN-1059) e o prompt base mandam consultar e agir, e perguntar ao usuário só decisão (gasto, produto, recusa); Rearmar e Desbloquear seguem gesto humano. Nenhuma rota nova da api: as leituras usam `list_backlog` e `list_events`.
- **Por quê:** TP-01 29ª, achados 13, 29 e 45: o Dev Lead perguntava "o plano está aprovado?" e "a tarefa foi concluída?".
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`run_ler_estado_da_pr`, `run_ler_plano`), `lib/engine/harness/tools/pedir_a_infra.ex` (`run`), `lib/engine/agents/dev_lead_server.ex` (`aviso_de_parada`, `tool_specs`), `lib/engine/infra/infra_lead_server.ex` (`responder_ao_dev_lead`)
- **Teste:** `test/engine/agents/dev_lead_tools_test.exs` (AT-996), `test/engine/harness/tools/pedir_a_infra_test.exs`, `test/engine/agents/dev_lead_server_test.exs` (AT-996)
- **Origem:** AT-996 (sub-AT da AT-953, EP-035), Rodada 382, lane EN3.

<a id="rn-1348"></a>
### RN-1348 — O dev que chega ao teto com a suíte verde e diff entrega em vez de bloquear {#rn-1348}

> **Revisa o teto de iterações do [ADR 0053](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0053-dev-lead-e-paralelismo-autorizado.md)** no ponto "o teto de iterações sempre bloqueia" (ADR 0053); o desbloqueio humano da [RN-1059](parte-06.md#rn-1059) e o teto de correções do gate (RN-015) não mudam.

- **Regra (AT-988):** (1) quando faltam 5 voltas para o teto de um agente de execução (`dev-*`), o `ToolLoop` injeta UMA vez a mensagem de sistema "Restam 5 voltas: com a suíte verde e diff, chame `report_done` agora; se não, `report_blocked` com a causa". (2) No `limit_reached` do dev (laço principal e correção pós-gate), se o último `terminal` saiu com `exit 0` E o worktree tem diff contra a `dev`, a tarefa segue o MESMO caminho do `report_done` (commit, push, PR, `in_review`, gate), com resumo fixo e a marca "Entregue no teto de iterações" no corpo da PR, e o evento `dev.entregue_no_teto` narra no chat. Sem `exit 0` ou sem diff, bloqueia como sempre ("limite de iterações atingido"): laço sem prova não se automatiza (AT-953, decisão 2).
- **Onde:** `lib/engine/harness/tool_loop.ex` (`avisa_ultimas_voltas`), `lib/engine/dev/dev_agent_server.ex` (`handle_outcome`, `handle_correction_outcome`, `suite_verde_com_diff?`, `narrar_entrega_no_teto`, `marca_do_teto`)
- **Teste:** `test/engine/dev/dev_agent_server_test.exs` ("AT-988"), `test/engine/harness/tool_loop_test.exs` ("AT-988")
- **Origem:** AT-988 (sub-AT da AT-951/953, EP-035), Rodada 383, lane E988.

<a id="rn-1346"></a>
### RN-1346 — O fechamento do Arquiteto lista os módulos usados por outro que ficaram sem contrato {#rn-1346}

- **Regra (AT-981):** ao confirmar a arquitetura, a instrução do turno de fechamento acrescenta, de forma determinística (`list_module_contracts`), os módulos que aparecem no `dependeDe` de outro e não têm contrato vigente, mandando declará-los antes do handoff. O handoff segue; o gate duro é o da api no plano do Dev Lead. Leitura que falha não acrescenta nada.
- **Onde:** `lib/engine/agents/arquiteto_server.ex` (`executar_offer_infra_handoff`, `modulos_sem_contrato_texto`)
- **Teste:** `test/engine/agents/arquiteto_server_test.exs` ("fechamento lista o módulo usado por outro…")
- **Origem:** AT-981 (achados 35, 38, 39 do TP-01 29ª), Rodada 383, lane E-arq.

<a id="rn-1347"></a>
### RN-1347 — A Infra lê o estado atual das PRs que propôs, e nenhum texto diz que a aprovação é fora da conversa {#rn-1347}

> **Revisa a [RN-772](parte-05.md#rn-772) e a [RN-849](parte-05.md#rn-849)** no texto: o cartão de aprovação da ADR aparece para o usuário na conversa (e em Precisa de você); a intenção continua sendo ler o estado antes de afirmar.

- **Regra (AT-986, achados 6 e 8):** (a) `propose_adr`, `listar_adrs_propostas` e o prompt do Arquiteto não dizem mais que a aprovação "acontece fora desta conversa". (b) A ferramenta `listar_prs_de_infra` (Infra) reusa a consulta de `listar_adrs_propostas` com `action_type = "open_infra_pr"`, no mesmo formato e com o mesmo cruzamento com o `git_merge` (RN-845): aberta, mergeada ou "não consegui ler". O prompt da Infra manda lê-la antes de afirmar o estado de uma PR sua.
- **Onde:** `lib/engine/harness/tools/listar_prs_de_infra.ex`, `lib/engine/harness/tools/listar_adrs_propostas.ex` (`consultar/3`), `lib/engine/infra/infra_lead_server.ex` (`tool_specs`, `run_tool`, prompt)
- **Teste:** `test/engine/harness/tools/listar_prs_de_infra_test.exs`, `test/engine/harness/tools/listar_adrs_propostas_test.exs`
- **Origem:** AT-986 parte E (TP-01 29ª), Rodada 383, lane E-arq.

<a id="rn-1363"></a>
### RN-1363 — A Infra propõe parar, remover e recriar o container pelo chat {#rn-1363}

> **Estende a [RN-508](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-508)** (a Infra só subia o container).

- **Regra (AT-980, achado 14, ADR 0298):** a Infra ganha `propose_container_stop`, `propose_container_remove` e `propose_container_recreate`, que propõem `container_stop`, `container_remove` e `container_recreate` pela `propose_action` da api (a api decide: `remove` e `recreate` nunca se auto-aprovam, RN-934). `recreate` aceita `ports` opcional (o payload da RN-1029). O prompt manda usar `recreate`, e não `start`, para container parado com spec antiga.
- **Onde:** `lib/engine/infra/tools/propose_container_{stop,remove,recreate}.ex`, `lib/engine/infra/infra_lead_server.ex` (`dispatch_container_ciclo`, `tool_specs`, prompt)
- **Teste:** `test/engine/infra/infra_lead_server_test.exs` ("RN-1363"), `test/engine/infra/tools/propose_container_ciclo_test.exs`
- **Origem:** AT-980 L4, Rodada 384, lane E980.

<a id="rn-1364"></a>
### RN-1364 — Parar, remover e recriar recusam localmente o modo que não é do broker {#rn-1364}

- **Regra (AT-980):** as três ferramentas só propõem em `container` e `mounted` (o broker). Em `runner` (e modo desconhecido) a recusa é local, nomeada ("runner fica para depois"), entra no laço como resultado de ferramenta (RN-163) e a api não é chamada.
- **Onde:** `lib/engine/infra/infra_lead_server.ex` (`recusa_de_ciclo_por_modo`)
- **Teste:** `test/engine/infra/infra_lead_server_test.exs` ("RN-1364")
- **Origem:** AT-980 L4, Rodada 384, lane E980.

<a id="rn-1365"></a>
### RN-1365 — Os tetos do `start` contam nove chamadas de controle {#rn-1365}

> **Revisa a [RN-605](https://github.com/viralabs-dev/brabo-contracts/blob/dev/packages/docs/business-rules/contracts.md#rn-605)** (seis chamadas, 195s/185s/225s).

- **Regra (AT-980, ADR 0298):** com a TAG `v1.4.0-dev.1` do contracts, `CHAMADAS_DE_CONTROLE_NO_START` é 9 (prova de rede e de porta antes do `run`). O `RunnerRouter` espera 9 x 30 + 5 = 275s no `start`, e o `propose_action` de ação de container espera 315s (teto da api, 285s, mais 30s de folga). `scripts/baixar-contratos.sh` passa a `v1.4.0-dev.1`.
- **Onde:** `lib/engine/runners/runner_router.ex`, `lib/engine/sessions/engine_api_client.ex` (`@teto_do_propose_action_de_container_ms`), `contracts/docker-cli.json`, `scripts/baixar-contratos.sh`
- **Teste:** `test/engine/runners/runner_router_test.exs`, `test/engine/sessions/engine_api_client_propose_action_test.exs`
- **Origem:** AT-980 L5/L4, Rodada 384, lane E980. O espelho do lado da api (`TETO_DO_PROPOSE_ACTION_DE_CONTAINER_NO_ENGINE_MS`) precisa subir a 315_000 na mesma rodada.

<a id="rn-1360"></a>
### RN-1360 — O dev que precisa de contrato pede ao Arquiteto sem passar pelo LLM do Dev Lead {#rn-1360}

- **Regra (AT-981 C2):** o `report_blocked` aceita `precisa_de: "arquiteto"`. O `DevAgentServer` entrega então o pedido ao Arquiteto (mesmo canal da `pedir_ao_arquiteto`, RN-1012: `chat.message` do `dev-lead` e mensagem ao Arquiteto) e avisa o Dev Lead de que o pedido já foi, para ele só criar a tarefa no módulo dono quando o contrato novo sair. A entrega não depende de o modelo do Dev Lead chamar ferramenta alguma. A `causa` (RN-047/RN-810) segue valendo para o disjuntor; o `precisa_de` não a substitui.
- **Onde:** `lib/engine/dev/tools/report_blocked.ex`, `lib/engine/dev/hooks/termination.ex`, `lib/engine/dev/dev_agent_server.ex` (`avisar_dev_lead/4`), `lib/engine/agents/dev_lead_server.ex` (`aviso_de_bloqueio`)
- **Teste:** `test/engine/dev/bloqueio_conta_so_o_dev_test.exs` ("precisa_de arquiteto…")
- **Origem:** AT-981 C2, Rodada 384, lane E981.

<a id="rn-1378"></a>
### RN-1378 — O Dev Lead levanta cada tarefa antes do plano com `levantar_tarefa` {#rn-1378}

- **Regra (AT-991, AT-952 decisão 1):** a ferramenta `levantar_tarefa` grava `arquivos`, `expoe`, `consome`, `dependencias_npm` e `aceite` pela rota interna `PUT /internal/sessions/:sessionId/tasks/:taskId/levantamento` da api (RN-1370). Lista com item vazio ou `aceite` em branco é recusado sem chamar a api; a recusa da api (400/404) volta ao modelo. Falta contrato entre módulos: o prompt manda usar `pedir_ao_arquiteto` antes de levantar.
- **Revisão (AT-1014):** a descrição da ferramenta e o bloco LEVANTAMENTO do prompt dizem que a tarefa que cria uma tabela do contrato lista no `expoe` a linha `tabela <nome>` e, em `arquivos`, a migração dela; o prompt do Arquiteto pede também a declaração, no dono, de toda tabela que outro módulo cita com `->`. A recusa do plano com tabela sem dono é da api (RN-1509).
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`run_levantar_tarefa`), `lib/engine/sessions/engine_api_client.ex` (`set_levantamento`), `lib/engine/agents/dev_lead_server.ex` (`tool_specs`, `run_tool`, prompt)
- **Teste:** `test/engine/agents/dev_lead_tools_test.exs` ("AT-991")
- **Origem:** AT-991, Rodada 385, lane E991.

<a id="rn-1379"></a>
### RN-1379 — O plano recusa tarefa sem levantamento e leva `depende_de` {#rn-1379}

- **Regra (AT-991, AT-952 decisão 2):** antes de propor, `propose_execution_plan` recusa a tarefa `todo` do plano que ainda não tem levantamento, com a frase que manda chamar `levantar_tarefa`. `tarefas[].depende_de` (ids encurtados viram UUID, RN-721) vai à api como `dependeDe`; ciclo e `consome` sem `expoe` são da api (RN-1371). Falha de leitura do backlog não recusa (RN-792).
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`conferir_levantamento`, `resolver_deps`)
- **Teste:** `test/engine/agents/dev_lead_tools_test.exs` ("AT-991")
- **Origem:** AT-991, Rodada 385, lane E991.

<a id="rn-1380"></a>
### RN-1380 — Dois devs no módulo só com lote de arquivos disjuntos {#rn-1380}

> **Revisa a [RN-083](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-083)** no engine: o `agentes` > 1 deixa de ser "paralelização que só o usuário libera" quando há lote disjunto levantado.

- **Regra (AT-991, AT-952 decisão 4):** `agentes: N` num módulo passa quando há N tarefas do plano nele, sem `depende_de` entre si e com `arquivos` disjuntos (glob contra glob, pelo trecho fixo antes do primeiro curinga). Senão a recusa cita as tarefas e o arquivo em comum. O teto de agentes e de custo continua da api.
- **Onde:** `lib/engine/agents/lote_disjunto.ex`, `lib/engine/agents/dev_lead_tools.ex` (`conferir_lotes`)
- **Teste:** `test/engine/agents/dev_lead_tools_test.exs` ("AT-991")
- **Origem:** AT-991, Rodada 385, lane E991.

<a id="rn-1381"></a>
### RN-1381 — O kickoff do Dev Lead manda levantar, declarar dependência e juntar lote {#rn-1381}

- **Regra (AT-991):** o prompt do kickoff troca "um agente por módulo é o começo razoável" por: levante cada tarefa, declare `depende_de` pela tarefa que expõe o que a outra consome e junte em lote o que tem arquivos disjuntos; sem lote disjunto, um agente por módulo.
- **Onde:** `lib/engine/agents/dev_lead_server.ex` (`build_kickoff/2`)
- **Origem:** AT-991, Rodada 385, lane E991.

<a id="rn-1401"></a>
### RN-1401 — O QA julga as PRs em paralelo: um ciclo por tarefa {#rn-1401}

> **Revisa o ADR 0038** (QA Lead serial) e **estende a [RN-806](parte-05.md#rn-806)** e a [RN-722](parte-04.md#rn-722).

- **Regra (AT-989):** o `QaCiclos` (um por projeto, na mesma chave `{project_id, "qa"}` do Registry, então o `Dispatcher`, o `GateRescuer` e o encerramento da sessão não mudam) abre um `QaLeadServer` POR TAREFA e não roda ciclo nenhum por conta própria. Duas PRs prontas no mesmo projeto são julgadas ao mesmo tempo; cada `qa_verdict` sai sem esperar o outro. O processo do ciclo sai ao terminar (veredito ou bloqueio) e leva ao `QaCiclos` a contagem de retomadas do gate ([RN-1349](parte-07.md#rn-1349)), que sobrevive ao ciclo; suspenso esperando decisão fica vivo. Pedido repetido de tarefa em voo (ou na fila) é ignorado, e os pedidos anteriores ao veredito continuam descartados (RN-806). O `em_voo?` do resgate (RN-722) responde por tarefa: ciclo, suspenso ou na fila conta como em voo. Ciclo que morre sem avisar libera a vaga e a linha de `GateState` segue `in_progress` para o resgate reabrir. O clone limpo já é por diretório do worktree da tarefa (RN-1121).
- **Onde:** `lib/engine/gates/qa_ciclos.ex`, `lib/engine/gates/qa_lead_server.ex` (`init/1`, `handle_continue/2`, `concluir`), `lib/engine/gates/qa_lead_supervisor.ex`
- **Teste:** `test/engine/gates/qa_ciclos_test.exs`, `test/engine/gates/qa_lead_server_test.exs` ("AT-989"), `test/engine/gates/gate_rescuer_test.exs`
- **Origem:** AT-989 (EP-035), itens 6 e 9 da AT-951, Rodada 386.

<a id="rn-1402"></a>
### RN-1402 — O gate tem teto de ciclos simultâneos por projeto {#rn-1402}

- **Regra (AT-989):** no máximo `QaCiclos.teto/1` ciclos RODANDO ao mesmo tempo por projeto: o número de dev agents ativos (`dev-<módulo>`, sem o `dev-lead`; no mínimo 1), limitado por `:qa_ciclos_maximo` (15, o teto de agentes). `:qa_ciclos_por_projeto` fixa o número (testes). A N+1ª tarefa espera na fila e entra quando uma vaga abre (ciclo terminado ou suspenso). Ciclo suspenso esperando decisão humana não ocupa vaga, como o Lead serial, que ficava livre nessa espera; ao ser retomado ele não pede vaga de novo.
- **Onde:** `lib/engine/gates/qa_ciclos.ex` (`teto`, `abrir_vagas`)
- **Teste:** `test/engine/gates/qa_ciclos_test.exs` ("a N+1ª task espera uma vaga")
- **Origem:** AT-989 (EP-035), Rodada 386.

<a id="rn-1403"></a>
### RN-1403 — O ambiente do QA sobe enquanto a QA-estratégia monta o plano {#rn-1403}

> **Revisa a [RN-674](parte-04.md#rn-674)** (o plano é o primeiro passo do ciclo) no ponto da ordem.

- **Regra (AT-989):** no começo do ciclo o clone limpo ([RN-1121](parte-07.md#rn-1121)) é preparado numa `Task` enquanto a QA-estratégia monta o plano de teste; a Automação só começa quando os dois acabaram. O plano continua sendo um insumo, nunca um veredito, e falha dele não segura a revisão. A parte da api é a [RN-1404](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api/parte-12.md#rn-1404) (a QA-estratégia sem raciocínio).
- **Onde:** `lib/engine/gates/qa_lead_server.ex` (`run_area`)
- **Teste:** `test/engine/gates/qa_lead_server_test.exs` (os ciclos existentes passam pelo mesmo caminho)
- **Origem:** AT-989 (EP-035), item 5 do levantamento, Rodada 386.

<a id="rn-1415"></a>
### RN-1415 — A fundação declara todos os workspaces e as dependências npm {#rn-1415}

> **Completa a [RN-1133](parte-07.md#rn-1133)** e a [RN-1006](parte-06.md#rn-1006).
> **Estendida pela [RN-1506](parte-07.md#rn-1506)** (AT-1020): na correção, o worktree limpo conta como commit executado.
> **Estendida pela [RN-1506](parte-07.md#rn-1506)** (AT-1020): na correção, o worktree limpo conta como commit executado.

- **Regra (AT-992):** a fundação do primeiro módulo pegável cria a raiz com TODOS os workspaces do `module_map`, o `package.json` de cada módulo já com as `dependencias_npm` do levantamento ([RN-1378](parte-07.md#rn-1378)) e o lockfile, numa tacada só. README da raiz, compose e entrada do servidor ficam com a tarefa integradora.
- **Onde:** `lib/engine/agents/dev_lead_server.ex` (`build_kickoff/2`)
- **Teste:** `test/engine/agents/dev_lead_server_test.exs` ("RAIZ do workspace")
- **Origem:** AT-992 (EP-035), Rodada 387, lane E992.

<a id="rn-1416"></a>
### RN-1416 — A tarefa de módulo não toca a raiz do workspace {#rn-1416}

- **Regra (AT-992, revisada na AT-1020):** só a tarefa de fundação (`fundacao` da api) e a integradora (título com "integra") alteram `package.json`, lock, README e compose da raiz. As demais passam pelo `report_done` com essa conferência no worktree (`git status`). Duas saídas: (a) o lock da raiz (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`) é derivado do `package.json` do módulo e só conta quando o `package.json` da raiz também mudou; (b) o desbloqueio com orientação do dono (`desbloqueio.orientacao` não vazia no dev-context, RN-1135) libera a raiz para AQUELA tarefa, sem ler o texto da orientação. Sem saída, a recusa manda o modelo chamar `report_blocked` pedindo ao usuário que desbloqueie (sem `git checkout`: o container não tem git).
- **Onde:** `lib/engine/dev/raiz_da_fundacao.ex` (`dona?/1`, `autorizada?/1`, `da_raiz/1`, `recusa/1`), `lib/engine/dev/tools/report_done.ex` (`run/2`), `lib/engine/dev/dev_agent_server.ex` (`dono_da_raiz` do contexto)
- **Teste:** `test/engine/dev/raiz_da_fundacao_test.exs`
- **Origem:** AT-992 (EP-035), Rodada 387, lane E992.

<a id="rn-1417"></a>
### RN-1417 — O Dev Lead narra o segundo dev do plano aprovado {#rn-1417}

- **Regra (AT-992):** o resultado do plano traz `segundoDev` (módulos em que o `dev-<m>-2` subiu) e `segundoDevRecusado` (módulo e motivo, p.ex. o teto da área, conferido pela api no aceite da paralelização); o Dev Lead cita os dois ao narrar, e o módulo recusado segue com um agente. O teto não é conferido na proposta do engine: a api é a dona dele.
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`resumo_do_plano/1`, `segundo_dev/1`)
- **Teste:** `test/engine/agents/dev_lead_tools_test.exs` ("RN-1417")
- **Origem:** AT-992 (EP-035), Rodada 387, lane E992.

<a id="rn-1419"></a>
### RN-1419 — A rede provada retoma sozinha a tarefa bloqueada por falta dela {#rn-1419}

- **Regra (AT-995; completa a RN-1059 e a RN-864):** o `container.running` leva `redeProvada` (ausente vale `false`; só `true` quando a prova de DNS rodou e passou). Com `true`, o `DesbloqueioPorRedeWorker` lê o backlog do projeto e retoma, pelo mesmo desbloqueio da retomada automática (ator `system`), as tarefas com `blockedOrigin` `infra` e motivo de rede (`falha passageira de rede`, `sem rede`, `EAI_AGAIN`, `ENOTFOUND`, `getaddrinfo`), com a orientação "a rede do container voltou (provada às HH:MM UTC); parta do último commit do worktree". Bloqueio de outra causa (parecer de QA, limite de uso, PR divergente) não é tocado; `EngineApiClient.unblock_task/5` manda `orientacao` quando há.
- **Onde:** `lib/engine/workers/desbloqueio_por_rede_worker.ex` (`perform/1`), `lib/engine/outbox/drain.ex` (`handlers_for("container.running")`), `lib/engine/sessions/engine_api_client.ex` (`unblock_task/5`)
- **Teste:** `test/engine/workers/desbloqueio_por_rede_worker_test.exs`, `test/engine/outbox/drain_test.exs`
- **Origem:** AT-995 (EP-035), Rodada 388, lane E995.

<a id="rn-1420"></a>
### RN-1420 — Uma retomada por prova de rede por tarefa {#rn-1420}

- **Regra (AT-995):** o job é único pelo id do evento do outbox (`event_id`, propagado pelo `Drain`) e não retenta (`max_attempts: 1`): a mesma prova nunca retoma duas vezes. A tarefa que voltar a bloquear pela rede só é retomada por uma prova NOVA (outro evento); sem ela, fica para a pessoa. Falha da api na retomada não repete.
- **Onde:** `lib/engine/workers/desbloqueio_por_rede_worker.ex` (`unique`), `lib/engine/outbox/drain.ex` (`enqueue_and_mark/1`)
- **Teste:** `test/engine/workers/desbloqueio_por_rede_worker_test.exs` ("a mesma prova")
- **Origem:** AT-995 (EP-035), Rodada 388, lane E995.

<a id="rn-1506"></a>
### RN-1506 — A correção sem nada a commitar publica e reabre o gate {#rn-1506}

> **Estende a [RN-1078](parte-07.md#rn-1078).**

- **Regra (AT-1020):** no `report_done` da correção (gate ou conflito), se o `git status --porcelain` do worktree local sai vazio (o `wip` já foi enviado), o commit vale `executed` sem propor `git_commit`, e o push e a guarda do HEAD igual ao do remoto seguem como na RN-1078. Sem worktree local (modo `runner`) ou com o git falhando, vale o commit de sempre. A entrega inicial sem diff continua falhando (`GitExecutor.commit/1` não muda). Commit ou push recusado na correção bloqueia (origem `infra`) com motivo em linguagem simples ("Não consegui salvar/enviar a correção para o repositório do projeto"); o texto técnico fica no diagnóstico.
- **Onde:** `lib/engine/dev/dev_agent_server.ex` (`handle_correction_outcome/3`, `worktree_limpo?/1`)
- **Teste:** `test/engine/dev/conflito_e_push_test.exs` ("worktree limpo conta como commit feito", "commit recusado bloqueia em linguagem simples"), `test/engine/actions/git_executor_test.exs` (o executor ainda recusa o commit vazio)
- **Origem:** AT-1020 (EP-036), TP-01 30ª, achados 28 e 42.

<a id="rn-1505"></a>
### RN-1505 — O Dev Lead lê a execução do projeto, a decisão do usuário vence a ferramenta e a pergunta repetida é recusada {#rn-1505}

> **Estende a [RN-1335](#rn-1335), a [RN-874](parte-05.md#rn-874) e a [RN-862](parte-05.md#rn-862).**

- **Regra (AT-1018):** `ler_plano` dá "execucao ativa: sim" com `execution.plan_applied` na sessão do Dev Lead, com `execution.activated` ou com dev agent do projeto (`execucao_ativa?`): o `execution.activated` é gravado na sessão de EXECUÇÃO, não na do Dev Lead. O desfecho do plano vem do evento mais recente (`execution.plan_applied` = "aprovado e aplicado"; `execution.plan_failed` = "falhou ao aplicar: motivo"). `ler_estado_da_pr` de tarefa `done` diz "gate=aprovado, PR mergeada", nunca `awaiting_user` (a api o guarda por desenho). O fluxo do time diz que o merge é automático com a chave do projeto ligada (padrão). O bloco de decisões do turno manda a decisão do usuário vencer a leitura de ferramenta que a contradiga, sem reabrir a pergunta. `declare_open_question` recusa a `pergunta` de texto igual (normalizado por `ArtifactDedupe.normalizar/1`) a uma aberta (nomeia o `questionId`) ou respondida (nomeia a escolha), sem gravar evento; paráfrase não é pega.
- **Por quê:** TP-01 30ª, achados 11, 15, 20 e 35: `ler_plano` dizia "execução ativa: não" com a execução rodando e o Dev Lead reabriu a mesma pergunta três vezes.
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`run_ler_plano`, `desfecho_do_plano`, `gate_da_leitura`), `lib/engine/harness/fluxo_do_time.ex`, `lib/engine/harness/decisoes_do_projeto.ex` (`montar/3`), `lib/engine/harness/tools/declare_open_question.ex` (`sem_repeticao`)
- **Teste:** `test/engine/agents/dev_lead_tools_test.exs` e `dev_lead_tools_ler_plano_test.exs` (AT-1018), `test/engine/harness/decisoes_do_projeto_test.exs`, `fluxo_do_time_test.exs`, `tools/declare_open_question_test.exs`
- **Origem:** AT-1018 (EP-036), Rodada 396, lane E1.

<a id="rn-1507"></a>
### RN-1507 — A Infra escreve a TAG da imagem do serviço de QA e o Brabo fixa o digest {#rn-1507}

> **Revisa o item 3 do ADR 0229 e a [RN-935](parte-06.md#rn-935) no engine.**

- **Regra (AT-1015/A):** `run.qa.services[].image` aceita `nome:tag` (sem `latest`, sem imagem sem tag) ou `nome@sha256:<64 hex>`. O prompt e a descrição da ferramenta mandam escrever a tag do compose e nunca perguntar o digest ao dono. Quem resolve o digest é a api, na proposta (RN-1507 da api, que a recusa de rede nomeada); da api para dentro o digest segue obrigatório.
- **Onde:** `lib/engine/infra/instrucoes_de_execucao.ex` (`servico`), `lib/engine/infra/tools/propose_infra_pr.ex`, `lib/engine/infra/infra_lead_server.ex` (prompt do passo 7)
- **Teste:** `test/engine/infra/instrucoes_de_execucao_qa_test.exs`
- **Origem:** AT-1015 (EP-036), TP-01 30ª, achado 30.

<a id="rn-1508"></a>
### RN-1508 — `propose_infra_pr` sem arquivo é recusada antes do HALT {#rn-1508}

- **Regra (AT-1015/A):** `files` ausente ou vazio na `propose_infra_pr` volta ao modelo (RN-163) com "inclua o arquivo que muda, por exemplo o compose com o serviço do banco", sem proposta e sem rodar o Workflows. A api recusa o mesmo na proposta (400 `infra_pr_sem_arquivos`).
- **Onde:** `lib/engine/infra/infra_lead_server.ex` (`recusa_de_infra_pr`, `recusa_de_pr_sem_arquivos`)
- **Teste:** `test/engine/infra/infra_lead_server_test.exs` (`com files vazio`)
- **Origem:** AT-1015 (EP-036), TP-01 30ª, achado 34.

<a id="rn-1512"></a>
### RN-1512 — O QA de Automação espera a vez da instância de QA em vez de bloquear a tarefa {#rn-1512}

> **Revê a [RN-940](parte-06.md#rn-940) para a recusa por teto e depende da [RN-936](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api/parte-11.md#rn-936) (o `codigo`).**

- **Regra (AT-1017):** quando a subida da instância (`qa_environment_start`) volta `failed` com `executionResult.codigo == "instancia_de_qa_ocupada"` (teto de 1 por projeto, [RN-935](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api/parte-11.md#rn-935)), o `QaAutomacaoAgent` espera a vez: grava UMA vez o evento `qa.awaiting_environment` (ator `qa-automacao`, `{taskId, desde}`) e tenta de novo com recuo de 15, 30, 60 e depois a cada 120 s (`:qa_instancia_espera_intervalos_ms`). Quando a subida passa, segue o fluxo normal. Passados 60 min (`:qa_instancia_espera_maxima_ms`), bloqueia com origem `infra` e o motivo "QA de Automação esperou 60 min a vez no ambiente de teste; outra tarefa segue com ele" ([RN-059](parte-01.md#rn-059)). Qualquer outra falha da subida, ou `failed` sem `codigo` (api antiga), segue a RN-940. A tarefa que já está bloqueada por esse motivo não é desbloqueada sozinha.
- **Por quê:** TP-01 30ª, achado 18: com os ciclos de QA em paralelo ([RN-1401](#rn-1401)), duas PRs chegaram com 54 s de diferença e a segunda tarefa bloqueou, sem desbloqueio quando a instância liberava. O ciclo esperando segue vivo para o resgate ([RN-722](parte-04.md#rn-722)).
- **Onde:** `lib/engine/gates/qa_automacao_agent.ex` (`subir`, `esperar_a_vez`, `ocupada?`), `test/support/fake_engine_api_client.ex` (`propose_action`, `:fake_propose_action_seq`).
- **Teste:** `test/engine/gates/qa_automacao_agent_instancia_test.exs` ("ocupada espera a vez", "ocupada até o teto de espera").
- **Origem:** AT-1017 (EP-036), Rodada 396, lane Q1017.

<a id="rn-1513"></a>
### RN-1513 — O QA só aprova com prova: regra sem teste, teste pulado e decisão não cumprida reprovam {#rn-1513}

> **Revisa a [RN-817](parte-05.md#rn-817)** (teste pulado deixa de ser observação no `resumo`), a [RN-765](parte-05.md#rn-765) (`outra_tarefa` passa a ser marcação explícita na matriz) e a [RN-1116](#rn-1116) (regra sem prova nunca é `melhorias`).

- **Regra (AT-1023):** `emit_qa_verdict` só aceita `approved` (além do exit 0) quando a `coverageMatrix` tem uma linha por regra da história (`rf` + `rnf`) e por decisão do dono desta tarefa, e nenhuma linha está sem prova. Linha sem prova (`covered: false`, ou `covered: true` cujos `tests` todos retornam cedo sem asserir) só passa com `motivo: "outra_tarefa"`, ou com `motivo: "aceito_pelo_dono"` e ao menos uma decisão registrada NAQUELA tarefa. A recusa volta ao laço ([RN-163](parte-01.md#rn-163)). O engine detecta o teste que retorna cedo por variável de ambiente (`if (!x) return;` antes de qualquer `expect`/`assert`, só JS/TS, regex) e o lista no recorte como "não prova nada"; o `it.skip` já é pulado no JUnit ([RN-996](parte-06.md#rn-996)). O prompt e o recorte mandam cada decisão do dono virar uma linha da matriz, e decisão não cumprida por outro agente reprova com origem `infra`, nunca vai para `melhorias`. `resumo` e `melhorias` falam em linguagem simples para o usuário leigo.
- **Por quê:** TP-01 30ª, achados 29 e 32: o QA viu testes que retornam cedo sem banco e, na 2ª volta, aprovou com eles como "melhoria". A justificativa livre era a saída; agora só há `outra_tarefa` e a decisão registrada.
- **Onde:** `lib/engine/gates/tools/emit_qa_verdict.ex:149` (`recusa_da_matriz`), `lib/engine/gates/testes_sem_prova.ex:44` (`retorna_cedo?`), `lib/engine/gates/recorte_da_tarefa.ex:266` (`secao_dos_testes_sem_prova`), `lib/engine/gates/qa_lead_server.ex:983` (`testes_sem_prova`), `lib/engine/gates/qa_automacao_agent.ex` (`build_ctx`, prompt do veredito)
- **Teste:** `test/engine/gates/tools/emit_qa_verdict_test.exs` ("approved e a matriz"), `test/engine/gates/testes_sem_prova_test.exs`, `test/engine/gates/recorte_da_tarefa_test.exs` ("decisão da tarefa vira linha da matriz")
- **Origem:** AT-1023 (EP-036), Rodada 398, lane E1023.

<a id="rn-1515"></a>
### RN-1515 — A prova de app de pé é do módulo que sobe o app, e o esqueleto prova o compose cedo {#rn-1515}

> **Revisa a [RN-1097](#rn-1097) e a [RN-1119](#rn-1119)** (a receita e a prova do app de pé deixam de valer para toda tarefa), a [RN-1330](#rn-1330) (o compose real também é provado na fundação do esqueleto) e a [RN-1089](#rn-1089) (a correção de subida vai ao dono do ponto de entrada). Estende a [RN-1006](parte-06.md#rn-1006).

- **Regra (AT-1016):** a api diz, no contexto do dev, o `moduloDoPontoDeEntrada` e se a tarefa é o `esqueletoDoApp` (campos opcionais; sem eles vale o comportamento de antes, e projeto com dois apps, api + web, também). (1) Tarefa de OUTRO módulo: o recorte do QA troca "o ponto de entrada REAL sobe" pela suíte do módulo com um teste que monta o registrador numa instância do framework (ex.: `inject`), e o app de pé é observação no `resumo`; o que é da rota (README ↔ código, mesmo `code` de erro) continua item. O kickoff do dev só leva a receita de subir o app no módulo do ponto de entrada, no esqueleto ou com o módulo desconhecido (`RecorteDaTarefa.de_outro_modulo_que_o_do_app?/2`, régua única). (2) A fundação do esqueleto pede a `ProvaDeCompose` ao broker, como a última tarefa; a reprovação volta ao dev do esqueleto, sem passar pelo usuário. (3) O `ReiniciarAppWorker` aceita `modulo` na falha (só o nome, `^[a-z0-9][a-z0-9_-]{0,63}$`) e o aviso ao Dev Lead manda criar a correção nesse módulo, que espera as dependências sozinha; um `app.restarted` logo depois de um `app.restart_failed` acorda o Dev Lead com `{:app_voltou, %{}}` para arquivar (`arquivar_tarefa`) a correção que ficou aberta. (4) O prompt do plano põe os scripts `build`/`migrate`/`start` da raiz, o servidor vazio e o Dockerfile na fundação do esqueleto (a integradora só registra as rotas), e a Infra sabe que o Dockerfile é rascunho. O lado da api é a RN-1514.
- **Onde:** `lib/engine/gates/recorte_da_tarefa.ex` (`de_outro_modulo_que_o_do_app?`, `secao_do_ponto_de_entrada`), `lib/engine/dev/dev_agent_server.ex` (`receita_de_prova`), `lib/engine/gates/qa_lead_server.ex` (`prova_de_compose`), `lib/engine/workers/reiniciar_app_worker.ex` (`falha`, `perform`), `lib/engine/agents/dev_lead_server.ex` (`aviso_de_app`, `aviso_de_app_voltou`), `lib/engine/dev/context_builder.ex` (`build`), `lib/engine/infra/infra_lead_server.ex`
- **Teste:** `test/engine/gates/recorte_da_tarefa_test.exs` ("a prova do app de pé é do módulo que o sobe"), `test/engine/dev/report_done_instrucao_test.exs`, `test/engine/gates/qa_lead_server_test.exs` ("fundação do esqueleto"), `test/engine/workers/reiniciar_app_worker_test.exs`, `test/engine/agents/dev_lead_server_test.exs`
- **Origem:** AT-1016 (EP-036), TP-01 30ª, achados 13, 14, 22, 25, 31 e 38.

<a id="rn-1516"></a>
### RN-1516 — A decisão do dono acorda o Dev Lead que perguntou, que executa ou diz em uma frase o que só o dono faz {#rn-1516}

> **Estende a [RN-1003](parte-06.md#rn-1003) e a [RN-1012](parte-06.md#rn-1012).** O lado da api é a RN-1516 da api (a linha de outbox na transação do fechamento). Desbloquear e Rearmar seguem gesto humano ([RN-1335](#rn-1335)).

- **Regra (AT-1019):** o drain roteia `open_question.answered` para o `DecisaoDoDonoWorker`. Quando o `autor` é `dev-lead`, o worker entrega `{:decisao_do_dono, %{pergunta, resposta}}` pelo `Engine.Dev.Wake` e o `DevLeadServer` abre turno (ou enfileira, com turno em curso) com o aviso "Execute AGORA com as suas ferramentas... ou diga em UMA frase simples o que só o dono faz e onde. Não pergunte de novo." Outro autor (Criativo, PO, Arquiteto) é no-op. Entrega at-most-once; a decisão segue no contexto passivo (`DecisoesDoProjeto`). O texto de `declare_open_question` diz que a sugestão é ação com ferramenta que existe ou escolha de produto/gasto, que o que só o usuário faz no painel não vira pergunta e que não se sugere "reabrir" tarefa concluída.
- **Onde:** `lib/engine/workers/decisao_do_dono_worker.ex` (`perform`), `lib/engine/outbox/drain.ex` (`handlers_for`), `lib/engine/agents/dev_lead_server.ex` (`aviso_de_decisao`), `lib/engine/harness/tools/declare_open_question.ex` (`spec`)
- **Teste:** `test/engine/workers/decisao_do_dono_worker_test.exs`, `test/engine/outbox/drain_test.exs` (`open_question.answered`), `test/engine/agents/dev_lead_server_test.exs` (`RN-1516`), `test/engine/harness/tools/declare_open_question_test.exs` (`RN-1517`)
- **Origem:** AT-1019 (EP-036), TP-01 30ª, achados 41 e 43.

<a id="rn-1517"></a>
### RN-1517 — A correção é tarefa nova no mesmo módulo, e a Infra mexe só no container de trabalho, com o estado à vista {#rn-1517}

> **Revisa a [RN-1006](parte-06.md#rn-1006)** (fundação ou correção). Estende a [RN-1364](#rn-1364). O lado da api é a RN-1517 da api (`containerDoProjeto` e `instanciaDeQa` no contexto da Infra).

- **Regra (AT-1019):** (1) o kickoff do Dev Lead e a spec de `create_task` dizem que a correção num módulo que já tem tarefa, inclusive concluída, é tarefa NOVA no mesmo módulo; não existe "reabrir". (2) O kickoff da Infra traz "Container de trabalho: <status> desde <t>. Instância de QA ativa: tarefa <id> (<status>) | nenhuma." (3) `propose_container_recreate` e o passo 7 do prompt dizem que recriar é só o container de TRABALHO e que NUNCA é a instância de QA, que é do QA de Automação e da api: pedido para recriá-la ou liberá-la é respondido como "não é minha; o QA espera a vez", sem proposta. (4) O aviso de parada do Dev Lead diz que a instância de QA não é dele nem da Infra.
- **Onde:** `lib/engine/agents/dev_lead_tools.ex` (`spec_create_task`), `lib/engine/agents/dev_lead_server.ex` (`aviso_de_parada`), `lib/engine/infra/infra_lead_server.ex` (`estado_registrado`), `lib/engine/infra/tools/propose_container_recreate.ex` (`spec`)
- **Teste:** `test/engine/agents/dev_lead_server_test.exs` (`RN-1517`), `test/engine/agents/dev_lead_tools_test.exs` (`create_task do Dev Lead`), `test/engine/infra/infra_lead_server_test.exs` (`RN-1517`)
- **Origem:** AT-1019 (EP-036), TP-01 30ª, achados 19, 21 e 43.

<a id="rn-1521"></a>
### RN-1521 — A Infra declara o banco do compose em `run.qa.services` e a URL em `run.env`, e o dev roda a migração de verdade {#rn-1521}

> **Estende a [RN-851](parte-05.md#rn-851) e a [RN-1507](#rn-1507)** (ADR 0229, AT-1015). O lado da api é a RN-1520 da api.

- **Regra (AT-1015):** (1) `run.env` (opcional) é validado no engine com a MESMA régua da api, antes do HALT: até 20 variáveis `[A-Z_][A-Z0-9_]*`, valor de texto de uma linha; a recusa nomeia `` `run.env` `` ou `` `run.env.<NOME>` ``. É valor de DESENVOLVIMENTO (tipicamente `DATABASE_URL` do banco descartável em `127.0.0.1`), nunca segredo real, e o prompt da Infra e a spec de `propose_infra_pr` dizem isso. (2) `propose_infra_pr` cujo compose declara imagem de banco conhecido (postgres, pgvector, mysql, mariadb, mongo, redis, valkey, minio) que não está em `run.qa.services` é recusada antes do HALT, em linguagem simples, mandando declarar o serviço (imagem por `nome:tag`, o Brabo fixa o digest) e a URL em `run.env`, sem perguntar nada técnico ao dono. (3) O prompt da Infra pede o serviço de dados do compose em `run.qa.services` e a URL em `run.env` sempre que o ADR ou o mapa do Arquiteto pede banco. (4) O recorte do QA cita as variáveis de `run.env` e proíbe pedir ao dono uma URL de banco de teste; o kickoff do dev diz que o banco está em `127.0.0.1` no container de trabalho e que a migração roda de verdade nele antes de dar a tarefa por pronta. Limite: a lista de bancos é fixa; imagem fora dela não é conferida.
- **Onde:** `lib/engine/infra/instrucoes_de_execucao.ex` (`run_env`), `lib/engine/infra/infra_lead_server.ex` (`recusa_de_banco_fora_do_qa`, prompt), `lib/engine/infra/tools/propose_infra_pr.ex` (`spec`), `lib/engine/gates/recorte_da_tarefa.ex` (`secao_do_ambiente_limpo`), `lib/engine/dev/dev_agent_server.ex` (`initial_message`)
- **Teste:** `test/engine/infra/instrucoes_de_execucao_test.exs` (`run.env`), `test/engine/infra/infra_lead_server_test.exs` (`banco do compose exige run.qa.services`), `test/engine/gates/recorte_da_tarefa_test.exs` (RN-817), `test/engine/dev/report_done_instrucao_test.exs` (`RN-1521`)
- **Origem:** AT-1015 (EP-036), TP-01 30ª, achados 24, 30 e 34.
