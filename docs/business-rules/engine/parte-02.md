---
id: rn-engine-parte-02
title: 'Regras de negócio — Engine — parte 2 (desde RN-305)'
sidebar_label: 'Engine — parte 2 (desde RN-305)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

# Engine — parte 2 (desde RN-305)

## Staff: código pronto, dormente para disparo automático (RN-305/RN-306, ADR 0088)

Não é fase planejada: `packages/contracts/fluxo.yml` declara o Staff/Principal Engineer como
`status: planned` desde o ADR 0085 ("contrato pronto, ativação decidida,
aguarda gatilho"). O dono do produto decidiu antecipar o CÓDIGO mesmo sabendo
que o gatilho automático (a Anamnese notando um problema sistêmico
RECORRENTE) não vai disparar — a Anamnese está pausada
(`ANAMNESE_ENABLED=false`, decisão de produto de 2026-08-10). Ver a
pendência já documentada em RN-086: o mesmo sinal que faria a Anamnese
propor subir o teto de paralelismo é o que faria ela propor um handoff ao
Staff, e nenhum dos dois dispara enquanto ela estiver pausada.

<a id="rn-305"></a>

### RN-305 — O Staff ativa pelo caminho GENÉRICO de handoff, sem `USER_STARTED_AGENTS`, e sem `kickoff/1` {#rn-305}

`USER_STARTED_AGENTS` (`apps/api/src/domain/sessions/agent-activation.ts`) é
a exceção do Criativo (inicia SEM handoff, por comando do usuário) — o Staff
NÃO entra nela. Investigação confirmou que `canActivateAgent` já ativa
qualquer agente com handoff `accepted` endereçado a ele, o mesmo caminho que
já vale para `dev-lead`/`arquiteto`/`infra`; e `assertHandoffTargetAllowed`
(`apps/api/src/domain/agents/agent-areas.ts`) só recusa handoff endereçado a
SUBAGENTE de área — o Staff não tem área, então nenhuma mudança de domínio
na api foi necessária. "Acionável manualmente" significa que a MECÂNICA de
domínio permite (qualquer agente pode chamar
`EngineApiClient.create_handoff(..., "staff", ...)`, e um humano aceita pela
rota já existente), não que existe hoje uma tela dedicada para escolher
"endereçar handoff ao Staff" — a UI genérica de handoff a agente à escolha
segue no backlog (`docs/explanation/backlog.md`), como já estava antes desta
mudança.

`Engine.Agents.StaffServer` (`apps/engine/lib/engine/agents/staff_server.ex`)
é o quinto agente conversacional solo (junto de Criativo, PO, Arquiteto, Dev
Lead), espelhando o Arquiteto — `GenServer` por sessão, rehydration do event
log, laço bounded de tool use com teto 14 (`staff_server.ex:49`) — mas **sem
`kickoff/1`**: os outros leads sintetizam uma instrução de abertura a partir
de um artefato anterior no event log da sessão (product_brief, module_map,
backlog); o Staff não tem essa fonte, porque o problema sistêmico nasce de
fora da sessão. `StaffSupervisor.start_agent/2` sobe o processo (rehidrata o
histórico) e ele fica ocioso até a primeira `user_message`
(`staff_server.ex:60`) — que é como quem endereçou o handoff explica o
problema. `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:60`
(cláusula `start/2` de `"staff"`) nunca chama `kickoff` (a função nem
existe), ao contrário de po/arquiteto/dev-lead/infra.

- **Onde:** `apps/api/src/domain/sessions/agent-activation.ts`
  (`canActivateAgent`, `USER_STARTED_AGENTS` — intocado),
  `apps/api/src/domain/agents/agent-areas.ts`
  (`assertHandoffTargetAllowed` — intocado),
  `apps/engine/lib/engine/agents/staff_server.ex`,
  `staff_supervisor.ex`,
  `apps/engine/lib/engine_web/controllers/agent_command_controller.ex`
  (cláusulas `start/2`/`message/2`/`via_for/2` de `"staff"`),
  `apps/engine/lib/engine/application.ex` (`Engine.Agents.StaffSupervisor`
  na árvore de supervisão)
- **Teste:** `apps/engine/test/engine/agents/staff_server_test.exs`
  (rehydration, ausência de kickoff automático — o turno só roda por
  `user_message`)
- **ADR:** [0088](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0088-staff-agente-dormente-para-disparo-automatico.md)

<a id="rn-306"></a>

### RN-306 — `propose_rfc` grava o artefato DIRETO e devolve o handoff no MESMO tool call, sem `proposed_action` {#rn-306}

`Engine.Agents.StaffTools.propose_rfc`
(`apps/engine/lib/engine/agents/staff_tools.ex:41`) é a única ferramenta do
Staff: problema, opções com trade-offs, recomendação e o escopo de uma PoC
DESCARTÁVEL (`descartavel: true` é FIXO — nunca escrito pelo modelo). `run/2`
(`staff_tools.ex:89`) grava `artifact.rfc_staff` via
`EngineApiClient.append_event_returning/3` — mesmo padrão SEM tabela e SEM
caso de uso dedicado de `Engine.Harness.Tools.EmitInsight` (o `emit_insight`
do Arquiteto), e não o de `artifact.c4_diagram` (ADR 0068), que tem caso de
uso próprio na api porque DERIVA o nível Container do `module_map` vigente —
o RFC não deriva nada do lado de lá, todo o payload vem do tool call.

Depois de gravar, o MESMO `run/2` chama
`EngineApiClient.create_handoff(..., "staff", "arquiteto", artifact_id)` —
sem confirmação humana no meio, mesmo padrão de
`CriativoServer.executar_confirm_readiness/1` emitindo o product_brief e
oferecendo o handoff ao PO na mesma resposta. `propose_rfc` NÃO é
`proposed_action`: registrar um documento de arquitetura não é efeito
externo (não é git, terminal, nem gasto de agente) — a decisão real
(adotar, adaptar, recusar a recomendação) é do Arquiteto, no handoff que a
ferramenta já devolve. Falha ao criar o handoff NÃO derruba o processo nem
perde o RFC já gravado (RN-116) — o motivo entra no tool-result, e o modelo
sabe que precisa tentar de novo só o handoff, não reescrever o RFC.

- **Onde:** `apps/engine/lib/engine/agents/staff_tools.ex`
- **Teste:** `apps/engine/test/engine/agents/staff_server_test.exs`
  ("propõe o RFC, grava o artefato e devolve o handoff ao arquiteto";
  "propose_rfc com opções vazias vira tool-result de erro"; "falha ao
  devolver o handoff ao arquiteto NÃO derruba o processo")
- **ADR:** [0088](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0088-staff-agente-dormente-para-disparo-automatico.md)

**Declarado, não escondido**: a roster do painel do time
(`apps/web/src/lib/agent-status.ts`, `staffActive`) e o card do dashboard
(`ProjectCardSummary.roster`, `apps/api/.../projects-summary.repository.ts`)
mostram o Staff quando ativo, mesmo critério de `infraActive` — evitando a
divergência que o comentário de `RosterFacts` já alertava. `SessionPage.tsx`
NÃO foi tocado: `staff` fica fora de `AGENTES_DE_CHAT`, o mesmo padrão já
aceito para `infra` (um lead REAL e ATIVO também fora dessa lista — o
handoff para ele "nunca é aceito por AQUI", conforme o comentário do próprio
arquivo). O caminho ponta a ponta de uso hoje é a rota interna
(`POST .../agent/message`, `agent: "staff"`), não a tela de Sessão.

---

## O appsec ganha o segundo momento do secops (RN-360/361, ADR 0090)

`packages/contracts/fluxo.yml` já declarava o `id: appsec` como `proposto`, com o critério
de separação escrito por antecipação: "mesmo padrão do QA: dois MOMENTOS, não
dois agentes por ora". Esta mudança constrói esse segundo momento — threat
model de DESIGN, ANTES de existir código/PR — decisão consciente do dono do
produto de antecipar a ativação, sem esperar o gate `implementavel` que o
próprio registro citava como gatilho.

<a id="rn-360"></a>

### RN-360 — O threat model de DESIGN roda sobre story + module_map, sem worktree/task_id, no MESMO processo do secops {#rn-360}

Quem roda o appsec é o MESMO `Engine.Gates.SecOpsAgentServer` que já existe
para o veredito determinístico de PR — não um processo novo. `run_design/2`
(`apps/engine/lib/engine/gates/secops_agent_server.ex:76`) é um `GenServer.cast`
para a mesma chave de `Registry` (`{project_id, "secops"}`) que `run/2` já
usa; o `handle_cast({:run_design, story_id}, state)`
(`secops_agent_server.ex:93`) busca o contexto por
`Engine.Gates.AppSecContextBuilder.fetch/2`
(`apps/engine/lib/engine/gates/appsec_context_builder.ex:31`) — a story no
backlog do projeto (`EngineApiClient.list_backlog/1`, a MESMA leitura que a
RN-164 deu ao PO) e o `module_map` vigente da sessão que criou a story
(`EngineApiClient.get_infra_context/2`, a MESMA leitura sem task/story que a
área de Infra já faz) — e então chama `Engine.Gates.AppSecAgent.run/3`
(`apps/engine/lib/engine/gates/appsec_agent.ex:47`).

`AppSecAgent` é módulo SEM ESTADO (não é GenServer, mesma forma de
`QaPerformanceSegurancaAgent`), com registro de ferramentas SEM `Terminal` —
`[ReadFile, SearchWorkspace, EmitThreatModel]` — rodando um checklist
STRIDE-lite (Spoofing/Tampering/Repudiation/Information disclosure/Denial of
service/Elevation of privilege) via `Engine.Harness.ToolLoop.run/1`. A
diferença estrutural do "segundo momento sem Terminal, sem task_id" para o
padrão de gate anterior: nenhum `dev_state`/`worktree_path` entra no `ctx` —
`ReadFile`/`SearchWorkspace` degradam para o fallback de
`Engine.Actions.Workspace.workspace_dir/1` (o checkout COMPARTILHADO do
projeto, não um worktree de agente), e `session_id` vem de
`story["sessionId"]`, nunca de um `dev_state`. `EmitThreatModel`
(`apps/engine/lib/engine/gates/tools/emit_threat_model.ex`) não tem veredito
`approved`/`changes_requested` — o appsec sempre TERMINA registrando o
threat model, nunca aprovando/reprovando nada —, e por isso não reaproveita
`Engine.Gates.Hooks.Termination` (a forma extraída é outra): tem hook
PRÓPRIO, `Engine.Gates.Hooks.AppSecTermination`.

Terminado com sucesso, `run_appsec_design/3`
(`secops_agent_server.ex:234`) emite `artifact.threat_model`
(`storyId`/`threatModel`/`requisitosDeSeguranca`/`riscos`, schema em
`apps/engine/lib/engine/harness/artifact_schemas.ex:71` — `riscos` fica de
fora das chaves obrigatórias porque lista vazia é resposta válida). Falha
(teto de iterações, orçamento, ou o modelo parando sem chamar
`emit_threat_model`) vira `agent.error` durável com origem
(`modelo`/`politica`/`infra`), mesma régua da RN-059 — nunca resposta vazia
nem silêncio só em broadcast.

**O gatilho automático existe desde a [RN-539](#rn-539)**. Esta entrega foi
mantida autocontida de propósito (nenhum arquivo de outra frente tocado:
`decide.ts`, `apps/api/config/gates.yml` e `dev_lead_tools.ex` intocados), e declarava a
lacuna: `run_design/2` era ACIONÁVEL e nada acionava sozinho. O ponto de
disparo que ela nomeava — `assess_implementability` do Dev Lead, frente
`qa-estrategia`, gate `implementavel`, mesmo ADR 0090 — passou a ser o
chamador de verdade, em paralelo e uma vez só por story.

- **Onde:** `apps/engine/lib/engine/gates/secops_agent_server.ex` (`run_design/2`,
  `handle_cast/2`, `run_appsec_design/3`, `emit_threat_model/3`,
  `emit_bloqueio_appsec/3`); `apps/engine/lib/engine/gates/appsec_agent.ex`;
  `apps/engine/lib/engine/gates/appsec_context_builder.ex`;
  `apps/engine/lib/engine/gates/tools/emit_threat_model.ex`;
  `apps/engine/lib/engine/gates/hooks/appsec_termination.ex`;
  `apps/engine/lib/engine/harness/artifact_schemas.ex` (schema `threat_model`)
- **Teste:** `apps/engine/test/engine/gates/appsec_agent_test.exs`,
  `apps/engine/test/engine/gates/appsec_context_builder_test.exs`,
  `apps/engine/test/engine/gates/secops_agent_server_test.exs` (os três
  testes de `run_design`)
- **Origem:** [ADR 0090](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0090-qa-estrategia-e-appsec-segundo-momento.md)

<a id="rn-361"></a>

### RN-361 — O threat model concluído cria TRÊS handoffs, sempre endereçando o LEAD {#rn-361}

`criar_handoffs_appsec/3` (`secops_agent_server.ex:326`) cria um handoff por
alvo declarado em `packages/contracts/fluxo.yml` (`saidas` do `appsec`): arquiteto,
dev-lead e infra — mesmo padrão de
`OfferInfraHandoffUseCase`/`ArquitetoServer.executar_offer_infra_handoff/1`
(chamadas SEPARADAS, uma por alvo, para uma falha de handoff não desfazer os
outros dois já criados). O id do fluxo é `area-infra`, mas o AGENTE
endereçável é `"infra"` (`apps/api/src/domain/agents/agent-areas.ts` —
`lead: 'infra'`), nunca `area-infra`: handoff externo endereça só o LEAD de
área (ADR 0038), e `CreateHandoffUseCase.assertHandoffTargetAllowed`
recusaria um `toAgent` que não resolve a um lead/agente-sem-área. Falha de UM
alvo vira `agent.error` narrado por alvo (RN-116) — os outros dois handoffs
já criados não são desfeitos.

**Desde a [RN-636](parte-04.md#rn-636) os três são PERGUNTADOS, não mais sempre
criados:** o destino que já tem oferta pendente ou já está ativo no projeto não
recebe outra, e isso não é falha.

- **Onde:** `apps/engine/lib/engine/gates/secops_agent_server.ex:55`
  (`@appsec_handoff_targets`), `:377` (`criar_handoffs_appsec/3`)
- **Teste:** `apps/engine/test/engine/gates/secops_agent_server_test.exs`
  ("run_design: threat model concluído emite artifact.threat_model e cria
  os TRÊS handoffs")
- **Origem:** [ADR 0090](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0090-qa-estrategia-e-appsec-segundo-momento.md)

---

## "N agentes online" no dashboard — status AO VIVO, nunca presença histórica (RN-409, ADR 0097)

<a id="rn-414"></a>

### RN-414 — `rag_search`: agentes ganham a ferramenta que o produto nunca tinha exposto {#rn-414}

`grep -rn "rag" apps/engine/lib` dava ZERO ocorrências antes desta
entrega — o RAG completo (pgvector, busca híbrida) só era consumido pela
aba web "Chat RAG". A tool nova `rag_search`
(`apps/engine/lib/engine/harness/tools/rag_search.ex`, categoria
`:direct`, leitura não é efeito externo) chama `POST /internal/rag/search`
— rota nova que REUSA `HybridSearchUseCase` sem duplicar a lógica de
busca — e devolve hits formatados com citação (`path` + trecho), sempre
com `degraded: true` visível no INÍCIO do texto quando o embedding não
estava disponível (nunca escondido pelo corte de teto).

Tetos próprios, no espírito da RN-150: `top_k` clampado a 10 dentro da
própria tool (não confia no que a api aceitaria), teto de 16 KiB no texto
formatado (menor que os 32 KiB de `search_workspace`/`read_file` — cada
hit de RAG já é chunk+excerpt inteiro). Falha de rede vira erro legível
ao modelo, nunca crash do `ToolLoop` (RN-163).

Registrada em `Engine.Harness.Tools` (PO/Arquiteto/conversacionais) e
`Engine.Dev.Tools` (dev agent); estendida também aos gates de leitura que
já citam ADR/convenção indexada (QA-automação, QA-estratégia, AppSec,
QA-performance/segurança) — não a `Infra.WorkflowsAgent` nem
Psicólogo/Anamnese, que raciocinam sobre event log, não sobre docs/código
do projeto.

- **Onde:** `apps/engine/lib/engine/harness/tools/rag_search.ex`;
  `apps/engine/lib/engine/sessions/engine_api_client.ex` (`rag_search/4`);
  `apps/api/src/interfaces/http/internal/internal-rag.controller.ts`
- **Teste:** `rag_search_test.exs` (hits formatados com citação;
  degradação visível; falha de rede sem crash; teto de bytes truncando
  com marca clara; clamp de `top_k`); `engine_api_client_rag_test.exs`
- **Origem:** ver [ADR 0100](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0100-rag-search-e-modelos-garantidos-no-boot.md)

---

<a id="rn-417"></a>

### RN-417 — Psicólogo e Anamnese consultam por relevância, com degradação declarada para recência {#rn-417}

`Psychologist.ContextBuilder`/`Anamnese.ContextBuilder` continuam lendo o
que sempre leram (eventos recentes / janela temporal), e ganham uma
SEGUNDA fonte, `EngineApiClient.rag_search/4`, com uma query derivada do
GATILHO da análise — a causa de término já classificada, no Psicólogo;
competências do catálogo ainda sem `current_profile`, na Anamnese
(NUNCA texto livre de hipótese/racional, pela proibição já estabelecida
de a Anamnese jamais inferir saúde/personalidade/idade/gênero — a query
só contém nomes de competência/membro/projeto). Os hits entram no
orçamento EXISTENTE de `Triage` (`max_prompt_events`/`max_payload_chars`)
— descontam vagas da janela de recentes, nunca somam por fora dela.

A chamada ao RAG é estritamente ADITIVA: sem hit (RAG indisponível, erro,
ou simplesmente sem resultado), o comportamento é IDÊNTICO ao de antes
desta RN — nenhum teste pré-existente precisou mudar. `degraded: true`
(RAG caiu pra léxico-only por falta de embedding) aparece EXPLICITAMENTE
no contexto final, nos dois agentes — nunca escondido pelo corte de
teto.

Os kickoffs de Psicólogo (`psychologist-kickoff`) e Anamnese
(`anamnese-kickoff`) passam a resolver como TEMPLATE do grafo
(`EngineApiClient.get_prompt_template/2`) quando `graph_templates_enabled?`
está ligada (`GRAPH_TEMPLATES_ENABLED`, default `false`) — com fallback
obrigatório pro texto inline em qualquer falha (api fora, template não
semeado, flag desligada). `:pinned => true` continua igual nos dois
caminhos.

O TERCEIRO consumidor da mesma flag é o prompt de sumarização do
`ContextManager` (`context-manager-summarize`, o quarto e último template da
leva da [RN-413](https://github.com/viralabs-dev/brabo-infra/blob/dev/deploy/docs/business-rules/infra.md#rn-413) — era o único ainda sem consumidor, lacuna que a
[ADR 0101](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0101-memoria-relacional-como-projecao-do-event-log.md)
declarou aberta e que fecha aqui). Mesma régua, byte a byte: flag ligada
tenta o template e substitui `{{turnos}}` pelo MESMO corpo `<role>:
<content>` que a trilha inline já montava; qualquer desfecho que não seja
`{"body" => corpo}` com corpo binário não-vazio cai no inline — SEM erro e
SEM log de erro, porque flag desligada, template ainda não semeado e api do
grafo fora do ar são o MESMO caminho de degradação. Com a flag desligada (o
default) a api nem é chamada. O render é função privada PRÓPRIA, não um
helper compartilhado: o conjunto de placeholders é do template, não do
mecanismo — cada um dos três consumidores tem o seu. E o fallback
determinístico de quando o MODELO falha (`"(N turnos anteriores
omitidos)"`) é outra coisa e NÃO passa por template nenhum: é comportamento
de código, não texto de prompt, e o próprio `.md` do template declara isso.

> **Desde a [RN-621](parte-03.md#rn-621)** o prompt de resumo, nas duas trilhas, pede que
> cada turno mantenha o idioma original e que citação e código não se traduzam;
> o template versionado subiu para a versão `"2"`.

**Consumo do restante do grafo (`query_user_context` — hipóteses com
evidência e perfis lidos DIRETO do Neo4j) fica DECLARADO fora desta
entrega**: ainda sem rota HTTP exposta do lado api; Psicólogo/Anamnese
hoje só consultam o RAG (pgvector) via `rag_search`, não o grafo de
relações em si.

- **Onde:** `apps/engine/lib/engine/psychologist/context_builder.ex`,
  `apps/engine/lib/engine/workers/psychologist_worker.ex`;
  `apps/engine/lib/engine/anamnese/context_builder.ex`,
  `apps/engine/lib/engine/workers/anamnese_worker.ex`;
  `apps/engine/lib/engine/harness/context_manager.ex` (`prompt/1`,
  `render_template/2`, `prompt_inline/1`)
- **Teste:** `context_builder_test.exs` dos dois agentes (hits presentes;
  falha do RAG degrada sem erro; `degraded: true` visível; clamp de
  `top_k`; query derivada do gatilho); `psychologist_worker_test.exs`/
  `anamnese_worker_test.exs` (template com sucesso e com fallback;
  `:pinned` idêntico nos dois caminhos; flag desligada nunca chama a api);
  `context_manager_test.exs` (template com `{{turnos}}` substituído;
  `{:error, :not_found}` cai no inline e a compactação termina normal;
  flag desligada nunca chama `get_prompt_template`)
- **Origem:** ver [ADR 0101](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0101-memoria-relacional-como-projecao-do-event-log.md)

---

<a id="rn-419"></a>

### RN-419 — O runner local se autentica por ticket de uso único, escopado a projeto e papel {#rn-419}

**REVISADA pela [RN-421](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-421) (ADR 0104)**: a condição de recusa do
ticket citada abaixo (`workspaceMode !== 'local'`) virou `executionMode
!== 'runner'` — mesma régua, nome novo. O resto desta entrada continua
valendo tal como está.

O canal `terminal:<projectId>` (socket Phoenix novo, `/runner`) recebe
dois papéis distintos — `:runner` (o CLI na máquina do usuário, no
máximo UM por projeto, exclusividade garantida por
`:global.register_name/3`) e `:web` (a aba Terminal, múltiplos
simultâneos) — e os dois entram autenticados por TICKET DE USO ÚNICO,
mesmo padrão de segurança da RN-108 (ticket de socket de sessão), com uma
inversão de propriedade: o ticket é EMITIDO PELO ENGINE
(`runner_socket_tickets`, schema `"engine"`, migration Ecto própria — não
uma extensão da tabela de ticket de sessão, que é da api), e a API o pede
via rota HTTP interna nova (`POST /internal/projects/:projectId/runner-tickets`)
— o inverso do fluxo de ticket de sessão, onde a api grava direto na
própria tabela.

`POST /projects/:projectId/runner-ticket` (role `developer`+, recusa se
`workspaceMode !== 'local'`) e `POST /projects/:projectId/terminal-ticket`
(role `viewer`+, qualquer modo) são as duas rotas públicas que emitem o
ticket pro cliente certo — o runner pede a primeira, a web pede a
segunda. Ticket consumido (validação + `UPDATE` condicional de uso
único) no `join` do canal; ticket de OUTRO projeto ou reusado nunca abre
o tópico.

- **Onde:** `apps/engine/lib/engine/runners/socket_ticket.ex`,
  `apps/engine/lib/engine/runners/registry.ex`,
  `apps/engine/lib/engine_web/channels/{runner_socket,terminal_channel}.ex`;
  `apps/api/src/interfaces/http/runner/runner-tickets.controller.ts`,
  `apps/api/src/application/use-cases/runner/request-runner-ticket.use-case.ts`
- **Teste:** `runner_socket_test.exs`/`terminal_channel_test.exs` (join
  com ticket válido sucede; ticket reusado recusa; ticket de outro
  projeto não abre o tópico errado; segundo `:runner` no mesmo projeto é
  recusado; um segundo runner consegue conectar depois que o primeiro
  cai); `request-runner-ticket.use-case.spec.ts`/
  `runner-tickets.controller.spec.ts` (recusa pra projeto não-`local` no
  ticket de runner; ticket de terminal funciona pra qualquer modo)
- **Origem:** ver [ADR 0103](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0103-runner-local-execucao-na-maquina-do-usuario.md)

---

<a id="rn-420"></a>

### RN-420 — Comando de agente roteado ao runner passa pelo MESMO pipeline de aprovação; PTY é ação do usuário, auditada {#rn-420}

**REVISADA pela [RN-423](https://github.com/viralabs-dev/brabo-runner/blob/dev/docs/business-rules/runner.md#rn-423) (ADR 0104)**: a condição pra rotear deixou
de ser binária. `workspace_mode == "local"` virou `execution_mode ==
"runner"` **E** `workspace_verified_at` não-nulo **E** runner conectado —
faltando qualquer uma das TRÊS, o comando é RECUSADO explicitamente, nunca
cai no `System.cmd`/bind-mount de `mounted` (que não existe pra um projeto
`runner`, sem bind-mount nenhum). O resto desta entrada — o pipeline de
aprovação de sempre, PTY como ação do usuário — continua valendo tal como
está.

`Engine.Actions.TerminalExecutor` decide rotear um comando pro runner (em
vez do `System.cmd` de sempre, dentro do container) **DEPOIS** que o
pipeline normal (`decide()`/`proposed_action`) já aprovou — o roteamento
é só uma escolha de DESTINO pro mesmo comando já autorizado, nunca um
segundo caminho de execução que escapa da política (que continua com os
tetos absolutos da RN-418 valendo igual, sudo/git incluídos). Condição
pra rotear (histórico, ver revisão acima): `workspace_mode == "local"` E
runner conectado (`Engine.Runners.Registry.connected?/1`) — sem qualquer
uma das duas, o comportamento de sempre continua (`System.cmd` no
container via bind-mount, ADR 0072 vira FALLBACK, nunca removido).

PTY interativo é DIFERENTE: é ação do USUÁRIO autenticado digitando no
terminal da própria máquina, não do agente — por isso NÃO passa por
`proposed_action`. Mas precisa deixar rastro: `pty_open`/`pty_close`
vindos da web emitem `terminal.session.started`/`terminal.session.ended`
no event log (endereçados à sessão mais recente do projeto,
`ProjectSession.latest_id/1`, mesmo mecanismo que a Anamnese já usa pra
narrar algo project-scoped). Achado real na consolidação: sem runner
conectado, a web precisa de um `pty_error` EXPLÍCITO de volta — descartar
o pedido só com um log no servidor deixaria a aba presa em "carregando"
pra sempre, nunca alcançando o estado "sem runner" que a tela já sabia
mostrar.

- **Onde:** `apps/engine/lib/engine/actions/terminal_executor.ex`,
  `apps/engine/lib/engine/runners/runner_router.ex`,
  `apps/engine/lib/engine_web/channels/terminal_channel.ex`
- **Teste:** `terminal_executor_test.exs` (roteia pro runner com modo
  `local` + runner conectado; `cwd` passa adiante; cai no caminho atual
  sem runner conectado; nunca roteia em modo `container`);
  `terminal_channel_test.exs` (`pty_open` sem runner conectado devolve
  `pty_error` pra web, nunca fica sem resposta)
- **Origem:** ver [ADR 0103](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0103-runner-local-execucao-na-maquina-do-usuario.md)

## O explorador de pasta do Runner vira três colunas, e a criação de um projeto `runner` deixa de esperar o passo final (RN-436/436)

<a id="rn-454"></a>

### RN-454 — A aba Insights sabe que o Psicólogo está pausado ANTES de o usuário esbarrar no 503 {#rn-454}

Achado por USO: a aba Insights, com zero hipóteses, mostrava "Sem hipóteses
ainda — o Psicólogo analisa cada sessão encerrada" mesmo com
`PSYCHOLOGIST_ENABLED=false` — a mesma frase que aparece quando o Psicólogo
está ATIVO e só ainda não rodou. As duas situações são indistinguíveis pelo
texto, o que é a mesma classe de defeito que a RN-088/RN-107 já fecharam
para outras telas: um estado que existe e o produto sabe, mas não mostra.

A [RN-117](parte-01.md#rn-117) já cobria a descoberta da pausa, mas só no CLIQUE de
"Reanalisar" (503 → `PsychologistDisabledError`) — e esse botão só existe
na faixa de análises, que só aparece quando `runs.length > 0`. Uma sessão
sem hipótese nenhuma nunca chega perto dele, então a pausa era invisível
justamente na tela vazia.

`GET /internal/psychologist/status` (engine, `PsychologistCommandController.status/2`)
é leitura pura de `PsychologistWorker.enabled?/0` — SEM efeito colateral,
diferente de `/reanalyze`, que cria um job quando ativado. A api expõe
`GET /projects/:projectId/psychologist/status` (`GetPsychologistStatusUseCase`,
`role:viewer`) por cima disso — projeto na URL só por consistência com as
rotas irmãs (`hypotheses`, `psychologist/analyses`); a flag em si é GLOBAL,
como a RN-117 já registra. `ProjectInsightsTab.tsx` consome essa leitura
(`usePsychologistStatus`) e escolhe a frase do estado vazio por ela: pausado
mostra "O Psicólogo está pausado — nenhuma sessão é analisada até ser
reativado" (`insights.projectInsightsTab.emptyPaused`); do contrário, mantém
a frase original, que É honesta quando a feature está de fato ativa. O
aviso persistente (`pausedNotice`) e os botões de "Reanalisar" também
passaram a refletir essa leitura proativa, e não só o `useState` descoberto
pelo 503 — que continua existindo, como reforço, para o caso raro de a
flag mudar EM VOO entre a leitura de status e o clique.

- **Onde:** `apps/engine/lib/engine_web/controllers/psychologist_command_controller.ex`
  (`status/2`), `apps/engine/lib/engine_web/router.ex`
  (`GET /internal/psychologist/status`),
  `apps/api/src/application/ports/api-to-engine-client.port.ts`
  (`getPsychologistStatus`),
  `apps/api/src/infrastructure/http-clients/api-to-engine-client.ts`,
  `apps/api/src/application/use-cases/execution/get-psychologist-status.use-case.ts`,
  `apps/api/src/interfaces/http/psychologist/psychologist.controller.ts`
  (`status`), `apps/web/src/lib/api-client.ts` (`getPsychologistStatus`),
  `apps/web/src/lib/hooks.ts` (`usePsychologistStatus`),
  `apps/web/src/routes/ProjectInsightsTab.tsx`
- **Teste:**
  `apps/engine/test/engine_web/controllers/psychologist_command_controller_test.exs`
  (`status/2`, `enabled: true`/`false`),
  `apps/api/test/infrastructure/http-clients/api-to-engine-client.spec.ts`
  (`getPsychologistStatus`),
  `apps/api/test/application/use-cases/execution/get-psychologist-status.use-case.spec.ts`,
  `apps/web/src/routes/ProjectInsightsTab.test.tsx`
- **Borda:** a flag continua GLOBAL (ver RN-117) — a rota da api aceita
  `projectId` na URL só para bater com o padrão das rotas irmãs do
  controller, e não porque a resposta varia por projeto.
- **Origem:** achado por USO real navegando a aba Insights com
  `PSYCHOLOGIST_ENABLED=false`, não roteiro. Sem ADR — extensão pontual do
  mecanismo de leitura já existente da RN-117, mesmo padrão da RN-088/
  RN-107 para o resto do produto.

---

## Pasta local anexada vira o quarto escopo do índice RAG, lido pelo NAVEGADOR (RN-455..457, ADR 0113)

<a id="rn-459"></a>

### RN-459 — Teto de iterações não termina mais calado em quatro dos seis agentes conversacionais {#rn-459}

Achado durante a investigação da faixa de atividade do turno (RN-460):
`arquiteto_server.ex`, `dev_lead_server.ex`, `ux_designer_server.ex` e
`staff_server.ex` terminavam CALADOS quando o teto de iterações estourava
(`defp run_turn(state, remaining) when remaining <= 0, do: state`, sem
evento nenhum) — contradizendo a regra permanente de que laço de agente
não termina calado. Só o PO já emitia `toolloop.limit_reached`
(RN-166); o Criativo diverge deliberadamente com `agent.error` (`reason:
"limite_de_iteracoes"`, decisão documentada no próprio código — reusar o
nome do `ToolLoop` mentiria sobre quem produziu o evento) e não foi
tocado. Os quatro corrigidos passam a emitir `toolloop.limit_reached`
(mesmo evento do PO, mesmo payload `iteration`/`max_iterations`) antes de
retornar — nenhuma mudança na estrutura de `dispatch_tool` de cada um.

- **Onde:** `apps/engine/lib/engine/agents/arquiteto_server.ex:195`,
  `dev_lead_server.ex:244`, `ux_designer_server.ex:121`,
  `staff_server.ex:113`
- **Teste:** `apps/engine/test/engine/agents/{arquiteto,dev_lead,
  ux_designer,staff}_server_test.exs` ("teto de iterações emite
  toolloop.limit_reached")
- **Origem:** achado por leitura completa dos seis servers, durante a
  implementação da RN-460; escopo estendido por decisão do dono do
  produto

## A busca do RAG deixa rastro, e o rastro congela os pesos (RN-479..481)

<a id="rn-492"></a>

### RN-492 — O comando de terminal do dev agent roda DENTRO do container real, quando há um {#rn-492}

`Engine.Actions.TerminalExecutor.decisao_de_execucao/1` ganha a QUINTA saída
(`:executar_no_container`): projeto em `execution_mode: container` com uma
linha REGISTRADA `running` em `project_containers`
(`Engine.Containers.ProjectContainerLifecycle.running?/1`, leitura read-only
direta da tabela, mesmo padrão de `Engine.Projects.Project`). Antes desta
regra, mesmo com um container de pé (RN-491), TODO comando de terminal
rodava via `System.cmd` no processo do engine, contra a pasta compartilhada
— o container ficava ocioso.

O comando atravessa engine → api → broker
(`POST internal/projects/:projectId/container-exec`,
`ExecutarComandoNoContainerUseCase`, `ContainerBrokerPort.exec`) e roda via
`docker exec`. `cwd`, quando presente, é TRADUZIDO do caminho de HOST (dentro
de `PROJECT_WORKSPACES_ROOT`) para dentro de `/work` — o único diretório que
o container enxerga — trocando o prefixo `<project_workspaces_root>/
<workspace_dir_name>` por `/work` e preservando o sufixo (o worktree
individual de um dev agent, `.worktrees/<agent_id>`, incluso). O worktree em
si não muda de lugar nem de mecanismo de criação: `Workspace.ensure!/4`
continua escrevendo no MESMO diretório físico que o broker monta em `/work`
(verificado em código: `raizDoProjeto` do broker e `PROJECT_WORKSPACES_ROOT`
do engine resolvem a mesma pasta, via `workspace_dir_name`, RN-109) — o
container é só mais um observador dela.

**`running` REGISTRADO nunca confirma que o container está de pé DE VERDADE
agora (RN-486).** Se ele morreu ou foi removido por fora entre o registro e
esta chamada, `broker.exec` falha e vira `failed_result` NORMAL — exit_code
`nil`, mensagem nomeando o motivo — nunca crash, nunca fallback silencioso de
volta pro `System.cmd` fora do container (isso reabriria o vetor de
isolamento que esta regra existe para fechar). `mounted` nunca cai nesta
saída: o broker recusa subir container pra esse modo
(`ModoDeExecucaoNaoSuportadoError`).

- **Onde:** `apps/engine/lib/engine/actions/terminal_executor.ex`
  (`decisao_de_execucao/1`, `run_no_container/4`, `cwd_para_container/2`),
  `apps/engine/lib/engine/containers/project_container_lifecycle.ex`,
  `apps/engine/lib/engine/sessions/engine_api_client.ex`
  (`executar_comando_no_container/4`),
  `apps/api/src/interfaces/http/internal/internal-projects.controller.ts`
  (`POST :projectId/container-exec`),
  `apps/api/src/application/use-cases/containers/executar-comando-no-container.use-case.ts`,
  `apps/api/src/application/ports/container-broker.port.ts` (`exec`,
  `timeoutMs`)
- **Teste:** `apps/engine/test/engine/actions/terminal_executor_test.exs`
  (as cinco saídas de `decisao_de_execucao/1`; tradução de `cwd` na raiz e
  num worktree; `sucesso: false` e falha de transporte viram `failed_result`;
  container sem linha `running`/em `stopped` cai no caminho de sempre),
  `apps/api/test/application/use-cases/containers/executar-comando-no-container.use-case.spec.ts`
  (`BrokerRecusouError`/`BrokerIndisponivelError` nunca propagam; outro erro
  propaga),
  `apps/api/test/infrastructure/http-clients/container-broker.client.spec.ts`
- **ADR:** [0130](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0130-broker-de-container.md), [0134](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0134-dev-agents-executam-dentro-do-container.md)
- **Origem:** plano do dono do produto, Parte 1 / PR 1.6

<a id="rn-502"></a>

### RN-502 — Dev agent só reivindica task com container `running`, e o terminal não cai mais fora dele {#rn-502}

Duas metades da mesma regra: **sem ambiente de execução, o dev agent não
começa**, e **sem ambiente de execução, o comando não roda em lugar nenhum**.

**A guarda do claim.** `Engine.Dev.AgentIo.try_claim/2` — o ponto ÚNICO de
claim — consulta
`Engine.Containers.ProjectContainerLifecycle.running?/1` ANTES de chamar
`claim_task/1`. Sem uma linha REGISTRADA `running` em `project_containers`
([RN-243](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-243)/ADR 0081), o agente cai em `:idle`, persiste, emite
`dev.blocked_by_container` e **não chama a api**. A guarda vem antes do claim
de propósito: reivindicar para devolver logo em seguida deixaria a task
marcada e sem dono vivo, que é o estado que `block_task/4` existe para nunca
produzir.

**Exceção: o Noop não exige container.** O dev agent `noop`
(`devAgentImpl: 'noop'`, `impl == "noop"` no estado) dispensa a guarda em
`try_claim/2`: ele não executa nada em container, só valida a infraestrutura
sem LLM, e a guarda o deixava parado em `blocked_by_container`. O
`DevAgentServer` real continua exigindo o container `running`
(`apps/engine/lib/engine/dev/agent_io.ex:154`, `try_claim`; AT-833).

**`:idle`, e não um status novo.** É o único estado do qual um wake ainda
resgata — os guards de `handle_info/2` são todos casados com ele
(`{:wake, :became_claimable}` exige `:idle`, `:rearm` exige `:idle_tripped`,
`gate_resolved` exige `task_id` batendo,
[RN-047](parte-01.md#rn-047)). Um
`:blocked_by_container` inventado seria um estado do qual nada resgata.

**No ENGINE e não só no `activate-execution` da api**, porque o claim tem um
caminho que nenhuma rota cobre: a REIDRATAÇÃO. `Engine.Dev.DevRehydrator` não
faz cast `:work`; quem claima depois de um restart é `DevAgentServer.init/1`
→ `finish_restart_recovery/1` → `try_claim/2`. Um gate só na fronteira HTTP
deixaria todo agente reidratado voltar a trabalhar sem container.

**O wake.** Leitura não avisa ninguém: um agente já parado continuaria parado
até um evento não relacionado passar por perto. Então a chegada em `running`
PUBLICA — `RegistrarTransicaoDeContainerUseCase` grava a linha e o evento na
MESMA transação, `aggregateType: 'container'` (o terceiro agregado que
`Engine.Outbox.Drain` passou a drenar, ao lado de `session` e `task`),
`aggregateId` = o PROJETO. `Engine.Workers.DevAgentWakeWorker` entrega
`{:wake, :became_claimable}` a TODOS os agentes do projeto
(`DevAgentState.list_by_project/1` — o container é do projeto, não de um
módulo). É a MESMA mensagem que já existia, e não uma nova: a semântica dela
já é "pode haver trabalho agora", e uma mensagem própria exigiria cláusula
nova de `handle_info/2` nos dois servers com guard idêntico ao que já existe.
Só `running` publica; `provisioning`/`stopped`/`failed`/`removed` não soltam
ninguém.

**A segunda metade: o terminal.** `Engine.Actions.TerminalExecutor`
degradava calado — `container` sem container `running` caía em
`:caminho_de_sempre`, isto é, `System.cmd` DENTRO do processo do engine, o
mesmo que fala com o banco, com a api e com todos os outros projetos. O ADR
0134 ([RN-492](#rn-492)) tinha fechado o isolamento só no caminho feliz.
Agora recusa (`:recusar_container_ausente`), espelhando o
`:recusar_nao_verificado`/`:recusar_runner_desconectado` que o modo `runner`
já tinha ([RN-423](https://github.com/viralabs-dev/brabo-runner/blob/dev/docs/business-rules/runner.md#rn-423)), e como `failed_result` normal — nunca crash.
`mounted` entra no MESMO ramo: com container `running` atravessa pro broker
igual a `container`; sem ele, recusa. O catch-all `:caminho_de_sempre`
encolhe para o que sempre deveria ter sido sozinho — **projeto inexistente ou
`project_id` malformado**. Nenhum modo de execução cai nele.

**Consequência declarada:** projeto sem container de pé para de trabalhar, e
diz por quê. É deliberado — é o que a regra existe para fazer — e é por isso
que ela só pode entrar DEPOIS das mudanças que dão container ao modo
`mounted`.

- **Onde:** `apps/engine/lib/engine/dev/agent_io.ex` (`try_claim/2`),
  `apps/engine/lib/engine/actions/terminal_executor.ex`
  (`decisao_de_execucao/1`),
  `apps/engine/lib/engine/outbox/drain.ex`,
  `apps/engine/lib/engine/workers/dev_agent_wake_worker.ex`,
  `apps/api/src/application/use-cases/containers/registrar-transicao-de-container.use-case.ts`
- **Teste:** `apps/engine/test/engine/dev/claim_com_container_test.exs` —
  `:work` inicial sem container cai em `:idle`, persiste, emite e **não**
  chama a api; o Noop dispensa a guarda (pega a task e emite `dev.working`); agente REIDRATADO para em
  `:idle` sem claimar; `container.running` na outbox percorre
  drain → worker → wake → agente e ele re-claima; e o caminho de sempre
  segue intacto com container `running`.
  `apps/engine/test/engine/actions/terminal_executor_test.exs` — recusa para
  `container` (sem linha e com `stopped`) e para `mounted`; `mounted` com
  `running` atravessa pro broker; só projeto inexistente cai em
  `:caminho_de_sempre`.
  `apps/api/test/application/use-cases/containers/ciclo-de-vida-do-container.use-case.spec.ts`
  — `running` publica `container.running` no agregado `container`; os outros
  destinos e a criação da linha não publicam nada
- **ADR:** [0143](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0143-agentes-de-dev-so-depois-do-container.md)
- **Origem:** plano "Nome e local na mesma tela, e container antes dos dev
  agents" (PR 7) — dez tasks do `exp001` travaram de uma vez porque nada
  ordenava container antes de dev agent

---

## O artefato de decisão dos conversacionais (RN-505)

<a id="rn-505"></a>

### RN-505 — `decision_record` reusa o padrão GENÉRICO de `emit_artifact`, não o dedicado {#rn-505}

Um agente conversacional que toma uma decisão relevante numa conversa (por
que escolheu X e não Y, o que considerou, o que aceitou perder) registra isso
com `emit_artifact` e `type: decision_record` — payload com `context`,
`options` (lista), `choice` e `consequences`, as quatro chaves obrigatórias
em `Engine.Harness.ArtifactSchemas` (`artifact_schemas.ex:82`), tool-emittable
desde que entrou em `@tool_emittable` (`artifact_schemas.ex:98`). **Sem
validação cruzada de propósito:** `choice` não precisa bater com um item de
`options` — texto livre é mais robusto, e o schema genérico só valida
presença de chave (a mesma régua de `note`/`business_rule`).

**Por que reusar o padrão GENÉRICO em vez do dedicado.** `artifact.project_image`
e `artifact.c4_diagram` (RN vizinhas desta) são artefatos VERSIONADOS — cada
emissão substitui a anterior como "vigente", com rota HTTP própria de leitura
e schema TypeScript dedicado na api. Uma decisão não é assim: é um registro
append-only por natureza, não um "vigente" que se substitui — o mesmo
raciocínio que já vale para `note`/`business_rule`. Pagar o preço do padrão
dedicado (schema TS, versionamento, rota nova) para um log que só precisa
existir e ser pesquisável no event log da sessão custaria estrutura que a
decisão não pede.

**Distinção declarada com `open_adr_pr` (só o Arquiteto tem).** Os dois
COEXISTEM, com propósitos diferentes: `decision_record` é para TODA decisão
relevante de qualquer um dos seis conversacionais, sem fricção nenhuma —
nunca commita arquivo, nunca abre PR, nunca espera aprovação humana.
`open_adr_pr` é para quando a decisão é grande o bastante para virar
DOCUMENTO real em `docs/adr/*.md`, com PR de verdade e aprovação humana
obrigatória. Um projeto pode ter dez `decision_record` e zero ADR numa
sessão — o segundo não é a versão "séria" do primeiro, é outra ferramenta
para outra escala de decisão.

**Wiring nos cinco conversacionais que ainda não tinham `emit_artifact`** —
PO (`po_server.ex:115`), Arquiteto (`arquiteto_server.ex:103`), Dev Lead
(`dev_lead_server.ex:153`), UX Designer (`ux_designer_server.ex:94`) e Staff
(`staff_server.ex:94`); o Criativo já tinha a ferramenta desde a Fase 3b, só
ganhou o tipo novo (é o `known/0` compartilhado quem decide, sem mudança no
`CriativoServer`). Em cada um, o `run_tool/3` comum ganhou a cláusula
`"emit_artifact" -> EmitArtifact.run/2` (ex.: `po_server.ex:279`) — **sem
tratamento especial**: diferente de `propose_execution_plan`/
`assess_implementability` no Dev Lead (que suspendem o turno esperando
aprovação, ADR 0086), `emit_artifact` nunca devolve `{:pending, _}`, então
entra no dispatch comum sem precisar do `reduce_while` que aquelas duas
ferramentas exigem. E os cinco ganharam a MESMA frase no `system_prompt/1`
(ex.: `po_server.ex:463`) explicando quando usar `type: decision_record` —
fora do texto de identidade (`Engine.Harness.Agents`) porque não é sobre
QUEM o agente é, é uma instrução operacional sobre uma ferramenta.

**Fora de escopo, declarado.** Agentes de execução (QA, SecOps, Dev Agent de
módulo) rodam sobre `ToolLoop`, sem harness comum aos seis conversacionais —
ficam de fora desta fatia, investigação própria por módulo antes de
estender. A amarração com a Frente 1 do mesmo plano (o dispatch do Infra
Lead emitindo um `decision_record` server-emitted quando propõe subir
container via runner) também fica de fora: depende de uma tool
(`propose_container_start_via_runner`) que outro PR está criando em
paralelo — ver TODO no PR desta mudança.

- **Onde:** `apps/engine/lib/engine/harness/artifact_schemas.ex` (schema +
  `@tool_emittable`); `apps/engine/lib/engine/agents/po_server.ex`,
  `arquiteto_server.ex`, `dev_lead_server.ex`, `ux_designer_server.ex`,
  `staff_server.ex` (alias + `tool_specs` + `run_tool/3` +
  `system_prompt/1`)
- **Teste:** `apps/engine/test/engine/harness/artifact_schemas_test.exs`
  (`describe("decision_record …")`);
  `apps/engine/test/engine/agents/po_server_test.exs` e
  `arquiteto_server_test.exs`
  (`describe("Frente 3 do plano de decision_record — emit_artifact")`)
- **Origem:** plano do dono do produto, Frente 3 ("Artefato de decisão")

---

## O `join` do agente local deixa de ser mudo (RN-514)

<a id="rn-514"></a>

### RN-514 — O runner DECLARA o que sabe fazer no `join`, o servidor CONCEDE a interseção em `socket.assigns`, e mensagem sem capacidade é RECUSADA em vez de sumir {#rn-514}

Até aqui o `join` do canal `terminal:<projectId>` era **mudo dos dois lados**:
o runner mandava `socket.channel(\`terminal:${projectId}\`, {})` e o servidor
os ignorava literalmente (`def join("terminal:" <> project_id, _params,
socket)`). Toda a identidade vinha do ticket — o papel (`:runner`/`:web`) sai
do `kind` —, e o servidor **não tinha como saber** se o binário do outro lado
era de uma versão que entende uma mensagem nova.

O defeito que isso produz é o pior possível, e é o que esta regra fecha: a
mensagem chega, o handler não existe do outro lado, e **nada acontece** — sem
erro, sem log, sem ninguém saber que a função nunca rodou.

**Três capacidades, e só o que o runner sabe fazer é declarado.** O
vocabulário do servidor é `exec` (comando aprovado, ADR 0104), `pty`
(terminal interativo, ADR 0103) e `espelho` (copiar o trabalho para uma pasta
fora da base montada). O runner declara **`exec` e `pty`**, e `espelho` fica
de fora **de propósito**: declarar o que não se implementa é exatamente o
defeito que a negociação existe para impedir — o servidor concederia,
entregaria a mensagem, e ela sumiria do mesmo jeito. `espelho` nasce só como
**nome do vocabulário**, sem comportamento nenhum; quem o implementa é a
sessão 6 da FASE 28.

**Ausência de params é o LEGADO, e isso é fato — não benevolência.** Todo
binário anterior a esta mudança manda params vazios, e todo binário anterior
a esta mudança sabe fazer `exec` e `pty`: são as duas funções com que o
runner nasceu. Conceder `{exec, pty}` a quem não declara nada é ler
corretamente a única coisa que aquele binário poderia ter dito. O contrário
faria **todo runner instalado parar de conectar**, que é mudança exigindo
ação do operador antes do deploy — `breaking/` e MAJOR, pela convenção do
repositório, e não é isto que esta entrega é. Params ausentes, `capacidades`
ausente, lista **vazia** e valor que não é lista caem todos no legado: são as
formas que "este binário não sabe declarar nada" assume no caminho de rede.

**Desconhecido é IGNORADO, nunca motivo de recusa.** O conjunto concedido é a
interseção do declarado com o vocabulário que **este** servidor conhece —
runner mais NOVO que o engine tem que conseguir conectar. Já declarar
**apenas** nomes desconhecidos é declaração vazia, não legado: quem sabe
declarar disse o que sabe fazer.

**O que cada modo EXIGE.** `runner` exige `exec` — é literalmente o que faz o
modo funcionar, e sem ele o `TerminalExecutor` rotearia comando aprovado para
um binário que não o executa, com a falha aparecendo como *timeout* em vez de
recusa. `container` e `mounted` não exigem nada (o runner nem é o caminho de
execução deles). **Nada exige `espelho` ainda** — o mecanismo de recusa nasce
implementado e testado, e não dispara na prática hoje. Isso é o desenho, não
pendência. Modo que não se conseguiu ler (projeto inexistente, id malformado,
consulta que falhou) exige **nada**: recusar por pré-condição não confirmada
seria colapsar "não sei" com "não tem" ([RN-088](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-088)).

**O conjunto concedido vive em `socket.assigns`, nunca em tabela.**
Capacidade é propriedade **daquela conexão** — uma tabela poderia afirmar que
um runner sabe algo que o processo conectado agora não sabe. É o mesmo
raciocínio que faz a entrada `:global` do `Engine.Runners.Registry` morrer
junto com o pid. Só o papel `:runner` recebe conjunto: o socket `:web` **não
ganha `:capacidades`** e nenhuma checagem de capacidade se aplica a ele — a
aba não executa nada, ela pede.

**Recusa do join nomeia a que falta.** `{:error, %{reason: ...}}` dizendo
qual capacidade o projeto exige e que o binário precisa ser atualizado. A
recusa é **fatal do lado do runner**, sem retry (`JoinRecusadoError`,
comportamento que já existia e não mudou) — por isso ela é a única chance de
explicar, e "recusado" sem o nome do que falta obrigaria a adivinhar. A
checagem acontece **antes** de `Registry.register/2`: registrar e recusar em
seguida deixaria o `Registry` afirmando um runner que não entrou.

**E a metade que entrega valor hoje: mensagem sem a capacidade concedida é
RECUSADA com resposta nomeada, nunca engolida.** `exec` para um runner sem
`exec` responde ao chamador no **mesmo formato de `exec_result`** que o
runner mandaria (`exitCode` 126 — "encontrado, mas não executável" —, a causa
no `output`), em vez de deixar o `RunnerRouter` bloqueado até o `receive ...
after` e o usuário ver um *timeout* no lugar da causa. `pty_*` para um runner
sem `pty` não é relayado, e a `:web` que originou recebe `pty_error` nomeado,
pelo mesmo broadcast filtrado que o runner usaria para reportar erro de PTY —
sem isso a aba ficaria em "carregando" para sempre, o defeito que o `whereis`
de `handle_in("pty_open", ...)` já tinha fechado para o caso "sem runner".
Como o legado tem as duas capacidades, **nada muda para ninguém hoje**.

**Isto não é fronteira de segurança.** Capacidade é negociação de
**protocolo**; quem autoriza continua sendo o ticket de uso único
([RN-108](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-108)) e o pipeline de
`proposed_action`. O que o runner ganha declarando é que mensagens daquele
tipo lhe sejam **entregues**, nunca permissão para nada.

- **Onde:** `apps/engine/lib/engine/runners/capacidades.ex` (novo — o
  vocabulário, o legado, o que cada modo exige e as duas mensagens);
  `apps/engine/lib/engine_web/channels/terminal_channel.ex:208`
  (`join/3` passa a receber `params`), `:215` (`autorizar_por_papel/3`),
  `:251` (`entrar_como_runner/3`, a concessão antes do `Registry`), `:305`
  (`exigencias_do_projeto/1`, que era `modo_de_execucao/1` até a RN-516 fazer a mesma consulta responder também o destino do espelho), `:595` (o gate de `exec` em
  `handle_info({:dispatch_exec, ...})`) e `:762` (o de `pty` em
  `handle_info({:relay, "pty_" <> _, ...})`);
  `apps/runner/src/channel.ts` (`CAPACIDADES_DO_RUNNER` e os params do
  `socket.channel/2`)
- **Teste:** `apps/engine/test/engine/runners/capacidades_test.exs` (novo — o
  vocabulário puro: legado, lista vazia, desconhecido ignorado, o que cada
  modo exige, e que nada exige `espelho`);
  `apps/engine/test/engine_web/channels/terminal_channel_test.exs`
  (`describe "capacidades declaradas no join (ADR 0147 ponto 1, RN-514)"` —
  concessão em `assigns`, join sem params, desconhecido ignorado, `:web` sem
  conjunto, a recusa nomeando `exec` num projeto `runner`, e as duas
  mensagens recusadas com resposta em vez de silêncio);
  `apps/runner/src/channel.spec.ts` (o CONTEÚDO dos params do join, `espelho`
  fora da lista, e a recusa virando `JoinRecusadoError` com a mensagem do
  servidor legível)
- **ADR:** [0147](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0147-agente-local-com-capacidades.md), ponto 1
- **Origem:** FASE 28, sessão 5

---

## Os artefatos dos agentes viram arquivo, em `docs/` (RN-523)

<a id="rn-523"></a>

### RN-523 — A pasta `docs/` é PROJEÇÃO do event log: derivada, por agente, e nunca fonte de verdade {#rn-523}

Todo artefato que os agentes produzem vive **exclusivamente no event log** —
`apps/engine/lib/engine/harness/tools/emit_artifact.ex:3-5` diz literalmente
que *"não há tabela de artefatos"*. Isso continua certo para a FONTE, e esta RN
não mexe nisso. O que ela fecha é outro buraco: essa memória não chegava a
lugar nenhum que uma pessoa abrisse. Quem abre a pasta do projeto no editor não
encontrava nada do raciocínio que produziu o código. (O **provisionamento
adiado** — criar projeto deixar de criar repositório, e o git nascer no aceite
do handoff ao Dev Lead — abre um intervalo inteiro em que o projeto não tem nem
repositório, e torna esta pasta ainda mais necessária; ele vem em PR próprio, e
esta RN não depende dele.)

Cada evento `artifact.*` de um tipo permitido vira um Markdown em
`docs/<agente>/` dentro do workspace do projeto. É **projeção derivada**, no
mesmo sentido estrito que o ADR 0101 deu ao grafo Neo4j: a fonte é o evento, a
pasta pode ser apagada inteira e reconstruída — desde a [RN-590](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-590) por
`artefatos:reprojetar` —, e **nada no produto lê dela** para decidir coisa
alguma.

**O mecanismo é o do `GraphProjector`, copiado peça por peça** — poller
próprio, `drainOnce()` público, flag contra ciclos sobrepostos, lote de 50, e
`markProcessed` só após sucesso. A linha de outbox é uma TERCEIRA, gravada na
mesma transação do evento, sob um `aggregate_type` PRÓPRIO
(`artifact_projection`): `Engine.Outbox.Drain` só drena `session`, `task` e
`container`, e disputar a linha `'session'` seria perder a corrida contra ele
quase sempre. Uma diferença deliberada em relação ao grafo: o `aggregateId` é o
**projeto**, não a sessão — a pasta é do projeto, e gravá-lo ali poupa o
projetor de uma consulta por artefato.

**A lista é de PERMITIDOS.** Tipo de artefato novo nasce fora da projeção e
entra quando alguém decidir que ele é documento, em vez de aparecer sozinho
numa pasta que o usuário lê. Ficam de fora `qa_verdict`, `secops_verdict`,
`task_blocked` e `infra_delegation_files`: são desfechos OPERACIONAIS, e um
veredito de gate por task encheria `docs/qa-lead/` de arquivos que ninguém
abre, custando à pasta a propriedade que a torna útil — caber numa olhada.

**Versionado sobrescreve; append-only leva o `seq`.** Os quatro tipos lidos por
redução ao maior `version` (`module_map`, `module_routing`, `project_image`,
`c4_diagram`) escrevem sempre o mesmo arquivo, e a pasta mostra o vigente — o
histórico continua inteiro no event log. Os demais viram arquivo próprio com o
`seq` do evento no nome, e **sem ele** dois artefatos do mesmo tipo com o mesmo
título gerariam o mesmo arquivo, com o segundo apagando o primeiro: a única
forma de esta projeção perder informação que a fonte tem.

**Duas barreiras contra o filesystem, e a segunda não é redundante.** O nome
sai do título que o MODELO escreveu. `slugDeArquivo` **deriva** um nome de um
alfabeto fechado (nenhum caminho de retorno deixa separador sobreviver;
devolve `null` quando não sobra nada), e `FsArtifactFileStore` confere de novo
com `relative()` antes de abrir. As duas respondem perguntas diferentes — "que
nome eu derivo disto" e "o que eu vou de fato abrir" —, e confiar só na
primeira faria a segurança da escrita depender de nenhuma mudança futura de
slug jamais deixar passar um separador, que é a contenção que o ADR 0130 recusa
por princípio.

**A projeção nunca derruba a fonte.** Nenhum throw escapa do ciclo: cada item
falha isolado, fica logado e permanece `processed_at IS NULL` para o ciclo
seguinte. Diferente do grafo, **não há aqui um erro que pare o lote inteiro** —
falha de escrita costuma ser do ITEM, e parar o lote bloquearia todos atrás
dele. Evento que sumiu do event log é marcado processado, não retentado para
sempre.

**Em modo `runner` a pasta desvia para a raiz gerenciada**, pelo mesmo motivo
físico do `permissions.json` ([RN-478](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-478)): quem escreve é a api, de
dentro do container dela, e o canal do runner só transporta comando, sem
primitiva de escrever conteúdo. Custo declarado: ali `docs/` não fica ao lado
do código.

**A escrita NÃO passa por `proposed_action`**, e não é omissão: aquele pipeline
é a origem de todo efeito externo de um AGENTE PEDINDO PARA AGIR, e aqui o
artefato já foi emitido e já está no event log. Passar a projeção pela fila
encheria as aprovações de decisões rotineiras — uma por artefato — e corroeria
o teto que dá sentido ao clique nas ações que são efeito externo de verdade.

- **Onde:** `apps/api/src/domain/artifacts/artifact-projection-events.ts` (o
  vocabulário e as regras de nome, puros);
  `apps/api/src/application/artifact-projection/artifact-projector.ts` (o
  poller); `apps/api/src/application/ports/artifact-file-store.port.ts` e
  `apps/api/src/infrastructure/filesystem/fs-artifact-file-store.ts` (a
  escrita, com a segunda barreira);
  `apps/api/src/infrastructure/filesystem/project-workspaces-root.ts`
  (`pastaDeArtefatosDoProjeto`, irmã de `permissionsFilePath`);
  `apps/api/src/application/use-cases/sessions/append-session-event.use-case.ts`
  (a terceira linha de outbox)
- **Teste:** `apps/api/test/domain/artifacts/artifact-projection-events.spec.ts`
  (as regras de nome, o traversal e a colisão por `seq`) e
  `apps/api/test/application/artifact-projection/artifact-projector.spec.ts`
  (caminho feliz, versionado sobrescrevendo, e a degradação: falha deixa a
  linha não processada, o ciclo seguinte retenta, uma falha não bloqueia o
  lote, evento sumido não é retentado para sempre, reprocessar é idempotente)
- **ADR:** [0148](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0148-artefatos-projetados-em-arquivo.md)
- **Origem:** pedido do dono do produto — *"criar apenas uma pasta por ora
  chamada docs, onde os artefatos estarão de cada um dos agentes"*

## A revogação de chave de dispositivo deixa de ser cega, e alcança a conexão viva (RN-519..520)

<a id="rn-539"></a>

### RN-539 — `assess_implementability` dispara o threat model de DESIGN em PARALELO, e uma vez só por story {#rn-539}

O appsec (`Engine.Gates.SecOpsAgentServer.run_design/2`, [RN-360](#rn-360))
nasceu implementado, testado e **sem chamador de produção nenhum**: a única
menção fora de teste era um comentário em `artifact_schemas.ex`. A própria
[RN-360](#rn-360) declarava a lacuna, e `packages/contracts/fluxo.yml` (papel `appsec`,
campo `acionamento`) já NOMEAVA o gatilho que faltava — `assess_implementability`
do Dev Lead, gate `implementavel`, o mesmo [ADR 0090](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0090-qa-estrategia-e-appsec-segundo-momento.md).
Era ele. `run_assessment/2` passa a chamá-lo por
`Engine.Gates.Dispatcher.run_appsec_design/2` — sexto callback do behaviour,
CÓPIA estrutural de `run_qa_estrategia/3` e trocável em teste pelo mesmo
motivo dos cinco vizinhos (o chamador é exercitado por um teste leve, sem
sandbox Ecto, e não deveria subir um GenServer real só para provar que
PEDIU).

**Em paralelo, e o parecer não espera.** O disparo acontece nas DUAS saídas
de `run_assessment/2` — com plano de teste e sem — e o desfecho de cada uma
fica byte a byte como era. Fazer o parecer depender do threat model faria o
gate `implementavel` depender de DUAS produções assíncronas em vez de uma, e
queimaria dois turnos do Dev Lead onde hoje se queima um: o ramo `:sem_plano`
já devolve `{:error, ...}` pedindo ao modelo que chame de novo
([RN-163](parte-01.md#rn-163)), e uma segunda espera empilhada nele multiplicaria a
janela. O threat model chega a quem precisa pelo caminho que a
[RN-361](#rn-361) já definiu — handoff para `arquiteto`, `dev-lead` e
`infra` —, nunca por este retorno; a mensagem do `:sem_plano` sequer menciona
o appsec, porque prometer ao modelo algo que ele não vai receber ali é o
defeito que a [RN-163](parte-01.md#rn-163) fecha.

**Desde a [RN-674](parte-04.md#rn-674) não há mais `:sem_plano`**: o parecer sai na
primeira chamada, o disparo do appsec acompanha a proposta, e a leitura do
histórico serve só à guarda abaixo. O appsec segue no DESIGN — a decisão do
dono que tirou o plano de teste do pre-dev foi sobre o QA.

**E uma vez só por story.** O modelo é INSTRUÍDO a chamar
`assess_implementability` de novo enquanto o plano de teste não existe: sem
guarda, cada rechamada custaria outra rodada de LLM do appsec e mais três
handoffs sobre a MESMA story. `disparar_appsec_se_preciso/3` só dispara
quando não há `artifact.threat_model` daquela `storyId` no histórico. A
pergunta aqui é EXISTE, não QUAL — o oposto do plano de teste, onde o mais
recente vence porque uma story pode ser reavaliada.

A leitura do event log é **uma** por chamada: as duas perguntas ("já há plano
de teste?", "já há threat model?") são respondidas sobre a mesma lista. Dois
`list_events/2` na mesma invocação seriam o amplificador de tráfego que o
[ADR 0060](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0060-superficie-de-leitura-de-codigo.md) recusa, e este caminho é
quente justamente por causa da retentativa. Histórico ILEGÍVEL não dispara
nada: ausência de resposta não é prova de ausência de artefato, e disparar ali
reabriria a rechamada por outra porta. A cláusula de args inválidos também não
dispara — ela não sabe qual é a story.

- **Onde:** `apps/engine/lib/engine/agents/dev_lead_tools.ex:544`
  (`run_assessment/2`, a leitura única do histórico) e `:576`
  (`disparar_appsec_se_preciso/3`, a guarda de idempotência);
  `apps/engine/lib/engine/gates/dispatcher.ex:29` (o callback) e `:86`
  (`Engine.Gates.Dispatcher.Live.run_appsec_design/2`);
  `apps/engine/test/support/fake_gate_dispatcher.ex:23`
- **Teste:** `apps/engine/test/engine/agents/dev_lead_tools_test.exs`,
  describe "assess_implementability dispara o appsec (RN-539)" — story sem
  threat model dispara, story com threat model NÃO dispara (a idempotência),
  threat model de outra story não conta, o desfecho de `:sem_plano` não muda,
  o parecer é proposto normalmente ao lado do disparo, args inválidos e
  histórico ilegível não disparam
- **ADR:** [0090](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0090-qa-estrategia-e-appsec-segundo-momento.md)
  (que declarava o gatilho automático como fora de escopo)
- **Origem:** `packages/contracts/fluxo.yml`, papel `appsec`. Fica declarado e NÃO feito:
  `artifact.threat_model` é emitido na sessão da STORY
  (`emit_threat_model/3` lê `story["sessionId"]`), enquanto a guarda lê o
  histórico da sessão do DEV LEAD. No caminho comum são a mesma sessão — o
  Dev Lead avalia stories que a própria sessão de execução criou. Não sendo,
  a guarda não enxerga o threat model e o appsec roda outra vez: custo de uma
  rodada de LLM repetida, nunca dado errado (o artefato é append-only e quem
  o consome é o handoff). Fechar isso exigiria a api aceitar busca de
  artefato por story ATRAVÉS de sessões, que hoje não existe

## A flag que liga um agente tem de CHEGAR ao processo (RN-540)

<a id="rn-540"></a>

### RN-540 — Flag booleana lida pelo `runtime.exs` é mapeada no `environment:` do serviço `engine` dos dois composes, com o default do código {#rn-540}

Uma pausa só é reversível se existir o caminho de ligar. A da Anamnese e a do
Psicólogo ([RN-115](parte-01.md#rn-115),
[RN-117](parte-01.md#rn-117)) foram declaradas reversíveis
em TRÊS lugares — o docblock de `AnamneseSchedulerWorker.enabled?/0` ("Ligar de
volta é `ANAMNESE_ENABLED=true` e reiniciar o engine"), o de
`PsychologistWorker.enabled?/0` e a tabela de
[configuração](https://github.com/viralabs-dev/brabo/blob/dev/docs/reference/configuration.md) — e o caminho **não existia em
ambiente nenhum**.

**Medido, não hipótese.** Com o compose de dev de pé:

```
$ docker compose … exec -T engine sh -lc \
    'echo "[$START_ANAMNESE] [$ANAMNESE_ENABLED] [$PSYCHOLOGIST_ENABLED]"'
[true] [] []
```

A causa é a camada que só o Compose tem: **ele não repassa o ambiente do host
ao container**. Uma variável chega ao processo se, e só se, estiver escrita no
`environment:` (ou num `env_file`) daquele serviço. O `engine` mapeava TREZE
variáveis de Anamnese/Psicólogo — todas TETOS de custo
(`ANAMNESE_INTERVAL_SECONDS`, `ANAMNESE_BUDGET_MICROS`,
`PSYCHOLOGIST_TRIAGE_THRESHOLD`, …) — e nenhuma das duas que decidem se os
agentes rodam. `ANAMNESE_ENABLED=true` no `.env` era inerte:
`apps/engine/config/runtime.exs` caía no default `"false"` e os dois seguiam
desligados **em silêncio, sem erro**.

Origem provável do defeito: quando o default do código virou `false`
(2026-08-10), ninguém precisou da variável para DESLIGAR. Só quem tenta LIGAR
descobre que o fio não existe — e essa pessoa, por construção, aparece meses
depois.

**A regra.** Toda flag BOOLEANA que o `runtime.exs` lê — a forma
`System.get_env("X", "true"|"false") == "true"` — tem de estar mapeada no
`environment:` do serviço `engine` dos dois composes. O recorte é o das
booleanas e não o das 58 variáveis do arquivo porque uma flag existe
exatamente para ser virada, e a virada acontece pelo ambiente: flag sem linha
no compose é interruptor sem fio. Teto numérico com default bom
(`READ_FILE_MAX_BYTES`) e variável de release (`SECRET_KEY_BASE`, `POOL_SIZE`)
ficam legitimamente de fora, e é por isso que a lista é DERIVADA do
`runtime.exs` em vez de mantida à mão.

O default difere por arquivo, e a diferença é a decisão:

- em `docker/docker-compose.yml` (dev) a linha repete o default do CÓDIGO. Dev
  é onde a promessa dos docblocks é exercida, e um default divergente ali faria
  o compose decidir produto por baixo do `runtime.exs`.
- em `docker/docker-compose.prod.yml` basta estar mapeada. Aquele arquivo
  desliga os agentes de fundo de propósito (`START_ANAMNESE:-false` contra o
  `true` do código), com o motivo escrito ao lado — cobrar igualdade
  reprovaria uma decisão consciente.

**Isto NÃO muda decisão de produto nenhuma.** As duas flags continuam
`false` por default nos dois composes: a pausa de 2026-08-10 segue valendo,
byte a byte. O que passou a existir é o interruptor.

**E `ANAMNESE_ENABLED=true` sozinho não basta.** `START_ANAMNESE` (chave de
BOOT, `apps/engine/lib/engine/application.ex:82,106-108`) decide se o `kickoff/0` que
AGENDA o tick periódico é chamado; `ANAMNESE_ENABLED` (flag de PRODUTO) decide
se uma rodada NOVA pode acontecer. São perguntas diferentes, e a Anamnese
periódica exige as duas em `true`. O Psicólogo tem só a segunda — o gatilho
automático dele é o fechamento de sessão, não um tick.

**`deploy/k8s/` fica de fora, e por decisão.** Lá não existe a camada que
quebra: um Deployment/ConfigMap não intercepta nada, e a variável é escrita
onde toda variável é escrita. O `brabo-config` tem QUATRO literais (endereços
de serviço e nível de log do web), sem nenhum dos 13 tetos nem
`START_ANAMNESE` — o engine roda com os defaults do código, coerentemente.
Não há interruptor sem fio a consertar ali.

- **Onde:** `docker/docker-compose.yml:406-425` (as quatro chaves de boot e as
  quatro flags de produto, no bloco de cada agente);
  `docker/docker-compose.prod.yml:308-315`;
  `apps/engine/config/runtime.exs:157,158,162,168,185,229,238,264` (as oito
  flags); `.env.example` (as duas perguntas, lado a lado)
- **Teste:** `scripts/ci/flags-do-engine-no-compose.spec.ts` — deriva as flags
  do `runtime.exs` e reprova nomeando a que faltar em qualquer dos dois
  composes, e a que divergir do default do código no de dev. `warn` nenhum:
  reprova mesmo, no job `test-packages`
- **Origem:** achado por medição direta no container do engine, 2026-09-08.
  Fica declarado: a lista de exceções `FLAGS_FORA_DO_COMPOSE` nasce VAZIA — ela
  existe para que "fora por decisão" tenha onde ser dito, e não vire
  indistinguível de "fora por esquecimento"

---

## A chave de dispositivo ganha tela, e a tela diz o alcance de revogar (RN-561)

<a id="rn-566"></a>

### RN-566 — O Infra Lead recusa `container_start` por MODO antes de propor: a lacuna da RN-494 fecha na tool que a declarava {#rn-566}

`propose_container_start` propunha às cegas. `dispatch_container_start/2`
montava o payload e chamava `EngineApiClient.propose_action(...)` direto — sem
uma leitura de projeto entre uma coisa e outra, e com **zero** ocorrências de
`execution_mode` na tool inteira. Num projeto `runner` a proposta só podia
terminar em falha: desde a [RN-507](https://github.com/viralabs-dev/brabo-runner/blob/dev/docs/business-rules/runner.md#rn-507)/[ADR 0145](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0145-docker-pre-requisito-do-runner.md)
`container_start` **não atende** esse modo, porque o payload dela ELEGE uma
candidata do roteamento do Arquiteto ([ADR 0131](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0131-roteamento-de-modulos-para-infra.md))
e em `runner` não há roteamento contra o qual eleger — o tipo daquele modo é
[`container_start_via_runner`](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-508).

**A régua não é nova, e não nasceu uma segunda.** A tool irmã já recusava
localmente ([RN-508](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-508)) e a página `/containers` já ramificava por
DESTINO ([RN-521](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-521), `acaoDeSubidaDoModo`): `container` e `mounted`
sobem pelo BROKER, `runner` sobe pelo agente local ([ADR 0144](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0144-a-segunda-raiz-do-broker.md)/[RN-503](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-503)).
O que esta regra faz é dar à tool que faltava a MESMA régua — uma leitura de
projeto (`recusa_local_de_subida/2`, que devolve `nil` ou motivo) e uma
CLÁUSULA por tool (`recusa_por_modo/3`). Duas réguas paralelas divergiriam no
primeiro modo novo do enum.

**A recusa de `container_start` é lista de PERMITIDOS**, como a do próprio
broker: `container`/`mounted` passam, `runner` é recusado NOMEANDO a tool
irmã, e modo novo no enum nasce recusado com mensagem em vez de proposto por
omissão. Projeto inexistente também recusa — mesma cláusula das duas tools.

**A recusa é ENTRADA do laço** ([RN-163](parte-01.md#rn-163)): texto de RESULTADO de
ferramenta, que o modelo lê e usa para chamar a tool certa. Nunca
`agent.error`, nunca fim de turno, nunca `proposed_action` — a api não é
chamada. E **não é silêncio**: o `emit` do `tool.call` passou a acontecer
ANTES da recusa nas DUAS tools (na irmã ele estava dentro do ramo que propõe),
como no `dispatch_tool/2` genérico do mesmo módulo — recusa sem rastro no
event log é a chamada sumindo do timeline do humano.

**As leituras são LOCAIS, e isso é a decisão.** `Project.get/1` e
`Engine.Runners.Registry.connected?/1` rodam no MESMO processo BEAM do Infra
Lead; um HTTP à api aqui poria uma chamada de rede dentro do laço do agente.
O custo declarado no `CLAUDE.md` — *"corrigir exigiria tocar o
prompt/instrução do Infra Lead"* — **não se confirmou**: nenhuma linha de
prompt mudou, e o texto da recusa é o que o modelo lê como resultado.

**O que esta regra NÃO fecha, e é metade da lacuna:** a proposta cega por
AUSÊNCIA DE IMAGEM continua possível em `container`/`mounted`. A recusa aqui é
sobre MODO, e exigir imagem decidida inverteria a ordem — eleger a imagem é
justamente o que essa proposta FAZ ([RN-491](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-491)). A `/containers` checa
as TRÊS coisas (imagem decidida, modo, pasta confirmada) porque tem um humano
clicando; o agente passa a checar UMA. `GetInfraContextUseCase` segue sem
`executionMode` — enriquecer o contexto do Infra Lead é frente à parte.
`container_stop`/`container_remove` não entram: são propostas pela tela, nunca
por agente ([RN-495](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-495)).

Nenhum teto muda: `container_start` segue `proposed_action` de verdade,
`maintainer`, nunca semeada em auto-aprovação (até a [RN-671](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-671), que a
semeia no aceite do handoff da Infra), e `container_remove` segue no
teto absoluto de git push/comando privilegiado ([RN-418](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-418)).

- **Código:** `apps/engine/lib/engine/infra/infra_lead_server.ex:599` (o
  dispatch de `container_start` consultando antes de propor), `:889`
  (`recusa_local_de_subida/2` — a leitura ÚNICA do projeto), `:474` (a
  cláusula de `container_start`: lista de permitidos), `:477` (a recusa
  nomeando `container_start_via_runner`), `:492` (a cláusula da irmã, com a
  segunda pergunta — runner conectado), `:409` (o `emit` do `tool.call`
  movido para antes da recusa);
  `apps/engine/lib/engine/infra/tools/propose_container_start.ex`
  (moduledoc — a tool deixou de propor às cegas)
- **Teste:** `apps/engine/test/engine/infra/infra_lead_server_test.exs:422`
  (caminho feliz em `mounted` — o broker atende os dois), `:448` (caso de
  falha: `runner` recusa NOMEADO, `propose_action` nunca chamada, o `tool.call`
  narrado mesmo assim), `:538` (projeto inexistente), `:380` (o caminho feliz
  de `container`, que passou a exigir a linha no banco)
- **ADR:** [0144](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0144-a-segunda-raiz-do-broker.md),
  [0145](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0145-docker-pre-requisito-do-runner.md)
- **Origem:** AT-048 (EP-020/HS-032) — a lacuna declarada no `CLAUDE.md` desde
  a [RN-494](https://github.com/viralabs-dev/brabo-broker/blob/dev/docs/business-rules/broker.md#rn-494)
