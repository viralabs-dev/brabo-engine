---
id: rn-engine-parte-05
title: 'Regras de negócio — Engine — parte 5 (desde RN-724)'
sidebar_label: 'Engine — parte 5 (desde RN-724)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

# Engine — parte 5 (desde RN-724)

## A Anamnese não paga duas vezes pela mesma janela, e o resgate de gate não reinicia ciclo que espera alguém (RN-722)

<a id="rn-724"></a>

### RN-724 — O ciclo de gate estacionado volta por um botão no fio, não só pelo terminal do operador {#rn-724}

- **Regra:** o ciclo de gate ESTACIONADO pelo resgate
  ([RN-722](parte-04.md#rn-722), [ADR 0207](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0207-ciclo-de-gate-velho-estaciona.md))
  é retomado por `POST /projects/:projectId/tasks/:taskId/gates/:gate/resume`,
  com o MESMO papel mínimo de quem decide a PR (`developer`). A api só
  autoriza e pede ao engine (`POST /internal/projects/:id/tasks/:taskId/gates/:gate/resume`),
  que delega a `GateRescuer.retomar_estacionado/3`: ciclo que não existe, não
  está estacionado ou gate fora de `qa`/`secops` é 409 `gate_nao_estacionado`
  e nada é despachado. No fio da sessão, o evento `gate.rescue_parked` vira um
  aviso com o botão "Retomar gate", inerte com o motivo em texto quando o papel
  não alcança `developer`; a recusa mostra a frase da api. Nenhum poll novo:
  o andamento do gate retomado chega pelo log da sessão.
- **Onde:** `apps/engine/lib/engine_web/controllers/gate_command_controller.ex:15`
  (`resume`),
  `apps/api/src/application/use-cases/gates/resume-parked-gate.use-case.ts:18`
  (`execute`),
  `apps/api/src/infrastructure/http-clients/api-to-engine-client.ts:379`
  (`resumeParkedGate`),
  `apps/api/src/interfaces/http/gates/gate-resume.controller.ts:40`
  (`resume`), `apps/web/src/routes/RetomarGateEstacionado.tsx:31`
  (`RetomarGateEstacionado`)
- **Teste:** `apps/engine/test/engine_web/controllers/gate_command_controller_test.exs`
  ("ciclo estacionado: 202 e despacha o gate de novo"; falha: "ciclo NÃO
  estacionado: 409 nomeado e nada despachado"),
  `apps/api/test/interfaces/http/gates/gate-resume.controller.spec.ts`
  (feliz, 409 `gate_nao_estacionado`, papel abaixo de `developer`),
  `apps/web/src/routes/RetomarGateEstacionado.test.tsx` (o clique chama a
  rota; a recusa vira toast com a frase da api; papel insuficiente deixa o
  botão inerte)
- **Origem:** AT-397, fechando a lacuna declarada na RN-722

<a id="rn-725"></a>

### RN-725 — Texto com escape literal é decodificado, e a recusa de argumento diz o que chegou {#rn-725}

**Contexto:** no TP-01 (03/10, Claude Haiku 4.5) o PO gravou títulos de
história com o escape unicode LITERAL (`código`): a normalização da
RN-719 só decodificava campo `array`/`object`. Recriadas com o título certo,
as histórias passaram pela recusa de duplicata (RN-720/RN-081), que não casou
o escapado com o normal. E as recusas "exige X" não diziam o que tinha
chegado: o PO gastou 28+ passos (48% do custo do teste) até o teto, e
`complete_story` respondia "ainda faltam RF, DoD, DoR ou business_rule_ids"
sem dizer qual.

**A regra:**

1. No mesmo ponto da RN-719, string com `\uXXXX` LITERAL (par surrogate
   incluído) é decodificada, e com ela `\n`, `\t`, `\"` e `\\` da MESMA
   string. String sem `\uXXXX` volta byte a byte — código num `content` com
   `"\n"` literal não muda. Isso revisa o "campo `string` nunca é tocado" da
   RN-719 só nesse caso.
2. A duplicata EXATA de história (api) e de regra (engine) compara o título
   com o escape decodificado, antes da caixa e do NFD de sempre.
3. Recusa de ferramenta que diz "exige `X`" ganha, no mesmo ponto, as CHAVES
   que chegaram (nomes, nunca valores), ou que chegou string/lista em vez de
   objeto. `emit_artifact` com chave faltando no `payload` diz as chaves
   faltantes e as recebidas, em vez de `{:missing_keys, …}`.
4. `complete_story` nomeia exatamente o que falta (`falta: business_rule_ids`),
   pela mesma régua de `missingForReady` da api, lida da história devolvida.

- **Onde:** `apps/engine/lib/engine/harness/argumentos_de_ferramenta.ex:102`
  (`decodificar_escapes`), `:152` (`chaves_recebidas`), `:166`
  (`com_chaves_recebidas`); `apps/engine/lib/engine/harness/tools/complete_story.ex:80`
  (`faltam`); `apps/api/src/domain/backlog/story-overlap.ts:39`
  (`decodificarEscapesLiterais`), `:25` (`normalizarTitulo`);
  `apps/engine/lib/engine/harness/artifact_dedupe.ex` (`normalizar`)
- **Teste:** `apps/engine/test/engine/harness/argumentos_de_ferramenta_test.exs`
  (describe "RN-725": escape decodificado, texto sem `\u` e lista intactos;
  recusa com as chaves e sem os valores; `complete_story` nomeia o campo);
  `apps/api/test/domain/backlog/story-overlap.spec.ts` (título escapado casa
  com o normal; título diferente segue diferente)
- **Origem:** AT-405, AT-408

<a id="rn-726"></a>

### RN-726 — Crédito do provedor esgotado pausa o dev agent, com origem `infra`, sem queimar as tarefas seguintes {#rn-726}

- **Regra:** quando o provedor do modelo recusa por falta de CRÉDITO (HTTP 402,
  ou o texto "available credits"/"add credits" do OpenRouter), o turno do dev
  agent não é "parou sem concluir": a tarefa é bloqueada com o motivo
  "crédito do provider esgotado" e origem `infra` (nunca `codigo`), o contador
  da parada automática (RN-047) NÃO avança, e o agente NÃO reivindica a
  próxima tarefa — fica em `idle_tripped` e emite `dev.credit_exhausted`
  (`motivo: credito_esgotado`), nunca `dev.idle_tripped`. A retomada é o
  Rearmar que já existia no painel do time, depois de recarregar o crédito; a
  tarefa bloqueada volta pelo desbloqueio de sempre. A tela de Executores
  mostra o agente `travado` com "crédito do provedor do modelo esgotado —
  recarregue e rearme para retomar", e o sino diz o mesmo. O mesmo
  reconhecimento faz `FalhaDeTurno.origem/1` devolver `infra` para o frame
  final de crédito (vale para os agentes de gate, como o QA). A sessão conta
  `dev.credit_exhausted` como trabalho pendente, como `dev.idle_tripped`.
  Desde a RN-730 o 402 chega com `code` próprio (`insufficient_credit`) e é
  ele que decide; o reconhecimento pelo texto ficou só como rede.
- **Onde:** `apps/engine/lib/engine/agents/falha_de_turno.ex:142`
  (`credito_esgotado?`),
  `apps/engine/lib/engine/dev/dev_agent_server.ex:931` (`handle_outcome`),
  `apps/engine/lib/engine/dev/agent_io.ex:279` (`pausar_por_credito`),
  `apps/web/src/lib/agent-status.ts:178` (`breakerReasonFor`),
  `apps/api/src/application/use-cases/sessions/get-session-pending-work.use-case.ts`
- **Teste:** `apps/engine/test/engine/dev/dev_agent_server_test.exs`
  ("402 do provider: origem infra, pausa sem idle_tripped e sem queimar a
  próxima task"; falha: "erro que não é de crédito segue como antes: parou sem
  concluir, conta no disjuntor"),
  `apps/engine/test/engine/agents/falha_de_turno_test.exs` ("402 do provider
  é infra e é reconhecido"), `apps/web/src/lib/agent-status.test.ts`
  ("RN-726: dev.credit_exhausted é travado com motivo de crédito…")
- **Origem:** AT-407 (TP-01 de 03/10: 402 do OpenRouter virou três tarefas
  bloqueadas com origem `codigo` e a parada automática)

<a id="rn-731"></a>

### RN-731 — O fecho do turno diz o que foi gravado com o número do servidor {#rn-731}

- **Regra:** o número do que um agente conversacional gravou num turno é FATO
  do servidor, nunca texto do modelo (RN-163). O Criativo, o PO e o Arquiteto
  contam, no processo do turno, cada ferramenta de escrita que voltou `ok`
  (`emit_artifact` por tipo — regra de negócio, decisão, nota, outro —,
  `create_epic`, `create_story`, `update_story`, `archive_story`,
  `create_task`), e o fecho da `agent.response` ganha, DEPOIS do texto do
  modelo e sem reescrevê-lo, a linha "Gravado neste turno: N …". Ferramenta
  recusada e leitura não contam; turno sem escrita não ganha linha; a contagem
  morre com o turno. A linha sai no idioma do turno (RN-622): o do autor,
  senão o do projeto; `pt*` em português ("Gravado neste turno: 1 regra de
  negócio"), qualquer outro idioma — ou nenhum resolvido — em inglês
  ("Recorded this turn: 2 business rules"), com singular e plural nos dois.
- **Onde:** `apps/engine/lib/engine/agents/gravado_no_turno.ex:66` (`anotar`),
  `:99` (`descarregar`),
  `apps/engine/lib/engine/harness/idioma_da_resposta.ex:272` (`idioma_do_turno`),
  `apps/engine/lib/engine/agents/texto_do_turno.ex:65` (`payload_do_turno`)
- **Teste:** `apps/engine/test/engine/agents/gravado_no_turno_test.exs` (feliz:
  seis regras e uma decisão gravadas, uma recusada — o fecho "8 regras" do
  modelo fica e ganha "6 regras de negócio, 1 decisão" ao lado; sem escrita:
  nada acrescentado; pt-BR e en, singular e plural; idioma fora dos dois cai em en),
  `apps/engine/test/engine/agents/criativo_server_test.exs`
- **Origem:** AT-414 (TP-01 de 03/10: o Criativo fechou com "Registrei as 8
  regras de negócio" e o painel tinha 6)

<a id="rn-732"></a>

### RN-732 — O texto do turno passa pela mesma régua de escape dos argumentos {#rn-732}

- **Regra:** o texto que o modelo escreve no turno de um agente conversacional
  — o `content` (fecho) e cada `passos` da `agent.response` — passa pela MESMA
  `decodificar_escapes/1` da RN-725 antes de ser gravado: `\u00e3` literal vira
  `ã`. Uma régua só, sem cópia, e com o mesmo limite: só age quando há
  `\uXXXX` literal, então texto sem escape — inclusive código com `"\n"`
  literal num bloco cercado — volta byte a byte. O `agent.delta` do streaming
  NÃO é decodificado: um escape pode chegar partido entre dois deltas, e a
  bolha gravada substitui o texto em curso no fim do turno. Regra própria, e
  não cláusula da RN-725, porque a superfície é outra (resposta do modelo, não
  argumento de ferramenta) e a decisão sobre o delta é desta.
- **Onde:** `apps/engine/lib/engine/agents/texto_do_turno.ex:65` (`payload_do_turno`),
  `apps/engine/lib/engine/harness/argumentos_de_ferramenta.ex:102` (`decodificar_escapes`)
- **Teste:** `apps/engine/test/engine/agents/texto_do_turno_test.exs` (feliz:
  os cinco escapes medidos, no fecho e num passo; intacto: texto sem escape e
  bloco de código com `\n` literal)
- **Origem:** AT-417 (TP-01 de 03/10, 2ª rodada: a resposta final do Criativo
  gravada com "colis\u00e3o", "usu\u00e1rio" e mais três escapes na bolha)

<a id="rn-733"></a>

### RN-733 — A falha de crédito diz o que fazer, e o `reason` nunca é a tupla {#rn-733}

- **Regra:** o `reason` gravado no `agent.error` dos conversacionais, do
  Infra Lead e do `ToolLoop` (dev agent) é o TEXTO do frame final quando há
  um — nunca a tupla `{:final, …}` inspecionada; outras formas seguem com
  `inspect/1`. Com crédito do provider esgotado (`errorCode:
  insufficient_credit`, RN-730, ou o reconhecimento por texto da RN-726), a
  `mensagem` da bolha é curta e acionável no idioma do turno (RN-622): pt
  "Crédito do provedor do modelo esgotado — recarregue a chave e tente de
  novo.", qualquer outro idioma "The model provider's credit is exhausted —
  top up the key and try again."; sem idioma resolvido, pt-BR. O JSON do
  provider fica só no `reason` (diagnóstico). Os demais erros mantêm a frase
  de sempre.
- **Onde:** `apps/engine/lib/engine/agents/falha_de_turno.ex:166` (`mensagem`),
  `:189` (`diagnostico`)
- **Teste:** `apps/engine/test/engine/agents/dev_lead_server_test.exs` (402
  em pt-BR e en: frase curta, `reason` sem `{:final`; erro `upstream`: frase
  de sempre), `apps/engine/test/engine/agents/falha_de_turno_test.exs`
- **Origem:** AT-421 (TP-01 de 03/10, 2ª rodada: o Dev Lead gravou
  `reason: "{:final, …"` e a bolha despejou o JSON do 402)

<a id="rn-735"></a>

### RN-735 — A rede `none` da imagem do Arquiteto diz que não instala dependências {#rn-735}

- **Regra:** a descrição de `choose_project_image` e o RESULTADO dela dizem
  que, com rede `none`, nenhum gerenciador de pacotes (npm, pnpm, pip, mix,
  cargo, go mod...) instala dependência no container, e que a Infra herda essa
  rede (RN-723). Com `none`, o resultado pede ao modelo que chame a ferramenta
  de novo com `egress` se a stack instala dependências. É AVISO: a api não
  adivinha a stack, e a contenção do broker (ADR 0130) não muda. (Desde a
  RN-906 a api RECUSA `none` quando a stack declarada de um módulo baixa
  dependências; fora desse caso, segue só o aviso.)
- **Código:** `apps/engine/lib/engine/harness/tools/choose_project_image.ex:96`
  (`mensagem_de_fixada`), `apps/engine/lib/engine/harness/tools/choose_project_image.ex:23`
  (`spec`)
- **Teste:** `apps/engine/test/engine/harness/tools/choose_project_image_test.exs`
- **Origem:** AT-420 (TP-01 de 03/10: `node:22-bookworm-slim` com rede `none`,
  e o dev agent não conseguiu `npm install`)

<a id="rn-742"></a>

### RN-742 — O dev agent não morre calado, e a resposta HTTP tardia não fica na caixa dele {#rn-742}

- **Regra:** toda chamada HTTP não-streamada do engine à api
  (`post_returning/3` e os GETs de `EngineApiClient.Live`) roda numa `Task`
  descartável; a resposta que chega depois do `receive_timeout` cai num
  processo que já acabou, nunca na caixa de mensagens de quem chamou, e
  exceção dentro do pedido volta como `{:error, _}`. E o dev agent que CAI
  (saída que não é `:normal` nem `:shutdown`) não é tratado como terminado: o
  `Engine.Dev.Monitor` grava `agent.error` DURÁVEL com origem `infra`
  (`reason: processo_do_dev_caiu`, `religado`, `taskId`) e o RELIGA a partir
  da própria linha de `dev_agent_states`, até 3 vezes por agente; o `resume`
  passa pelo `handle_continue({:restart_recovery, _})` que já existia, que
  bloqueia a task interrompida com diagnóstico (origem `infra`) e tenta o
  próximo claim. Sem linha, ou no teto, a linha sai e o erro diz que não
  houve religamento. O `llm_turn_stream/6` fica fora do isolamento (o `into:`
  grava no dicionário do chamador); os conversacionais já o chamam de dentro
  da Task do turno (`TurnoAssincrono`), então o padrão "HTTP dentro do
  GenServer" não os alcança — declarado. A web não mudou: a aba Executores
  passa a ver o `agent.error` e o `dev.blocked` da recuperação.
- **Onde:** `apps/engine/lib/engine/sessions/engine_api_client.ex:2243`
  (`isolado`), `apps/engine/lib/engine/dev/monitor.ex:69` (`ao_terminar`),
  `:107` (`registrar_e_religar`)
- **Teste:** `apps/engine/test/engine/sessions/engine_api_client_isolado_test.exs`
  (mensagem tardia não chega ao chamador; exceção vira `{:error, _}`),
  `apps/engine/test/engine/dev/monitor_test.exs` (crash grava `agent.error`
  infra e religa; `:normal` apaga a linha; sem linha não religa)
- **Origem:** AT-428 (08/10: `CaseClauseError` em
  `Finch.HTTP1.Conn.receive_response/8` depois do timeout do `npm install`)

**Revisada pela [RN-922](parte-06.md#rn-922) ([ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md)).** O dev que cai com `working` recente e sem retomada anterior na tarefa deixa de ser bloqueado: preserva o worktree como commit e retoma a mesma tarefa uma vez. Fora disso o bloqueio descrito acima segue.

<a id="rn-743"></a>

### RN-743 — Bloquear a task preserva o trabalho do worktree, e a próxima parte dele {#rn-743}

- **Regra:** antes de bloquear uma task (qualquer origem, inclusive o teto de
  orçamento `taskBudgetMicros`, cujo VALOR não muda aqui), o que o dev agent
  deixou no worktree vira commit na branch da própria task, com a identidade
  `<agente>[bot]` (`git add -A` + `commit --no-verify`). O `dev.blocked` leva
  `trabalhoPreservado` (`{branch, commit}` ou `null`) e o diagnóstico DIZ onde
  o trabalho ficou — ou que não foi possível preservá-lo, com o motivo; a falha
  ao preservar nunca impede o bloqueio. A próxima task do MESMO agente (logo,
  do mesmo módulo) nasce dessa branch (`create_from/4`) em vez de `dev`, uma
  vez só. Worktree limpo não gera commit. Declarado: o ponteiro mora só em
  memória (restart do engine perde o ponteiro, não o commit), e no modo
  `runner` o worktree está na máquina do usuário e o engine não preserva nada.
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:79`
  (`preservar_em`), `:66` (`create_from`),
  `apps/engine/lib/engine/dev/agent_io.ex:542` (`preservar_trabalho`),
  `apps/engine/lib/engine/dev/agent_io.ex:330` (`base_preservada`)
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs`
  (`preservar_em/3 e create_from/4`: commit com `dev-api[bot]` e a próxima
  task enxerga o arquivo; limpo é `:nada`; pasta sem repositório é erro),
  `apps/engine/test/engine/dev/bloqueio_preserva_trabalho_test.exs` (o
  `dev.blocked` diz a branch; falha ao preservar não impede o bloqueio)
- **Origem:** AT-429 (08/10: `feature/task-86dade03` sem commit, `package.json`
  e `src` perdidos depois do bloqueio por orçamento)

<a id="rn-744"></a>

### RN-744 — O dev sabe que o shell é `sh` e começa vendo o próprio worktree {#rn-744}

- **Regra:** a descrição da ferramenta `terminal` diz que o shell do container
  é `sh` (dash), não bash — sem brace expansion, sem `[[ ]]`, sem arrays, sem
  `source` — e dá a forma que funciona. O kickoff de cada task do dev agent
  ganha uma segunda mensagem fixada com o RETRATO do worktree: a branch e os
  arquivos que já existem (rastreados + não rastreados não ignorados), com teto
  de 80 linhas e o total real quando corta (ADR 0060); é o servidor que monta,
  sem parâmetro do modelo. Pasta que o engine não alcança (modo `runner`) diz
  que o retrato está indisponível e manda listar pelo `terminal`. Declarado e
  NÃO corrigido: o worktree do dev pode nascer antes do merge da PR de infra,
  então o que a Infra entregou por PR pode não estar na `dev` de onde ele
  parte.
- **Onde:** `apps/engine/lib/engine/harness/tools/terminal.ex:12` (`spec`),
  `apps/engine/lib/engine/dev/worktree_manager.ex:117` (`retrato`),
  `apps/engine/lib/engine/dev/dev_agent_server.ex:657` (`retrato_do_worktree`)
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs`
  (`retrato/2`: branch e arquivos; pasta inalcançável diz indisponível; a
  descrição do terminal diz `sh`)
- **Origem:** AT-444 (TP-01 de 08/10: `mkdir -p src/{a,b}` no dash e o dev
  recriando o que já existia)

<a id="rn-745"></a>

### RN-745 — Na resposta cortada, só a chamada incompleta é recusada {#rn-745}

- **Regra:** quando a resposta do modelo vem cortada pelo teto de saída
  (`truncated: true`, [RN-737](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-737)), só a ÚLTIMA chamada de ferramenta da
  resposta é tratada como incompleta e recusada com o erro nomeado (que agora
  diz "a última da resposta", que as anteriores foram executadas e pede "uma
  por chamada"). As chamadas anteriores da mesma resposta executam
  normalmente — medido no código: o stream OpenAI-compatível monta as
  chamadas em ordem, o corte cai na última, e o `parseArgumentos` da api
  devolve `{}` para o JSON partido. A chamada é identificada por nome e
  argumentos. Resposta cortada sem chamada conhecida continua recusando toda
  ferramenta (régua da RN-737). A descrição de `propose_adr` orienta um ADR por
  resposta.
- **Onde:** `apps/engine/lib/engine/harness/resposta_cortada.ex:44`
  (`registrar`), `:64` (`incompleta?`),
  `apps/engine/lib/engine/harness/argumentos_de_ferramenta.ex:26` (`executar`),
  `apps/engine/lib/engine/harness/tools/propose_adr.ex:27` (`spec`)
- **Teste:** `apps/engine/test/engine/harness/resposta_cortada_test.exs` ("só
  a última chamada da resposta cortada é recusada; as completas executam";
  "ferramenta de resposta cortada NÃO executa", sem chamada conhecida)
- **Origem:** AT-430 (08/10: o Arquiteto mandou 5 `propose_adr` numa resposta
  cortada e as cinco foram recusadas; 0 ADRs)

<a id="rn-746"></a>

### RN-746 — O fecho do Arquiteto diz o que gravou, e as escritas recusadas são contadas {#rn-746}

- **Regra:** a linha factual "Gravado neste turno: …" da
  [RN-731](#rn-731) passa a contar as escritas do Arquiteto (ADR proposto,
  mapa de módulos, atribuição de módulos, imagem decidida, diagrama C4,
  roteamento para a infra, contrato de módulos, insight), a RFC do Staff e o
  protótipo do UX Designer, e conta à parte as chamadas de ESCRITA recusadas
  (`{:error, _}`) do turno: "…; N chamadas de escrita recusadas". Turno que
  tentou escrever e não gravou nada fecha com "Gravado neste turno: nada; N
  chamadas de escrita recusadas." (en: "Recorded this turn: nothing; N write
  calls refused."). O Criativo passa a anotar a recusa também; Staff e UX
  Designer passam a anotar. Leitura nunca conta. O texto do modelo não é
  reescrito (RN-163: o agente não anuncia como feito o que o servidor
  recusou — quem lê vê o fato ao lado). Fora, declarado: Dev Lead (o plano
  suspende o turno, RN-284) e Infra Lead.
- **Onde:** `apps/engine/lib/engine/agents/gravado_no_turno.ex:81` (`anotar`),
  `:96` (`descarregar`), `:141` (`classe`),
  `apps/engine/lib/engine/agents/arquiteto_server.ex:330` (`dispatch_tool`)
- **Teste:** `apps/engine/test/engine/agents/gravado_no_turno_test.exs`
  ("Arquiteto com as cinco propose_adr recusadas fecha com nada gravado";
  "escritas do Arquiteto contadas, leitura e ferramenta desconhecida não")
- **Origem:** AT-431 (08/10: com os 5 `propose_adr` `ok: false`, o Arquiteto
  fechou com "✅ ADRs Propostas (5 decisões críticas)" e nenhuma linha factual)

<a id="rn-756"></a>

### RN-756 — A Anamnese só roda com interação de conteúdo técnico do sujeito; aprovar não conta {#rn-756}

- **Regra:** revisa a contagem de "interação própria" da RN-680/RN-722. Só
  contam para fazer alguém sujeito da rodada (a) evento `actor_kind: "user"`
  do próprio membro cujo tipo está em `tipos_de_evento_com_conteudo/0` —
  `chat.message` (mensagem escrita por ele) e
  `chat.structured_question_answered` — e (b) decisão de ação com motivo de
  recusa escrito (`rejectionReason` não vazio, uma correção). Aprovação,
  aceite de handoff, clique e qualquer outro evento de usuário NÃO contam:
  não são evidência de competência. O piso de 5 (RN-722), o teto diário e o
  desfecho sem sujeito (motivo no log; `anamnese.run_skipped` só na rodada
  pedida à mão) não mudam, e a triagem segue LOCAL, antes do LLM e do RAG.
- **Código:** `apps/engine/lib/engine/anamnese/elegibilidade.ex:61`
  (`avaliar`), `:102` (`recusa_com_motivo?`), `:108`
  (`tipos_de_evento_com_conteudo`)
- **Teste:** `apps/engine/test/engine/anamnese/elegibilidade_test.exs`
  (`só interação com conteúdo técnico conta (RN-756, AT-439)`: mensagem e
  resposta estruturada fazem sujeito; só aprovações, handoff e recusa sem
  motivo não fazem)
- **Origem:** AT-439 (TP-01, 08/10, projeto `c1dc053d`: duas rodadas durante
  a execução, US$ 0,20, ambas `skip_proficiency` com "o usuário apenas
  aprovou propostas")

<a id="rn-757"></a>

### RN-757 — O `terminal` auto-aprovado espera o comando, e o teto do comando é 2 min {#rn-757}

- **Regra:** a ação `terminal` que a api auto-aprova é EXECUTADA dentro da
  mesma requisição do `propose_action` (api → engine
  `/internal/actions/execute` → api `container-exec` → broker), e o engine
  espera essa requisição por `TERMINAL_ACTION_TIMEOUT_MS` + 120 s — não pelo
  default de 15 s do `Req`. O teto do comando (`TERMINAL_ACTION_TIMEOUT_MS`)
  passa de 15 s para 120 s nos três composes e no `runtime.exs`. A cadeia fica
  broker (T) < api → broker (T + até 45 s, [RN-604](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-604)) < engine →
  `container-exec` (T + 90 s) < engine → `propose_action` (T + 120 s), e com
  T = 120 s o salto de fora (240 s) segue abaixo dos 300 s de cabeçalhos do
  `fetch` do Node. Se a espera ainda estourar, o modelo recebe texto NOMEADO
  — o teto em segundos, que o processo pode seguir rodando e a sugestão de
  `nohup … &` com log —, nunca `%Req.TransportError{reason: :timeout}` cru.
  Exec assíncrono/streaming foi considerado e não feito: a menor mudança que
  faz `npm install` comum caber é o teto.
- **Onde:** `apps/engine/lib/engine/sessions/engine_api_client.ex:2006`
  (`opcoes_do_propose_action`) e
  `apps/engine/lib/engine/harness/hooks/action_pipeline.ex:85`
  (`resultado_de_teto_do_terminal`)
- **Teste:** `apps/engine/test/engine/sessions/engine_api_client_propose_terminal_test.exs`
  (api falsa que demora 16 s ainda é esperada; ordem dos tetos abaixo de
  300 s; o texto de estouro nomeia o teto)
- **Origem:** AT-440 (TP-01 de 08/10: `npm install 2>&1 | tail -50` num
  container `node:22-bookworm-slim` voltou "falha no pipeline:
  %Req.TransportError{reason: :timeout}"; medido nesta máquina, o mesmo
  `npm install` de `bcrypt`+`sqlite3`+`express` levou 5,3 s com a imagem em
  cache e prebuilds disponíveis — a cadeia, não o comando, cortava em 15 s)

<a id="rn-760"></a>

### RN-760 — A próxima task do dev agent parte da última branch dele ainda não mergeada {#rn-760}

- **Regra:** generaliza a [RN-743](#rn-743). Ao terminar uma task — aprovada
  nos gates (`nextAction: "done"`) ou bloqueada por QUALQUER motivo, inclusive
  o "ciclo de correção esgotado (gate)" que a api decide e chega ao engine só
  como `gate_resolved` —, o dev agent guarda a branch dela e a próxima task do
  MESMO agente (logo, do mesmo módulo) nasce dessa branch, e não de `dev`. O
  que sobrou sem commit no worktree é preservado antes, como na RN-743; o
  ponteiro gravado pelo `block_task/4` não é sobrescrito. Quando a branch
  anterior já é ancestral da `dev` local (mergeada), a próxima parte da `dev`,
  que já a contém. QUANDO a fila anda não muda: a próxima task continua sendo
  reivindicada ao fim dos gates, antes do merge do usuário (decisão do dono).
  Declarado: merge por squash num remoto não deixa a branch ancestral da `dev`,
  então a próxima segue partindo dela; o ponteiro continua só em memória, e no
  modo `runner` a checagem de merge não roda.
- **Onde:** `apps/engine/lib/engine/dev/agent_io.ex:352`
  (`levar_branch_para_a_proxima`), `:333` (`criar_worktree`),
  `apps/engine/lib/engine/dev/worktree_manager.ex:553`
  (`ja_mergeada_volta_ao_trabalho`)
- **Teste:** `apps/engine/test/engine/dev/bloqueio_preserva_trabalho_test.exs`
  (`levar_branch_para_a_proxima/1 e criar_worktree/2`: aprovada leva a branch
  para a próxima; o ponteiro do bloqueio não é sobrescrito),
  `apps/engine/test/engine/dev/worktree_manager_test.exs` (`add_worktree/4
  com a branch da task anterior`: não mergeada parte dela, mergeada parte da
  `dev`)
- **Origem:** AT-447 (TP-01 de 09/10: tasks `762833bd` e `5ebad64b` — a
  segunda nasceu de `dev` sem a rota de login da primeira, e o QA reprovou)

<a id="rn-763"></a>

### RN-763 — Encerrar a sessão de execução para os dev agents e os gates, e "Parar execução" na aba Executores {#rn-763}

- **Regra:** o fechamento da sessão (`session.closed`/`closed_abnormally`,
  pelo `SessionLifecycleWorker`, o ponto por onde todo fechamento passa) PARA
  os dev agents dela em todos os nós e os gates (QA lead e SecOps) do projeto
  — a régua que já valia para os conversacionais ([RN-581](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-581)). O
  processo é derrubado na hora, sem gravar o turno em curso, e o
  `Engine.Dev.Monitor` é avisado antes (`esquecer/1`): a linha durável sai e
  o agente NÃO é religado ([RN-742](#rn-742)). Para cada dev com task em curso
  (`working`, `awaiting_approval` ou `awaiting_gate`), o trabalho do worktree
  vira commit na branch da task ([RN-743](#rn-743)) e a task é BLOQUEADA com
  motivo "sessão de execução encerrada", origem `politica`, e o diagnóstico
  dizendo onde ficou o trabalho — volta à fila quando um humano a libera,
  nunca perdida. As linhas de `gate_states` da sessão saem, para o
  `GateRescuer` não reabrir ciclo da sessão encerrada. A aba Executores ganha
  "Parar execução" (papel `developer`, o de encerrar sessão), cujo mecanismo é
  o MESMO fechamento (`closing` → `closed`), sem estado novo; a confirmação
  diz antes do clique o que fica: as tarefas em curso (com a contagem), as PRs
  abertas, as aprovações pendentes e que a sessão não reabre. Declarado: ação
  pendente de dev agent continua pendente; PR aberta continua aberta; sessão
  com `execution.activated` não reabre ([RN-650](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-650)), então retomar é
  ativar a execução numa sessão nova; a contagem de tarefas da confirmação vem
  da janela de eventos da aba. A confirmação no "Encerrar" da barra da sessão
  é de outra atividade (AT-452).
- **Onde:** `apps/engine/lib/engine/dev/encerramento_da_sessao.ex:40`
  (`parar_da_sessao`), `:74` (`parar_processos`), `:104` (`devolver_task`),
  `apps/engine/lib/engine/dev/monitor.ex:34` (`esquecer`),
  `apps/engine/lib/engine/workers/session_lifecycle_worker.ex:94`
  (`parar_execucao`), `apps/web/src/components/PararExecucao.tsx`
- **Teste:** `apps/engine/test/engine/dev/encerramento_da_sessao_test.exs`
  (o dev morre sem ser religado, a linha sai, a task é bloqueada com origem
  `politica`; sessão sem dev é no-op e o dev de outra sessão fica de pé),
  `apps/web/src/components/PararExecucao.test.tsx` (a confirmação diz o que
  fica e fecha `closing` → `closed`; a recusa da api fica na confirmação; sem
  papel o botão fica inerte com o motivo)
- **Origem:** AT-456 (TP-01 de 09/10: com a sessão de execução encerrada, o
  `dev-encurtador-api` bloqueou a tarefa 3, pegou a 4 e abriu PR; o único
  freio foi parar o container)

<a id="rn-765"></a>

### RN-765 — O gate de QA julga a TAREFA, e RF de tarefa irmã é observação {#rn-765}

- **Regra:** a QA-estratégia (plano de teste, [RN-674](parte-04.md#rn-674)) e a
  QA-automação recebem, além da história, o RECORTE da tarefa: título e
  descrição, as regras de negócio da história e as OUTRAS tarefas da mesma
  história com o status (`siblingTasks` em `GET .../dev-context`). O veredito
  é sobre o que é DESTA tarefa: requisito que pertence a uma tarefa irmã
  (feita ou pendente) não reprova — vai ao `resumo` como observação, fora de
  `itens`, e não impede `approved`. A régua é de PROMPT, não de código: o
  `emit_qa_verdict` continua exigindo só a suite verde para aprovar. Desde a
  AT-479, quando a descrição da tarefa ou uma regra quantifica POR item ("por
  X", "cada", "de todos os" — "por exemplo"/"por padrão" não contam), o recorte
  ganha a seção "Forma da resposta": conferir que a resposta traz o valor de
  CADA item, não só o total (o painel aprovado com só `{totalCliques}` sobre
  "a contagem… de todos os links"), e que a recusa de entrada nomeia o campo —
  esta última é OBSERVAÇÃO no `resumo`, fora de `itens`, salvo regra que a
  exija. Continua régua de prompt: nenhuma reprovação nova no código.
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:18` (`texto`),
  `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:82` (`secao_da_forma`),
  `apps/api/src/application/use-cases/execution/get-dev-task-context.use-case.ts:220`
  (`tarefasIrmas`) e `apps/engine/lib/engine/gates/qa_automacao_agent.ex:170`

  `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:82` (`secao_da_forma`),
  `apps/api/src/application/use-cases/execution/get-dev-task-context.use-case.ts:220`
  (`tarefasIrmas`) e `apps/engine/lib/engine/gates/qa_automacao_agent.ex:225`
  (`com_o_recorte`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs` (desde
  a AT-479 também "regra que quantifica por item pede a conferência da forma da
  resposta" e o caso sem quantificador) e
  `apps/api/test/application/use-cases/execution/get-dev-task-context.use-case.spec.ts`
  (as irmãs sem a própria tarefa). O golden-set do QA (ADR 0168) NÃO ganhou
  caso: ele roda o modelo de verdade, e provar o veredito sem chamada paga
  não é possível — declarado.
- **Origem:** AT-448 (TP-01 de 09/10: o gate de QA da tarefa "Modelar tabela
  de usuários e hash bcrypt" reprovou três vezes por "RF01: login HTTP com
  JWT não existe nesta entrega", que é de outra tarefa, e a tarefa bloqueou;
  `artifact.qa_verdict` das tasks `42bea901` e `762833bd`)

<a id="rn-772"></a>

### RN-772 — O Arquiteto lê o status ATUAL das ADRs que propôs {#rn-772}

- **Regra:** o Arquiteto tem a leitura `listar_adrs_propostas`: as ações
  `open_adr_pr` do PROJETO, lidas agora de `proposed_actions` (mesmo
  Postgres, sem HTTP no laço), com o status de cada uma — pendente, aprovada,
  aprovada automaticamente, executada (com a URL da PR), recusada (com o
  motivo) ou falhada. Contida (ADR 0060, [RN-164](parte-01.md#rn-164)): sem parâmetro,
  escopo fechado no projeto do contexto, uma contagem e uma consulta por
  chamada, as 20 mais recentes, e o total real dito quando corta. Falha de
  leitura é `tool.result` `ok: false` com o motivo, nunca texto vazio. Desde a
  [RN-784](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-784) ela ESTÁ no piso do Jev.
- **Onde:** `apps/engine/lib/engine/harness/tools/listar_adrs_propostas.ex:37`
  (`run`), `:40` (`ler`), `apps/engine/lib/engine/agents/arquiteto_server.ex:629`
  (`ListarAdrsPropostas`)
- **Teste:** `apps/engine/test/engine/harness/tools/listar_adrs_propostas_test.exs`
  (aprovada aparece aprovada, executada com a PR, recusada com o motivo, só as
  do projeto; teto com o total real; sem proposta; leitura que falha vira erro
  nomeado)
- **Origem:** AT-454 (TP-01 de 09/10, sessão `771131f4`: com as 3 ADRs
  aprovadas, o fecho seguinte disse "As 3 ADRs seguem pendentes de aprovação")

<a id="rn-773"></a>

### RN-773 — O Arquiteto lê o backlog, e consulta antes de afirmar estado {#rn-773}

- **Regra:** o Arquiteto ganha a mesma `listar_backlog` do PO
  ([RN-164](parte-01.md#rn-164)), com a contagem de tarefas por história. O kickoff dele e
  o resultado do `propose_adr` dizem que o status das ADRs e as tarefas mudam
  fora da conversa e mandam consultar as duas leituras antes de afirmá-los, em
  vez do retrato de um resultado anterior. Nada de fluxo do time é narrado
  aqui ([RN-711](parte-04.md#rn-711)).
- **Onde:** `apps/engine/lib/engine/agents/arquiteto_server.ex:630`
  (`ListarBacklog`), `apps/engine/lib/engine/harness/tools/propose_adr.ex:108`
  (`propor`)
- **Teste:** `apps/engine/test/engine/harness/tools/listar_backlog_test.exs`
  (a contagem de tarefas por história), `apps/engine/test/engine/agents/arquiteto_server_test.exs`
  (as duas leituras estão no catálogo do Arquiteto)
- **Origem:** AT-454 (TP-01 de 09/10: com 17 tarefas no backlog, o Arquiteto
  disse "faltam as tarefas" e "não consigo verificá-las daqui")

<a id="rn-774"></a>

### RN-774 — A primeira tarefa de cada módulo tem o dobro do teto por tarefa {#rn-774}

A primeira tarefa de um módulo monta o esqueleto inteiro (manifesto, app,
banco, testes) e custa mais que as seguintes: no TP-01 de 08/10 ela gastou
US$ 0,53 com o Haiku 4.5 e foi bloqueada pelo teto fixo de US$ 0,50
(`taskBudgetMicros: 500000`). Por decisão do dono (09/10), ela ganha
**2× o teto por tarefa** (US$ 1,00 com o padrão); as demais seguem o teto
configurado. O multiplicador é constante nomeada no engine, não configuração.

"Primeira" é medida pelo log, nunca pelo estado da tarefa: é a tarefa cujo
`backlog.task_claimed` é o MAIS ANTIGO do projeto para aquele módulo. Bloquear
zera `assigned_to` e reiniciar o engine perde a memória do processo; o log não
muda, então a mesma tarefa reivindicada de novo depois de liberada continua a
primeira, e uma correção pedida por gate também recebe o 2×. A api responde
`task.primeiraDoModulo` no contexto do dev (`false` sem `module`, e `false` sem
claim nenhum do módulo — o teto normal é o conservador), e o teto EFETIVO é
resolvido num ponto só do engine. O bloqueio por orçamento diz o teto que valeu
para aquela tarefa ("teto da primeira tarefa do módulo: 1000000 micro-USD,
US$ 1.00"). Os gates de QA seguem com o `task_budget_micros` base — fora do
recorte do card.

- **Onde:** `apps/engine/lib/engine/dev/teto_da_tarefa.ex:32` (`efetivo`);
  `apps/engine/lib/engine/dev/dev_agent_server.ex:733` (`diagnostico_de_orcamento`);
  `apps/api/src/application/use-cases/execution/get-dev-task-context.use-case.ts:207`
  (`ehPrimeiraTarefaDoModulo`)
- **Teste:** `apps/engine/test/engine/dev/dev_agent_server_test.exs` (describe
  "RN-774": a primeira com US$ 0,53 não bloqueia, a segunda do mesmo módulo
  bloqueia — caso de falha —, a primeira de outro módulo também ganha 2×);
  `apps/engine/test/engine/dev/teto_da_tarefa_test.exs`;
  `apps/api/test/application/use-cases/execution/get-dev-task-context.use-case.spec.ts`
  (describe "RN-774")
- **Origem:** AT-433

<a id="rn-778"></a>

### RN-778 — O dev agent órfão fecha por evento novo no boot {#rn-778}

- **Regra:** no boot, para cada sessão não terminal, o dev agent cujo último
  `dev.*` na sessão é de espera (`dev.working`, `dev.blocked`, `dev.idle_tripped`
  e os demais que o `GetSessionPendingWorkUseCase` conta) e que NÃO tem linha
  em `dev_agent_states` NESTA sessão ganha `dev.error` com origem `infra`
  (`reason: dev_agent_sem_processo`) seguido de `dev.idle`, que o tira da régua
  do trabalho pendente ([RN-064](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-064)). É o molde
  da [RN-586](parte-03.md#rn-586) para o vocabulário `dev.*`: nunca reexecuta, nunca
  reescreve evento, e a linha durável é a prova de dono — com ela o
  `DevRehydrator` religa o agente, e fechá-lo seria matar um agente saudável.
  Não toca a tarefa: tarefa bloqueada ou com PR esperando o merge continua
  segurando a sessão de execução vigente pela RN-776 (AT-457), que tem dono
  humano.
- **Onde:** `apps/engine/lib/engine/dev/dev_orfao.ex:49` (`varrer`),
  `apps/engine/lib/engine/sessions/rehydrator.ex:81` (`varrer`)
- **Teste:** `apps/engine/test/engine/dev/dev_orfao_test.exs` (o órfão fecha
  com `dev.error` infra + `dev.idle`; o que tem linha durável e o que já está
  `idle` não; leitura que falha não fecha nada)
- **Origem:** AT-465 (TP-01 de 09/10: a sessão `63a4e1aa` reagendada pelo
  heartbeat a cada 30 s por um `dev.working` sem processo)

**Citada pela [RN-922](parte-06.md#rn-922) ([ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md)), sem mudar:** o dev sem linha durável em `dev_agent_states` continua só fechado, porque não há tarefa a retomar.

<a id="rn-779"></a>

### RN-779 — O worktree da task (re)pegada parte da `dev` ATUAL e a integra {#rn-779}

- **Regra:** antes de criar o worktree de uma task (primeira vez ou retomada),
  o engine faz `git fetch origin` no working tree do projeto (serializado por
  projeto) — é no remoto que as PRs são mergeadas, e a `dev` local só andava no
  checkout da inicialização. A ponta da `dev` é `origin/dev` quando a local
  ficou para trás. A task nasce: (1) da branch da task anterior não mergeada
  (RN-760), (2) da PRÓPRIA branch quando ela tem trabalho que a `dev` não
  contém — a task retomada num processo novo, que perdeu o ponteiro em memória
  (RN-743) —, ou (3) da ponta atual da `dev`. Nos casos (1) e (2) o worktree
  INTEGRA a ponta da `dev` (`merge --no-ff`, identidade `<agente>[bot]`) antes
  do primeiro passo. Conflito nessa integração vai para o agente
  ([RN-1010](parte-06.md#rn-1010)); só o que o agente não resolve é recusa NOMEADA
  ("conflito ao integrar a `dev` atual", com os arquivos): o merge é abortado, a branch de
  origem fica intacta e a task bloqueia com motivo próprio e origem `codigo`.
  `fetch` que falha bloqueia a task com o motivo do git, nunca cai na `dev`
  velha. A readoção depois de conflito de merge (RN-715) INTEGRA a `main` atual pelo sistema, como o claim (AT-798, [RN-1010](parte-06.md#rn-1010)).
  Medido no TP-01: a AT-447 DISPAROU no 1º claim (reflog: `Created from
  feature/task-b3cc92b8`); quem perdeu a base foi o reclaim, que redefiniu a
  branch para a `dev` LOCAL parada no merge da infra (`Reset to dev`).
  Declarado: no modo `runner` nada disso roda (o git é da máquina do usuário).
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:156`
  (`atualizar_remoto`), `:321` (`add_worktree`), `:399`
  (`ponta_do_trabalho`), `:462` (`retomada`), `:472` (`integrar_trabalho`)
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs`
  (`integração da dev atual (RN-779)`: retomada com branch antiga parte da dev
  nova do remoto; trabalho preservado integra a dev nova; anterior em
  `awaiting_user` é a base com a dev integrada; conflito é recusa nomeada)
- **Origem:** AT-458 (TP-01 de 09/10: `feature/task-c80daf6c` nasceu de
  `1fa2241` sem as 12 tarefas mergeadas depois, e o merge conflitou)

<a id="rn-780"></a>

### RN-780 — Resposta só de raciocínio cortada pelo teto é corte, não desistência {#rn-780}

- **Regra:** no `ToolLoop` (caminho de todo agente de execução e de gate),
  a resposta sem texto e sem chamada de ferramenta que a api marca
  `truncated: true` (o `finish_reason: length` da RN-737) é o raciocínio que
  comeu o teto de saída. A volta é retentada UMA vez, sem a resposta vazia no
  histórico e contando iteração — o teto de iterações e o orçamento da tarefa
  continuam valendo. Se repetir, o laço para marcando `corte_pelo_teto`, e o
  dev agent bloqueia a task com o motivo "resposta só de raciocínio, cortada
  pelo teto" e origem `modelo`, em vez de "parou sem concluir nem reportar
  bloqueio". Uma chamada de ferramenta no meio zera a retentativa. Declarado:
  o engine recebe da api `truncated` e `usage.outputTokens`, mas NÃO os
  `reasoningTokens` (ficam só em `token_usage`), então a resposta vazia que
  bate no teto sem `finish_reason: length` não é reconhecida.
- **Onde:** `apps/engine/lib/engine/harness/tool_loop.ex:256`
  (`parada_sem_chamada`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1218`
  (`motivo_da_parada`), `:1237` (`stop_diagnosis`)
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs` (`corte só
  de raciocínio`: retentada uma vez e segue; repetido para com
  `corte_pelo_teto`), `apps/engine/test/engine/dev/dev_agent_server_test.exs`
  (`resposta só de raciocínio cortada pelo teto bloqueia com motivo nomeado`)
- **Origem:** AT-459 (TP-01 de 09/10: a tarefa `c80daf6c` bloqueou em 40 s
  com 8.192 tokens de saída, todos de raciocínio)

<a id="rn-781"></a>

### RN-781 — A mensagem de commit do dev não grava pendência que é do sistema {#rn-781}

- **Regra:** o resumo do `report_done` é a mensagem de commit do dev agent, e
  commit, push e PR são feitos pelo sistema depois dele. Antes de propor o
  `git_commit`, o engine corta do marcador de pendência ("Pendente",
  "Pendência", "Pending") ao fim quando o resto fala de commit, push ou PR, e
  tira o parêntese "(ainda sem commit…)"; pendência que não fala disso fica.
  A descrição do campo `summary` diz que ele vira a mensagem de commit e que
  não se narra commit, push nem PR. Resumo que fica vazio cai na mensagem
  padrão `<agente>: <task>`.
- **Onde:** `apps/engine/lib/engine/dev/agent_io.ex:407`
  (`mensagem_de_commit`), `:382` (`propose_commit`),
  `apps/engine/lib/engine/dev/tools/report_done.ex:27` (`summary`)
- **Teste:** `apps/engine/test/engine/dev/mensagem_de_commit_test.exs`
  (corta a narração; tira o parêntese; pendência alheia ao sistema fica)
- **Origem:** AT-464 item 2 (TP-01 de 09/10: `git log feature/task-9d6dcd53`
  com "Pendente: commit… as ações git_commit, git_push e pr_open não estavam
  disponíveis neste passo")

<a id="rn-787"></a>

### RN-787 — O gate conta o diff da PR contra a `dev` da origem, e o parecer de QA grava lista {#rn-787}

- **Regra:** (1) o diff que o QA e o SecOps julgam (`dev...HEAD`,
  [RN-664](parte-04.md#rn-664)) usa a `dev` MAIS NOVA que o working tree enxerga: com
  origem local (caminho no disco) o gate faz antes `git fetch origin dev`,
  melhor esforço, e entre `origin/dev` e a `dev` local vale a que contém a
  outra. A `dev` local do clone não anda quando a PR é mergeada na origem, e o
  parecer do SecOps contava o acumulado das tarefas já mergeadas. Com origem
  remota não há fetch no gate (a credencial é do `Workspace`) — declarado. O
  semgrep e o gitleaks seguem varrendo o worktree inteiro, não só o diff:
  estreitar o que o scanner vê muda o que o gate reprova, e isso fica para o
  dono. (2) `itens` e `coverageMatrix` do parecer de QA chegam ao
  `artifact.qa_verdict` sempre como LISTA: string JSON de lista é decodificada
  (o molde da [RN-719](parte-04.md#rn-719)), e string que não é lista vira `[]`.
- **Onde:** `apps/engine/lib/engine/gates/diff.ex:44` (`base_mais_nova`),
  `apps/engine/lib/engine/gates/hooks/termination.ex:54` (`lista`)
- **Teste:** `apps/engine/test/engine/gates/diff_test.exs` (a tarefa B nascida
  da A, com a A mergeada na origem: o diff é só B) e
  `apps/engine/test/engine/gates/hooks/termination_test.exs` (string JSON vira
  lista; lista intacta; string inválida vira `[]`)
- **Origem:** AT-464 itens 1 e 3 (TP-01 de 09/10, sessão `80e3ce09`: "17
  arquivo(s) alterado(s) nesta PR" numa PR de 3 arquivos contra a `dev`, e
  `coverageMatrix`/`itens` gravados como `"[]"` nos últimos pareceres)

<a id="rn-790"></a>

### RN-790 — O README de como subir o entregável é critério do DoD que o PO escreve {#rn-790}

- **Regra:** a instrução de kickoff do PO manda incluir, no DoD da história que
  cria a entrada da aplicação (servidor, CLI, configuração ou persistência) — ou
  numa história própria —, o critério "README diz como instalar, configurar
  (variáveis de ambiente obrigatórias e opcionais, com o padrão) e subir a
  aplicação, e como criar o primeiro acesso, quando houver". O dev agent cumpre
  o DoD da história, e o gate o julga por ele. Régua de PROMPT, como a
  [RN-765](#rn-765): nenhuma ferramenta recusa história sem esse critério. A
  outra variante — o dev agent atualizar o README em toda tarefa que mexe em
  configuração/entrada — NÃO foi feita: exigiria classificar a tarefa no
  `AmbienteDoAgente` ou no `report_done`, regra nova de código — declarado.
- **Onde:** `apps/engine/lib/engine/agents/po_server.ex:605` (`kickoff_instruction`)
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs:438` (a
  instrução de kickoff traz o critério do README)
- **Origem:** AT-466 (TP-01 de 09/10: o `encurtador-api` saiu com um README só
  com `npm test`, sem `JWT_SECRET` obrigatório, `DB_PATH`/`PORT`, `npm start`
  nem como criar o primeiro membro)

<a id="rn-792"></a>

### RN-792 — Ao declarar o contrato, o Arquiteto recebe as rotas das histórias que o contrato não declara {#rn-792}

- **Regra:** depois de `declare_module_contracts` gravar a versão
  ([RN-684](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-684)), a ferramenta lê o backlog do projeto e extrai, de forma
  determinística e sem LLM, todo `MÉTODO /caminho` (GET, POST, PUT, PATCH,
  DELETE) do título, descrição, RF e DoD das histórias não arquivadas, e o
  mesmo padrão das `assinatura`s do contrato. Rota citada por história e
  ausente da UNIÃO das rotas do contrato (a história do front cita a rota do
  back) volta no resultado como DIVERGÊNCIA, com o que o contrato declara no
  mesmo método — entrada do laço ([RN-163](parte-01.md#rn-163)), para o Arquiteto
  corrigir o contrato ou registrar a decisão. Parâmetro (`:id`, `{id}`), barra
  final e query string são normalizados; teto de 10 linhas, com o total. A
  leitura do backlog falhar NÃO recusa a declaração (já gravada): o resultado
  diz que não conferiu. Fica de fora, declarado: rota que só o contrato
  declara (não é divergência), história editada DEPOIS da declaração (só é
  conferida na próxima), e o contrato acompanhar a rota que o DEV renomeou
  (o QA nomeia a divergência no parecer, [RN-786](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-786), mas nada a leva
  de volta ao Arquiteto).
- **Onde:** `apps/engine/lib/engine/harness/rotas_do_contrato.ex:37`
  (`divergencias`), `apps/engine/lib/engine/harness/tools/declare_module_contracts.ex:125`
  (`conferencia_com_historias`)
- **Teste:** `apps/engine/test/engine/harness/tools/declare_module_contracts_test.exs`
  (`GET /painel` na história × `GET /panel` no contrato acusa; rota igual com
  parâmetro e barra normalizados não acusa; backlog ilegível diz que não
  conferiu)
- **Origem:** AT-468 (TP-01 de 09/10: a história pedia `GET /painel`, o
  contrato declarou `GET /panel`, e ninguém acusou na arquitetura)

<a id="rn-796"></a>

### RN-796 — O item do gitleaks diz a regra e o trecho com o segredo mascarado {#rn-796}

- **Regra:** o item que o `gitleaks` põe no parecer do SecOps leva, além do
  caminho e da linha, a regra que acusou (`RuleID`) e o trecho acusado
  (`Match`) com o segredo (`Secret`) trocado por `***` — nunca o segredo em
  claro. Sem o `Secret` para mascarar, o trecho não entra. E o ambiente do
  agente de execução ([RN-706](parte-04.md#rn-706)) diz em uma linha que senha, token ou
  chave de teste são gerados em tempo de execução, nunca literais. Sem
  allowlist nova.
- **Onde:** `apps/engine/lib/engine/actions/gitleaks_detector.ex:121`
  (`mensagem`), `apps/engine/lib/engine/harness/ambiente_do_agente.ex:102`
  (`montar`)
- **Teste:** `apps/engine/test/engine/actions/gitleaks_relatorio_test.exs`,
  `apps/engine/test/engine/harness/ambiente_do_agente_test.exs`
- **Origem:** AT-470

<a id="rn-797"></a>

### RN-797 — A task cuja branch não tem diff contra a `dev` fecha como "já na dev" {#rn-797}

- **Regra:** no `report_done`, antes de propor commit, push e PR, o dev agent
  pergunta se a branch do worktree traz algo que a `dev` não tem: árvore limpa
  e `git diff --quiet <ponta da dev>...HEAD` sem diferença. É o caso da task
  reintegrada ([RN-779](#rn-779)) cujo código já entrou por outra PR. Sem
  diff, a task fecha como `done` com o evento `dev.task_already_in_dev`
  (agente, task, branch, motivo) — sem commit, sem PR, sem gates e sem
  clique. Qualquer dúvida (pasta que o engine não alcança, como no modo
  `runner`; git que falha; ref da `dev` ausente) é "tem diff": a task segue
  para os gates, nunca fecha sozinha. Mede DIFF e não ancestralidade, então
  cobre também o merge por squash que a [RN-760](#rn-760) declara não ver.
  Declarado: a PR antiga da branch, se existir, não é fechada no provider.
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:418`
  (`sem_diff_contra_a_dev?`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1150`
  (`ja_na_dev`)
- **Teste:** `apps/engine/test/engine/dev/tarefa_ja_na_dev_test.exs`
- **Origem:** AT-474

<a id="rn-798"></a>

### RN-798 — O QA confere os comandos do README tocado pela entrega contra os scripts {#rn-798}

- **Regra:** quando o diff da entrega contra a `dev` toca um README, o QA
  confere, sem LLM, que todo `npm run <s>`, `npm test`, `npm start`,
  `pnpm [run] <s>` e `yarn [run] <s>` citado nele existe em `scripts` do
  `package.json` da mesma pasta (senão o da raiz do worktree). A conferência
  entra na consolidação como mais um parecer ("Conferência do README"):
  divergência é `changes_requested` com um item por comando, nomeando o
  script que falta; sem divergência, aprova. Sem README no diff, diff que
  falhou ou `package.json` inalcançável, nada é afirmado. De FORA, declarado:
  subcomando embutido do gerenciador (`pnpm install`, `pnpm dlx`…), comando
  com flag antes do script (`pnpm --filter x test`), flags de CLI do próprio
  projeto e comando que não é de Node.
- **Onde:** `apps/engine/lib/engine/gates/conferencia_do_readme.ex:28`
  (`conferir`), `apps/engine/lib/engine/gates/qa_lead_server.ex:818`
  (`conferencia_do_readme`)
- **Teste:** `apps/engine/test/engine/gates/conferencia_do_readme_test.exs`
- **Origem:** AT-475

<a id="rn-805"></a>

### RN-805 — O plano de teste gravado é o que a ferramenta aceitou {#rn-805}

- **Regra:** `emit_plano_de_teste` valida os argumentos JÁ normalizados
  ([RN-719](parte-04.md#rn-719): `criteriosExecutaveis` em string JSON vira lista), e o
  hook que encerra o laço da QA-estratégia lê `criteriosExecutaveis` pela MESMA
  normalização (`Termination.lista/1`, a da [RN-787](#rn-787)). Antes, a tool
  dizia "plano registrado: 9 critérios", o hook levava a string crua, o
  artefato era recusado (`:criterios_vazios`), o agente devolvia `{:ok, plano}`
  mesmo assim e a Automação caía no `Enum` da string — o QA Lead morria e o
  gate ficava parado até o resgate (18 min no uso real). Artefato recusado
  agora é falha NOMEADA da QA-estratégia (`agent.error`, origem `codigo`) e a
  revisão segue sem plano, como já seguia quando o plano falha; a Automação
  também normaliza os critérios que recebe.
- **Onde:** `apps/engine/lib/engine/gates/hooks/termination_plano_de_teste.ex:23`
  (`criterios_executaveis`), `apps/engine/lib/engine/gates/qa_estrategia_agent.ex:231`
  (`emit_returning`)
- **Teste:** `apps/engine/test/engine/gates/qa_estrategia_agent_test.exs`
  ("critérios em string JSON viram lista: o plano é gravado e devolvido como lista")
- **Origem:** AT-478 (TP-01 de 10/10)

<a id="rn-806"></a>

### RN-806 — Um ciclo de QA por tarefa: pedido anterior ao veredito é descartado {#rn-806}

- **Regra:** o QA Lead roda UM ciclo por task. Pedido `{:run, task}` para a
  task cujo ciclo está suspenso esperando decisão é ignorado, e ao fim de um
  ciclo (veredito ou bloqueio) todo `{:run, task}` que esperava na caixa do
  processo é descartado — foi pedido antes de o veredito existir, e a
  correção legítima do dev só nasce depois dele. No uso real o resgate
  ([RN-722](parte-04.md#rn-722)) disparou o ciclo duas vezes no mesmo instante, e o
  segundo, rodando depois do aprovado, gravou um parecer contrário sobre a
  tarefa já mergeada. De FORA, declarado: duas réplicas do engine (a caixa é
  por processo, a mesma ressalva do `GateRescuer`) e a causa da dupla
  varredura do resgate, que não foi corrigida aqui.
- **Onde:** `apps/engine/lib/engine/gates/qa_lead_server.ex:106` (`handle_cast`),
  `apps/engine/lib/engine/gates/qa_lead_server.ex:157` (`descartar_pedidos_obsoletos`)
- **Teste:** `apps/engine/test/engine/gates/qa_lead_server_test.exs` ("pedido
  repetido que esperava na caixa é descartado ao fim do ciclo"; "pedido para a
  task com ciclo suspenso não abre um segundo")
- **Origem:** AT-478 (TP-01 de 10/10)

<a id="rn-810"></a>

### RN-810 — Falha de rede passageira do provider é retentada, e o bloqueio dela é `infra` sem contar no disjuntor {#rn-810}

- **Regra:** quando a chamada ao modelo volta com erro de REDE do provider —
  o `code` `connection`/`timeout` que a api normaliza (ADR 0041) ou, sem
  código, o texto do transporte (`EAI_AGAIN`, `ECONNRESET`, `ETIMEDOUT`,
  `ECONNREFUSED`, `ENOTFOUND`) —, o `ToolLoop` a retenta até duas vezes, com
  espera de 1 s e 3 s, gravando `toolloop.network_retry` a cada uma. Vale para
  todo consumidor do `ToolLoop` (dev agents e subagentes de gate). Esgotado o
  teto, a origem do desfecho é `infra`, nunca `codigo`, e o bloqueio da task
  do dev agent por essa causa NÃO incrementa o contador de bloqueios seguidos
  ([RN-047](parte-01.md#rn-047)): o agente segue reivindicando. No uso real um
  `getaddrinfo EAI_AGAIN openrouter.ai` de 17 s bloqueou duas tarefas como
  `codigo` e desarmou o dev. A correção pós-gate segue a mesma régua
  (AT-621, [RN-864](#rn-864)).
- **Onde:** `apps/engine/lib/engine/harness/tool_loop.ex:285`
  (`llm_turn_com_retentativa`), `apps/engine/lib/engine/agents/falha_de_turno.ex:119`
  (`falha_de_rede?`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1047`
  (`bloquear_parada`), `apps/engine/lib/engine/dev/agent_io.ex:228`
  (`finish_task`)
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs` ("falha de
  rede do provider: retenta e segue quando a rede volta"; "falha de rede que
  persiste esgota o teto"), `apps/engine/test/engine/dev/dev_agent_server_test.exs`
  ("erro de rede do provider: origem infra e o disjuntor não conta"),
  `apps/engine/test/engine/agents/falha_de_turno_test.exs`
- **Origem:** AT-484 (TP-01 de 10/10)

<a id="rn-811"></a>

### RN-811 — O "já na dev" compara com a `dev` do remoto atualizada {#rn-811}

- **Regra:** antes da checagem "já na dev" ([RN-797](#rn-797)) no
  `report_done`, o dev agent atualiza a `dev` do remoto pelo MESMO `fetch`
  que a [RN-779](#rn-779) faz no claim, serializado por projeto. Sem ele a
  comparação usava a `dev` do dia em que o worktree nasceu: a branch da task
  cujos commits já tinham entrado na `dev` remota pela PR de outra task passou
  por QA e SecOps com 0 arquivos. `fetch` que falha não decide nada — compara
  com o que há, e na dúvida a task segue para os gates.
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:418`
  (`sem_diff_contra_a_dev?`), `apps/engine/lib/engine/dev/worktree_manager.ex:438`
  (`sem_diff_atualizado?`), `apps/engine/lib/engine/dev/dev_agent_server.ex:931`
  (`handle_outcome`)
- **Teste:** `apps/engine/test/engine/dev/tarefa_ja_na_dev_test.exs` ("caminho
  feliz: com a dev atualizada, a branch não tem diff"; "falha: remoto
  inalcançável não fecha a task sozinha")
- **Origem:** AT-486 (TP-01 de 10/10)

<a id="rn-813"></a>

### RN-813 — Tarefa que toca o ponto de entrada exige evidência de que ele sobe {#rn-813}

- **Regra:** extensão do recorte da [RN-765](#rn-765). Quando o título ou a
  descrição da tarefa toca o ponto de entrada, a fiação (rotas, migração,
  registro) ou o README de execução, o recorte do gate de QA ganha a seção
  "Ponto de entrada": exigir evidência de que o entrypoint REAL sobe (o
  `start`/`main` do projeto rodado, ou um teste que importe o entrypoint real,
  não um app montado no próprio teste) e responde numa rota ou comando. Sem
  essa evidência, a lacuna vai para `itens`. É régua de PROMPT: o contrato
  externo dos gates (`apps/api/config/gates.yml`) e o código do `emit_qa_verdict` não
  mudam, e nenhum gate novo nasce. Tarefa que não toca nada disso não ganha a
  seção.
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:121`
  (`secao_do_ponto_de_entrada`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("tarefa que toca a fiação exige evidência do ponto de entrada real" e "tarefa
  que não toca entrypoint nem fiação não ganha a seção")
- **Origem:** AT-483 (TP-01 de 10/10: o `server.ts` nunca chamava a migração da
  tabela `links` e `/:code` sombreava `GET /links`; os 53 testes passavam porque
  cada um montava o próprio banco e app)

<a id="rn-814"></a>

### RN-814 — O parecer do QA lista todas as lacunas numa volta {#rn-814}

- **Regra:** extensão do recorte da [RN-765](#rn-765): o gate de QA lista em
  `itens` TODAS as lacunas da tarefa que achar na volta, de uma vez, nunca uma
  por volta — cada volta é uma correção paga e um passo do teto do ciclo. O
  prompt anterior só mandava listar "quais regras faltam", e lacuna que não era
  regra descoberta ficava para a volta seguinte. Régua de prompt.
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:20` (`texto`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs` ("o
  recorte pede todas as lacunas numa volta só")
- **Origem:** AT-487 (TP-01 de 10/10, tarefa `c7ced5a2`: duas reprovações por
  duas lacunas que já existiam na entrega original)

<a id="rn-817"></a>

### RN-817 — O QA roda a suíte em estado limpo, e teste pulado não é verde {#rn-817}

- **Regra:** extensão do recorte da [RN-765](#rn-765), para toda tarefa. Antes
  de rodar a suíte, o gate de QA encerra o que o PRÓPRIO projeto deixou de pé
  (servidor do `start` escutando numa porta do projeto), só processos daquela
  pasta, nunca de fora. Teste que sobe processo deve encerrar o GRUPO (ou
  subir `node` direto, não via `npm`); o que não encerra trava a suíte num
  clone limpo e é lacuna em `itens`. Teste que se PULOU por ambiente (porta
  ocupada, ferramenta ausente) não conta como verde: vai ao `resumo` como
  observação. É instrução do recorte, não passo do harness: quem roda a suíte
  é o próprio QA pelo `terminal`, que já passa pela política e pelo
  roteamento de container dos três modos — um `pkill` no harness precisaria
  de um segundo caminho de execução por modo. Régua de prompt; o contrato dos
  gates não muda.
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:178`
  (`secao_do_ambiente_limpo`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("RN-817: pede ambiente limpo, encerrar o grupo e pulado como observação")
- **Origem:** AT-496 (TP-01 de 10/10: `npm test` travava num clone limpo — o
  teste matava o `npm` e o `node` neto ficava na 3000 —, e no container o QA
  viu exit 0 porque o teste se pulava com a porta ocupada por um servidor
  órfão)

<a id="rn-818"></a>

### RN-818 — A evidência do ponto de entrada é a que o ambiente do dev produz {#rn-818}

- **Regra:** extensão da [RN-813](#rn-813). A seção "Ponto de entrada" diz o
  que CONTA como evidência no ambiente do dev — subir o processo do
  entrypoint na pasta do projeto, rodar o script no container do projeto,
  bater numa rota do processo de pé — e o que NÃO cabe ali: construir imagem
  Docker, `docker compose`, rede externa. Exigência desse segundo tipo nunca
  vai para `itens`; vai ao `resumo` como observação. Régua de prompt.
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:121`
  (`secao_do_ponto_de_entrada`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("RN-818: com ponto de entrada diz o que conta e o que não cabe" e "RN-818:
  sem ponto de entrada não traz a régua de evidência")
- **Origem:** AT-492 (TP-01 de 10/10, task `c708f8b2`: a 4ª volta exigiu
  construir a imagem a partir do Dockerfile, o container do projeto não tem
  Docker, e o ciclo esgotou em bloqueio `politica`)

<a id="rn-819"></a>

### RN-819 — O QA varre regra por regra antes de emitir {#rn-819}

- **Regra:** extensão da [RN-814](#rn-814). Além de listar todas as lacunas, o
  recorte pede uma VARREDURA POR REGRA antes de emitir: percorrer cada regra
  de negócio e cada critério da tarefa, um por um, apontando onde está a prova
  ou que ela falta, e só emitir depois de passar por todas. "Liste todas"
  sozinho não segurou lacuna pré-existente aparecendo na volta seguinte.
  Régua de prompt.
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:20` (`texto`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("RN-819: pede varredura por regra antes de emitir")
- **Origem:** AT-490 (TP-01 de 10/10: tarefas 2 e 11 trouxeram na 2ª volta
  lacuna que já estava na entrega)

<a id="rn-823"></a>

### RN-823 — O ciclo de gate que o reinício do engine matou é retomado no boot, e o fio diz isso {#rn-823}

- **Regra:** no BOOT do engine, a linha `in_progress` de `gate_states`
  RECENTE (abaixo de `gate_rescue_stale_after_seconds`, 15 min, e por isso
  invisível para o tick) sem processo vivo NESTE nó nem nos OUTROS nós do
  cluster é órfã do reinício, não um ciclo lento: o boot a retoma na hora
  (`Dispatcher.run_qa`/`run_secops`), sem esperar o limiar. "Vivo" é a régua da
  [RN-722](parte-04.md#rn-722) (a task em voo no lead), perguntada também aos outros nós
  por `:erpc.multicall` — nó que não responde conta como VIVO, a régua do
  `TurnoOrfao` ([RN-586](parte-03.md#rn-586)). Valem as guardas de sempre: ação pendente
  de ator do gate não reinicia, e dev dono ausente só apaga a linha. Antes de
  redespachar, o boot grava `gate.interrupted` no log da sessão (`taskId`,
  `gate`, `ultimaAtividadeEm`, `retomadoEm`), e o fio o mostra como aviso, nos
  dois idiomas. O tick periódico NÃO muda: fora do boot, linha recente é ciclo
  em voo. Resíduo declarado: nó que ainda não entrou no cluster no instante do
  boot não é perguntado, e o pior desfecho é o de sempre (trabalho duplicado e
  barato; o segundo veredito é recusado pela api).
- **Onde:** `apps/engine/lib/engine/gates/gate_rescuer.ex:231` (`run_boot`),
  `:240` (`interrompido_no_boot`),
  `apps/web/src/routes/RetomarGateEstacionado.helpers.ts:21` (`cicloInterrompido`)
- **Teste:** `apps/engine/test/engine/gates/gate_rescuer_test.exs` ("boot com
  ciclo RECENTE órfão do reinício: grava gate.interrupted e retoma já
  (RN-823)"; falhas: "boot com ciclo recente esperando ação PENDENTE do gate:
  não reinicia nem grava (RN-823)" e o processo local vivo intocado),
  `apps/web/src/routes/RetomarGateEstacionado.test.tsx` ("cicloInterrompido
  (RN-823)")
- **Origem:** AT-495 (TP-01 de 10/10: o reinício das 18:51 matou o ciclo de QA
  da tarefa 10, e o dev ficou `awaiting_gate` 15 min sem tela nenhuma dizer)

**Revisada pela [RN-923](parte-06.md#rn-923) ([ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md)).** A retomada do boot conta como a automática do ciclo (`auto_resumes`): se o ciclo já usou a sua, o boot o estaciona em vez de redespachá-lo, e o subagente retomado leva o plano do último `agent.turn_resumed`.

<a id="rn-832"></a>

### RN-832 — O dev agent sabe que `report_done` faz commit, push e PR, e que teste novo entra no script `test` {#rn-832}

- **Regra:** o dev agent não tem nem precisa de `git_commit`, `git_push` ou
  `pr_open`: commit, push e PR acontecem quando ele chama `report_done`. A
  descrição de `report_done`, a de `report_blocked` ("falta ferramenta de git"
  não é motivo de bloqueio), o kickoff do dev agent e a mensagem de ambiente
  ([RN-706](parte-04.md#rn-706)) dizem isso — a de ambiente mandava, até aqui, usar as
  ações tipadas de git, que o dev não tem. O kickoff e o ambiente dizem também
  que, se o script `test` do `package.json` lista arquivos um a um, todo
  arquivo de teste novo entra nele. Só texto: nenhuma regra nova de código, e
  o Jev segue sem piso para dev agents ([RN-758](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-758)) — até a [RN-839](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-839), que pôs `report_done`/`report_blocked` no piso deles.
- **Onde:** `apps/engine/lib/engine/dev/tools/report_done.ex:16` (`spec`),
  `apps/engine/lib/engine/dev/tools/report_blocked.ex:12` (`spec`),
  `apps/engine/lib/engine/dev/dev_agent_server.ex:666` (`initial_message`),
  `apps/engine/lib/engine/harness/ambiente_do_agente.ex:102` (`montar`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs`
  ("caminho feliz: report_done, kickoff e ambiente carregam as duas
  instruções"; falha: "o ambiente não manda mais usar as ações tipadas de git")
- **Origem:** AT-499 (TP-01, 11ª: tarefa bloqueada com a suíte verde por
  "git_commit não existe"; quatro voltas de QA por teste fora do script `test`)

<a id="rn-845"></a>

### RN-845 — A leitura das ADRs propostas diz se a PR já foi mergeada {#rn-845}

- **Regra:** na linha de uma ADR `executed`, `listar_adrs_propostas`
  ([RN-772](#rn-772)) não afirma mais "PR aberta" pelo status da AÇÃO: cruza o
  `pullRequestId` do resultado com o `git_merge` EXECUTADO do mesmo projeto
  (a ação pela qual todo merge passa, [RN-418](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-418)) e diz "PR MERGEADA em
  <data da decisão>" ou "PR aberta (nenhum merge dela registrado no Brabo)".
  Resultado sem id de PR, ou consulta de merge que falha, vira "estado da PR:
  NÃO CONSEGUI LER" — nunca "aberta". Contida (ADR 0060): uma consulta a mais,
  só sobre os ids listados, no mesmo Postgres. Limite declarado: PR fechada
  sem merge FORA do Brabo (no provider remoto) não é vista, e segue lida como
  aberta — perguntar ao provider seria HTTP no laço do agente.
- **Onde:** `apps/engine/lib/engine/harness/tools/listar_adrs_propostas.ex:88`
  (`cruzar_com_merges`), `:102` (`merges_por_pr`), `:155` (`estado_da_pr`).
- **Teste:** `apps/engine/test/engine/harness/tools/listar_adrs_propostas_test.exs`
  ("PR mergeada aparece como mergeada…", "estado da PR ilegível diz que não
  leu, nunca aberta").
- **Origem:** AT-514 (TP-01, 11/10: o Arquiteto disse "aberta como PR" 30 s
  depois do merge).

<a id="rn-846"></a>

### RN-846 — A rota HTTP vai ao README e o erro de entrada é do projeto {#rn-846}

- **Regra:** extensão da [RN-819](#rn-819). O kickoff do dev agent de
  execução pede que rota HTTP criada ou mudada entre no README (método,
  caminho, corpo, respostas e códigos) e que erro de entrada (JSON malformado,
  campo inválido) responda com mensagem própria no formato do projeto, nunca a
  mensagem crua da biblioteca. O recorte do QA confere as duas coisas na
  varredura por regra, e o que faltar vai a `itens`. Régua de prompt.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:666`
  (`initial_message`) e `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:20`
  (`texto`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs`
  ("RN-846: kickoff pede a rota no README e erro de entrada próprio") e
  `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs` ("RN-846: confere
  rota no README e erro de entrada próprio")
- **Origem:** AT-515 (TP-01, 12ª: o README não documentava a API, e JSON
  malformado respondia 400 com "Expected property name…" do parser)

<a id="rn-849"></a>

### RN-849 — O turno de prontidão da arquitetura abre com o estado atual das ADRs {#rn-849}

- **Regra:** extensão da [RN-845](#rn-845). Quando o usuário confirma que a
  arquitetura está pronta, o servidor do Arquiteto LÊ o estado das ADRs pelo
  mesmo código de `listar_adrs_propostas` (Postgres local, sem HTTP, mesmo teto
  de 20 linhas) e o põe na mensagem de abertura desse turno, com a instrução de
  não afirmar estado de ADR diferente. Leitura que falha diz "NÃO CONSEGUI LER"
  e manda dizer que não sabe — nunca "pendente".
- **Onde:** `apps/engine/lib/engine/harness/tools/listar_adrs_propostas.ex:50`
  (`contexto_de_prontidao`), `apps/engine/lib/engine/agents/arquiteto_server.ex:223`
  (`contexto_de_prontidao`).
- **Teste:** `apps/engine/test/engine/harness/tools/listar_adrs_propostas_test.exs`
  ("contexto_de_prontidao/2 (RN-849)").
- **Origem:** AT-519 (TP-01: no turno de prontidão o Arquiteto disse "pendente
  de aprovação" sobre ADR já mergeada, repetindo a leitura do turno anterior).

<a id="rn-850"></a>

### RN-850 — A rota entra na seção "Rotas HTTP" e o README não leva nota de processo {#rn-850}

- **Regra:** extensão da [RN-846](#rn-846). O kickoff do dev agent pede que a
  rota entre DENTRO da seção "Rotas HTTP" do README (criada antes de "Testes"
  se faltar), nunca no fim do arquivo, e que o README, que é do usuário, não
  ganhe nota de processo nem instrução para agentes. O recorte do QA confere
  as duas coisas. Régua de prompt.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:666`
  (`initial_message`) e `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:20`
  (`texto`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs`
  ("RN-850: a rota vai dentro de Rotas HTTP e o README não leva nota de
  processo") e `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("RN-850: confere a seção Rotas HTTP e a ausência de nota de processo")
- **Origem:** AT-520 (TP-01: cada tarefa acrescentou rotas no fim do README,
  depois de "Testes", e sobrou um parágrafo de processo para agentes)

<a id="rn-851"></a>

### RN-851 — O compose da Infra sobe o APP na máquina do usuário, e a PR declara como rodá-lo {#rn-851}

- **Regra:** o kickoff do Infra Lead pede o compose que SOBE O APP (não só
  ambiente de dev): `build` do Dockerfile de cada módulo com `FROM` = a imagem
  decidida (`projectImage` do contexto da Infra; sem ela, a candidata do
  roteamento, dito no README), porta `${APP_PORT:-8080}:<porta interna>`, volume
  para dados persistentes, `.env.example` commitado (nunca `.env`) e a seção
  "Rodar na sua máquina" no README. O container de TRABALHO dos agentes segue
  subindo pelo broker, e não há deploy. `propose_infra_pr` ganha o campo
  OBRIGATÓRIO `run` (`command` até 300 caracteres; `urls` de 1 a 5, `label` até
  60, `kind` em `api_docs | web`, `url` começando com `http://localhost:` ou
  `http://127.0.0.1:`; `envExample` booleano), validado no engine ANTES do HALT
  com recusa nomeada que entra no laço (RN-163) e repassado no
  payload de `open_infra_pr`. Decisão no [ADR 0213](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0213-o-entregavel-roda-na-maquina-pelo-compose-da-infra.md).
- **Onde:** `apps/engine/lib/engine/infra/instrucoes_de_execucao.ex:27`
  (`validar`), `apps/engine/lib/engine/infra/infra_lead_server.ex:1414`
  (`build_kickoff`) e `:1327` (`abrir_pr`), e
  `apps/engine/lib/engine/infra/tools/propose_infra_pr.ex:24` (`spec`)
- **Teste:** `apps/engine/test/engine/infra/infra_lead_server_test.exs`
  (describe "o compose sobe o app e a PR leva `run` (RN-851)")
- **Origem:** AT-517 (o entregável não tinha como ser rodado pelo usuário)

<a id="rn-853"></a>

### RN-853 — O dev expõe OpenAPI e Swagger quando a tarefa toca rotas {#rn-853}

- **Regra:** parte do ADR 0213. Quando a
  tarefa toca ponto de entrada ou rotas (a MESMA régua do recorte do QA,
  `toca_ponto_de_entrada?`, nunca uma cópia), o kickoff do dev ganha a
  cláusula: módulo que expõe HTTP serve `/openapi.json` (OpenAPI 3) e `/docs`
  (UI Swagger); sem rede ou sem pacote, `/docs` é página HTML que carrega o
  swagger-ui de CDN; módulo web serve a página inicial; a URL entra na seção
  "Rodar na sua máquina" do README. Tarefa que não toca rotas não paga a
  cláusula (a mensagem é fixada e volta a cada iteração).
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:698`
  (`clausula_de_openapi`),
  `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:113`
  (`toca_ponto_de_entrada?`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs`
  ("RN-853: tarefa que toca rotas pede /openapi.json e /docs"; falha: "RN-853
  falha: tarefa sem rota nem entrypoint não paga a cláusula")
- **Origem:** AT-517

<a id="rn-854"></a>

### RN-854 — O QA prova `/openapi.json` e `/docs` dentro do container {#rn-854}

- **Regra:** parte do ADR 0213. Na seção
  de ponto de entrada do recorte ([RN-813](#rn-813)), o QA sobe o app pelo
  comando do README em background DENTRO do container, bate em
  `localhost:<porta interna>/openapi.json` e `/docs` (`curl`, `wget` ou
  `node -e fetch`) e encerra o grupo de processos ([RN-817](#rn-817)). Falha
  vai a `itens`; o `docker compose up` real fica no `resumo` como "provado só
  na máquina do usuário".
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:121`
  (`secao_do_ponto_de_entrada`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("tarefa que toca rotas pede /openapi.json e /docs, compose em resumo";
  falha: "falha: tarefa sem rota não recebe a seção")
- **Origem:** AT-517

<a id="rn-862"></a>

### RN-862 — A pergunta em aberto do lado do engine: ferramenta, veredito e decisão no contexto {#rn-862}

- **Regra:** o Criativo, o PO, o Arquiteto e o Dev Lead declaram toda dúvida
  deixada para o usuário com `declare_open_question` (`pergunta` até 500,
  `sugestao` até 300 opcional, `afeta: {regras, historias, tarefas}`), que
  grava `artifact.open_question` com `questionId` (uuid), `autor` e
  `sessionId`; payload inválido é recusa nomeada e não grava. A instrução é UMA
  frase central, no texto do fluxo dos quatro (RN-711), nunca por servidor. No
  gate de QA, requisito "não confirmado pelo usuário" (ou contradito por decisão
  vigente) é `needs_user_decision`, nunca `changes_requested`:
  `emit_qa_verdict` o aceita só com `pergunta` ou `openQuestionId`, o QA Lead o
  consolida acima de `approved`, o veredito vai à api com a pergunta e o ciclo
  fica ESTACIONADO (ADR 0207, `gate.rescue_parked`, sem resgate automático)
  até a api pedir a retomada pela rota da RN-724. As `decisoes` do dev-context
  entram no kickoff do dev e no recorte do QA como "Decisões registradas
  para esta tarefa/módulo — vencem RF/DoR quando conflitam" (`pergunta → decisao`); vazio não escreve
  nada. A pergunta gravada conta no fecho do turno (RN-731), e o PO passa
  `question_id` em `update_story`/`complete_story` quando corrige a história a
  partir de uma resposta ([ADR 0214](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0214-pergunta-em-aberto-vira-pendencia.md)).
- **Onde:** `apps/engine/lib/engine/harness/tools/declare_open_question.ex:54` (`run`),
  `apps/engine/lib/engine/harness/fluxo_do_time.ex:116` (`frase_da_pergunta`),
  `apps/engine/lib/engine/gates/tools/emit_qa_verdict.ex:81` (`run`),
  `apps/engine/lib/engine/gates/qa_lead.ex:89` (`consolidar_decisao`),
  `apps/engine/lib/engine/gates/qa_lead_server.ex:595` (`estacionar_por_decisao`),
  `apps/engine/lib/engine/dev/context_builder.ex:121` (`secao_de_decisoes`)
- **Teste:** `apps/engine/test/engine/harness/perguntas_em_aberto_test.exs`
  ("válida grava artifact.open_question…"; "inválida é recusa nomeada…";
  "consolidação: needs_user_decision vence approved"; "o recorte diz a régua…";
  "ContextBuilder: a história leva as decisões…"),
  `apps/engine/test/engine/gates/qa_lead_server_test.exs` ("grava a pergunta
  na api, estaciona o ciclo e só o gesto humano o retoma")
- **Origem:** AT-521, [ADR 0214](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0214-pergunta-em-aberto-vira-pendencia.md)

<a id="rn-863"></a>

### RN-863 — `api_docs` é sempre `/docs`, toda rota entra no OpenAPI, e o QA reprova a que falta {#rn-863}

- **Regra:** módulo HTTP declara em `run.urls` SEMPRE `/docs` (a UI Swagger,
  `kind: "api_docs"`) mesmo antes de existir, e módulo web a página inicial —
  nunca uma rota de negócio; o kickoff da Infra diz isso no passo do README
  (estende a RN-851). A validação do `run` recusa, nomeada e com a MESMA régua
  nos dois lados, `api_docs` cuja URL não termina em `/docs` (estende a
  RN-852). A cláusula do dev diz que TODA rota HTTP criada ou mudada na tarefa
  entra no `/openapi.json` — path com método, corpo e respostas (estende a
  RN-853). No recorte do QA, cada rota da seção "Rotas HTTP" do README precisa
  estar em `paths` do `/openapi.json` servido; rota faltando é item que
  reprova, nunca observação (estende a RN-854).
- **Onde:** `apps/engine/lib/engine/infra/instrucoes_de_execucao.ex:60` (`url`),
  `apps/api/src/domain/infra/run-instructions.ts:77` (`recusaDoRun`),
  `apps/engine/lib/engine/infra/infra_lead_server.ex:1414` (`build_kickoff`),
  `apps/engine/lib/engine/dev/dev_agent_server.ex:698` (`clausula_de_openapi`),
  `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:20` (`texto`)
- **Teste:** `apps/engine/test/engine/infra/infra_lead_server_test.exs`
  ("run api_docs em rota de negócio é recusado com motivo, sem propor"),
  `apps/api/test/application/use-cases/execution/get-run-instructions.use-case.spec.ts`
  ("recusaDoRun (RN-852)"),
  `apps/engine/test/engine/dev/report_done_instrucao_test.exs` ("RN-853: …"),
  `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs` ("RN-854: …")
- **Origem:** AT-524, [ADR 0213](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0213-o-entregavel-roda-na-maquina-pelo-compose-da-infra.md)

<a id="rn-864"></a>

### RN-864 — Falha passageira de rede volta sozinha em até 3 tentativas, e o dev pausa {#rn-864}

- **Regra:** a task bloqueada pelo dev agent com origem `infra` por falha
  PASSAGEIRA de rede/provedor — lista de permitidos explícita: DNS
  (`EAI_AGAIN`, `ENOTFOUND`, `getaddrinfo`), `ECONNRESET`, `ETIMEDOUT`,
  `aborted`, HTTP 5xx/429 do provedor (códigos `rate_limit`/`upstream`,
  `connection`/`timeout`) — é RETOMADA sozinha até 3 vezes, depois de 1, 3 e
  10 min (decisão do dono), por um job Oban que chama o MESMO desbloqueio do
  humano (`UnblockTaskUseCase`, pela rota interna `.../tasks/:taskId/unblock`,
  ator `system`, no-op se a task já não está bloqueada). O motivo do bloqueio
  diz qual retomada foi agendada; depois da 3ª retomada a falha seguinte fica
  bloqueada como antes, e o motivo diz que as 3 já foram tentadas. E o agente
  PAUSA 1 min em vez de pegar a próxima task (o wake é ignorado durante a
  pausa). Crédito esgotado (402, RN-726/730) e erro de código NÃO entram:
  bloqueiam na hora. O contador de retomadas é só em memória: reiniciar o
  engine o zera. Vale também para a correção pós-gate (AT-621): o 503 do
  provider numa correção segue o mesmo caminho do laço principal (crédito
  RN-726 + retomada), com o motivo marcado "(correção)".
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:843`
  (`handle_correction_outcome`), `apps/engine/lib/engine/agents/falha_de_turno.ex:140`
  (`passageira?`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1075`
  (`bloquear_passageira`), `apps/engine/lib/engine/dev/agent_io.ex:302`
  (`pausar_por_rede`), `apps/engine/lib/engine/workers/retomada_de_tarefa_worker.ex:33`
  (`agendar`), `apps/api/src/application/use-cases/execution/unblock-task.use-case.ts:33`
  (`ator`)
- **Teste:** `apps/engine/test/engine/dev/dev_agent_server_test.exs` ("falha
  passageira: agenda a retomada, pausa e não queima a fila", "fim da pausa
  volta a reivindicar"; falha: "falha passageira depois de 3 retomadas fica
  bloqueada pedindo o clique", "402 não agenda retomada"; correção: "correção
  com 503: infra, retomada agendada, pausa e disjuntor intacto", "correção sem
  crédito: pausa por crédito, sem retomada", "correção com erro não
  passageiro: bloqueia na hora, sem retomada"),
  `apps/engine/test/engine/workers/retomada_de_tarefa_worker_test.exs`
- **Origem:** AT-525

<a id="rn-865"></a>

### RN-865 — Endpoint e verbo HTTP com caminho também ligam a conferência do OpenAPI, e ela cobre as rotas do código {#rn-865}

- **Regra:** a régua única de "a tarefa toca ponto de entrada/rotas"
  (`toca_ponto_de_entrada?`, usada pelo recorte do QA e pela cláusula do dev da
  RN-853) casa também "endpoint" e verbo HTTP seguido de caminho
  (`POST /links`). Sem isso, tarefa descrita como "Endpoint protegido…" não
  recebia nem a cláusula do OpenAPI (dev) nem a conferência do `/openapi.json`
  (QA) — foi assim que `POST /links` e `GET /panel` ficaram fora do OpenAPI
  com as duas tarefas aprovadas no TP-01. A conferência do QA passa a exigir em
  `paths` do `/openapi.json` servido, além das rotas da seção "Rotas HTTP" do
  README, cada rota que o CÓDIGO registra; a que falta é item que reprova
  (estende a RN-863).
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:103`
  (`@ponto_de_entrada`), `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:114`
  (`toca_ponto_de_entrada?`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("RN-865: tarefa que diz só endpoint ou verbo com caminho recebe a seção";
  falha: "falha: tarefa sem rota não recebe a seção")
- **Origem:** AT-527

<a id="rn-868"></a>

### RN-868 — O tick do resgate de gates é uma corrente só {#rn-868}

- **Regra:** o `GateRescueSchedulerWorker` reagenda o próprio sucessor com a
  MESMA unicidade do `kickoff/0` (estados `available`/`scheduled`/`retryable`,
  sem `executing`, janela de dois intervalos). Antes só o `kickoff/0` era
  único: o job em execução não conta, então o kickoff do boot com o tick
  anterior em voo, ou um retry que re-roda o `perform/1`, abria uma SEGUNDA
  corrente, e elas nunca se fundiam. Medido no uso real (14/10): 11 jobs
  agendados ao mesmo tempo e a linha "espera decisão humana" da RN-722 11
  vezes por tick para UMA linha de `gate_states`. Não era defeito de dado. Com
  a unicidade no reagendamento as correntes duplicadas colapsam numa só no
  tick seguinte.
- **Onde:** `apps/engine/lib/engine/workers/gate_rescue_scheduler_worker.ex:42`
  (`unicidade`)
- **Teste:** `apps/engine/test/engine/workers/gate_rescue_scheduler_worker_test.exs`
  ("o tick se reagenda e mantém a corrente viva"; falha: "com um sucessor já
  agendado, o tick não abre uma segunda corrente")
- **Origem:** AT-529

<a id="rn-874"></a>

### RN-874 — O PO recebe no turno as decisões do usuário e as perguntas abertas do projeto {#rn-874}

- **Regra:** todo turno do PO leva, como mensagem `system` EFÊMERA
  acrescentada pela fachada `EngineApiClient` logo depois do fluxo do time
  (RN-711) — nunca em `state.messages` nem no prompt do servidor —, as
  decisões do usuário (`artifact.decision_record`, `choice` e `context`) e as
  perguntas AINDA abertas do projeto (`artifact.open_question` sem
  `open_question.answered` com o mesmo `questionId`), de TODAS as sessões. O
  texto manda escrever a RESPOSTA decidida na história, regra, DoR, DoD e
  tarefa, nunca "pergunta em aberto N"; pergunta ainda aberta é citada pelo
  `questionId`, sem inventar resposta. A leitura é LOCAL (Postgres direto, sem
  HTTP no laço), dos 200 eventos mais recentes desses tipos, com teto de 10
  decisões, 10 perguntas, 240 caracteres por item e 3 000 no texto. As
  perguntas abertas vêm ANTES das decisões e o corte é por linha inteira
  (revisado pela [RN-1058](parte-06.md#rn-1058)). Sem
  decisão nem pergunta aberta, ou com a leitura falhando, o turno segue sem a
  mensagem, nunca cai. Só o `po` recebe. Cada decisão leva o seu
  `questionId` e as histórias de `afeta.historias`, para o PO citar o id em
  `complete_story`/`update_story` e corrigir uma história `ready` (RN-859, AT-752).
- **Onde:** `apps/engine/lib/engine/harness/decisoes_do_projeto.ex:34`
  (`anexar`), `:49` (`texto`),
  `apps/engine/lib/engine/session_events/event.ex:224`
  (`list_types_for_project`),
  `apps/engine/lib/engine/sessions/engine_api_client.ex:753`
  (`DecisoesDoProjeto`)
- **Teste:** `apps/engine/test/engine/harness/decisoes_do_projeto_test.exs`
  ("o turno do PO leva a decisão e só a pergunta AINDA aberta", "a decisão sai
  com o questionId e as histórias de afeta", "custo de
  entrada tem teto"; falha: "sem decisões nem perguntas não acrescenta nada",
  "leitura que falha deixa o turno sem a mensagem, sem queda")

<a id="rn-876"></a>

### RN-876 — O `needs_user_decision` recusado pela api volta ao QA, e só o aceite estaciona o gate {#rn-876}

- **Regra:** o gate de QA só ESTACIONA (`gate.rescue_parked`) quando a api
  aceita o veredito `needs_user_decision` com `nextAction: "await_user"`. Se a
  api RECUSA (400, 404, ou o 409 `pergunta_ja_respondida`), a recusa volta ao
  laço da QA de Automação como mensagem nova (RN-163: erro é entrada do laço),
  retomando o MESMO contexto em que ela emitiu — no 409, com a decisão já
  tomada para o QA aplicar em vez de perguntar de novo. As outras delegações
  não rodam de novo. A volta conta no teto de iterações do próprio laço;
  esgotado, a tarefa é bloqueada com o motivo e a origem `modelo` (RN-059),
  nunca estacionada em silêncio. Antes, o retorno da api era descartado e o
  gate estacionava sem pergunta no fio (medido: `openQuestionId: "1"`, 400 do
  `@IsUUID`). A ferramenta `emit_qa_verdict` recusa, DENTRO do laço e antes da
  api, `openQuestionId` que não é uuid.
- **Onde:** `apps/engine/lib/engine/gates/qa_lead_server.ex:601`
  (`devolver_ao_qa`), `apps/engine/lib/engine/gates/qa_lead_server.ex:312`
  (`devolver_ao_qa`), `apps/engine/lib/engine/gates/qa_lead_server.ex:697`
  (`texto_da_recusa`), `apps/engine/lib/engine/gates/qa_automacao_agent.ex:186`
  (`devolver`), `apps/engine/lib/engine/gates/tools/emit_qa_verdict.ex:75`
  (`uuid`)
- **Teste:** `apps/engine/test/engine/gates/qa_lead_server_test.exs` ("400:
  nada estaciona, o QA recebe o motivo e uma nova volta acontece"; "409 no
  laço: a volta seguinte do QA lê a decisão"; falha: "teto esgotado depois da
  recusa: bloqueio narrado, nunca estacionamento"),
  `apps/engine/test/engine/harness/perguntas_em_aberto_test.exs` ("AT-526
  (RN-876): openQuestionId que não é uuid é recusa nomeada; uuid passa")
- **Origem:** AT-526

<a id="rn-877"></a>

### RN-877 — O recorte do QA manda conferir as decisões antes de pedir decisão {#rn-877}

- **Regra:** a instrução do recorte do QA diz que, antes de
  `needs_user_decision`, ele confere as decisões listadas; requisito que uma
  delas já responde não é pergunta e a decisão se aplica. `openQuestionId` só
  com o uuid de uma pergunta ABERTA; sem ele, a pergunta nova vai em
  `pergunta`/`sugestao`. É lembrete de leitura: não muda a régua do veredito.
- **Onde:** `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:20` (`texto`)
- **Teste:** `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("AT-526 (RN-877): manda conferir as decisões antes de needs_user_decision";
  a falha da instrução é coberta pelo teste da RN-876 da ferramenta)
- **Origem:** AT-526

<a id="rn-878"></a>

### RN-878 — O idioma do agente de execução vale desde a primeira frase {#rn-878}

- **Regra:** nos turnos SEM autor humano dos agentes de execução (`dev-*`,
  `qa-*`), a orientação de idioma da RN-622 diz que vale desde a PRIMEIRA
  frase, inclusive a narração antes de cada ferramenta, e perde a ressalva
  "salvo pedido do usuário" (não há usuário no turno). Medido na sessão
  `6c68fbc0` (projeto pt-BR, `anthropic/claude-haiku-5.5`): a orientação
  chegava, e mesmo assim a iteração 0 do `qa-automacao` e do
  `dev-encurtador-api` abria em inglês ("I'll start by running…"). O caminho
  continua UM (a fachada, RN-622): nada em prompt de servidor,
  `agent_instructions` ou descrição de ferramenta (RN-667). O teto de 50 tokens
  (AT-169) segue: medido com `gpt-tokenizer`, `pt-BR` 32/26, `en` 19/19 e o
  genérico com código na forma curta no pior caso 30/30 (cl100k/o200k); código
  fora da forma curta cai na orientação de sempre, que já cabia. Turno com
  autor e os conversacionais não mudam. Sem idioma resolvido, nada é
  acrescentado. A eficácia se mede no próximo TP-01.
- **Onde:** `apps/engine/lib/engine/harness/idioma_da_resposta.ex:164`
  (`orientacao_de_execucao`), `:154` (`agente_de_execucao?`)
- **Teste:** `apps/engine/test/engine/harness/idioma_da_resposta_test.exs`
  ("agente de execução: vale desde a primeira frase, dentro do teto"; falha:
  "agente de execução sem idioma resolvido: nada é acrescentado")
- **Origem:** AT-530

<a id="rn-879"></a>

### RN-879 — URL absoluta do entregável com a porta, e o mesmo `code` para o mesmo erro {#rn-879}

- **Regra:** quando a tarefa toca ponto de entrada ou rotas, a cláusula do dev
  manda que URL absoluta devolvida pela API do entregável (ex.: o link curto)
  venha de `PUBLIC_BASE_URL` ou do `Host` da requisição COM a porta — nunca
  `http://localhost` fixo nem o hostname sem porta —, e que o mesmo caso de
  erro responda o mesmo `code` em todas as rotas. O recorte do QA confere as
  duas coisas e trata a divergência (ex.: `not_found` × `link_not_found`)
  como ITEM. Decisão do dono de 14/10: regra geral.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:698` (`clausula_de_openapi`);
  `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:122` (`secao_do_ponto_de_entrada`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs`
  ("RN-879/880: tarefa que toca rotas leva URL com porta, code único e CORS" e
  a falha "RN-879/880 falha: tarefa sem rota não recebe CORS nem PUBLIC_BASE_URL");
  `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs` ("RN-879/880: URL,
  code de erro e CORS")
- **Origem:** AT-531
