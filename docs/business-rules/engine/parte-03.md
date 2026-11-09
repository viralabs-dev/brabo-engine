---
id: rn-engine-parte-03
title: 'Regras de negócio — Engine — parte 3 (desde RN-577)'
sidebar_label: 'Engine — parte 3 (desde RN-577)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

# Engine — parte 3 (desde RN-577)

## O broker de container na instalação, com consentimento (RN-575)

<a id="rn-577"></a>

### RN-577 — `open_adr_pr` e `open_infra_pr` são recusadas pelo agente, antes de propor, quando o projeto não tem repositório {#rn-577}

Numa instalação real (AT-088, 2026-09-14), um projeto sem repositório —
`project_repositories`, `project_git_connections` e `repo_bootstraps` vazias —
recebeu três `open_adr_pr` do Arquiteto e uma `open_infra_pr` do Infra Lead. O
humano aprovou as quatro, e as quatro terminaram `failed` com *"Projeto sem
repositório provisionado"* (`ExecuteAdrPrUseCase`, `ExecuteInfraPrUseCase`).
A pessoa aprovou quatro ações que só podiam falhar.

**Não é borda, é o caso comum.** Desde a [RN-541](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-541) criar um projeto
não cria repositório, e o gatilho do repositório é o aceite do handoff do
Arquiteto para o Dev Lead ([RN-522](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-522)). O Arquiteto trabalha ANTES desse
handoff — então num projeto novo **todo** `open_adr_pr` falhava por
construção.

**A regra:** as duas tools perguntam, ANTES de propor, se o projeto tem
repositório, e sem ele RECUSAM com motivo NOMEADO — o que falta, e quando passa
a existir. A `proposed_action` não nasce, e a fila de aprovação não recebe o
que não pode dar certo.

**O molde é o da [RN-566](parte-02.md#rn-566), sem régua nova e sem tocar prompt.** A
recusa é resultado de ferramenta ([RN-163](parte-01.md#rn-163)),
entrada do laço — nunca `agent.error`, nunca fim de turno —, e o modelo segue
o turno lendo o motivo.

**A leitura é LOCAL, e o predicado é o MESMO da execução.** O engine já lia
`project_repositories` direto do Postgres (`Engine.Projects.ProjectRepository`,
os consumidores de `default_branch/1` e `remoto_de_trabalho/1`), então não
houve HTTP no laço do agente a medir nem a justificar: a pergunta nova,
`recusa_de_pr_sem_repositorio/2`, é a MESMA que
`ProvisionedRepositoryRepository.findByProjectId` faz nos dois casos de uso —
existe linha para o projeto. Se os dois divergissem, a tool deixaria passar o
que a execução recusa, ou recusaria o que ela aceitaria. As duas tools usam a
MESMA função, com o mesmo texto.

**No Infra Lead a pergunta vem antes do HALT.** `propose_infra_pr` não propõe
na hora: ela interrompe o turno para `finalize/3` rodar o `WorkflowsAgent` e
consolidar numa PR só. Recusar depois disso (em `abrir_pr/3`) teria gastado um
laço de LLM inteiro e registrado duas delegações `completed` para uma PR que
não pode existir. A recusa acontece na interceptação, e o turno CONTINUA.

**Rastro durável nas duas.** A AT-048 achou que recusa local não deixava rastro
no event log; a RN-566 resolveu emitindo o `tool.call` antes da recusa, e aqui
vale o mesmo — no Arquiteto o `dispatch_tool/2` já o emitia; no Infra Lead a
interceptação de `propose_infra_pr` não emitia nada e passa a emitir, no ramo
da recusa, com o título e os CAMINHOS (nunca o conteúdo dos arquivos). E o
PORQUÊ vai junto: um `tool.result` com `ok: false` e `erro` com o motivo — a
forma que o Criativo já usa —, porque só o `tool.call` diria que a chamada
existiu, não por que ela não virou proposta. No caminho que propõe nada muda:
o rastro dele continua sendo a própria `proposed_action`.

**Os casos de uso de execução continuam recusando como antes** — defesa em
profundidade: a recusa do agente é uma camada ANTES, nunca no lugar.

**O que esta regra NÃO decide:** ONDE o repositório deveria nascer. O texto da
recusa descreve o gatilho vigente, e ele MUDOU: a AT-092 foi decidida na
[RN-582](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-582) (ADR 0165) — o repositório nasce no aceite do handoff AO
Arquiteto, antes do primeiro turno dele, com o aceite ao Dev Lead como segunda
porta. O texto mudou junto, como esta regra prometia: ele nomeia o gatilho
novo e, como o Arquiteto só trabalha depois desse aceite, diz que a recusa
significa provisionamento FALHADO (o `repository.provision_failed`) ou projeto
anterior à regra, com as duas saídas. Deixou de ser o caso comum; a recusa
continua, porque essas duas situações existem. A `open_infra_pr` também é afetada no projeto novo por outro
caminho (o Infra Lead é acionado pelo handoff do Arquiteto, que pode acontecer
antes do handoff ao Dev Lead); esta regra só faz a proposta não nascer, não
reordena os handoffs.

- **Código:** `apps/engine/lib/engine/projects/project_repository.ex:74`
  (`recusa_de_pr_sem_repositorio/2` — o predicado e o texto, únicos para as
  duas tools); `apps/engine/lib/engine/harness/tools/propose_adr.ex:54` (a
  recusa antes de propor), `:61` (o `tool.result` com o motivo);
  `apps/engine/lib/engine/infra/infra_lead_server.ex:251` (a interceptação de
  `propose_infra_pr` perguntando antes do HALT), `:632`
  (`recusa_de_infra_pr/4`), `:309` (o `tool.call` com os caminhos), `:314` (o
  `tool.result`)
- **Teste:** `apps/engine/test/engine/agents/arquiteto_server_test.exs:107`
  (caso de falha: sem repositório, `open_adr_pr` nunca proposta, motivo como
  resultado de ferramenta, `tool.call` e `tool.result` no event log), `:80`
  (caminho feliz: com repositório, propõe);
  `apps/engine/test/engine/infra/infra_lead_server_test.exs:491` (caso de
  falha: sem repositório, nem `propose_action` nem delegação do Workflows, o
  turno segue, rastro durável), `:89` (caminho feliz: com repositório, a PR
  consolidada é proposta)
- **Origem:** AT-088 — instalação real em 2026-09-14

<a id="rn-578"></a>

### RN-578 — O clique que dispara turno de agente responde ao ACEITAR, e a recusa deixa de ser calada {#rn-578}

Numa instalação real da v6.1.0 (2026-09-14), responder o formulário de
perguntas do Criativo levou **97,3 s**, confirmar a prontidão **97,3 s** e
confirmar a arquitetura pronta **51,8 s** — cada clique segurado pelo turno
INTEIRO do agente, porque o `handle_call` do conversacional só respondia ao
`GenServer.call` do controller do engine quando a Task do turno terminava. Turno
acima do teto (120 s no Criativo, 180 s nos outros) virava 500 num comando que
tinha funcionado. E a recusa de uma segunda mensagem com turno em curso
(`{:error, :turno_em_andamento}`) era descartada pelo controller, que respondia
202: um *"Continue"* digitado durante o kickoff do Arquiteto foi aceito e nunca
lido, sem rastro nenhum.

**A regra ([ADR 0163](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0163-o-clique-responde-ao-aceitar.md), que generaliza
o [ADR 0086](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0086-dev-lead-plano-suspende-para-aprovacao.md)):**

1. **O aceite sai na hora.** `TurnoAssincrono.iniciar/3` responde `:ok` ao
   `from` assim que a Task sobe — depois de persistir `agent.status: working`,
   nunca antes. Vale para os seis conversacionais e para as quatro rotas de
   usuário que disparam turno (`…/agents/:agent/message` e, por ela,
   `…/structured-question/:id/answer`; `…/readiness`;
   `…/agents/arquiteto/handoff-infra`) e para a devolução de história
   (`ReturnStoryUseCase`). O status e o corpo da api NÃO mudam
   (`201 { ok: true }`): sempre significaram "aceito"; o que mudou foi quando
   chegam.
2. **A recusa ANTES de o turno subir é síncrona e nomeada.** O engine responde
   409 (`turno_em_andamento`, `aguardando_aprovacao`) ou 422
   (`sem_regra_de_negocio`) com `{error, motivo}`, e a api repassa o MESMO
   status com a MESMA frase. `turno_em_andamento` ganha `agent.error` durável
   (origem `politica`); os outros dois já tinham.
3. **O desfecho do turno segue pelo canal e pelo log, nunca pelo HTTP.** Falha
   continua `agent.error` durável, com a mesma origem de antes.
4. **A tela deixa de tratar "a chamada resolveu" como fim de turno.** Depois do
   aceite, ela acompanha o fim pelo canal (`agent.done`) e, como rede de
   segurança, pela cauda do log a cada 4 s: fecha quando o `agent.status`
   persistido mais recente daquele agente não é `working`. Sem nenhum
   `agent.status` do agente na janela, não fecha — não saber não é "acabou".
5. **O handoff ao Dev Lead continua nascendo DEPOIS do de Infra.** O
   `:offer_dev_handoff` que chega com o turno de fechamento do Arquiteto em
   curso fica pendente e roda quando o turno fecha — sucesso, falha, crash ou
   cancelamento. *(Superado pela [RN-672](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-672): o Arquiteto não oferece
   mais ao Dev Lead, e a pendência deixou de existir.)*

**O que esta regra NÃO fecha:** o `chat.message` que a api grava antes de
perguntar ao engine continua no log quando o engine recusa (agora explicado pelo
`agent.error`, antes órfão e mudo); engine reiniciado no meio do turno não grava
`idle`, e a faixa fica até o "Parar" ou um recarregamento; e mensagem ao
`infra` pelo compositor caía no Criativo pela cláusula final de
`AgentCommandController.message/2` — pré-existente, medido aqui e fechado
depois pela [RN-584](#rn-584), que tirou o destinatário padrão.

**Revisada para a MENSAGEM pela [RN-673](parte-04.md#rn-673)** (ADR 0191): a mensagem do
usuário que chega com turno em curso não recebe mais `turno_em_andamento` —
entra na fila do agente e é lida no fim do turno. A recusa do item 2 segue
valendo para os comandos que não são fala (revisão, prontidão, oferta de
handoff).

- **Código:** `apps/engine/lib/engine/agents/turno_assincrono.ex:120` (o
  aceite), `:130` e `:314` (a recusa durável);
  `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:241`
  (202), `:243`/`:253`/`:263` (409/409/422);
  `apps/engine/lib/engine/agents/dev_lead_server.ex:211`;
  `apps/engine/lib/engine/agents/arquiteto_server.ex:160` (adiar), `:202`
  (drenar); `apps/api/src/infrastructure/http-clients/api-to-engine-client.ts:591`,
  `:612`; `apps/web/src/lib/session-turno.ts:33` (`turnoTerminouNoLog`),
  `:349` (`acompanharTurnoPeloLog`), `:316`;
  `apps/web/src/routes/SessionPage.tsx:491`, `:517`, `:578`;
  `apps/web/src/lib/session-promocao.ts:141`;
  `apps/web/src/lib/recusa-do-agente.ts:17`
- **Teste:** `apps/engine/test/engine/agents/turno_assincrono_test.exs:66`
  (aceite com a task viva), `:84` (`working` gravado antes do aceite), `:178`
  (recusa durável — caso de falha);
  `apps/engine/test/engine_web/controllers/agent_command_controller_test.exs:35`,
  `:66` (409), `:107` (422);
  `apps/engine/test/engine/agents/arquiteto_server_test.exs:209` (ordem dos
  handoffs), `:237` (cancelamento);
  `apps/api/test/infrastructure/http-clients/api-to-engine-client.spec.ts:520`,
  `:538`, `:580` (500 continua genérico);
  `apps/web/src/routes/SessionPage.turno-preso.test.tsx:181`, `:252` (409);
  `apps/web/src/routes/SessionPage.readiness-turno-preso.test.tsx:172`, `:210`
  (422); `apps/web/src/lib/fim-do-turno-pelo-log.test.ts:29`, `:76`
- **Origem:** AT-089 — instalação real da v6.1.0 em 2026-09-14

<a id="rn-579"></a>

### RN-579 — Com o canal da sessão vivo, a tela de Sessão troca o poll curto por invalidação e um fallback longo; resposta de corpo vazio tem `ETag` {#rn-579}

A instalação medida na AT-093 (v6.1.0, 14/09) mostrou UM navegador fazendo
7.088 requisições em 56 minutos — mediana de 118/min, pico de 263/min —
contra os 300/min do `RATE_LIMIT_USER`. Duas abas visíveis no pico passam do
teto, e o 429 cai no navegador do dono da conta. Quase tudo era poll de 3–5s
da tela de Sessão sobre dados que mudam raro (ações, handoffs e backlog
voltavam 304 em 99% das vezes), enquanto a tela já mantinha aberto o canal
`session:<id>` com o engine. O teto NÃO muda: o que cai é o pedido.

**A regra:**

1. **O engine avisa toda escrita confirmada.** A fachada
   `Engine.Sessions.EngineApiClient` emite `event.appended` (só `type` e
   `actorId`, nunca o `payload`) depois que a api CONFIRMA `append_event`,
   `append_event_returning`, `propose_action` (`proposed_action.created`),
   `create_handoff` (`handoff.offered`) e `create_epic/story/task`
   (`backlog.*_created`). Escrita recusada não avisa. Antes, só
   `ArtifactEmitter` e o Infra Lead avisavam, à mão — e avisavam mesmo quando a
   api recusava o append. **Desde a AT-157, a escrita que a API faz por conta
   própria também avisa** — a decisão de um humano noutra aba, uma transição de
   sessão, o chat respondido pelo modelo da própria api. `AppendSessionEventUseCase`
   e o `SendChatMessageUseCase` (os dois únicos pontos que gravam em
   `session_events` sem passar pelo engine) chamam
   `SessionChannelNotifier.eventAppended`, que pede ao engine
   `POST /internal/sessions/:id/event-appended`; o engine faz o MESMO
   `event.appended` (só `type` e `actorId`). O aviso sai DEPOIS do commit da
   transação mais externa (`aposCommit` no `DrizzleUnitOfWork`): transação
   desfeita não avisa, e avisar de dentro dela faria a web buscar antes de o
   evento existir. Escrita que veio do engine (rota `/internal/*`, marcada pelo
   `OrigemEngineMiddleware`) NÃO é avisada de novo pela api — a fachada já
   avisou. É melhor esforço e não é aguardado: o aviso perdido nunca falha a
   escrita, e o fallback de 15s o cobre. São só os dois pontos: outro caso de
   uso que passe a gravar em `session_events` sem `AppendSessionEventUseCase`
   precisa chamar o notifier também.
2. **"Canal vivo" é join CONFIRMADO.** `connectSessionHeartbeat` marca a sessão
   viva no `ok` do join e a desmarca em erro/fechamento do canal ou do socket e
   no cleanup. O estado é por sessão e por aba, fora do React, porque o
   intervalo é de cada OBSERVADOR e três observadores (Shell, `SessionPage`,
   `ContextAside`) leem a mesma chave de eventos.
3. **Com o canal vivo, o poll vira fallback.** Eventos, ações, handoffs,
   backlog e a própria sessão passam de 3–5s para 15s; o orçamento, de 5s para
   30s. `intervaloDaSessao` é `Math.max`: quem já pollava mais devagar não
   acelera. Canal caído devolve o intervalo curto NA HORA — a tela nunca fica
   pior do que era.
4. **O TIPO do aviso decide o que invalidar, com janela.** Todo aviso
   invalida os eventos e o orçamento; `proposed_action.*`/`action.*` também as
   ações, `handoff.*` os handoffs, `backlog.*` o backlog. Cada alvo tem janela
   mínima entre duas buscas (eventos 3s, ações/handoffs/backlog 2s, orçamento
   10s): a primeira sai na hora, as seguintes dentro da janela viram UMA no fim
   dela. Sem isso, uma rajada de `tool.result` viraria uma busca por evento. A
   regra do achado C segue, e só para os EVENTOS: durante um turno em
   streaming eles não são antecipados; as ações são.
5. **Aba oculta não polla.** `refetchIntervalInBackground: false` (o default do
   TanStack v5, agora escrito em `OPCOES_PADRAO_DAS_QUERIES`) — medido por
   teste, não suposto.
6. **Corpo vazio tem validador.** Handler que devolve `null` saía com corpo
   vazio e SEM `ETag` (o `res.send` do Express só gera `ETag` com corpo), então
   o 304 era impossível: `sessions/:id/budget` voltou 304 em 0% das 483
   chamadas medidas e `execution/session` em 22% (o tempo com execução ativa).
   A api grava o `ETag` do corpo vazio quando `send` sai sem corpo — decidido
   sobre o que vai ao fio, não sobre o valor do handler, para que um handler
   com `@Res()` que escreve depois nunca herde o validador do vazio. 304 NÃO
   reduz a contagem do rate limit (o guard conta antes do handler); reduz banda.
7. **Compõe com o acompanhamento do turno pela cauda do log ([RN-578](#rn-578)).**
   O turno ACEITO continua sendo acompanhado pela leitura da cauda a cada 4s
   (`acompanharTurnoPeloLog`) — é a rede contra o `agent.done` perdido, e o
   aviso do canal pode se perder junto com ele, então o tique NÃO vira
   fallback de 15s. O que muda: o `event.appended` do `agent.status` do agente
   ACOMPANHADO roda a leitura NA HORA (`avisoPedeVerificacaoDoTurno`), e o
   turno fecha assim que o log diz que fechou, sem esperar o tique. Aviso de
   outro agente, de outro tipo, ou sem turno acompanhado não lê nada a mais. E
   o poll de 3s dos eventos continua PAUSADO durante o streaming (achados 2/7):
   `intervaloDaSessao` só vale quando a pausa não vale, e a invalidação pelo
   canal respeita a mesma regra do achado C.

**Números** (teste de orçamento, uma aba na tela de Sessão, por minuto):
**123** com o canal caído (o comportamento de antes, intacto como fallback) e
**46** com ele vivo — dos quais 24 são do Shell (resumo dos projetos e sessão
de execução, que não são da sessão e seguem em 5s). Duas abas: 246 → 92.
Desde a [RN-632](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-632) (AT-278) as leituras de PROJETO pollam no ritmo de
projeto (15s) e as abas Executores e Visão geral passam pelo MESMO
`criarInvalidadorDoCanal` — a medição com as telas de verdade e duas abas mora
lá.

**O que esta regra NÃO fecha:** o aviso da escrita que a api faz por conta
própria (item 1, AT-157) é melhor esforço — se o engine estiver fora ou o
aviso se perder, a tela chega pelo fallback, em até 15s (eram 3s); o aviso vai
ao nó do engine que recebeu a chamada, e o broadcast do Phoenix PubSub o
entrega aos inscritos de qualquer nó do cluster (não medido em cluster). O status
`working` do roster continua dependendo do `event.appended` do `agent.status`,
que sai depois de a api gravá-lo. `projects-summary` e `execution/session`
(Shell) seguem em 5s. Durante um turno aceito, a leitura da cauda de 4s da
RN-578 soma até 15 req/min, só enquanto o turno dura. Não é mudança de modelo de consistência (sem ADR): a
fonte continua sendo o GET, o canal continua sendo só gatilho — como já era
desde a Fase 4a —, e o que muda é a latência máxima das escritas sem aviso.

- **Código:** `apps/engine/lib/engine/sessions/engine_api_client.ex:581`,
  `:607`, `:630`, `:1135` (`avisar_canal`);

  `:607`, `:630`, `:953` (`avisar_canal`);
  `apps/engine/lib/engine/sessions/live_broadcast.ex` (`event_appended/3`);
  `apps/engine/lib/engine_web/controllers/session_command_controller.ex:46`
  (`event_appended`, a rota do aviso da api);
  `apps/api/src/application/use-cases/sessions/append-session-event.use-case.ts:232`
  (`eventAppended`);
  `apps/api/src/infrastructure/persistence/drizzle/drizzle-context.ts:39`
  (`aposCommit`), `:53` (`veioDoEngine`);
  `apps/web/src/lib/canal-vivo.ts:35` (fallback), `:66` (estado), `:108`
  (`intervaloDaSessao`), `:134` (`alvosDoEvento`), `:150` (janelas), `:207`
  (`criarInvalidadorDoCanal`); `apps/web/src/lib/session-channel.ts:161`,
  `:165`, `:131`, `:229`; `apps/web/src/lib/session-turno.ts:414`
  (o aviso: invalida e, do acompanhado, antecipa a leitura), `:86`
  (`avisoPedeVerificacaoDoTurno`), `:344` (a leitura imediata);
  `apps/web/src/lib/hooks.ts` (`useSessionEvents`, `usePendingActions`,
  `useHandoffs`, `useBacklog`); `apps/web/src/lib/query-policy.ts:86`;
  `apps/api/src/interfaces/http/shared/etag-do-corpo-vazio.ts:40`;
  `apps/api/src/main.ts:80`
- **Teste:** `apps/web/src/lib/canal-vivo.orcamento.test.tsx:138` (antes, 123),
  `:155` (depois, 46), `:176` (canal cai — caso de falha), `:186` (rajada),
  `:214` (aba oculta); `apps/web/src/lib/session-channel.test.ts:237`, `:253`
  (queda — caso de falha), `:267`;
  `apps/engine/test/engine/sessions/engine_api_client_aviso_no_canal_test.exs:29`,
  `:57` (append recusado não avisa — caso de falha), `:71`;
  `apps/api/test/application/use-cases/sessions/aviso-ao-canal-da-sessao.spec.ts`
  (AT-157: avisa com tipo e ator; recusada não avisa e transação desfeita não
  avisa — casos de falha; engine fora do ar não falha a escrita; escrita vinda
  do engine não é avisada em dobro),
  `apps/api/test/infrastructure/http-clients/origem-engine.middleware.spec.ts`,
  `apps/engine/test/engine_web/controllers/session_command_controller_event_appended_test.exs`;
  `apps/api/test/interfaces/http/shared/etag-do-corpo-vazio.spec.ts:56` (a
  causa), `:69`, `:98` (`@Res()` tardio — caso de falha);
  `apps/api/test/interfaces/rate-limit.guard.spec.ts:183` (2 × 263 estoura,
  2 × 118 não); `apps/web/src/routes/SessionPage.canal-e-acompanhamento.test.tsx:166`
  (o predicado), `:203` (o aviso do acompanhado fecha o turno sem esperar o
  tique), `:221` (aviso de outro agente não lê, e o tique de 4s segue sendo a
  rede — caso de falha), `:244` (turno fechado: nem aviso nem tique leem)
- **Origem:** AT-093 — logs da api instalada (v6.1.0), 2026-09-14; AT-157 — o aviso da escrita da própria api

<a id="rn-580"></a>

### RN-580 — O agente conversacional que sobe sobre uma conversa recebe o FIM dela, com perguntas e ferramentas, e o começo que não coube é resumido com o número escrito {#rn-580}

Os seis agentes conversacionais (Criativo, PO, Arquiteto, Dev Lead, UX
Designer e Staff) reconstroem o histórico do event log no `init/1` — no
restart e, também, quando sobem numa sessão que já tem conversa (o PO no
handoff do Criativo). Medido em 13/09 (AT-073, contra a `b61bc49cd`), os seis
tinham a MESMA cópia de `rehydrate/2`, com três defeitos:

1. **Liam o começo.** `EngineApiClient.list_events/2` pede `limit=200` sem
   `latest`, e a rota interna — que nem aceitava `latest` — devolve os
   PRIMEIROS 200. Numa conversa de 201 eventos o agente acordava sem a
   mensagem que estava respondendo. A tela já tinha resolvido isso com
   `latest: true` e aviso de recorte ([RN-180](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-180));
   o engine não tinha herdado.
2. **Reconstruíam só `chat.message` e `agent.response`.** A pergunta feita por
   formulário (`chat.structured_question`) e as ferramentas chamadas
   (`tool.call`/`tool.result`) sumiam.
3. **Cortavam calados.** E as leituras dos kickoffs (PO, Arquiteto, Dev Lead,
   UX Designer) e das regras do product_brief (Criativo) filtravam em memória
   os mesmos PRIMEIROS 200 eventos de todos os tipos: numa conversa longa com o
   Criativo, o brief nascia depois do evento 200 e o PO recebia "(sem product
   brief disponível)".

**A regra:**

1. **Um caminho só.** `Engine.Agents.Reidratacao` substitui as seis cópias; os
   seis servidores chamam `historico/3` no `init/1`.
2. **A cauda, com o teto do ADR 0060.** A leitura é `latest=true&limit=200` — o
   `MAX_LIMIT` da rota, nem mais (a api cortaria) nem menos (deixaria de fora o
   que ela entrega de graça). O teto NÃO ficou ilimitado.
3. **O que entra.** `chat.message` e `agent.response` como sempre (de qualquer
   agente da sessão — é o que o PO herda do Criativo); `chat.structured_question`
   como fala do agente, com rótulos e opções; `tool.call`/`tool.result` do
   PRÓPRIO agente como nota de texto com a ferramenta, os argumentos (cortados
   em 1.500 caracteres) e o desfecho — nunca como mensagem `role: "tool"`, porque
   o evento não guarda o id da chamada e um `tool_result` sem o `tool_use`
   correspondente é recusado pelo provider. `chat.structured_question_answered`
   fica DE FORA de propósito: a api grava as mesmas respostas num `chat.message`
   logo depois (`AnswerStructuredQuestionUseCase` reusa
   `SendAgentMessageUseCase`), e reidratar os dois duplicaria a resposta.
4. **O começo que não coube é dito, com o número.** O `seq` é gapless e começa
   em 1, então o número de eventos omitidos é o `seq` do primeiro da cauda menos
   um — SUBTRAÇÃO, sem requisição a mais. Quando ele é maior que zero, o
   histórico abre com UMA mensagem de sistema que escreve esse número e traz o
   resumo da compactação de contexto mais recente do agente (quando foi
   gravado) e a abertura da conversa (as seis primeiras mensagens dos primeiros
   40 eventos, cortadas em 500 caracteres). São mais duas leituras com teto —
   três no total, e uma só quando a conversa cabe.
5. **`context.compacted` grava o resumo daqui em diante** — `summary`, `agent`
   e `messagesSummarized`, ao lado das contagens de sempre. Conversa compactada
   antes disto fica DECLARADA ("compactada N vez(es) antes de o resumo passar a
   ser gravado; aquele resumo se perdeu"), nunca reconstruída; os eventos
   antigos não mudam.
6. **Histórico ilegível não vira conversa vazia.** Se a leitura falha, o agente
   recebe uma mensagem de sistema dizendo que não conseguiu ler o histórico.
7. **Kickoffs e refs do brief leem POR TIPO, pela cauda.** A rota interna ganhou
   `types` (até 20, validados; malformado é 400) — mudança de CONTRATO,
   aditiva: sem `latest`/`types` a resposta é a de antes. Quando a leitura por
   tipo bate no teto, o kickoff diz que pode haver itens mais antigos.

**Medido por agente:** os seis mudaram na reidratação (`init/1`). Nos kickoffs,
PO, Arquiteto, Dev Lead e UX Designer mudaram; o Criativo mudou nas refs do
product_brief e no guardrail de zero regra; o Staff não tem kickoff (ADR 0088).

**O que esta regra NÃO fecha:** o texto que a ferramenta devolveu não estava no
log — fechado pela [RN-589](#rn-589), daqui em diante (sessão antiga continua sem).
`InfraLeadServer` (que reidrata por `Reidratacao.historico/3` desde a AT-150,
sem cópia própria) e `DevLeadTools.run_assessment/2` (que lê a CAUDA, `latest`
com o mesmo teto de 200) também passam pelo caminho comum; nenhum leitor de
`list_events/2` sem `latest` sobra em `apps/engine/lib`. A reidratação pode trazer MAIS do que o
contexto vivo tinha (a cauda inteira, mesmo o que já tinha sido compactado); o
`ContextManager` compacta de novo no próximo turno.

- **Código:** `apps/engine/lib/engine/agents/reidratacao.ex:71` (`historico/3`),
  `:46` (o teto), `:104` (`eventos_do_tipo/3`), `:148` (`mensagens/2`), `:167`
  (pergunta estruturada), `:170` (ferramenta), `:271` (omitidos por
  subtração), `:274` (o resumo do começo), `:294` (a compactação), `:328` (a
  abertura); `apps/engine/lib/engine/harness/context_manager.ex:138` (o resumo
  gravado); `apps/engine/lib/engine/sessions/engine_api_client.ex:1077`

  gravado); `apps/engine/lib/engine/sessions/engine_api_client.ex:1261`
  (`list_events/3`); os seis `init/1` —
  `apps/engine/lib/engine/agents/criativo_server.ex:89`, `po_server.ex:93`,
  `arquiteto_server.ex:87`, `dev_lead_server.ex:132`, `ux_designer_server.ex:85`,
  `staff_server.ex:86`; as leituras por tipo — `criativo_server.ex:435`,
  `po_server.ex:352`, `arquiteto_server.ex:313`, `dev_lead_server.ex:431`,
  `ux_designer_server.ex:246`;
  `apps/api/src/interfaces/http/internal/leitura-interna-de-eventos.ts:24`,
  `apps/api/src/interfaces/http/internal/internal-sessions.controller.ts:306`,
  `apps/api/src/infrastructure/persistence/drizzle/session-event.repository.ts:56`
- **Teste:** `apps/engine/test/engine/agents/reidratacao_test.exs:57` (pergunta
  estruturada), `:92` (a resposta entra UMA vez), `:108` (ferramenta com
  desfecho), `:128` (sem `tool.result`), `:136` (ferramenta de outro agente
  fica de fora), `:157` (pede a cauda com teto 200), `:176` (o fim entra, o
  começo vira resumo com o número), `:194` (o resumo da compactação), `:233`
  (compactação antiga declarada), `:248` (histórico ilegível — caso de falha),
  `:255` (abertura falhando não apaga o número), `:270` (leitura por tipo e o
  aviso de teto); `apps/engine/test/engine/agents/reidratacao_dos_seis_test.exs:59`
  (os seis `init/1`), `:84` (o brief depois do evento 200 chega ao PO), `:118`
  (a regra depois do evento 200 entra no brief do Criativo), `:135` (Arquiteto,
  Dev Lead e UX leem por tipo); `apps/engine/test/engine/harness/context_manager_test.exs:74`
  (o resumo gravado), `:101` (fallback do sumarizador);
  `apps/api/test/interfaces/http/internal/leitura-interna-de-eventos.spec.ts:13`
  (sem os parâmetros, as opções de antes), `:40` (tipo malformado é 400);
  `apps/api/test/infrastructure/persistence/session-event-latest.repository.spec.ts:129`
  (`types` filtra e o `limit` conta só eles), `:143` (`types` com `latest`)
- **Origem:** AT-073, levantada em 2026-09-13

## O repositório nasce no aceite do handoff ao Arquiteto, e a execução não começa sem ele (RN-582)

<a id="rn-584"></a>

### RN-584 — A mensagem de chat não tem destinatário padrão: cada agente que conversa tem cláusula própria, e o resto é recusa nomeada {#rn-584}

A última cláusula de `EngineWeb.AgentCommandController.message/2` não olhava o
agente: casava QUALQUER nome que as cláusulas de cima não tivessem pegado e
entregava a mensagem ao **Criativo**. Uma mensagem escrita para o `infra` era
lida por outro agente, o clique respondia 202, e o Criativo respondia no fio —
nada quebrava, e ninguém via. Achado como adjacência da
[RN-578](#rn-578) (AT-089) e corrigido aqui (AT-098).

**A medição, antes do conserto** (os três lados, na `dev` de `72ee8cdcf`):

| Destino | A tela oferece? | A api aceita? | O engine tinha cláusula? |
|---|---|---|---|
| `criativo` | sim (composer: fallback da sessão criativa e `AGENTES_DE_CHAT`) | sim | NÃO — era a cláusula final, sem guarda |
| `po`, `arquiteto`, `dev-lead`, `ux-designer`, `staff` | sim (`AGENTES_DE_CHAT`, o `agent.activated` mais recente) | sim | sim, uma cada |
| `infra` | não no composer (fora de `AGENTES_DE_CHAT` desde o achado 9-fix e a [RN-499](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-499)) | sim | não — caía no Criativo |
| qualquer outro nome do roster (`qa`, subagentes, `secops`, `psicologo`…) | só pelo formulário de perguntas estruturadas, que responde ao ATOR que perguntou (`agent={event.actor.id}`); hoje só Criativo e PO perguntam | sim | não — caía no Criativo |
| nome desconhecido, ou nenhum | não | sim (a api não valida o `agent`; só o `sessionId` vira segmento de URL checado, RN-128) | não — caía no Criativo |

**A regra:**

1. **Cada agente que conversa tem cláusula PRÓPRIA**, o Criativo inclusive
   (`"agent" => "criativo"`). A cláusula final deixou de existir como
   entrega: ela é RECUSA.
2. **Nome sem cláusula é 422 NOMEADO**, `{error, motivo}` no molde da
   [RN-578](#rn-578): `agente_sem_conversa`, com uma frase que nomeia o agente
   e diz que a mensagem ficou registrada e nenhum agente a leu. A api repassa
   422 como `UnprocessableEntityException` com a MESMA frase (o
   `postComandoDeTurno` da RN-578, sem código novo), e a tela a mostra pelo
   `mensagemDaRecusaDoAgente` que já existia. Sem `"agent"` no corpo é
   `agente_ausente`, e agente que conversa sem texto é `mensagem_sem_texto` —
   três motivos, porque "não conversa" dito a quem conversa seria mentira.
3. **O `infra` tem recusa PRÓPRIA**, com frase que diz o que ele faz: trabalha
   por proposta (a PR de infra, a subida do container), e o que pede decisão
   aparece em Aprovações. Não é falta de código, é a mesma leitura da
   [RN-499](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-499) — o Infra Lead é propositivo. E o `user_message/2` que o
   `InfraLeadServer` ainda exporta **não serve** para uma cláusula: ele roda o
   turno INTEIRO dentro do `handle_call` (até 180 s), sem o aceite do ADR 0163
   e sem "Parar" (`via_for/2` não o conhece). Ligá-lo devolveria ao clique a
   espera que a [RN-578](#rn-578) tirou.
4. **O "Parar" também não adivinha.** `cancel/2` sem `"agent"` parava o turno
   do Criativo; passa a ser 422 `agente_ausente`. A api sempre manda o agente
   nas duas rotas, então essas duas recusas só alcançam chamador quebrado.
5. **A tela continua não oferecendo o `infra` no composer** — nenhuma mudança
   de UI: `AGENTES_DE_CHAT` já o excluía, e o que mudou é que, se um dia
   alguém o puser lá, o engine recusa com nome em vez de entregar a outro, e a
   guarda do CI reprova antes.

> **Desde a [RN-617](#rn-617) (ADR 0175), os itens 3 e 5 não valem mais:** o
> turno do Infra Lead migrou para o `TurnoAssincrono`, e só então ele ganhou
> cláusula própria de `message/2`, o `via_for/2` do "Parar" e o lugar em
> `AGENTES_DE_CHAT`. A recusa `agente_sem_conversa` dele saiu; a regra de
> fundo desta RN — nenhum destinatário padrão, todo nome sem cláusula recusado
> com nome — é a mesma.

**A guarda que fecha a classe** mora em
`scripts/ci/destinos-do-composer.spec.ts`, porque o destino nasce em
TypeScript e a cláusula mora em Elixir — nenhuma das duas suítes lê a outra
linguagem. Ela DERIVA os destinos da fonte (`AGENTES_DE_CHAT`, os literais
`agentParaEnviar = '…'` do `SessionPage.tsx` e o `AgentKey` do roster) e exige:
cláusula própria que conversa e `via_for/2` do "Parar" para cada destino do
composer; nenhuma cláusula sem agente fixo na cabeça que entregue a um agente;
a última cláusula de `message/2` sendo recusa; o `infra` fora do composer e
com recusa própria; e `@agentes_de_conversa` igual ao conjunto das cláusulas
que conversam. Cinco mutações medidas, todas mortas (o catch-all antigo de
volta, `infra` em `AGENTES_DE_CHAT`, a cláusula do Criativo renomeada, o
`via_for` do Staff removido, a cláusula do `infra` renomeada).

**O que esta regra NÃO fecha, declarado:**

- **Se o Infra Lead passa a conversar pelo composer era decisão de produto, sem
  dono** — tomada na [RN-617](#rn-617) (AT-141): sim. Dar a ele uma cláusula exige, antes, migrar o turno dele para o
  `TurnoAssincrono` (o aceite e a recusa `turno_em_andamento` da
  [RN-578](#rn-578)) e registrá-lo no "Parar"; e exige decidir o que uma
  conversa faz com um agente cujo contrato é propor. O `user_message/2` dele
  segue exportado e sem chamador.
- **O `chat.message` gravado pela api antes da recusa continua no log** — e
  desde a [RN-587](#rn-587) o engine grava o `agent.error` da recusa ao lado,
  então o fio explica a si mesmo.
- **A api não valida o `agent`.** Recusar lá, antes de gravar, exigiria uma
  segunda lista de quem conversa do lado TypeScript — e divergir dela das
  cláusulas é o defeito que esta regra fecha. Quem decide é quem tem as
  cláusulas (decisão mantida na [RN-587](#rn-587)).

- **Código:**
  `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:42`
  (`@agentes_de_conversa`), `:177` (a cláusula do Criativo), `:192` (a recusa
  do `infra`), `:283` (`mensagem_sem_texto`), `:249` (`agente_sem_conversa`),
  `:312` (`agente_ausente`), `:310` (o "Parar" sem agente);
  `apps/api/src/interfaces/http/agents/agents.controller.ts:115` e `:174`
  (a resposta 422 documentada); `apps/web/src/lib/session-readiness.ts:37`
  (`AGENTES_DE_CHAT`, a fonte que a guarda lê)
- **Teste:** `scripts/ci/destinos-do-composer.spec.ts` (a guarda da classe);
  `apps/engine/test/engine_web/controllers/agent_command_controller_test.exs:124`
  (caminho feliz: o Criativo pela cláusula própria), `:231` (o `infra`: 422 e
  nenhum dos dois sobe — caso de falha), `:258` (todo nome do catálogo de
  áreas e do roster fora de conversa), `:286`, `:302`, `:317`;
  `apps/api/test/infrastructure/http-clients/api-to-engine-client.spec.ts:575`
  (o destino viaja como escolhido, e o 422 chega com a frase)
- **Origem:** AT-098 — adjacência medida no PR #594 (AT-089)

<a id="rn-585"></a>

### RN-585 — O fim do turno só fica visível depois de o turno fechar no agente {#rn-585}

Desde o [ADR 0163](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0163-o-clique-responde-ao-aceitar.md)
([RN-578](#rn-578)) o turno dos seis conversacionais roda numa Task, e o
desfecho que a Task grava — `agent.response`, ou `agent.error` quando a api
narra orçamento, credencial ou binding no frame final — sai ANTES de o
resultado chegar ao GenServer do agente e zerar `turno_assincrono`. Um teste
que lia o state logo depois do `agent.error` reprovava em ~1 de 4 rodadas
(AT-099: 8 de 30 medidas). A pergunta era se a MESMA janela existia para
o usuário: a tela via o turno acabar e a mensagem seguinte ouvia 409
`turno_em_andamento`?

Não existe, e a regra é o que faz ela não existir:

1. **Os dois sinais de fim de turno saem só de `finalizar/1`**, que roda no
   processo do GenServer, dentro do `handle_info` que JÁ zerou
   `turno_assincrono`: `agent.done` no canal e `agent.status: idle`
   persistido. São os dois, e só eles, que a tela usa para fechar o turno
   (`onAgentDone` e `turnoTerminouNoLog`, [RN-578](#rn-578) item 4).
2. **A mensagem de quem viu um desses sinais é atendida depois desse
   `handle_info`** — o GenServer atende uma mensagem por vez —, então encontra
   o agente livre e é aceita.
3. **O que a Task grava não é sinal de fim.** `agent.response` e `agent.error`
   aparecem no fio com o turno ainda aberto no agente. Tela ou cliente que
   passasse a fechar o turno por eles reabriria a janela; emitir `agent.done`
   ou `idle` de dentro da Task também.

Não houve mudança de comportamento: a ordem já era esta desde a RN-578. O que
esta RN acrescenta é a ordem ESCRITA e travada por teste nos seis
conversacionais — o teste para o GenServer com a Task terminada e prova que
nenhum dos dois sinais saiu, sem timeout — e a correção do teste do PO, que
passa a esperar o `idle` persistido em vez do `agent.error`.

- **Código:** `apps/engine/lib/engine/agents/turno_assincrono.ex:158` (zera o
  turno no `handle_info`), `:495` (`finalizar/1`, único emissor dos dois
  sinais); `apps/web/src/lib/session-turno.ts:30` (`turnoTerminouNoLog`)
- **Teste:** `apps/engine/test/engine/agents/turno_assincrono_test.exs:434`
  (os seis conversacionais: com o GenServer suspenso e a Task terminada, o
  `agent.response` já está no log e nem `agent.done` nem `idle` saíram; depois
  do `idle`, a mensagem seguinte é aceita — o caso de falha é a recusa
  `turno_em_andamento`, que o teste nega);
  `apps/engine/test/engine/agents/po_server_test.exs:478` (espera o `idle`
  antes de ler o state)
- **Origem:** AT-099 — teste intermitente do `PoServerTest`, medido em
  2026-09-19

<a id="rn-586"></a>

### RN-586 — O turno que o reinício do engine interrompeu fecha com desfecho durável, e nunca é refeito {#rn-586}

Desde a [RN-578](#rn-578) o `agent.status: working` é gravado ANTES do aceite, e
o fim do turno (`agent.status: idle` e `agent.done`) só sai de `finalizar/1`,
dentro do processo do agente ([RN-585](#rn-585)). Se o engine cai no meio do
turno, o processo e a Task morrem juntos e ninguém grava o fim: o último
`agent.status` do agente fica `working` **para sempre** (AT-156, reproduzido —
subir o servidor de novo sobre esse log não gravava nada, nos seis). Os dois
leitores desse sinal o tomam por turno em curso: a tela (`turnoTerminouNoLog`,
[RN-578](#rn-578) item 4) mantém a faixa de atividade, e o
`GetSessionPendingWorkUseCase` conta trabalho pendente SEM teto (o terceiro
sinal da [RN-064](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-064)), então a sessão não fecha por heartbeat. Só a
próxima mensagem do usuário destravava, e só porque ela sobe o agente.

1. **O `working` que ficou sem turno vivo é fechado por evento NOVO**, nunca
   reescrito (evento é imutável): um `agent.error` com origem `infra` e
   `reason: turno_interrompido_por_reinicio` — a frase diz que o engine foi
   reiniciado, que o turno não foi concluído e que quem decide tentar de novo é
   o usuário ([RN-059](parte-01.md#rn-059): falha nunca vira
   resposta vazia) — seguido de `agent.status: idle` persistido. O canal recebe
   `agent.error` e `agent.done`, para a faixa de quem está com a tela aberta
   sair sem recarregar. Vale para os que compartilham `TurnoAssincrono` — seis
   na origem, sete desde a [RN-617](#rn-617).
2. **O turno NUNCA é reexecutado.** Refazê-lo gastaria token em nome de uma
   mensagem que o usuário talvez já tenha esquecido, sobre um histórico
   reconstruído; nenhuma chamada ao modelo acontece no fechamento.
3. **Só o ÚLTIMO `agent.status` de cada agente conta**, e só `working`:
   `idle` já está fechado, e `awaiting_approval` (Dev Lead suspenso,
   [RN-284](parte-01.md#rn-284)) é decisão pendente, não turno morto.
4. **"Sem turno vivo" olha o cluster, e na dúvida não fecha.** O registro dos
   agentes é local; num rollout o pod antigo pode estar rodando o turno, e
   fechá-lo dali mataria um turno saudável. Nó que não responde conta como vivo.
   O repasse de sessão do drain ([RN-588](#rn-588), `Monitor.expect_handoff/1`)
   é do `SessionServer`, não dos conversacionais: enquanto o pod antigo está de
   pé o agente dele segue registrado lá, e a varredura do pod novo o enxerga;
   o `Adopter` não varre — quem chega ao `working` órfão depois que o pod antigo
   morre é o `init/1` do agente.
5. **Dois pontos de entrada, uma função** (`Engine.Agents.TurnoOrfao`): a
   varredura de boot em cada sessão reidratada (`Rehydrator`, fora do caminho do
   readiness — o boot não espera a api), que fecha o turno mesmo que ninguém
   mande mensagem, e o `init/1` de cada servidor, rede de segurança para quando
   o boot não conseguiu escrever (api ainda fora do ar). Falha de leitura ou de
   escrita é logada e o agente sobe.

Declarado e não fechado: ~~o Infra Lead (`infra`) roda o turno dentro do
`handle_call`, sem `TurnoAssincrono`, e fica de fora~~ — fechado na
[RN-617](#rn-617), que o pôs no `TurnoAssincrono` e em `TurnoOrfao`; a janela de leitura é a
das 200 mais recentes `agent.status` da sessão; se a api estiver fora no boot E
ninguém acordar o agente, o `working` fica até a próxima subida dele; e o
fechamento não recupera o que o turno já tinha gravado antes da queda.

- **Código:** `apps/engine/lib/engine/agents/turno_orfao.ex:89` (`varrer/2`),
  `:99` (`fechar_ao_subir/3`), `:122` (`encerrar/3`);
  `apps/engine/lib/engine/sessions/rehydrator.ex:75` (varredura no boot); o
  `init/1` dos seis `*_server.ex` chama `TurnoOrfao.fechar_ao_subir/3`
- **Teste:** `apps/engine/test/engine/agents/turno_orfao_test.exs:72` (nos seis:
  o `working` sem turno vivo vira `agent.error` `infra` + `idle`, e o LLM não é
  chamado), `:108` (`awaiting_approval` não é órfão; `idle` e o `working` de
  outro agente não são fechados), `:124` (`varrer/2` pula o agente com processo
  vivo em ESTE nó ou num nó `:peer` de verdade do cluster; leitura e escrita
  que falham não derrubam a subida);
  `apps/engine/test/engine/sessions/rehydration_test.exs:46` (o boot dispara a
  varredura)
- **Origem:** AT-156, herdada da AT-089 (RN-578) — reproduzida em 2026-09-19

**Revisada pela [RN-920](parte-06.md#rn-920) ([ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md)).** O item 2 ("o turno NUNCA é reexecutado") deixou de valer para o turno recente: a varredura de boot o retoma UMA vez, se a última atividade do agente tem até 900 s, com a mensagem efêmera do diário; o turno velho ou já retomado continua só fechado, e o botão "Retomar" ([RN-921](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-921)) é o caminho humano. Os itens 1, 3, 4 e 5 seguem.

<a id="rn-587"></a>

### RN-587 — A mensagem que nenhum agente leu fica no fio dizendo isso: o engine grava o `agent.error` da recusa {#rn-587}

A api grava o `chat.message` ANTES de perguntar ao engine (o engine reconstrói a
conversa lendo o log, e a mensagem precisa ser durável mesmo com ele fora do
ar). Quando o engine recusava, a mensagem ficava no fio do usuário com cara de
entregue e o motivo morava só no toast — a tela afirmando o que a fonte negou.
As duas RNs de origem deixaram isso declarado ([RN-578](#rn-578), [RN-584](#rn-584));
esta o fecha (AT-132).

**A medição, antes do conserto**, por recusa:

| Recusa | Quem a produz | `agent.error` durável ao lado do `chat.message`? |
|---|---|---|
| 409 `turno_em_andamento` | `TurnoAssincrono` (RN-578) | JÁ SIM — `emitir_recusa_por_turno_em_andamento/1`, com teste |
| 409 `aguardando_aprovacao` | `DevLeadServer.handle_call` (RN-578) | JÁ SIM — `reason: "aguardando_aprovacao_de_plano"` |
| 422 `agente_sem_conversa`, `mensagem_sem_texto`, `agente_ausente` | o controller (RN-584), sem `*Server` | NÃO — a explicação vivia só no toast |

**A regra:**

1. **O engine é a fonte da recusa E do registro.** As três recusas 422 gravam
   `agent.error` (origem `politica`, `mensagem` igual à frase do 422,
   `reason` igual ao `motivo`) e o transmitem no canal da sessão — o mesmo par
   durável/efêmero das duas 409. O fio já desenha `agent.error`
   (`SessionPage.tsx`, `lerFalhaDeTurno`), então nenhuma tela mudou.
2. **Só há o que gravar com sessão nomeada.** Sem `projectId`/`sessionId` no
   corpo (chamador quebrado) a recusa segue só como resposta.
3. **O ator não vem da rota.** `infra` e os seis que conversam entram como
   `agent`; qualquer outro nome (que a rota pública deixa passar) é o `system`
   `engine` — um nome digitado nunca vira ator no log.
4. **Não se apaga nem se adia o `chat.message`.** Evento é imutável, e gravá-lo
   só depois do aceite reordenaria o log: o turno roda numa Task e o
   `agent.response` poderia preceder a mensagem que responde (e uma falha entre
   o aceite e o append rodaria um turno sobre mensagem não gravada).

**A api continua sem validar `agent`, e agora isso é decisão e não lacuna.** A
validação que a AT-098 pedia é a recusa 422 do engine, e ela é o mecanismo
ÚNICO: a api a repassa (`postComandoDeTurno`) e o engine a registra. Uma lista
do lado TypeScript seria a segunda cópia que diverge no primeiro agente novo, e
uma lista GERADA a partir das cláusulas exigiria parsear Elixir — sem ganho
para o usuário, que já vê a mensagem e a explicação no fio.

- **Código:** `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:573`
  (`recusar_mensagem/5`) e `:574` (`registrar_recusa_de_mensagem/3`)
- **Teste:** `apps/engine/test/engine_web/controllers/agent_command_controller_test.exs:215`
  (`qa`, o agente do roster que segue sem conversa — até a RN-617 o caso era o
  `infra`, que passou a conversar: o `agent.error` com a frase e o motivo), `:178` (nome desconhecido
  não vira ator), `:194`, `:209`, `:224` (sem sessão: nada gravado — caso de
  falha); mutação medida: com o registro removido, 4 dos 5 falham;
  `scripts/ci/destinos-do-composer.spec.ts` (a recusa de `message/2` é
  `recusar_mensagem/5` e ela grava o `agent.error`; seis mutações mortas)
- **Origem:** AT-132 — declarado aberto nas RN-578 (AT-089) e RN-584 (AT-098)

<a id="rn-588"></a>

### RN-588 — Repassar uma sessão não deixa o pod antigo apagar a linha do par {#rn-588}

No rollout, o drain do pod antigo para o `SessionServer` e pede a um par que
assuma a sessão (`Engine.Shutdown`); o `init` do par regrava a linha de
`engine.session_states`. O `:DOWN` do processo parado, porém, chega ao
`Engine.Sessions.Monitor` do pod antigo por mensagem — e o Monitor é um
GenServer único, que serializa o `:DOWN` de cada sessão com um DELETE por ida
ao banco, sem esperar pelo repasse seguinte. Quando o `:DOWN` era processado
DEPOIS do upsert do par, o `DELETE ... WHERE session_id` — que não olha dono
nem geração — levava a linha DO PAR: a sessão ficava com dono e sem linha,
invisível ao `Adopter`, ao `Rehydrator` e ao `local_sessions/0` do drain do
par. Se o par era OUTRO pod antigo (`.33 → .28 → novo`), ele não a via ao
drenar, e o SIGTERM dele a matava: `active` na api e sem dono (AT-078, o
`rollout-test` do `propriedades.yml`, ~3 órfãs em 13 rodadas).

A regra: o drain marca o stop com `Monitor.expect_handoff/1` (o
`expect_stop/1` de sempre MAIS "a linha não é minha"), e o Monitor NÃO apaga a
linha de uma sessão repassada — registra em `Logger.info` que a manteve. Sem
adoção, quem apaga é o próprio drain (`terminate_unadopted`), como já era; o
Monitor continua apagando a linha de toda sessão que morre por outra causa e a
do `expect_stop/1` do `SessionLifecycleWorker` (a api já encerrou a sessão).
Sem migration: a linha não ganhou coluna de dono, e a marca vive no estado do
Monitor, por sessão. Toda apagada do Monitor passou a deixar UMA linha de log
com sessão, nó e linhas removidas — o log da drenagem nunca chega ao log do
pod (o `preStop` o descarta), o do Monitor chega.

**Inferência que fica:** o instante em que a linha sumiu nunca foi medido no
k3d; a leitura vem do artefato da rodada `35452845830` (sem linha + segundo pod
antigo) e do código, e a corrida foi provada em ExUnit, não observada. A
próxima falha do k3d, se houver, traz a linha do Monitor.

- **Código:** `apps/engine/lib/engine/sessions/monitor.ex:45`
  (`expect_handoff/1`), `:119` (`apagar_linha/1`);
  `apps/engine/lib/engine/shutdown.ex:130` (`release/1`, o drain marca o repasse)
- **Teste:** `apps/engine/test/engine/sessions/monitor_repasse_test.exs:52`
  (Monitor suspenso: o `:DOWN` tardio não apaga a linha regravada pelo par),
  `:67` (cadeia antigo → antigo → novo: o segundo drain ainda vê a sessão),
  `:87` (sem adoção a linha continua saindo pelo drain), `:100`
  (`Shutdown.release/1` marca o repasse — trocar a chamada de volta por
  `expect_stop/1` reprova SÓ este teste)
- **Origem:** AT-078 — sessão órfã intermitente do rollout do engine

<a id="rn-589"></a>

### RN-589 — O texto que a ferramenta devolveu entra no `tool.result`, cortado com o total dito {#rn-589}

A RN-580 declarou aberto: só o Criativo gravava `tool.result`, e sem o texto —
nos outros cinco a nota da reidratação dizia que o log não registra o
desfecho, e o agente reidratado sabia QUE chamou `create_epic`, não o id do
épico que ela respondeu.

**A regra:**

1. **Os seis gravam.** Criativo, PO, Arquiteto, Dev Lead, UX Designer e Staff
   emitem `tool.result` depois de TODA chamada que devolve texto. O payload sai
   de UM lugar, `Engine.Agents.ResultadoDeFerramenta.payload/2`: `tool`, `ok`
   e — no sucesso — `resultado`; na falha, `erro` (como o Criativo já fazia).
2. **Com teto, e o teto diz o total.** O texto é cortado em 2.000 caracteres;
   quando corta, `resultadoTotal` traz o tamanho REAL (ADR 0060). O motivo do
   teto: o log é lido por todo membro do projeto e entra no backup, e uma
   listagem (`listar_backlog`) pode ser grande.
3. **Aditivo.** Campo novo em tipo existente, sem migration; `tool`/`ok`/`erro`
   seguem como eram. Evento é imutável: sessão anterior continua sem o texto, e
   a nota da reidratação segue dizendo isso para a chamada sem `tool.result`.
4. **A reidratação usa o texto.** `desfecho: ok, devolveu: <texto>` (com aviso
   `[cortado; o total real tinha N caracteres]` quando houver `resultadoTotal`).
   Continua nota de texto, nunca `role: tool` — o evento não guarda o id da
   chamada.
5. `propose_adr` deixou de gravar o próprio `tool.result` de recusa: o servidor
   do Arquiteto o grava para toda ferramenta, e os dois duplicariam o evento.

**O que fica aberto:** (a) e (b) fecharam na [RN-593](#rn-593) — (a) o Dev
Lead que SUSPENDE (`{:pending, _}`,
`propose_execution_plan`/`assess_implementability`) não gravava `tool.result` na
suspensão nem no `action_settled`; (b) o `InfraLeadServer` tinha o próprio
`tool.result` e não passava por este módulo; (c) o teto de 2.000 é ESCOLHA, não medida sobre o
acervo — nenhum resultado real foi amostrado; (d) **decisão de produto
pendente (TODO humano da AT-151):** as ferramentas dos seis devolvem ids,
listas de regras/backlog/métricas e mensagens de erro — nenhuma lê arquivo do
repositório nem saída de comando —, mas se uma ferramenta assim nascer, ela
gravaria conteúdo dele no log; o corte é a única contenção.

- **Código:** `apps/engine/lib/engine/agents/resultado_de_ferramenta.ex:24`
  (`payload/2`), `criativo_server.ex:382`, `po_server.ex:259`,
  `arquiteto_server.ex:336`, `dev_lead_server.ex:407`,
  `ux_designer_server.ex:232`, `staff_server.ex:198`;
  `apps/engine/lib/engine/agents/reidratacao.ex:244` (`desfecho/1`)
- **Teste:** `apps/engine/test/engine/agents/reidratacao_test.exs:128` (texto e
  aviso de corte na nota; `:145` sessão antiga sem `tool.result`),
  `apps/engine/test/engine/agents/po_server_test.exs:252` (o evento gravado,
  cortado, com `resultadoTotal`)
- **Origem:** AT-151 — declarado aberto na RN-580 (AT-073)

<a id="rn-593"></a>

### RN-593 — O Dev Lead suspenso e o Infra Lead gravam o `tool.result` pelo módulo comum {#rn-593}

A [RN-589](#rn-589) declarou dois abertos: o Dev Lead que suspende numa
aprovação não gravava `tool.result` em momento nenhum, e o `InfraLeadServer` só
gravava o de recusa de `propose_infra_pr`, com payload montado à mão. Nos dois
casos o agente reidratado ([RN-580](#rn-580)) lia "o log não registra o
desfecho desta chamada" sobre um plano que o usuário já tinha decidido, ou sobre
toda chamada de `validate_infra_file` e de subida de container.

**A regra:**

1. **Dev Lead: o `tool.result` nasce na RETOMADA, nunca na suspensão.** Quando
   `propose_execution_plan`/`assess_implementability` suspende
   (`{:pending, _}`), o log fica só com o `tool.call`: não há desfecho, e
   gravar "pending" ali seria a mesma mentira que seria para o modelo. Quando o
   `{:action_settled, …}` da MESMA ação chega, o servidor grava o `tool.result`
   com o MESMO texto que entra na mensagem `role: "tool"`. `ok` segue a
   partição de `texto_do_desfecho/1`: `executed`/`auto_approved`/`approved`
   são `true`; recusa, falha e status que o módulo não conhece são `false` —
   `ok: true` sobre desfecho que ninguém classificou seria afirmar sucesso sem
   saber. Desfecho de OUTRA ação continua ignorado e não grava nada.
2. **Infra Lead: toda ferramenta despachada inline grava.**
   `validate_infra_file`, `propose_container_start` e
   `container_start_via_runner` gravam `tool.result` por
   `Engine.Agents.ResultadoDeFerramenta.payload/2` — proposta aceita pela api é
   `ok: true`; recusa local por modo ([RN-566](parte-02.md#rn-566)), recusa da api
   ([RN-591](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-591)) e runner ausente são `ok: false` com o motivo. A recusa
   de `propose_infra_pr` sem repositório ([RN-577](#rn-577)) passa pelo mesmo
   módulo, com o payload de antes (`tool`, `ok: false`, `erro`) e o corte.
3. **`propose_infra_pr` aceita segue SEM `tool.result`**, de propósito: ela não
   emite `tool.call` (o rastro dela é a `proposed_action`), e um resultado sem
   chamada viraria nota órfã na reidratação.

**O que segue aberto:** a suspensão atravessada por um restart do engine
continua perdendo a inscrição no `Wake` (ADR 0086) — ali o `tool.result` nunca
nasce, e a reidratação diz que o log não tem o desfecho, o que é verdade; o
teto de 2.000 caracteres continua ESCOLHA, não medida: nenhum acervo real foi
amostrado nesta mudança (o item (c) da [RN-589](#rn-589)); a saída do
`validate_infra_file` (hadolint/actionlint) pode citar trechos do arquivo que o
PRÓPRIO agente escreveu, e o corte é a única contenção — é o item (d) da
[RN-589](#rn-589) com o primeiro caso concreto.

- **Código:** `apps/engine/lib/engine/agents/dev_lead_server.ex:377`
  (`handle_info/2` do `action_settled`, o `tool.result` em `:271`), `:856`
  (`sentido_do_desfecho/1`);
  `apps/engine/lib/engine/infra/infra_lead_server.ex:1120`
  (`registrar_resultado/4`), `:317` (a recusa de `propose_infra_pr`)
- **Teste:** `apps/engine/test/engine/agents/dev_lead_server_test.exs:292` (a
  suspensão não grava), `:364` (a retomada grava o texto que o modelo leu),
  `:488` (recusado é `ok: false` com o motivo);
  `apps/engine/test/engine/infra/infra_lead_server_test.exs:253`
  (o desfecho de `validate_infra_file`), `:409` (proposta aceita), `:485` (recusa por modo),
  `:863` e `:914` (`container_start_via_runner` com e sem runner)
- **Origem:** AT-190 — declarado aberto na [RN-589](#rn-589) (AT-151)

<a id="rn-601"></a>

### RN-601 — O engine e o broker aplicam aos dois tokens de serviço a régua da api {#rn-601}

Os três processos que comparam o token de serviço usam a mesma régua da
[RN-598](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-598), cada um na sua linguagem. O espaço em volta é descartado, e
um valor feito só de espaço conta como ausente. Em produção,
`BRABO_SERVICE_TOKEN` ausente, o literal público de desenvolvimento
(`dev-service-token-change-me`) ou um valor com menos de 16 caracteres depois
do trim DERRUBAM o boot, com uma mensagem que nomeia a variável. As duas
últimas recusas valem também para `BRABO_SERVICE_TOKEN_PREVIOUS` quando ele
está definido. Um anterior igual ao atual não conta como rotação. Fora de
produção só o trim se aplica, e o atual vazio cai no default de dev.

Antes, o engine lia os dois crus em `config/runtime.exs`: sem trim, sem piso,
e em produção subia com o default público quando a variável faltava (e com a
string vazia quando o compose a passava vazia). Só a api recusar subir
protegia a instalação. O broker já aplicava a régua ao atual, mas ao anterior
só o trim.

Duas divergências de forma, declaradas. No engine, "produção" é
`config_env() == :prod` (a release), e não `NODE_ENV`, que ele não lê; a
imagem de produção é sempre uma release `:prod`. E a régua fica inline no
`runtime.exs`, e não num módulo de `lib/`, porque numa release esse arquivo
roda num config provider antes de o código da aplicação estar carregado.

Consequência: todo processo que avalia esse `runtime.exs` numa release
`:prod` precisa do token, inclusive a migração (`bin/engine eval
Engine.Release.migrate()`). Por isso o serviço `migrate-engine` dos composes de
produção e de instalação passou a receber `BRABO_SERVICE_TOKEN` e
`BRABO_SERVICE_TOKEN_PREVIOUS`, sem default. O smoke de CI mostrou isso: sem
eles, a migração morria antes de migrar. O Job de migração do Kubernetes já os
recebia pelo `envFrom` de `brabo-secrets`.

- **Onde:** `apps/engine/config/runtime.exs:85`
  (`exigir_token_de_servico_de_producao`), `:105` (`service_token`), `:121`
  (`service_token_previous`); `apps/broker/src/config.ts:89` (`anterior`),
  `:125` (`exigirTokenDeProducao`)
- **Teste:** `apps/engine/test/engine/runtime_service_token_test.exs` (avalia o
  `runtime.exs` de verdade por `Config.Reader.read!/2`, com `env: :prod` e
  `:dev`); `apps/broker/src/config.spec.ts` (describe "lerConfiguracao —
  produção, o token ANTERIOR (RN-601)")
- **Borda:** a régua é copiada nos três processos, não compartilhada: são três
  linguagens ou runtimes, e nenhum teste confere que as três cópias continuam
  iguais. O piso conta caracteres (`String.length` no Elixir, `.length` no TS),
  o que só difere para token fora do ASCII.
- **Origem:** AT-216 (achado da AT-205)

<a id="rn-610"></a>

### RN-610 — O Infra Lead recusa a subida por ESTADO, na ordem da `/containers`: já de pé, sem imagem, pasta nunca confirmada {#rn-610}

A [RN-566](parte-02.md#rn-566) deu às duas tools de subida do Infra Lead a recusa por
MODO e declarou o resto: a `/containers` checa três coisas antes de oferecer o
botão (imagem decidida, modo, pasta confirmada) e o agente checava uma. A
decisão do mantenedor (AT-142, 2026-09-27) foi fechar essa distância por
**recusas locais no despacho**, no molde da RN-566/[RN-577](#rn-577), e NÃO por
contexto enriquecido — `GetInfraContextUseCase` não muda.

`recusa_local_de_subida/2` continua lendo o projeto UMA vez. Primeiro o MODO
(`recusa_por_modo/2`, a régua da RN-566 sem mudança de texto) — é ele que diz
qual tool usar, e responder "falta imagem" a quem chamou a tool errada
apontaria a porta errada. Depois o ESTADO (`recusa_por_estado/3`), uma
cláusula por motivo, na MESMA ordem de `decidirSubida`
(`apps/web/src/routes/containers-subida.ts`), avaliadas só até a primeira
recusa:

| Cláusula | `propose_container_start` | `container_start_via_runner` | Leitura local |
|---|---|---|---|
| container já REGISTRADO `running`/`provisioning` (`ja_esta_de_pe`) | recusa | recusa | `project_containers.status` |
| nenhuma imagem decidida (`sem_imagem_decidida`) | **não** recusa | recusa | existe `artifact.project_image` em alguma sessão do projeto |
| pasta nunca confirmada (`runner_nunca_confirmou`) | — | recusa | `projects.workspace_verified_at` nulo |
| nenhum runner conectado agora | — | recusa (já existia, RN-508) | `Engine.Runners.Registry` |

**Por que `propose_container_start` não recusa por imagem.** Eleger a imagem é
o que essa proposta FAZ ([RN-491](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-491)): exigir decisão antes inverteria a
ordem. A tela checa imagem nos dois modos porque o botão dela não elege nada.
`container_start_via_runner` não elege — sobe a imagem JÁ decidida, e
`ExecuteContainerStartViaRunnerUseCase` falha sem ela —, então ali a cláusula
vale. O predicado é o MESMO da api (`ObterContainerDoProjetoUseCase`):
EXISTÊNCIA do evento, nunca validade do payload, porque a api degrada payload
ilegível para o default em vez de tratá-lo como ausência.

**Por que "já de pé" recusa, se a execução não falharia.**
`SubirCicloDeVidaDoContainerUseCase` é idempotente sobre `provisioning`/
`running`, então a proposta aprovada seria um nada que gastou uma decisão
humana — e em `container`/`mounted` pior que nada: elegeria uma versão nova de
`artifact.project_image` que o container de pé, com a versão congelada na
linha ([RN-245](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-245)), não usaria. Registrado não é observado
([RN-486](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-486)): o texto não afirma que o container está vivo, diz o que
fazer quando ele morreu por fora. `stopped`, `failed` e `removed` não recusam.
Erro de consulta devolve `nil` e cai no caminho de sempre — "não consegui
olhar" nunca vira recusa.

**Os textos, que são o resultado de ferramenta que o modelo lê**
([RN-163](parte-01.md#rn-163)) — nunca `agent.error`, nunca
fim de turno, com `tool.call`/`tool.result` (`ok: false`) no event log pelo
mesmo `registrar_resultado/4` da [RN-593](#rn-593):

- já de pé: *"o container deste projeto já está REGISTRADO como `<status>` —
  subir não é a próxima ação, e `<tool>` não foi proposta. O registro não é
  observação (RN-486): se o container morreu por fora, ou se a imagem precisa
  mudar, diga ao usuário que parar ou remover é pela página `/containers`; só
  depois disso uma nova subida faz sentido. Não repita a chamada agora."*
- sem imagem: *"nenhuma imagem de container foi decidida para este projeto
  (`artifact.project_image`, RN-105) — `container_start_via_runner` sobe a
  imagem JÁ decidida e não elege nenhuma, então aprovada ela só poderia falhar,
  e não foi proposta. Quem decide a imagem é o Arquiteto
  (`choose_project_image`): diga isso ao usuário e não repita a chamada até
  haver decisão."*
- pasta nunca confirmada: *"a pasta deste projeto nunca foi confirmada por um
  agente local (`workspace_verified_at` vazio, RN-423) — nenhum `brabo-runner`
  jamais conectou a ele, e `container_start_via_runner` não foi proposta. Peça
  ao usuário para rodar `brabo-runner --project <id> --dir <pasta>` na máquina
  dele: a confirmação acontece quando o runner conecta."*

Nenhuma linha de prompt mudou, e nenhuma medição com modelo real foi feita
nesta regra: a premissa de que o modelo entende a recusa é a da RN-566.

**O que NENHUMA cláusula checa, declarado:** instalação sem broker (o engine
não lê `BROKER_URL`; quem recusa é a api ao propor, com 409
`sem_broker_na_instalacao`, [RN-591](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-591)) e papel/sessão (o agente não é
quem clica). A cláusula de pasta usa o carimbo, que não é batimento
([RN-468](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-468)) — por isso a de runner conectado continua depois dela.

- **Código:** `apps/engine/lib/engine/infra/infra_lead_server.ex:889`
  (`recusa_local_de_subida`), `:945` (`recusa_por_estado`), `:1025`
  (`recusa_ja_de_pe`), `:1027` (`recusa_sem_imagem_decidida`), `:1028`
  (`recusa_pasta_nunca_confirmada`), `:1029` (`recusa_runner_desconectado`);
  `apps/engine/lib/engine/containers/project_container_lifecycle.ex:83`
  (`status_registrado`);
  `apps/engine/lib/engine/session_events/event.ex:120` (`imagem_decidida?`)
- **Teste:** `apps/engine/test/engine/infra/infra_lead_server_test.exs:742`
  (via runner, `running` recusa), `:808` (`provisioning` recusa), `:818`
  (`stopped` não recusa), `:779` (sem imagem), `:790` (pasta nunca
  confirmada), `:854` (`propose_container_start` com container `running`),
  `:854` (`propose_container_start` sem imagem PROPÕE), `:863` (caminho feliz
  do via runner), `:901` (sem runner conectado)
- **Origem:** AT-142

---

<a id="rn-617"></a>

### RN-617 — O Infra Lead conversa pelo composer, e o turno dele passa pelo `TurnoAssincrono`: aceite imediato, "Parar", turno órfão fechado {#rn-617}

A decisão que a [RN-584](#rn-584) deixou aberta — *"se o Infra Lead passa a
conversar pelo composer"* — foi tomada pelo mantenedor (AT-141, 2026-09-27):
**sim**, e ele vira o SÉTIMO conversacional
([ADR 0175](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0175-infra-lead-conversa-pelo-composer.md)). A condição que a
RN-584 escreveu veio primeiro: o turno dele deixou de rodar DENTRO do
`handle_call`/`handle_cast` e passou pelo MESMO `Engine.Agents.TurnoAssincrono`
dos outros seis; só depois a cláusula de `message/2` nasceu.

**Etapa 1 — o turno.**

1. **Os três turnos do Infra Lead sobem numa Task** — o kickoff (ainda `cast`,
   só no start FRESCO do handoff aceito), a correção de gate (`{:correct, _}`)
   e a mensagem do composer. A mensagem responde ao ACEITE, com o
   `agent.status: working` gravado ANTES ([RN-578](#rn-578)); o desfecho vai
   pelo canal e, quando é falha, pelo `agent.error` durável. O
   `user_message/2` que rodava o turno inline SAIU: o nome ficou e é o aceite.
2. **Segunda mensagem com turno em curso é `409 turno_em_andamento`**, com o
   `agent.error` de origem `politica` no fio — inclusive durante o kickoff,
   que antes prendia a mensagem na fila do processo pelo turno inteiro.
3. **"Parar" alcança o Infra Lead** (`via_for("infra")` no `cancel/2`): mata
   a Task — e com ela o `WorkflowsAgent`, que roda dentro da consolidação —,
   grava `agent.error` `cancelado_pelo_usuario` e devolve `idle`.
4. **A consolidação com o Workflows é parte da função de turno** e devolve o
   `state`; os sinais de fim (`agent.done`, `agent.status: idle`) saem só de
   `TurnoAssincrono`, no processo do servidor ([RN-585](#rn-585)).
5. **A correção de gate que chega com turno em curso entra numa FILA**
   (`correcoes_pendentes`) e sobe no fecho do turno, na ordem de chegada — o
   `TurnoAssincrono` sem `from` DESCARTA o pedido que encontra turno em
   curso, e o gate pediria mudança a ninguém.
6. **O turno órfão do reinício fecha** pela [RN-586](#rn-586): `infra` entrou
   em `TurnoOrfao` (`@agentes`), no boot e no `init/1`.
7. **O histórico vem de `Engine.Agents.Reidratacao`** ([RN-580](#rn-580)),
   como já vinha, e o `tool.result` de `ResultadoDeFerramenta`
   ([RN-593](#rn-593)).
8. **O teto de iterações é o dele, 14** (o mesmo de Arquiteto, Dev Lead, UX
   Designer e Staff), e esgotá-lo passa a emitir `toolloop.limit_reached`
   ([RN-166](parte-01.md#rn-166)) — antes o 14º passo
   terminava calado.

**Etapa 2 — o composer.**

9. **`message/2` tem cláusula PRÓPRIA para `infra`**, e a recusa
   `agente_sem_conversa` dele saiu — um nome, um caminho.
   `@agentes_de_conversa` o inclui; a mensagem a um Infra Lead que não está de
   pé (engine reiniciado) o reergue SEM kickoff, e ele reidrata no `init/1`.
10. **A tela o oferece pela regra de sempre**: `infra` entrou em
    `AGENTES_DE_CHAT`, então ele é o destinatário quando é o `agent.activated`
    mais recente — sem destinatário padrão (RN-584). O aceite do handoff DELE
    continua no card próprio da [RN-499](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-499); o card do fio o exclui por
    NOME (`offeredHandoff`), senão o convite aparecia duas vezes e, sendo o
    mais antigo, voltava a esconder o do Dev Lead ([RN-136](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-136)). A faixa
    de atividade ganhou frase para as quatro ferramentas dele.
11. **Conversar não abre efeito externo.** As ferramentas são as mesmas
    quatro; a PR de infra e as duas subidas de container continuam nascendo
    `proposed_action`, com as recusas locais das [RN-566](parte-02.md#rn-566),
    [RN-577](#rn-577) e [RN-610](#rn-610) intactas.

**O teto de 180 s deixou de importar para o turno.** Ele era menor que os
225 s do `propose_action` de container ([RN-605](https://github.com/viralabs-dev/brabo-contracts/blob/dev/packages/docs/business-rules/contracts.md#rn-605)), e uma mensagem que
levasse o modelo a propor `container_start` podia estourar o `GenServer.call`
com a proposta de pé. Com o aceite imediato, o `GenServer.call` só espera o
aceite; o `propose_action` corre dentro da Task, sem ninguém esperando
síncrono. O 180 000 ficou, igual ao dos outros seis, como teto do ACEITE.

**Não muda, declarado:** `SOLO_CONVERSATIONAL_AGENTS` (gerada por
`pnpm --filter api gerar:areas`) é a lista dos agentes SEM área que o handoff
manual endereça; o Infra Lead é lead de área e continua fora dela, e
`AGENTES_DE_CHAT` não é gerada. O Infra Lead não ganhou perguntas estruturadas
nem leitura de backlog — conversar com ele é conversar com o que o kickoff lhe
deu e com as quatro ferramentas.

- **Código:** `apps/engine/lib/engine/infra/infra_lead_server.ex:187`
  (`user_message`), `:211` (`TurnoOrfao.fechar_ao_subir`), `:248`
  (`handle_cast(:kickoff`), `:270` (`handle_cast({:correct`, a fila), `:280`
  (`handle_cast(:cancel`), `:296` (`handle_call({:user_message`), `:368`
  (`handle_info`), `:373` (`drenar_correcao_pendente`), `:456`
  (`toolloop.limit_reached`), `:1164` (`concluir`);

  (`toolloop.limit_reached`), `:1057` (`concluir`);
  `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:44`
  (`@agentes_de_conversa`), `:192` (a cláusula do `infra`), `:618`
  (`via_for`); `apps/engine/lib/engine/agents/turno_orfao.ex:57` (`@agentes`);
  `apps/web/src/lib/session-readiness.ts:37` (`AGENTES_DE_CHAT`);
  `apps/web/src/lib/session-handoffs.ts:120` (`ofertasAcionaveis`)
- **Teste:** `apps/engine/test/engine/infra/infra_lead_server_test.exs:1033`
  (aceite imediato, `working` antes), `:1048` (409 com turno em curso — caso
  de falha), `:1077` ("Parar"), `:1103` ("Parar" sem turno), `:1107` (a
  correção de gate na fila), `:1792` (`toolloop.limit_reached`);
  `apps/engine/test/engine/agents/turno_orfao_test.exs:76` (o órfão, agora nos
  sete); `apps/engine/test/engine/agents/reidratacao_dos_seis_test.exs:62` (a
  reidratação, nos sete);
  `apps/engine/test/engine_web/controllers/agent_command_controller_test.exs:236`
  (202, 409 e "Parar" pela rota), `:283` (reergue sem kickoff);
  `apps/web/src/routes/SessionPage.cancelar-turno.test.tsx:256` (o composer
  envia ao Infra Lead e o "Parar" é dele);
  `apps/web/src/lib/session-readiness.test.ts:123`;
  `scripts/ci/destinos-do-composer.spec.ts:174` (a guarda: `infra` é destino,
  com UMA cláusula que conversa)
- **Origem:** AT-141 (decisão do mantenedor), aberta pela AT-098

**Revisada pela [RN-924](parte-06.md#rn-924) ([ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md)).** A fila `correcoes_pendentes`, só em memória, passou a ser durável (`infra.correction_queued`/`_delivered`), no molde da fila de mensagens; o turno órfão do Infra Lead segue a retomada da [RN-920](parte-06.md#rn-920).

<a id="rn-621"></a>

### RN-621 — O resumo da compactação mantém o idioma original de cada turno, e não traduz citação nem código {#rn-621}

Quando o contexto de um agente passa do limiar, o `ContextManager` troca os
turnos antigos por UM resumo, escrito por outra chamada de LLM (o ator
`context-manager`) e reinserido como mensagem `system`. O prompt dessa chamada
é pt-BR e não dizia nada sobre idioma: numa conversa em inglês, ou com dois
idiomas, o resumo saía traduzido, e o modelo seguinte lia a própria memória na
língua do prompt de resumo — o desvio de idioma que o épico de idioma persegue,
nascido fora do turno do usuário. A orientação de idioma do turno não protege
isto: ela nunca está em `messages`, então nunca é resumida, mas também nunca é
vista pelo sumarizador.

A regra é uma frase no prompt de resumo, nas DUAS trilhas (o texto inline e o
template versionado `prompts/context-manager-summarize.md`, que sobe para a
versão `"2"`):

> Mantenha cada turno no idioma original; não traduza citações nem código.

1. **O idioma é POR TURNO**, nunca um idioma da sessão: numa sessão com dois
   autores de línguas diferentes, os dois sobrevivem ao resumo.
2. **Citação e código são texto literal** e não se traduzem — um identificador
   ou uma mensagem de erro traduzida no resumo deixa de ser encontrável.
3. **A frase vem ANTES dos turnos**, para que o texto de um turno no fim do
   prompt não seja lido como continuação dela.
4. **Custo:** o acréscimo é de 76 bytes — 19 tokens pela heurística do engine
   (bytes/4), no máximo 38 por uma régua pessimista de 1 token a cada 2 bytes —,
   dentro do teto de 50 tokens de entrada por chamada decidido pelo mantenedor
   para a orientação de idioma (AT-169, resposta 8). O teste reprova a frase que
   passar dele pelas duas réguas.
5. **Não é `agent_instructions`:** é texto de código e de template versionado,
   fora do teto de `instruction_patch` ([RN-007](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-007)), porque o sumarizador
   não é agente de projeto e não tem instrução por projeto.

**Decidido sem linha de base, declarado:** o mantenedor decidiu mudar o prompt
já, sem esperar a validação paga mostrar que o resumo em pt-BR desvia (AT-169,
resposta 4). A consequência é que a validação da AT-167 mede o CONJUNTO
(orientação + resumo novo), sem medir o resumo antigo isolado.

**O que esta regra NÃO fecha, declarado:**

- **Com `graph_templates_enabled?` ligada, vale a versão ATIVA no grafo.** Uma
  instalação que semeou a versão `"1"` continua mandando o prompt antigo até
  rodar `scripts/dev/seed-prompts.ts` de novo — o hash do corpo mudou, então o
  seeder cria a versão nova. Com a flag desligada (o default) vale o inline, que
  já tem a frase. Semear de novo também tira do corpo a seção de documentação
  que fazia o sumarizador receber os turnos em dobro (AT-244, ver
  [RN-413](https://github.com/viralabs-dev/brabo-infra/blob/dev/deploy/docs/business-rules/infra.md#rn-413)); o template está na versão `"3"`.
- **O fallback de quando o sumarizador falha** (`"(N turnos anteriores
  omitidos)"`) não é resumo e não ganha a frase: não há texto de turno nele.
- **A frase é pt-BR.** Ela pede o idioma de cada turno, não o do prompt; se um
  modelo a obedece em conversa de outra língua é o que a validação da AT-167
  mede.

- **Código:** `apps/engine/lib/engine/harness/context_manager.ex:214`
  (`@instrucao_de_idioma`), `:276` (`prompt_inline`), `:233` (`prompt`, a
  escolha entre template e inline); `prompts/context-manager-summarize.md`
- **Teste:** `apps/engine/test/engine/harness/context_manager_test.exs:417`
  (caminho feliz: o prompt enviado ao sumarizador tem a frase, antes dos
  turnos), `:433` (o teto de 50 tokens, pelas duas réguas), `:443` (o template
  versionado carrega a MESMA frase), `:453` (falha do sumarizador: o fallback
  não finge resumo nem ganha a frase)
- **Origem:** AT-166, especificada na AT-081 e destravada pela AT-169
  (decisões do mantenedor de 2026-09-28)
