---
id: rn-engine-parte-04
title: 'Regras de negócio — Engine — parte 4 (desde RN-622)'
sidebar_label: 'Engine — parte 4 (desde RN-622)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

# Engine — parte 4 (desde RN-622)

## O idioma das respostas dos agentes (RN-618..620, RN-622..624, ADR 0177)

<a id="rn-622"></a>

### RN-622 — O idioma chega ao modelo como a ÚLTIMA mensagem de cada chamada do turno, efêmera: o do AUTOR quando há um, o do PROJETO quando não há {#rn-622}

As RN-618..620 decidiram EM QUE idioma o agente responde e mostraram isso na
tela; nada disso chegava ao modelo. Esta regra é o transporte (AT-164, sobre a
especificação da AT-081 e o mecanismo verificado por provider na AT-161).

1. **Uma mensagem `role: "system"` no FIM da lista, a cada chamada de LLM do
   turno** — inclusive as iterações de ferramenta —, e NUNCA no histórico:
   ela não entra em `state.messages`, então não se acumula de turno em turno,
   não é resumida pela compactação ([RN-621](parte-03.md#rn-621)) e some com o turno. No
   OpenAI-compatível ela vai no fim da conversa; no Anthropic é içada para o
   fim do `system` do topo (AT-161). Não é `agent_instructions`: é texto de
   código, fora do teto de `instruction_patch` ([RN-007](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-007)).
2. **Um lugar só.** Quem acrescenta é a fachada `EngineApiClient`
   (`llm_turn/5` e `llm_turn_stream/6`), por onde passa TODA chamada de LLM do
   engine — os sete conversacionais, o `ToolLoop` (dev agents e gates) e o
   Infra Lead. Nenhum servidor monta a orientação.
3. **Turno COM autor humano** (a mensagem que alguém digitou a um agente): a
   api resolve o idioma DAQUELA pessoa naquela sessão
   (`ResolverIdiomaDaRespostaUseCase`, [RN-618](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-618) — override da sessão
   > conta > detectado confirmado > interface) e o manda no comando
   `agent/message` como `idiomaDaResposta`, campo OPCIONAL. O servidor do
   agente o põe no estado do TURNO durante o `handle_call`, e a Task do turno
   o herda do dicionário de processo (`TurnoAssincrono`); o GenServer não o
   guarda para o turno seguinte. Dois autores na mesma sessão recebem cada um
   o seu.
4. **Turno SEM autor humano** (kickoff, dev agents, gates, commit, corpo de
   PR, a retomada do Dev Lead depois da aprovação): o idioma do PROJETO
   ([RN-619](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-619)), lido de `projects.language` a cada chamada (decisão do
   mantenedor, AT-169 resposta 1).
5. **O sumarizador da compactação (`context-manager`) fica fora**: "responda
   em X" traduziria o resumo, e preservar o idioma de cada turno nele é a
   [RN-621](parte-03.md#rn-621).
6. **Falha nunca derruba o turno.** A resolução que falha na api vira log e a
   mensagem segue SEM `idiomaDaResposta`; turno com autor sem idioma segue
   SEM orientação — nunca o do projeto no lugar do da pessoa. A leitura do
   idioma do projeto que falha no engine vira `warning` e a chamada segue sem
   orientação. Valor que não tem forma de código BCP-47 também não vira
   orientação: nada que não seja um código é interpolado no prompt.
7. **Os textos** são constantes de código, um por idioma: `pt-BR` ("Responda
   em português brasileiro (pt-BR), salvo pedido explícito do usuário por
   outro idioma nesta mensagem."), `en`, e um genérico em inglês que nomeia o
   código BCP-47 para qualquer outro idioma da lista aberta (AT-168
   resposta 2). O texto não depende do modelo: trocar de modelo no meio da
   sessão não muda nada, e não há cascata por modelo nem caso especial de
   DeepSeek.
8. **Custo** — teto decidido de 50 tokens de ENTRADA por chamada (AT-169
   resposta 8). Medido com `gpt-tokenizer`, só o conteúdo, cl100k / o200k:
   `pt-BR` 29 / 23, `en` 18 / 18, genérico `es-MX` 26 / 26 e o PIOR caso (o
   genérico com o código mais longo que a forma aceita) 42 / 42; a moldura
   de mensagem soma ~4, então o pior caso fica em ~46. O teste trava o texto
   em 160 caracteres como vigia do teto.
9. **Medição:** o `chat.message` gravado pela api carrega `idiomaAlvo` e
   `origem` quando a resolução deu certo — o evento é imutável e diz, para
   sempre, o que foi pedido ao modelo naquele turno (AT-082).

**O que esta regra NÃO fecha, declarado:**

- **Chat humano sem agente** (`SendChatMessageUseCase`) fica fora, por
  decisão do mantenedor (AT-169 resposta 3).
- **Só a MENSAGEM a um agente carrega autor** (e a resposta ao formulário de
  pergunta estruturada, que a reusa). Os outros comandos que uma pessoa
  dispara — confirmar prontidão ao Criativo, aceitar handoff — sobem turno
  sem autor e caem no idioma do PROJETO: o product brief do
  `confirmReadiness` sai no idioma do projeto.
- **Artefato de turno com autor**: esta regra o declarava seguindo o idioma de
  quem escreveu; desde a [RN-623](#rn-623) a mesma mensagem ganha a cláusula
  do artefato, no idioma do projeto.
- **Não medido:** o tokenizador do DeepSeek e o da Anthropic; se a orientação
  basta contra o prompt de sistema em pt-BR é o que a validação paga da
  AT-167 mede. No Anthropic, a orientação içada ao topo muda o prefixo do
  cache a cada troca de autor ou de idioma — cache não é observável hoje.

- **Código:** `apps/engine/lib/engine/harness/idioma_da_resposta.ex:294`
  (`anexar`), `:253` (`com_idioma_do_autor`), `:161` (`orientacao`), `:94`
  (`@sem_orientacao`), `:301` (`texto_do_turno`), `:326`
  (`idioma_do_projeto`);
  `apps/engine/lib/engine/sessions/engine_api_client.ex:738`
  (`IdiomaDaResposta`), `:854` (`IdiomaDaResposta`);

  `apps/engine/lib/engine/sessions/engine_api_client.ex:738`
  (`IdiomaDaResposta`), `:854` (`IdiomaDaResposta`);
  `apps/engine/lib/engine/projects/project.ex:64` (`idioma`);
  `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:527`
  (`idioma_da_resposta`);
  `apps/engine/lib/engine/agents/criativo_server.ex:140` (`handle_call`, e a
  MESMA cláusula nos outros seis);
  `apps/engine/lib/engine/agents/turno_assincrono.ex:134`
  (`copiar_dicionario`);
  `apps/api/src/application/use-cases/agents/send-agent-message.use-case.ts:151`
  (`resolverIdioma`), `:155` (`idiomaAlvo`);
  `apps/api/src/infrastructure/http-clients/api-to-engine-client.ts:215`
  (`idiomaDaResposta`)
- **Teste:** `apps/engine/test/engine/harness/idioma_da_resposta_test.exs:78`
  (sem autor: o idioma do projeto, no fim), `:123` (com autor: o do autor
  vence o do projeto), `:134` (autor sem idioma resolvido: sem orientação),
  `:98` (a consulta que falha — caso de falha: lista intacta e log), `:93` (o
  sumarizador fica fora), `:67` (o vigia do teto de 50 tokens), `:340` (ponta
  a ponta: o idioma do autor no fim de cada chamada e fora do histórico),
  `:370` (a fachada também anexa no `llm_turn/5`);
  `apps/engine/test/engine_web/controllers/agent_command_controller_test.exs:402`
  (o comando leva o idioma até o modelo), `:414` (campo inválido: aceito, sem
  orientação);
  `apps/api/test/application/use-cases/agents/send-agent-message.use-case.spec.ts:109`
  (resolve pelo autor e pela sessão — o override da sessão vence), `:125` (a
  resolução que falha não derruba a mensagem — caso de falha);
  `apps/api/test/infrastructure/http-clients/api-to-engine-client.spec.ts:528`
  (o campo viaja só quando resolvido)
- **Origem:** AT-164, especificada na AT-081 e destravada pelas decisões das
  AT-168 e AT-169 (mantenedor, 2026-09-28); mecanismo verificado na AT-161

<a id="rn-623"></a>

### RN-623 — Num turno COM autor, a resposta é no idioma da pessoa e o ARTEFATO compartilhado é no idioma do PROJETO {#rn-623}

A [RN-619](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-619) prometeu o idioma do projeto para o artefato
compartilhado, e a [RN-622](#rn-622) pôs o idioma do AUTOR em todo turno com
autor — então o que um agente gravava DURANTE a conversa com uma pessoa saía no
idioma dela. Decisão do mantenedor (AT-168 resposta 8, AT-245): **o artefato
segue o PROJETO**; a resposta de chat continua no idioma do autor.

1. **O mecanismo é a mesma mensagem da RN-622, com uma segunda cláusula.**
   Num turno com autor, quando a chamada leva ao menos uma ferramenta que
   grava artefato compartilhado e o idioma do projeto (`projects.language`)
   DIFERE do do autor, a orientação vira "Responda em português brasileiro
   (pt-BR), salvo pedido… **Artefatos do projeto: em en.**" — no idioma do
   texto base: a cláusula do `pt-BR` é em português, a dos outros em inglês
   ("Write project artifacts in X."). Continua UMA mensagem `system` efêmera
   no fim, montada pela fachada; quem decide é o conjunto de ferramentas que a
   MESMA chamada leva ao modelo, que a fachada já tem.
2. **Por que a orientação, e não a descrição da ferramenta.** A descrição
   viaja em TODA chamada, em cada ferramenta, com os idiomas iguais ou não; a
   cláusula existe só quando eles diferem, e mora no único lugar que já decide
   o idioma. Sem acréscimo nenhum quando os idiomas são iguais, quando a
   chamada não tem ferramenta de artefato, e em turno SEM autor (que já recebe
   o idioma do projeto).
3. **O que é artefato compartilhado** — o que a ferramenta PERSISTE é lido por
   outras pessoas e pelos próximos agentes:
   - `emit_artifact` (`business_rule`, `note`, `decision_record`) — Criativo,
     PO, Arquiteto, Dev Lead, UX Designer, Staff;
   - `create_epic`, `create_story`, `create_task` — PO;
   - `create_module_map`, `assign_story_modules`, `choose_project_image`,
     `create_c4_diagram`, `route_modules_to_infra`, `propose_adr` (o ADR de
     `open_adr_pr`), `emit_insight` — Arquiteto;
   - `propose_execution_plan`, `assess_implementability` — Dev Lead;
   - `propose_prototype` — UX Designer; `propose_rfc` — Staff;
   - `propose_infra_pr` — Infra Lead.
   O product brief NÃO passa por aqui: ele é emitido pelo SERVIDOR no
   `confirmReadiness`, que é turno sem autor e já sai no idioma do projeto
   (como o handoff e o revise, que esta regra não muda).
4. **O que NÃO é:** `ask_structured_questions` (é pergunta à PESSOA do
   turno), `offer_handoff` (não leva texto), as de leitura (`listar_*`,
   `rag_*`, `read_file`, `search_workspace`), `validate_infra_file` (só
   valida) e as propostas de subir container (pedem decisão, não gravam
   artefato). Os dev agents e os gates não têm turno com autor.
5. **Falha nunca derruba o turno.** Ler o idioma do projeto que falha vira
   `warning` e segue SÓ a orientação do autor — nunca sem orientação, nunca a
   do projeto no lugar da da pessoa. Autor sem idioma resolvido segue sem
   orientação, como na RN-622.
6. **Custo** — o teto de 50 tokens de entrada da AT-169 vale para a mensagem
   inteira. Medido com `gpt-tokenizer`, só o conteúdo, cl100k / o200k, sobre
   todos os pares de `pt-BR`, `en`, `es`, `es-MX` e `zh-Hant-TW`: pior caso
   `pt-BR` → `zh-Hant-TW` 42 / 36; `en` → `pt-BR` 26 / 26; genérico `es-MX` →
   `zh-Hant-TW` 36 / 36. A cláusula só entra com os DOIS códigos na forma
   canônica curta (`idioma[-Escrita][-Região]`, ex.: `pt-BR`, `zh-Hant-TW`,
   `es-419`), porque é a FORMA que segura o teto: o pior dela (`pt-BR` → código
   de 12 caracteres) mede 44 / 37, ~48 com a moldura da mensagem. Código fora
   dessa forma fica só com a orientação do autor, e o log diz. O teste trava
   todo par em 165 caracteres como vigia.

**O que esta regra NÃO fecha, declarado:** a lista é por NOME de ferramenta —
ferramenta nova que grave artefato entra nela no mesmo PR (o teste amarra
cada nome a uma spec que existe, mas não descobre ferramenta nova). Se o
modelo SEGUE as duas cláusulas na mesma mensagem é o que a validação paga da
AT-167 mede; os tokenizadores do DeepSeek e da Anthropic seguem não medidos.

- **Código:** `apps/engine/lib/engine/harness/idioma_da_resposta.ex:174`
  (`orientacao`), `:127` (`@ferramentas_de_artefato`), `:118`
  (`@forma_curta`), `:301` (`texto_do_turno`), `:319` (`grava_artefato?`),
  `:320` (`idioma_do_projeto_para_o_artefato`);
  `apps/engine/lib/engine/sessions/engine_api_client.ex:738`
  (`IdiomaDaResposta`), `:854` (`IdiomaDaResposta`);

  `apps/engine/lib/engine/sessions/engine_api_client.ex:738`
  (`IdiomaDaResposta`), `:854` (`IdiomaDaResposta`);
  `apps/web/src/routes/settings/ProjectLanguageSection.tsx`
- **Teste:** `apps/engine/test/engine/harness/idioma_da_resposta_test.exs:157`
  (idiomas diferentes: a orientação diz os dois), `:168` (iguais: só um),
  `:175` (código fora da forma curta: só o do autor, com log), `:190` (o vigia
  do teto), `:204` (cada nome da lista é uma spec que existe), `:235` (autor
  pt-BR, projeto en, numa mensagem só), `:259` (sem ferramenta de artefato:
  só o autor), `:290` (idioma do projeto ilegível — caso de falha: só o do
  autor, com log), `:316` (sem autor: nada muda), `:340` (ponta a ponta pelo
  Criativo); `apps/web/src/routes/settings/idioma-do-projeto.test.tsx:84`
- **Origem:** AT-245, sobre a decisão da AT-168 (resposta 8) e as do
  mantenedor de 2026-09-29

<a id="rn-625"></a>

### RN-625 — O laço pergunta ao Jev qual ferramenta, e o modelo do usuário vê só o menu que sobra; o Jev restringe e nunca decide {#rn-625}

Decisão do mantenedor (AT-236, 2026-09-28) e, sobre o critério, de 2026-09-29:
antes de cada chamada de chat de um agente, a api pergunta ao Jev
(`typesafe/jev-1.13`, Decisions API do OpenRouter) qual ferramenta cabe no
passo, e o provider de chat recebe só o **menu** que a política P3 tira dessa
resposta. O mecanismo está no [ADR 0179](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0179-o-laco-pergunta-ao-jev-qual-ferramenta.md);
a decisão de adoção, com os números, também.

1. **Quando.** Só com o provider do modelo do turno igual a `openrouter`, com
   duas ou mais ferramentas no pedido, com agente no turno (fora a Anamnese e o
   sumarizador da compactação), sem `catalogoCompleto` pedido pelo engine e com
   o workspace ligado (`workspaces.tool_router_enabled`, padrão ligado,
   `PUT workspaces/:workspaceId/tool-router`, `owner`). Qualquer condição falha:
   nenhuma chamada, nenhum evento. Com provider ≠ `openrouter` nem o workspace é
   lido. A chave é a do titular do workspace, a mesma do chat (RN-058).
2. **A política é a P3 e só restringe.** Menu = {escolha do Jev, ferramenta
   anterior da MESMA execução}. `responder_sem_ferramenta` do Jev, ou nenhuma
   ferramenta anterior no catálogo do passo, deixa o catálogo INTEIRO. Não há
   `tool_choice` (o modelo ainda pode responder em texto) e não há limiar de
   confiança na v1: a confiança é gravada e é da AT-239 propor um. Critério de
   adoção: **80%**, decisão do dono de 2026-09-29 — top-1 do Jev 73% (66–79),
   cobertura de menu da P3 91% (85,1–94), top-2 90%; cobertura é o TETO da
   acurácia ponta a ponta (62%–91% em replay), e a validação real é a AT-239.
3. **O `state`** é o que o produto tem antes do passo, recortado das `messages`
   que o engine já manda, sem leitura de banco: `agente` = o `agentId`;
   `contexto` = o começo (1.500 caracteres) da mensagem `system` que o
   `ToolLoop` põe na frente (`apps/engine/lib/engine/harness/tool_loop.ex:98`,
   `system_msg`, montada por `system_prompt/1` em `:316`); `pedido` = a última
   mensagem `user` — nos agentes de execução a mensagem inicial do laço
   (`apps/engine/lib/engine/dev/dev_agent_server.ex:651`, `initial_message/2`,
   ou a de correção em `:523`), nos conversacionais a fala da pessoa; e
   `passos_recentes` = as 6 últimas chamadas de ferramenta depois dessa
   mensagem, uma entrada por chamada, argumento e resultado cortados em 500
   caracteres — o resultado vem da mensagem `tool` que o laço anexa
   (`tool_loop.ex:293`, `concluir_despacho/5`, com `toolCallId`). A execução
   corrente é "depois da última `user`" porque `ctx.messages` recomeça a cada
   `ToolLoop.run`. Teto de 8 mil tokens; estourou, queda `estado_grande`.
4. **O turno nunca falha por causa do Jev.** Erro HTTP, timeout (2.000 ms,
   `TOOL_ROUTER_TIMEOUT_MS`), erro de rede, JSON inesperado, escolha fora das
   opções, estado grande e colisão com o nome reservado: o provider recebe o
   catálogo inteiro e o evento leva `motivoDaQueda` e `origemDaQueda`
   (`infra`, `modelo` ou `codigo` — RN-059), nunca calado.
5. **A política não muda.** O Jev não aprova, não nega e não escolhe modelo. A
   ferramenta escolhida que exige aprovação continua exigindo; a chamada a uma
   ferramenta fora do cardápio é despachada como sempre e o evento só registra
   `foraDoCardapio`. O teto de iteração é o de antes (a chamada ao Jev não é uma
   iteração).
6. **Registro por passo.** O engine grava `tool_router.decided`, na fachada
   `EngineApiClient` para todos os agentes, com menu antes e depois, escolha,
   confiança, segunda opção, `aplicado`, queda, latência, custo real e
   `foraDoCardapio`. A api grava UMA linha de `token_usage` do Jev: ator = o
   próprio agente (o gasto entra no orçamento de área, ADR 0110), `modelName =
   typesafe/jev-1.13`, `modelId` nulo, `estimated = false`, `costMicros` = o
   `usage.cost` da resposta, preço por milhão IMPLÍCITO (`custo ÷ tokens`) com
   `price_implicit = true` — mantém `tokens × preço = custo` da RN-044 sem
   inventar preço de catálogo. Sem `usage.cost` na resposta não há linha. O gate
   de orçamento não é reconsultado entre o Jev e o chat.
7. **Sair do beco.** Menu restringido e o modelo responde sem chamar ferramenta
   (nem em texto recuperável), sem erro do provider: a fachada repete o passo UMA
   vez com `catalogoCompleto: true`, que pula o Jev. No stream, só se nada foi
   escrito para a pessoa. Pede mais ferramentas, nunca uma que o agente não tinha.

**O que esta regra NÃO fecha, declarado:** a tela (mostrar que o passo foi
roteado, com a confiança, e a faixa "escolhendo ferramenta" pelo frame
`tool_routing_started`) é de `apps/web`; o ganho é da AT-239; um timeout que o
OpenRouter cobrou sem devolver `usage.cost` não entra em `token_usage`; o
endpoint é ALPHA e o smoke manual
(`jev-tool-router.smoke.spec.ts`, teto US$ 0,05) é quem acusa a mudança.

- **Código:** `apps/api/src/domain/llm/tool-router.ts:27` (`MODELO_DO_JEV`),
  `:109` (`montarPedidoAoJev`), `:166` (`lerRespostaDoJev`), `:216`
  (`recortarEstado`), `:272` (`menuP3`);
  `apps/api/src/application/use-cases/llm/decidir-ferramenta-do-passo.use-case.ts:118`
  (`preparar`), `:143` (`executar`), `:305` (`registrarGasto`);
  `apps/api/src/application/use-cases/llm/run-llm-turn.use-case.ts:190`
  (`decisaoDoJev`); `apps/api/src/application/use-cases/llm/stream-llm-turn.use-case.ts:212`
  (`preparar`); `apps/api/src/infrastructure/llm/jev-tool-router.ts:32`
  (`decidir`); `apps/api/src/db/schema/iam.ts:169` (`toolRouterEnabled`);
  `apps/api/src/db/schema/llm.ts:375` (`priceImplicit`);
  `apps/engine/lib/engine/harness/roteamento_de_ferramenta.ex:60` (`registrar`),
  `:112` (`custo_micros`), `:123` (`repetir_com_catalogo_inteiro?`), `:146`
  (`mesclar_repeticao`); `apps/engine/lib/engine/sessions/engine_api_client.ex:754`
  (`llm_turn`), `:845` (`llm_turn_stream`);

  (`mesclar_repeticao`); `apps/engine/lib/engine/sessions/engine_api_client.ex:754`
  (`llm_turn`), `:845` (`llm_turn_stream`);
  `apps/engine/lib/engine/harness/tool_loop.ex:132` (o custo do Jev no orçamento
  local)
- **Teste:** `apps/api/test/domain/llm/tool-router.spec.ts:25` (`questions` é
  objeto), `:86` (forma inesperada vira queda — caso de falha), `:138` (o
  `state`), `:210` (a P3);
  `apps/api/test/infrastructure/llm/jev-tool-router.contract.spec.ts:60` (a
  resposta gravada), `:121` (erro HTTP), `:130` (timeout), `:142` (rede),
  `:149` e `:154` (JSON inesperado), `:163` (escolha fora das opções);
  `apps/api/test/application/use-cases/llm/decidir-ferramenta-do-passo.use-case.spec.ts:186`
  (provider ≠ openrouter não chama), `:222` (workspace desligado), `:255`
  (estado grande), `:277` (a P3), `:318` (sem ferramenta = catálogo inteiro),
  `:331` (sem anterior = inteiro), `:352` (a política não muda), `:369` (as
  quedas), `:456` (o metering, no orçamento de área);
  `apps/engine/test/engine/harness/roteamento_de_ferramenta_test.exs:67` (o
  evento), `:103` (a queda no evento), `:180` (sair do beco), `:288` (o custo no
  laço), `:299` (a aprovação continua exigida), `:325` (o roteamento não conhece
  a política)
- **Origem:** AT-238, sobre a especificação da AT-235, as dezesseis decisões da
  AT-236, a medição da AT-237/AT-280 e a decisão do dono de 2026-09-29 (critério
  de 80%)

## Decidir no chat, onde o dono está (RN-626)

<a id="rn-629"></a>

### RN-629 — O QA Lead trata o subagente que SUSPENDE de novo na retomada do mesmo jeito que na primeira vez, e resultado que não conhece vira bloqueio nomeado {#rn-629}

O `qa-automacao` roda vários comandos e cada um pode pedir aprovação humana. O
`QaLeadServer` já parava a área quando `run/5` devolvia `{:awaiting, _}` (achado
AB, ADR 0052), mas a RETOMADA (`retomar/3`, quando a decisão chega) devolvia o
resultado de um laço que podia suspender OUTRA vez — e esse segundo
`{:awaiting, _}` entrava na lista de resultados colhidos como se fosse parecer.
Ao consolidar, `registrar_resultado/5` não tinha cláusula para ele e o
GenServer caía (`FunctionClauseError`, medido em 29/09/2026: 06:55:01 e
07:00:10), deixando as três tasks entregues em `awaiting_qa` para sempre, sem
veredito e sem desfecho nomeado.

1. **Um só lugar decide o que fazer com o resultado de um subagente**
   (`tratar_resultado/6`), venha ele de `run/5` ou de `retomar/3`.
   `{:awaiting, _}` guarda o estado em voo (chaveado pela nova ação), mantém a
   linha de `gate_states` em `in_progress` com o subagente e PARA a área: sem
   veredito, sem bloquear a task, sem registrar a delegação. Quem retoma é o
   mesmo `{:action_settled, _}` do `Engine.Dev.Wake` (ADR 0086), quantas vezes
   forem necessárias.
2. **Resultado que o lead não conhece nunca derruba nem some** (RN-059): vira
   `{:blocked, …}` com origem `codigo` (falta uma cláusula aqui, não é infra,
   modelo nem política), que `registrar_resultado/5` grava como delegação
   `failed` e `QaLead.consolidar/1` transforma em bloqueio da task com a origem.

**Declarado, não resolvido:** o restart do engine com o lead suspenso perde a
inscrição no Wake (lacuna aceita do ADR 0086); o `GateRescuer` reinicia a área
inteira (ADR 0067), não retoma o `ctx`. Esta regra não muda o ADR 0090 (o
momento do QA-estratégia) nem o teto de iterações do subagente.

- **Código:** `apps/engine/lib/engine/gates/qa_lead_server.ex:127`
  (`handle_info`), `:237` (`tratar_resultado`), `:230` (resultado desconhecido)
- **Testes:** `apps/engine/test/engine/gates/qa_lead_server_test.exs:325`
  (segunda suspensão na retomada: fica suspenso, não decide nada, e a segunda
  decisão conclui a área); `:278` (uma suspensão, o caminho feliz)
- **Origem:** AT-248, sobre o achado E2 da análise de uso real de 2026-09-29

<a id="rn-636"></a>

### RN-636 — O AppSec só oferece o threat model a quem ainda não recebeu oferta nem está ativo {#rn-636}

O AppSec criava três ofertas por história com `run_design`, aos mesmos três
destinos — N histórias, 3N ofertas pendentes (AT-292, que funde a AT-273 do
vault por decisão do dono; [ADR 0182](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0182-ciclo-de-vida-do-handoff.md)).

1. **Pergunta no modo `seAusente`.** `criar_handoffs_appsec/3` chama
   `EngineApiClient.create_handoff_if_absent/5`, que manda `seAusente: true` à
   MESMA rota interna. A api decide sob o lock do destino ([RN-635](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-635)):
   com oferta pendente em QUALQUER sessão do projeto, devolve a existente
   (`desfecho: ja_oferecido`) e não a substitui; com o destino ativo, 409
   `agente_ja_ativo`. Perguntar antes, pelo engine, seria corrida com outra
   oferta.
2. **"Já atendido" não é falha.** As duas respostas acima seguem sem
   `agent.error`. Falha de verdade (5xx, rede) continua narrada por alvo, com
   origem ([RN-116](parte-01.md#rn-116), [RN-361](parte-02.md#rn-361)).
3. **O artefato fica.** O `artifact.threat_model` é gravado ANTES e de qualquer
   jeito; o que deixa de nascer é a oferta repetida.

- **Onde:** `apps/engine/lib/engine/gates/secops_agent_server.ex:377`
  (`criar_handoffs_appsec/3`);
  `apps/engine/lib/engine/sessions/engine_api_client.ex:1142`

  `apps/engine/lib/engine/sessions/engine_api_client.ex:1326`
  (`create_handoff_if_absent`);
  `apps/api/src/domain/sessions/ciclo-de-vida-do-handoff.ts:71`
  (`decidirOferta`)
- **Teste:** `apps/engine/test/engine/gates/secops_agent_server_test.exs`
  ("run_design (RN-636): destino com oferta pendente ou já ativo não recebe
  outra, e isso não é erro", "run_design (RN-636): falha de verdade ao
  oferecer segue narrada, só para aquele destino");
  `apps/api/test/application/use-cases/agents/ciclo-de-vida-do-handoff.spec.ts`
  ("`seAusente` (AppSec, RN-636)…")
- **Origem:** AT-292, AT-273

## A PR do dev agent mira `dev`, e o gate julga o diff dessa PR (RN-664)

<a id="rn-664"></a>

### RN-664 — O trabalho dos agentes nasce de `dev`, a PR deles mira `dev`, e o gate julga o diff contra `dev` — os três juntos {#rn-664}

> **Revisada pela [RN-1021](parte-06.md#rn-1021) (AT-617):** no repositório do projeto a branch de trabalho agora é a `main` (trunk), e a constante `@branch_de_trabalho` do código vale `"main"`. O texto abaixo descreve a política de `dev` que ela substituiu; onde ele diz `dev` para a branch de trabalho do projeto, leia `main`.

A política de branches do produto manda o trabalho nascer de `dev` (o bootstrap
cria `dev` e `qa` a partir de `main`, [RN-582](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-582)), mas até aqui ninguém
apontava os agentes para ela: o `pr_open` do dev agent não levava
`targetBranch` e a api completava com `repo.defaultBranch` (`main`); a PR de
ADR do Arquiteto nascia de `main` e mirava `main`; o working tree do projeto
abria a `default_branch`; o gate calculava o diff contra ela; e o contexto do
QA dizia "Repositório · branch main" (AT-250, item A4 do uso real de 29/09).
Toda PR de agente pulava a esteira `dev → qa → main`.

Decisão do dono (30/09): os TRÊS passam a usar `dev`, juntos — mudar só um
deixaria o gate julgando um diff que não é o da PR. A branch de TRABALHO é
`dev` e NÃO é a `default_branch` do provider (que segue sendo a que a promoção
alcança por último e continua lida onde ela é a pergunta):

- o working tree do projeto abre `dev` (`ensure_remoto/2` ignora o
  `default_branch` do remoto para escolher a base), e o worktree de cada dev
  agent nasce de `dev` EXPLICITAMENTE, não do HEAD — workspace inicializado
  antes desta regra está parado na `default_branch` (a marca de pronto impede
  re-inicializar) e ganha a `dev` local a partir de `origin/dev`, sem `fetch`
  novo;
- o `pr_open` do dev agent leva `targetBranch: "dev"` no payload, e a api, sem
  o campo (ação proposta antes), completa com `dev` e não mais com a
  `defaultBranch`; a PR de ADR nasce de `dev` e mira `dev`;
- o diff do gate é `dev...HEAD`, e a linha de contexto do projeto diz
  "Repositório · branch de trabalho dev".

**Repositório SEM `dev`** (adotado sem bootstrap, ou bootstrap que não chegou a
`create_dev_branch`): NÃO há queda para a `default_branch` — seria o agente
trabalhando e o gate julgando sobre uma base que não é a da PR. Cada ponto
falha NOMEADO, pelo comportamento que já tinha para branch ausente, com uma
exceção nova: o working tree recusava nada e criava uma `dev` LOCAL VAZIA
(o caminho do bare que nunca recebeu push), marcava pronto e nunca mais
re-inicializava. Agora esse caminho só vale para o remoto SEM branch nenhuma;
com branches e sem `origin/dev`, a inicialização levanta com a mensagem
nomeada (`mensagem_sem_branch_de_trabalho/1`, "o repositório do projeto não
tem a branch `dev`… crie a branch… e tente de novo") e o `.git` é desfeito
(AT-112), então a próxima tentativa, com a `dev` criada, inicializa normal. O
worktree recusa com a mesma mensagem quando não há `dev` nem `origin/dev`; o
diff falha com o erro do git nomeando a revisão; o provider recusa a PR (e a
criação da branch do ADR) nomeando a ref. O `infra` (`open_infra_pr`) NÃO
mudou: segue nascendo e mirando a `defaultBranch`.

O valor mora em DOIS lugares, de propósito, um por linguagem, e mudam juntos:
`BRANCH_DE_TRABALHO` na api e `branch_de_trabalho/0` no engine.

- **Código:** `apps/engine/lib/engine/projects/project_repository.ex:166`
  (`branch_de_trabalho`), `:177` (`branch_de_trabalho`), `:191`
  (`mensagem_sem_branch_de_trabalho`);
  `apps/engine/lib/engine/actions/workspace.ex:71` (`ensure_remoto`), `:224`
  (`init_from_bare!`), `:273` (`remoto_vazio?`);
  `apps/engine/lib/engine/actions/workspace/runner_git.ex:160` (`add_worktree`),
  `:183` (`garantir_base`), `:330` (`remoto_vazio?`);
  `apps/engine/lib/engine/dev/worktree_manager.ex:37` (`create`), `:321`
  (`add_worktree`), `:527` (`garantir_base`);
  `apps/engine/lib/engine/dev/agent_io.ex:436` (`propose_pr`);
  `apps/engine/lib/engine/gates/diff.ex:29` (`compute`);
  `apps/engine/lib/engine/harness/project_context.ex:29` (`repo_line`);
  `apps/api/src/domain/actions/protected-branches.ts:26` (`BRANCH_DE_TRABALHO`);
  `apps/api/src/application/use-cases/actions/execute-git-action.use-case.ts:208`
  (`targetBranch`); `apps/api/src/application/use-cases/actions/execute-adr-pr.use-case.ts:86`
  (`fromRef`), `:99` (`targetBranch`)
- **Teste:** `apps/engine/test/engine/gates/diff_test.exs:64` (o diff é só a
  mudança do agente, nada da `main` — caminho feliz), `:73` (sem `dev` o diff
  falha nomeando a revisão — caso de falha), `:91` (o contexto diz a branch de
  trabalho); `apps/engine/test/engine/actions/workspace_test.exs:87`, `:98`,
  `:110` (repositório adotado sem `dev`: recusa nomeada, `.git` desfeito, e
  passa depois de criada a branch — caso de falha), `:130`;
  `apps/engine/test/engine/dev/worktree_manager_test.exs:119`, `:127`
  (workspace de antes da regra), `:147` (sem `dev` nem `origin/dev`);
  `apps/engine/test/engine/dev/dev_agent_server_test.exs:114`;
  `apps/api/test/application/use-cases/actions/execute-git-action.use-case.spec.ts:184`,
  `:213`; `apps/api/test/application/use-cases/actions/execute-adr-pr.use-case.spec.ts:143`,
  `:151` (sem `dev`, `failed` com o motivo do provider)
- **Origem:** AT-250 (item A4 da análise do uso real de 29/09), decisão do dono
  de 30/09

## O idioma das respostas dos agentes (RN-618..620, RN-622..624, ADR 0177)

<a id="rn-667"></a>

### RN-667 — O formulário estruturado segue o idioma da resposta: a descrição da ferramenta não fixa idioma nenhum {#rn-667}

A validação paga da AT-167 achou, para autor com preferência `en` (C06/C12),
a chamada `ask_structured_questions` com a **prosa em inglês e as perguntas do
formulário em português** — no DeepSeek tratado, 8 das 15 respostas de
C06+C12. A causa é do produto, e mora num lugar só: a descrição da ferramenta
dizia que `label` era "o texto da pergunta, **em pt-BR**". Era uma SEGUNDA
orientação de idioma, fixa, fora da fachada da [RN-622](#rn-622), competindo
com ela em toda chamada do Criativo e do PO (as duas usam a MESMA spec).

1. **O mecanismo é tirar a orientação concorrente, não acrescentar outra.** A
   descrição passou a dizer "o texto da pergunta, **no idioma da sua
   resposta** (vale também para `options`)", e o exemplo, que segue em
   português, é marcado "os textos seguem o idioma da sua resposta". Ela não
   nomeia idioma NENHUM: QUAL é o idioma continua decidido só pela mensagem
   efêmera de `Engine.Harness.IdiomaDaResposta`, e a fachada `EngineApiClient`
   não muda.
2. **A orientação da RN-622/623 fica byte a byte.** Zero token a mais nos 50
   de teto. `ask_structured_questions` segue FORA de `@ferramentas_de_artefato`
   (é pergunta à pessoa do turno, [RN-623](#rn-623) item 4), então autor `en`
   num projeto `pt-BR` recebe as perguntas em inglês — e é o que se quer.
3. **Custo, onde ele cai.** A descrição viaja em toda chamada que leva a
   ferramenta, com qualquer autor: medido com `gpt-tokenizer`, só o texto que
   mudou, +23 tokens em cl100k e +19 em o200k (a linha de `label` 18/17 → 29/27;
   a do exemplo 8/6 → 20/15). Não é a orientação indo para a descrição — a
   frase aponta para ela sem dizer idioma, e o que foi embora era justamente a
   frase que dizia um.
4. **Guarda.** Nenhuma descrição de ferramenta do harness (as 22 de
   `Engine.Harness.Tools.*`) pode citar `pt-BR`, `(en)`, "in English", "em
   português" ou "em inglês" — a do `emit_artifact`, que exige as CHAVES do
   payload "em INGLÊS", fica de fora porque fala de contrato, não de texto para
   a pessoa.

**O que esta regra NÃO fecha, declarado:** a medição paga antes/depois
**não rodou** (sem chave do OpenRouter na máquina da mudança) — o "antes" é o
da AT-167 (DeepSeek tratado: 8 de 15 respostas de C06+C12 com o formulário em
português), e o "depois" é **pendência do dono**:
`pnpm --filter @brabo/scripts idioma:validar --arquivo-de-chave ~/.config/brabo/openrouter-test.env --bracos tratamento --casos C06,C12 --rodadas 5 --teto-usd 0.5 --saida ~/.cache/brabo/validacao-idioma/at-282`,
seguido de `idioma:validar --relatorio --saida` na mesma pasta e da revisão do
formulário (rótulo `formulario` do `idioma:revisar`). Teto sugerido US$ 0,50:
o braço tratado inteiro custou US$ 0,21 (DeepSeek) e US$ 0,94 (Haiku) em
17 casos, e estes são 2. O script lê a descrição do arquivo do produto, então
mede o texto novo sem cópia. Se o formulário continuar em português com a
descrição neutra, o passo seguinte é uma cláusula condicional na orientação
(só quando a chamada leva `ask_structured_questions`), e ela tem de caber no
pior caso da RN-623 (44 / 37), que já está a ~48 com a moldura.

- **Código:** `apps/engine/lib/engine/harness/tools/ask_structured_questions.ex:193`
  (`descricao`), `:44` (`spec`)
- **Teste:** `apps/engine/test/engine/harness/tools/ask_structured_questions_test.exs:199`
  (a descrição manda seguir o idioma da resposta), `:207` (não nomeia idioma
  — caso de falha: a forma antiga "em pt-BR" é reprovada pela mesma régua),
  `:214` (nenhuma das ferramentas do harness fixa idioma);
  `scripts/idioma/validacao.spec.ts:60` (a medição lê a descrição nova)
- **Origem:** AT-282, da revisão humana da AT-167 (PR #750, 29/09); entrada
  na rodada aprovada pelo mantenedor em 2026-09-30

## O Infra Lead não anuncia subida que não fez (RN-668)

<a id="rn-668"></a>

### RN-668 — O que o turno do Infra Lead anuncia sobre a subida do container é decidido pelo código, não pelo texto do modelo {#rn-668}

É a [RN-163](parte-01.md#rn-163) ("nada se anuncia que o
código não vá executar") aplicada ao Infra Lead. No uso real de 29/09 (sessão
`be70`, seq 282) ele escreveu que subiria o container "em paralelo" à PR de
infra, e nenhum `tool.call` de subida veio depois (AT-264). Havia duas causas no
código, e as duas fecham aqui:

1. **O lote inteiro da resposta é despachado antes do encerramento.**
   `propose_infra_pr` aceita encerra o turno sem nova ida ao modelo — é o único
   ponto em que o CÓDIGO corta o laço com o modelo querendo continuar —, mas
   ela parava o despacho no MEIO do lote: uma `propose_container_start` (ou
   `container_start_via_runner`) pedida na MESMA resposta, depois da PR, sumia
   sem `tool.call`, sem `tool.result` e sem aviso. Agora é a forma do Dev Lead
   (`propose_execution_plan`): todas as chamadas da resposta rodam, e só depois
   a PR aceita encerra o turno. Uma segunda `propose_infra_pr` na mesma resposta
   é recusada com motivo (`tool.call` + `tool.result` com `ok: false`) — só a
   primeira consolida com o Workflows.
2. **O fecho do turno diz, com frase do SERVIDOR, quando a subida NÃO foi
   proposta** — a forma do desfecho consolidado do Criativo (`encerrar/2`). A
   decisão é pelo que o laço executou (alguma proposta de subida ACEITA pela api
   neste turno?), nunca pelo que o modelo escreveu; não há leitura do texto
   dele. Fala-se em dois casos: o turno terminou pela PR e nenhuma subida foi
   proposta; ou uma subida foi tentada, recusada, e nenhuma proposta aceita veio
   depois. Turno que nunca tocou na subida (uma pergunta, uma correção de gate)
   não ganha frase nenhuma, e container já REGISTRADO `running`/`provisioning`
   também não (a mesma leitura local de `recusa_ja_de_pe/2`, sem HTTP).

O kickoff e a descrição de `propose_infra_pr` passam a dizer o que o código faz:
a subida vem ANTES da PR ou na MESMA resposta, porque a PR encerra o turno. Isso
é ajuda ao modelo, não a garantia — a garantia é o fecho do item 2.

Nada aqui sobe container nem propõe subida, com as recusas por modo e estado
intactas (RN-566/RN-610). Desde a [RN-671](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-671) (AT-260) a primeira subida
é passo do SERVIDOR no kickoff, marcada pelo MESMO `registrar_subida`: no caso
comum ela foi proposta e o fecho do item 2 não tem o que dizer; ele segue
falando quando a subida do servidor foi recusada (ou NEGADA pela política, que
desde então conta como recusa) e quando ela não cabia ao servidor (sem
roteamento, `runner`) e o modelo não a propôs.

- **Código:** `apps/engine/lib/engine/infra/infra_lead_server.ex:505`
  (`dispatch_calls`), `:541` (`recusa_pr_repetida_no_lote`), `:1252`
  (`registrar_subida`), `:1254` (`fechar_subida`), `:1155`

  (`dispatch_calls`), `:539` (`recusa_pr_repetida_no_lote`), `:1140`
  (`registrar_subida`), `:1150` (`fechar_subida`), `:1154`
  (`desfecho_da_subida`); `apps/engine/lib/engine/infra/tools/propose_infra_pr.ex`
  (a descrição da tool)
- **Teste:** `apps/engine/test/engine/infra/infra_lead_server_test.exs:1075`
  (a subida pedida depois da PR na mesma resposta é despachada — caminho feliz),
  `:1107` (a PR encerra o turno sem subida e o fio diz — caso de falha),
  `:1147` (subida recusada e prometida, sem proposta: o fecho diz), `:1132`
  (container já de pé: nada a dizer), `:1169` (recusa corrigida no turno: sem
  frase), `:1190` (turno sem subida: sem frase), `:1199` (segunda
  `propose_infra_pr` no lote é recusada)
- **Origem:** AT-264 (uso real de 2026-09-29, item A18 da análise)

## O git credenciado roda no host do runner (RN-676)

<a id="rn-673"></a>

### RN-673 — A mensagem que chega com turno em curso entra numa fila persistida no log e é lida no fim do turno, N mensagens num turno só {#rn-673}

Até aqui a mensagem que chegava a um agente conversacional no meio de um turno
era 409 `turno_em_andamento` ([RN-578](parte-03.md#rn-578)): gravada como `chat.message`
(a api grava antes de falar com o engine) e nunca lida. O uso real de 29/09
mediu três numa sessão só — PO, Infra Lead e Dev Lead. Decisão do dono (01/10),
para os SETE conversacionais pelo mesmo caminho:

1. **Fila, não recusa.** Com turno em curso, a mensagem entra na fila do agente
   (`TurnoAssincrono.receber_mensagem/4`), o agente grava `chat.message_queued`
   (`mensagemId`, `texto`, `idioma`, `posicao`) e o clique recebe 202 com
   `{entrega: "enfileirada", posicao}`. Sem turno, o turno sobe na hora, como
   sempre (`entrega: "lida"`). A rota da api devolve também o `mensagemId` — o
   id do `chat.message`.
2. **N mensagens = 1 turno.** No FIM do turno (`finalizar/1`, nunca
   `suspender/1`) as pendentes viram UM turno, na ordem de chegada, num texto só
   (`FilaDeMensagens.texto_do_turno/1`: uma é ela mesma; várias, numeradas), e o
   agente grava `chat.message_delivered` com os ids. A entrega é uma mensagem a
   si mesmo, depois do fecho do servidor (a correção de gate do Infra Lead e o
   handoff do Arquiteto vêm primeiro). A mensagem que chega entre o fim do turno
   e a entrega entra no FIM da fila, e a fila é entregue na hora.
3. **Teto de 10** pendentes por agente e sessão. A 11ª é 409
   `fila_de_mensagens_cheia`, com `agent.error` durável de origem `politica` —
   ela está gravada e não será lida.
4. **Cancelar.** `POST …/agents/:agent/messages/:messageId/cancel`
   (`developer`, o mínimo da rota de mensagem): só quem ENVIOU (403
   `mensagem_de_outra_pessoa`), só em sessão que aceita conversa
   ([RN-581](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-581)). Quem decide se ela ainda está na fila é o processo do
   agente, que serializa a corrida com a entrega: 409 `mensagem_fora_da_fila`
   quando já foi lida ou cancelada. O engine grava `chat.message_cancelled` em
   nome de quem cancelou; com o agente fora do ar, grava direto (a fila é o log).
5. **Persistida no log, nunca em tabela.** Pendente = enfileirada e nem
   entregue nem cancelada — a mesma derivação no engine e na tela. O `init/1`
   dos sete reconstrói a fila e agenda a entrega; a [RN-580](parte-03.md#rn-580) tira do
   histórico a cancelada e a pendente do próprio agente; no boot, depois de
   fechar o turno órfão ([RN-586](parte-03.md#rn-586)), o agente com fila pendente é
   acordado. O turno interrompido continua nunca refeito.
6. **Turno suspenso em aprovação** (Dev Lead, RN-284) segue recusando com
   `aguardando_aprovacao` — sem fim previsto, enfileirar prometeria leitura sem
   data. A fila que já existia espera a retomada terminar.
7. **A tela.** Com turno em curso o composer não trava mais para mensagem a
   agente: o botão vira "Pôr na fila" e a mensagem não arma turno novo. No fio,
   "na fila de <agente>" com Cancelar para o autor, e "cancelada" riscada. O
   chat sem agente segue travando.

A recusa `turno_em_andamento` continua para o que não é fala: revisão de
história do PO, prontidão do Criativo, oferta de handoff do Arquiteto.

- **Código:** `apps/engine/lib/engine/agents/turno_assincrono.ex:322`
  (`receber_mensagem`), `:245` (`tratar_resultado`), `:519` (`entregar_fila`),
  `:380` (`cancelar_mensagem`), `:425` (`fila_ao_subir`), `:559`
  (`emitir_recusa_por_fila_cheia`);
  `apps/engine/lib/engine/agents/fila_de_mensagens.ex:71` (`pendentes`), `:111`
  (`fora_do_historico`), `:158` (`texto_do_turno`), `:182`
  (`acordar_pendentes`);
  `apps/engine/lib/engine/agents/reidratacao.ex:178` (`fora_do_historico`);
  `apps/engine/lib/engine/agents/dev_lead_server.ex:251` (`_mensagem_id`);
  `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:405`
  (`cancel_queued_message`), `:468` (`responder_ao_aceite`);
  `apps/api/src/application/use-cases/agents/cancel-queued-agent-message.use-case.ts:35`
  (`CancelQueuedAgentMessageUseCase`);
  `apps/api/src/infrastructure/http-clients/api-to-engine-client.ts:69`
  (`entregaDaResposta`);
  `apps/api/src/domain/sessions/conversa-em-sessao-encerrada.ts:72`;
  `apps/web/src/lib/fila-de-mensagens.ts:27` (`estadosNaFila`);
  `apps/web/src/lib/enfileirar-mensagem.ts:25` (`useEnfileirarMensagem`);
  `apps/web/src/routes/PainelDaFila.tsx:20` (`PainelDaFila`, que substituiu o selo — RN-978)
- **Teste:** `apps/engine/test/engine/agents/fila_de_mensagens_test.exs:156`
  (entra na fila — caminho feliz), `:181` (N mensagens = 1 turno), `:223` (a
  que chega na janela vai ao fim), `:246` (teto de 10 — caso de falha), `:276`
  e `:306` (cancelar e cancelar fora da fila), `:322` (restart), `:349` (Dev
  Lead suspenso), `:78`/`:120` (derivação e reidratação);
  `apps/engine/test/engine_web/controllers/agent_command_controller_test.exs:70`;
  `apps/api/test/application/use-cases/agents/cancel-queued-agent-message.use-case.spec.ts:40`,
  `:61` (outra pessoa — caso de falha), `:95`, `:106`;
  `apps/api/test/application/use-cases/agents/send-agent-message.use-case.spec.ts:74`;
  `apps/api/test/infrastructure/http-clients/api-to-engine-client.spec.ts:531`;
  `apps/web/src/routes/SessionPage.fila-de-mensagens.test.tsx:163`, `:189`
  (fila cheia), `:207`, `:233`; `apps/web/src/lib/fila-de-mensagens.test.ts:17`
- **Origem:** AT-267 (item A21 da análise do uso real de 2026-09-29), decisão do
  dono de 01/10; [ADR 0191](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0191-a-mensagem-com-turno-em-curso-entra-numa-fila.md)

**Complementada pela [RN-924](parte-06.md#rn-924).** A mesma ideia (estado da fila no log, reconstruído no `init/1`) vale para a correção de gate do Infra Lead, e a fila de mensagens espera o fim do turno retomado ([RN-920](parte-06.md#rn-920)).

## O plano de teste nasce depois da entrega do dev (RN-674, ADR 0192)

<a id="rn-674"></a>

### RN-674 — A QA-estratégia escreve o plano sobre o código ENTREGUE, no começo do ciclo do `qa-verificada`, e o `implementavel` se julga sem ele {#rn-674}

No uso real de 29/09 o plano de teste PRE-DEV ([RN-341](https://github.com/viralabs-dev/brabo-contracts/blob/dev/packages/docs/business-rules/contracts.md#rn-341)) terminou
duas vezes em `toolloop.limit_reached` 8/8 sem `emit_plano_de_teste`: o laço
leu docs, RAG vazio e pastas até concluir que "o código ainda não existe". O
dono decidiu (01/10) pela saída (b): o plano nasce DEPOIS da entrega. O
[ADR 0192](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0192-plano-de-teste-depois-da-entrega.md) revisa o 0090 nesse
ponto, e a regra tem quatro partes:

1. **O plano é o primeiro passo do ciclo de revisão.** `run_area/3` do
   `QaLeadServer` obtém o plano da entrega ANTES das subespecialidades
   (`plano_de_teste_da_entrega/5`): reencontra na cauda da sessão (teto da
   reidratação, [RN-580](parte-03.md#rn-580)) o `artifact.plano_de_teste` da MESMA
   `taskId` — a rodada de correção não paga outro laço —, e senão roda
   `QaEstrategiaAgent.run/6` com o worktree do dev como `workspace_root`, as
   regras de negócio da task e a lista de arquivos que a entrega tocou
   (`git diff dev...HEAD`, até 40 nomes). Diff que falha vira texto ("não
   consegui listar: motivo"), nunca lista vazia.
2. **O plano é INSUMO, nunca veredito.** Ele chega à Automação no FIM da
   mensagem dela, para o passo de achar qual teste cobre cada regra; a régua do
   veredito não muda (uma linha de `coverageMatrix` por regra da story,
   `approved` só com suite verde e toda regra coberta) e o contrato externo
   segue sendo UM `qa_verdict` por ciclo. Plano que FALHA não segura a revisão:
   a QA-estratégia grava `agent.error` com origem ([RN-059](parte-01.md#rn-059))
   e a Automação recebe a mensagem de sempre, byte a byte.
3. **O `implementavel` se julga sobre a história e o `module_map`.**
   `run_assessment/2` não lê nem dispara plano: propõe o parecer na PRIMEIRA
   chamada, sobre o que o kickoff do Dev Lead já lhe dá, com payload
   `storyId`/`parecer`/`justificativa`. Gate, dono, severidade `warn` e
   aprovação humana não mudam; só a `entrada` (`[story-ready, module_map]`).
   O appsec ([RN-539](parte-02.md#rn-539)) segue disparando ali, no design.
4. **O teto continua 8.** `"qa-estrategia"` não ganha cláusula em
   `Iteracoes.tipo/1`; o que mudou foi o insumo. O agente passa a rodar sob o
   `task_budget_micros` que as subespecialidades compartilham
   ([RN-036](parte-01.md#rn-036)).

`run_design/3`, `Dispatcher.run_qa_estrategia/3` e `QaEstrategiaContext`
saíram, e `artifact.plano_de_teste` passa a exigir `taskId`. Declarado e não
decidido aqui: se os critérios executáveis do plano devem virar linhas
OBRIGATÓRIAS da `coverageMatrix` (e portanto reprovar entrega).

- **Onde:** `apps/engine/lib/engine/gates/qa_lead_server.ex:190` (`plano_de_teste_da_entrega`),
  `:741` (`plano_de_teste_da_entrega`), `:742` (`plano_ja_emitido`),
  `:747` (`arquivos_alterados`);
  `apps/engine/lib/engine/gates/qa_estrategia_agent.ex:87` (`run`),
  `:104` (`token_budget_micros`), `:189` (`descrever_arquivos`);
  `apps/engine/lib/engine/gates/qa_automacao_agent.ex:226` (`com_o_plano`);
  `apps/engine/lib/engine/agents/dev_lead_tools.ex:544` (`run_assessment`),
  `:577` (`propor_parecer`);
  `apps/engine/lib/engine/harness/artifact_schemas.ex:59` (`taskId`);
  `apps/api/config/gates.yml` (`qa-verificada`, `implementavel`); `packages/contracts/fluxo.yml`
  (`qa-estrategia`, `area-qa`, `dev-lead`)
- **Teste:** `apps/engine/test/engine/gates/qa_lead_server_test.exs`, describe
  "plano de teste da entrega (ADR 0192)" — o plano antes da Automação e dentro
  da mensagem dela (caminho feliz), o reuso por `taskId`, o plano de outra
  task que não conta, e o plano que falha sem segurar a revisão (caso de
  falha); `apps/engine/test/engine/gates/qa_estrategia_agent_test.exs` (os
  arquivos da entrega na mensagem, o diff que falhou, `taskId` no artefato);
  `apps/engine/test/engine/agents/dev_lead_tools_test.exs`, describe
  "assess_implementability (ADR 0090, insumo do ADR 0192)" (parecer na
  primeira chamada, payload sem plano); `dev_lead_server_test.exs`
  ("assess_implementability pending TAMBÉM suspende"); `apps/engine/test/engine/harness/artifact_schemas_test.exs`
  ("sem taskId é rejeitado"). ExUnit: provado só no CI (o `repo.hex.pm` deu
  403 no ambiente da rodada).
- **Origem:** AT-269 (item A23 da análise do uso real de 29/09); decisão do
  dono em 01/10

## A Anamnese religada: sujeito elegível e fato do perfil (RN-680)

<a id="rn-680"></a>

### RN-680 — A Anamnese não roda sem sujeito elegível, e a hipótese que a própria pessoa aceitou vira fato do perfil dela no grafo e entra no contexto dos agentes que conversam com ela {#rn-680}

Decisão do dono em 01/10 (AT-277): **religar a Anamnese com correções**. No
uso real de 29/09 ela rodou seis vezes e as seis terminaram em
`anamnese.run_skipped` ("nenhum membro elegível"), escritos pelo MODELO depois
de uma chamada paga (8 933 micros), e as três hipóteses aceitas ficaram na fila
sem destino. Ver o [ADR 0196](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0196-anamnese-religada-com-sujeito-e-fato-do-perfil.md).

1. **Sem sujeito elegível, a rodada não roda.** Sujeito é o membro EFETIVO do
   projeto (`projectRole ?? workspaceRole`, a régua da [RN-471](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-471)),
   fora do opt-out, com interação PRÓPRIA no que a rodada mostra ao modelo —
   evento dele com `actor_kind: "user"` na janela, ou decisão dele. A guarda
   vem ANTES da triagem e nem a hipótese na fila a atravessa. Sem sujeito:
   nenhuma chamada ao LLM e nenhuma busca no RAG; o motivo vai NOMEADO para o
   log do engine (`sem_sujeito_elegivel`, com `nenhum_membro` ou
   `nenhuma_interacao_propria` e os números) e, na rodada pedida à mão,
   também para o event log (`anamnese.run_skipped` com
   `causa: "sem_sujeito_elegivel"`). Pelo tick é só log — seria um aviso a cada
   15 minutos por projeto. O prompt passa a listar só os sujeitos.
2. **Membro do projeto é o EFETIVO.** Criar projeto não grava
   `project_members`, e a Anamnese lia só essa tabela — o dono do workspace
   nunca era membro. Os três casos de uso da Anamnese passam a ler
   `listEffectiveMembers`; `listMembers` continua só `project_members`.
3. **A hipótese ACEITA pela PRÓPRIA pessoa vira fato do perfil.** O
   `psychologist.hypothesis_accepted` carrega `projectId`, `sujeito` (o autor
   da sessão analisada), `hipotese`, `sugestao` e `fatoDoPerfil`, e o
   `GraphEventTranslator` — o mesmo do projetor e de `grafo:reprojetar` — o
   traduz para `(:FatoDoPerfil {hypothesisId})`, ligado à pessoa (`SOBRE`) e ao
   projeto (`NO_PROJETO`). `fatoDoPerfil` só é `true` quando quem aceitou é o
   sujeito: um fato sobre a pessoa nunca nasce do clique de outra, e o payload
   diz por quê (`motivoSemFato`). A recusada fica só registrada, como antes.
   Os aceites gravados antes desta RN não têm os campos e não viram fato.
4. **O fato entra no contexto dos agentes que conversam com a pessoa.** A
   mensagem do autor a um agente conversacional leva os fatos DELE neste
   projeto — lidos por `QueryUserContextUseCase`, escopados ao projeto, os 5
   mais recentes, com o total ao lado e o recorte dito —, e o engine os põe no
   turno como mensagem `system` EFÊMERA, pelo mesmo caminho do idioma
   ([RN-622](#rn-622)): nunca no histórico, antes da orientação de idioma, com
   teto de 2 000 caracteres. Grafo fora do ar vira log, e o turno segue sem os
   fatos. Turno sem autor não recebe fatos.
5. **Religada.** `ANAMNESE_ENABLED` volta ao default `true` no `runtime.exs` e
   nos três composes; `START_ANAMNESE` não muda (o de produção segue `false`,
   divergência já declarada). O Psicólogo segue pausado.

- **Código:** `apps/engine/lib/engine/anamnese/elegibilidade.ex:59` (`avaliar`);
  `apps/engine/lib/engine/workers/anamnese_worker.ex:63` (`maybe_analyze`),
  `:97` (`narrar_sem_sujeito`);
  `apps/api/src/domain/iam/membros-efetivos.ts:16` (`membrosEfetivos`);
  `apps/api/src/infrastructure/persistence/drizzle/project.repository.ts:209` (`listEffectiveMembers`);
  `apps/api/src/application/use-cases/execution/accept-hypothesis.use-case.ts:75` (`fatoDoPerfil`);
  `apps/api/src/application/graph-projection/graph-event-translator.ts:171` (`projectProfileFact`);
  `apps/api/src/application/use-cases/graph/query-user-context.use-case.ts:68` (`fatos`);
  `apps/api/src/domain/graph/perfil-do-autor.ts:30` (`textoDoPerfilDoAutor`);
  `apps/api/src/application/use-cases/agents/send-agent-message.use-case.ts:152` (`resolverPerfil`);
  `apps/engine/lib/engine/harness/perfil_do_autor.ex:68` (`anexar`);
  `apps/engine/lib/engine/harness/idioma_da_resposta.ex:253` (`com_idioma_do_autor`);
  `apps/engine/config/runtime.exs:315` (`anamnese_enabled?`)
- **Teste:** `apps/engine/test/engine/anamnese/elegibilidade_test.exs:17`
  (caminho feliz), `:35` e `:46` (sem sujeito — casos de falha);
  `apps/engine/test/engine/workers/anamnese_worker_test.exs:305` (sem membro,
  nem com fila, não chama o LLM), `:324`, `:343` (rodada à mão narra), `:360`;
  `apps/engine/test/engine/anamnese/context_builder_test.exs:82`;
  `apps/api/test/infrastructure/persistence/drizzle/project-effective-members.repository.spec.ts:69`;
  `apps/api/test/application/use-cases/execution/accept-dismiss-hypothesis.use-case.spec.ts:136`,
  `:156` (aceite de terceiro não vira fato);
  `apps/api/test/application/graph-projection/graph-projector.spec.ts:361`, `:386`;
  `apps/api/test/application/use-cases/agents/send-agent-message.use-case.spec.ts:181`,
  `:207` (grafo fora do ar);
  `apps/engine/test/engine/harness/perfil_do_autor_test.exs:14`;
  `apps/engine/test/engine_web/controllers/agent_command_controller_test.exs:428`
- **Origem:** AT-277 (item A31 da análise do uso real de 29/09; decisão do dono
  em 01/10)

## O teto da RN-418 vale também pela porta tipada (RN-689)

<a id="rn-690"></a>

### RN-690 — O assistente guarda os `toolCalls` da resposta: o resultado da ferramenta não chega órfão ao provider {#rn-690}

Os agentes conversacionais com laço próprio (Criativo, PO, Arquiteto, Dev Lead,
UX Designer, Staff e Infra Lead) guardavam no histórico a mensagem do
assistente SEM os `toolCalls` da resposta e, em seguida, a mensagem
`role: "tool"` com o `toolCallId`. No fio, o provider recebia um resultado que
respondia a chamada nenhuma e o descartava: o modelo nunca via o que a
ferramenta devolveu e repetia a mesma chamada até o teto do laço (medido na
v7.0.0: o PO chamou `listar_regras_de_negocio` 12 de 12 vezes em dois turnos).

A mensagem do assistente passa a levar os `toolCalls` NATIVOS da resposta
quando há algum — o mesmo formato que o `ToolLoop` já guardava e que o
`ContextManager` agrupa na compactação —, montada num lugar só. Resposta sem
`toolCalls` não ganha a chave. Chamada recuperada do texto (`ToolCallRecovery`,
id nulo) fica de fora: não há id para casar. A api já repassava o campo aos
providers (`toWireMessage` no OpenAI-compatível, `tool_use` no Anthropic); a
reidratação continua trazendo ferramentas como texto.

- **Onde:** `apps/engine/lib/engine/agents/mensagem_do_assistente.ex:17` (`de`);
  `apps/engine/lib/engine/agents/po_server.ex:280`, e o mesmo ponto nos outros seis servidores
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs:93` (a segunda
  chamada leva o `assistant` com `toolCalls` logo antes do `tool` que o
  responde; a resposta final, sem ferramenta, não ganha a chave — caso de falha)
- **Origem:** AT-350

<a id="rn-695"></a>

### RN-695 — A análise da Anamnese não entra no fio da sessão {#rn-695}

Medido no uso real da v7.0.0: o texto que o modelo da Anamnese escreve durante
a rodada ("Analisando a janela do log… usuário (09824667-…)… Decisão de
proficiência") aparecia como BOLHA no fio da sessão de ideação, entre o
Criativo e o PO, com o UUID cru do usuário. A Anamnese não conversa com
ninguém: ela analisa a PESSOA, e o que ela produz é o perfil
([RN-680](#rn-680)).

**A regra:** o texto da rodada é gravado como `anamnese.analysis`, nunca como
`agent.response`. O `ToolLoop` aceita `response_event` no contexto (padrão
`agent.response`, inalterado para todo outro consumidor) e a Anamnese o põe.
O fio da sessão não desenha NENHUM evento cujo ator é o agente `anamnese` —
inclusive o `agent.response` gravado antes da correção. O painel de log da
sessão continua mostrando os eventos dela; o resultado mora em Configurações ›
Perfil de proficiência, sem id cru. Nenhum marcador "perfil atualizado" entra
no fio: fica de fora até alguém pedir.

- **Onde:** `apps/engine/lib/engine/harness/tool_loop.ex:128` (`loop`);
  `apps/engine/lib/engine/workers/anamnese_worker.ex:157` (`build_ctx`);
  `apps/web/src/routes/session-timeline-montagem.tsx:147` (`ehDaAnamnese`)
- **Teste:** `apps/engine/test/engine/workers/anamnese_worker_test.exs:253`
  (o texto sai `anamnese.analysis`; `agent.response` nunca é gravado — caso de
  falha); `apps/web/src/routes/session-timeline-montagem.falha-de-turno.test.tsx:86`
  (a resposta da Anamnese some do fio, a do Criativo fica)
- **Origem:** AT-355

<a id="rn-697"></a>

### RN-697 — O turno da prontidão do Criativo só sintetiza: sem ferramentas {#rn-697}

O turno que `confirm_readiness` dispara consolida as regras num resumo e grava o
`product_brief`. No uso real (v7.0.0, Haiku 4.5) ele levou 25 s e gravou mais
quatro `artifact.business_rule` e um `chat.structured_question` que ninguém
responderia: o PO já tinha entrado pelo aceite implícito (RN-658). O turno passa
a ir ao modelo SEM catálogo de ferramentas, e nenhuma chamada é atendida nele —
nem a que o modelo copie do histórico. O catálogo volta intacto no turno
seguinte; o turno normal continua com `emit_artifact` e
`ask_structured_questions`.

- **Onde:** `apps/engine/lib/engine/agents/criativo_server.ex:223` (`executar_confirm_readiness`);
  `:268` (`ferramentas_da_prontidao`)
- **Teste:** `apps/engine/test/engine/agents/criativo_server_test.exs:172` (o turno
  vai com `tools: []` e não grava regra nem pergunta) e `:192` (regressão: o turno
  normal mantém as duas ferramentas)
- **Origem:** AT-352

<a id="rn-698"></a>

### RN-698 — O texto do turno vira UMA resposta, e o teto de iterações aparece no fio {#rn-698}

Com ferramentas, o modelo escreve em pedaços — um trecho antes da chamada, outro
na volta seguinte, muitas vezes continuando a mesma frase. Cada volta virava a
sua `agent.response`, e o fio recolhe as anteriores em "Passos do turno": à
mostra ficava só o último pedaço (" histórias e tarefas que cubram tudo.",
começando com espaço). O transporte não perdia nada — o frame `final` da api
leva o texto inteiro da VOLTA —; o que se partia era o TURNO. Nos sete
conversacionais, o texto de uma volta com ferramenta é acumulado no processo do
turno e gravado numa `agent.response` só quando o turno fecha (sem ferramenta,
teto, falha, suspensão do Dev Lead, PR da Infra). Pedaço que começa ou termina
com espaço entra como veio; dois pedaços colados viram parágrafos.

O `toolloop.limit_reached` dos conversacionais (RN-166) passa a ser uma linha
no fio, na bolha de falha, origem `modelo`, dizendo o teto ("parou no teto de N
passos sem terminar o turno"); sem o número no payload a linha diz `?`.

A `agent.response` do turno leva o `modelName` (RN-146) em TODO desfecho, não
só no fecho sem ferramenta: quando o turno fecha sem uma chamada final que o
traga (entregou um formulário `ask_structured_questions`, esgotou o teto,
falhou), vale o modelo da última volta acumulada. Sem chamada de LLM que tenha
devolvido modelo, o campo fica `nil` — nunca um modelo inventado (AT-384; o
Infra Lead não grava `modelName` em desfecho nenhum e segue fora).

**Revisão (decisão do dono, 03/10, AT-395): só o fecho do turno na bolha.** No
uso real (loja-teste-2, 02/10) a resposta única juntava o texto de TODAS as
voltas ("Vou registrar… Excelente! Registrei…", dois resumos seguidos no PO).
A `agent.response` do turno continua UMA, mas o `content` passa a ser só o
FECHO — o texto da última volta que escreveu algo (o turno que termina num
formulário, sem texto na última volta, fica com a anterior) — e o texto das
voltas anteriores vai, na ordem, no campo `passos`, ausente quando não há.
Nada some: o fio desenha cada passo como narração do mesmo turno+autor antes
do fecho, e o colapso de "Passos do turno" que já existia os recolhe, fechado
por padrão; os passos não contam no corte de mensagens do fio (RN-644). A
reidratação (RN-580) devolve `passos` ANTES do `content`, no mesmo
`assistant`, para o modelo não perder o que disse no meio do turno. Vale nos
sete conversacionais (o Infra Lead também, sem `modelName`). Sem teto próprio
para `passos`: o acúmulo já era gravado inteiro antes da revisão.

- **Onde:** `apps/engine/lib/engine/agents/texto_do_turno.ex:88` (`descarregar`);
  `:123` (`juntar`); `:51` (`descarregar_com_modelo`); `:65` (`payload_do_turno`);
  `apps/engine/lib/engine/agents/reidratacao.ex:183` (`acumular`);
  `apps/web/src/routes/session-timeline-montagem.tsx:884` (`passos`)
- **Teste:** `apps/engine/test/engine/agents/texto_do_turno_test.exs:43` (três
  voltas: fecho e dois passos), `:56` (uma volta, sem `passos`), `:60` (termina
  em formulário); `apps/engine/test/engine/agents/reidratacao_test.exs`
  (passos antes do fecho); `apps/web/src/routes/SessionPage.ordenacao-e-avisos.test.tsx:502`
  (só o fecho à mostra, passos ao expandir) e `:524` (sem passos, nada extra);
  `apps/engine/test/engine/agents/criativo_server_test.exs:209` (duas
  voltas, uma resposta inteira; nenhuma segunda), `apps/engine/test/engine/agents/texto_do_turno_test.exs`
  e `apps/web/src/routes/session-timeline-montagem.falha-de-turno.test.tsx:85`
  (a linha do teto; sem número, não inventa um); o modelo no formulário em
  `apps/engine/test/engine/agents/criativo_server_test.exs:703` (com modelo) e
  `:724` (sem modelo, `nil`)
- **Origem:** AT-354, AT-384, AT-395

<a id="rn-699"></a>

### RN-699 — O Dev Lead lê o module_map vigente e o backlog do PROJETO, e relê os dois quando o plano é recusado {#rn-699}

Medido no uso real (02/10): aceito o Dev Lead, ele respondeu que faltava o
module_map — e o mapa existia. O kickoff procurava o evento
`architecture.module_map_created`, que NENHUM código emite (o Arquiteto grava o
mapa pela api), e caía sempre em "(sem module_map)". O mapa agora vem da MESMA
leitura de projeto que o AppSec usa (`get_infra_context`, o vigente da api),
nunca de evento da sessão; sem mapa, o kickoff diz que não há.

No mesmo uso, as tarefas nasceram DEPOIS do kickoff, o Dev Lead inventou um
`task_id`, a api recusou o plano e o turno acabou sem nova tentativa. Ele ganha
`read_backlog`: leitura CONTIDA, sem parâmetro, escopada ao projeto (as tarefas
pendentes pela mesma rota da `listar_backlog` do PO, teto de 200 linhas dizendo
o total real, e o module_map vigente). A recusa da api volta ao laço dizendo
para chamar `read_backlog` e corrigir; e só o `propose_execution_plan`
bem-sucedido encerra o turno — antes, qualquer ferramenta bem-sucedida na
última chamada (uma leitura, um `emit_artifact`) encerrava. A instrução do
kickoff proíbe inventar `task_id` e pede que ele só diga ter avaliado as
histórias em que chamou `assess_implementability`.

- **Onde:** `apps/engine/lib/engine/agents/dev_lead_tools.ex:418` (`module_map_vigente`);
  `:353` (`spec_read_backlog`); `:419` (`tarefas_do_backlog`);
  `apps/engine/lib/engine/agents/dev_lead_server.ex:682` (`kickoff_instruction`);

- **Onde:** `apps/engine/lib/engine/agents/dev_lead_tools.ex:418` (`module_map_vigente`);
  `:353` (`spec_read_backlog`); `:419` (`tarefas_do_backlog`);
  `apps/engine/lib/engine/agents/dev_lead_server.ex:682` (`kickoff_instruction`);
  `:416` (`run_turn`)
- **Teste:** `apps/engine/test/engine/agents/dev_lead_server_test.exs:164` (o
  mapa vigente chega ao kickoff e o tipo antigo não é lido), o teste seguinte
  (sem mapa, diz que não há — caso de falha) e `:202` (plano recusado pela api →
  `read_backlog` no mesmo turno, com as tarefas reais)
- **Origem:** AT-362, AT-363

<a id="rn-700"></a>

### RN-700 — O PO não anuncia o handoff ao Arquiteto sem fazê-lo, e história sem tarefa não é entregue {#rn-700}

No uso real o PO escreveu "Handoff ao Arquiteto" e encerrou o turno sem chamar
`offer_handoff` (fere a RN-163), e entregou cinco histórias `ready` com zero
tarefas — o Dev Lead não tinha o que distribuir. No fim de todo turno do PO,
se o servidor ainda não registrou oferta ao Arquiteto naquele processo, ele lê
as regras do projeto (`uncoveredCount`, a mesma cobertura do aceite automático
da RN-660) e o backlog: com toda regra coberta e toda história com ≥ 1 tarefa,
o SERVIDOR oferece o handoff (molde da Infra que propõe sozinha, ADR 0190,
RN-671/672), e a RN-660 segue decidindo o aceite. Com regra coberta e história
sem tarefa, não oferece e grava `backlog.handoff_not_offered` (origem `modelo`)
nomeando as histórias; leitura ou oferta que falha grava o mesmo evento com
origem `infra`. Regra descoberta, ou backlog sem regra/história, não é julgado.
A instrução do PO passa a exigir tarefa por história. Quem cria as tarefas é o
PO (decisão do agente principal na AT-364: ele já tem `create_task`).

- **Onde:** `apps/engine/lib/engine/agents/po_server.ex:520` (`fechar_handoff`);
  `:563` (`oferecer_handoff`)
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs:592` (oferece e
  não repete), `:610` (história sem tarefa: não oferece, nomeia)
- **Origem:** AT-364

## O instalador oferece os modelos locais, e não confunde o dev com uma instalação (RN-691, RN-692)

<a id="rn-702"></a>

### RN-702 — A compactação de contexto respeita a janela padrão de 128k e nunca troca turnos por um marcador vazio {#rn-702}

- **Regra:** sem `context_window` no contexto (os agentes conversacionais não o
  declaram), a janela de compactação é `DEFAULT_CONTEXT_WINDOW`, cujo padrão
  passou de 8 192 para 128 000, o mesmo valor que os agentes de gate e de dev
  declaram. Quando o sumarizador (`context-manager`) falha ou devolve texto
  vazio, o resumo é DETERMINÍSTICO (um trecho de até 300 caracteres de cada
  turno substituído) e o `context.compacted` grava `summaryOrigin:
  "deterministico"` e `falha` com `origem` e `motivo` (RN-059). Com o
  sumarizador respondendo, `summaryOrigin: "modelo"` e `falha: null`.
- **Medição (AT-366):** sessão 17d41c20, Arquiteto em
  `anthropic/claude-haiku-4.5` (janela de 200k): 6 799 tokens passavam de
  `0,7 × 8 192 = 5 734` e compactavam 35 turnos; o sumarizador falhou e o
  resumo gravado foi o marcador `"(35 turnos anteriores omitidos)"`. No turno
  seguinte o Arquiteto pediu de novo uma confirmação que já tinha recebido.
- **Onde:** `apps/engine/lib/engine/harness/context_manager.ex:157` (`summarize`),
  `apps/engine/lib/engine/harness/context_manager.ex:188` (`resumo_deterministico`),
  `apps/engine/config/runtime.exs` (`default_context_window`)
- **Teste:** `apps/engine/test/engine/harness/context_manager_test.exs`
  ("sem context_window declarado: 6,8k tokens NÃO compactam"; "sumarizador
  respondendo: summaryOrigin modelo, sem falha"; caso de falha: "sumarizador
  falhando: falha NOMEADA com origem e resumo determinístico com o conteúdo")
- **Lacuna declarada:** a janela continua não sendo lida do catálogo por
  modelo (o engine não recebe o `context_window` do binding); 128k é o padrão
  da instalação, ajustável por `DEFAULT_CONTEXT_WINDOW`.
- **Origem:** AT-366

<a id="rn-706"></a>

### RN-706 — O agente de execução sabe onde está: pasta, imagem, rede, git tipado e o próprio módulo {#rn-706}

- **Regra:** os dev agents (`dev-*`) e os subagentes de QA (`qa-*`) recebem em
  toda chamada de LLM uma mensagem `system` EFÊMERA de ambiente, pelo mesmo
  caminho do idioma (RN-622) e do perfil do autor (RN-680) — nunca em
  `state.messages`, nunca por servidor. Ela diz a pasta real em que o
  `terminal` roda (o `workspace_root` do laço, traduzido para `/work` pela
  mesma regra do `TerminalExecutor` quando há container `running`
  REGISTRADO), a imagem e a rede do último `artifact.project_image`, que no
  terminal NÃO rodam git (o container de execução pode não ter git): a `main`
  atual, o commit do merge, o push e a PR são do sistema
  ([RN-1010](parte-06.md#rn-1010), AT-798; a liberação do `git merge` no modo pasta da
  [RN-1019](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-1019) segue na política, mas o engine não depende dela) e, para o dev
  agent, o MÓDULO dele: o que consome de outro módulo vem do contrato
  (`listar_contratos_de_modulos`) e se usa por stub/mock, nunca reimplementado,
  e arquivos de raiz que já existem na `dev` (`package.json`, lockfile) não se
  recriam. Sem container `running`, a mensagem DIZ isso e não afirma `/work`.
  Teto de 1 200 caracteres; falha de leitura vira mensagem ausente, nunca turno
  derrubado.
- **Medição (AT-379/AT-378, 02/10, loja-teste):** `dev-api` e `qa-automacao`
  rodaram `cd /workspace` (nenhum prompt cita essa pasta); `git status` deu
  exit 127 numa imagem sem git; o `dev-api` (módulo `api`) criou
  `src/catalog.js` e `package.json`, os mesmos do `dev-catalog`, e o merge
  conflitou.
- **Onde:** `apps/engine/lib/engine/harness/ambiente_do_agente.ex:102` (`montar`),
  `:48` (`com_ambiente`), `:65` (`anexar`),
  `apps/engine/lib/engine/harness/tool_loop.ex:87` (`com_ambiente`)
- **Teste:** `apps/engine/test/engine/harness/ambiente_do_agente_test.exs`
  ("caminho feliz: com container running, a pasta é /work/.worktrees/<agente>";
  caso de falha: "sem container running, não afirma /work")
- **Lacuna declarada:** nenhum aviso no resultado do `git_commit` para arquivo
  de outro módulo (o `module_map` não diz quais caminhos são de cada módulo,
  então o aviso não seria determinístico) e nenhum bloqueio de commit, por
  decisão do dono.
- **Origem:** AT-379, AT-378

<a id="rn-707"></a>

### RN-707 — O semgrep do gate de SecOps tem `$HOME` gravável, e a falha sem saída é nomeada {#rn-707}

- **Regra:** nos composes de produção e de instalação, o tmpfs `/home/engine`
  do engine nasce com o dono do usuário da imagem
  (`/home/engine:uid=1000,gid=1000,mode=0700`). O `SemgrepDetector.Live`
  distingue o exit `1` com JSON (achados) do exit `0`/`1` com stdout vazio,
  que vira `{:error, {:sem_saida, exit_code}}` em vez de `:invalid_output`.
  O veredito do gate NÃO muda: scanner que não rodou continua "pulado" no
  resumo do parecer.
- **Medição (AT-380):** dentro de `brabo-engine-1` (imagem de produção,
  `read_only: true`), o tmpfs `/home/engine` nascia `root` `2755`; o
  `semgrep scan` do gate saía `1` com stdout vazio e
  `PermissionError: '/home/engine/.semgrep'` no stderr, e o parser chamava
  isso de `:invalid_output`. Com o tmpfs `uid=1000` o mesmo comando devolve o
  JSON (exit 0). O Kubernetes não tinha o defeito (`fsGroup: 1000` no
  `emptyDir`).
- **Onde:** `apps/engine/lib/engine/actions/semgrep_detector.ex:73`
  (`interpretar`), `docker/docker-compose.prod.yml`,
  `docker/docker-compose.install.yml`
- **Teste:** `apps/engine/test/engine/actions/semgrep_detector_test.exs`
  ("JSON com results vira findings, inclusive com exit 1 (achou algo)"; caso
  de falha: "exit 1 com stdout vazio é falha de execução nomeada, não
  :invalid_output")
- **Decisão (revista pela [RN-714](#rn-714)):** a frase "o veredito do gate
  NÃO muda" deixou de valer: o dono decidiu (02/10) que SAST que não rodou
  deixa o gate PENDENTE e bloqueando.
- **Origem:** AT-380

<a id="rn-710"></a>

### RN-710 — O Workflows não é delegado sem CI que rode, e não pergunta a ninguém {#rn-710}

No aceite da Infra, o `infra-workflows` respondia com uma pergunta ("qual é o
provider do repositório do projeto?") que nenhum humano recebe — subagente não
conversa —, e a delegação terminava `failed` com origem `modelo` e um
`dev.error` genérico no fio (medido no loja-teste, 02/10). O projeto era
`local`: repositório bare no servidor, sem runner de CI.

- Provider `local` ou ausente: a delegação ao Workflows é **dispensada**
  (`delegation` `dispensed`, com a justificativa nomeada — "repositório local
  … não tem CI que rode"), e a PR de infra sai só com o que o Lead produziu.
  Só `github` e `gitlab` delegam.
- Quando delega, o prompt diz que o provider recebido JÁ é o do projeto e
  proíbe perguntar.
- O subagente que para com TEXTO em vez de chamar a ferramenta continua falha
  nomeada reportada ao lead, mas o diagnóstico diz o que ele pediu: "pediu
  informação que não recebeu, em vez de chamar emit_infra_delegation_result:
  <texto>" (até 300 caracteres).
- O título da PR de infra leva o prefixo `infra: ` só quando o resumo do
  modelo ainda não começa com ele (sem diferenciar maiúsculas) — antes saía
  "infra: infra: Dockerfile…" (AT-396).

- **Onde:** `apps/engine/lib/engine/infra/workflows_agent.ex:61` (`dispensa`),
  `apps/engine/lib/engine/infra/infra_lead.ex:69` (`com_prefixo`),
  `apps/engine/lib/engine/infra/workflows_agent.ex:183` (`parada_sem_ferramenta`),
  `apps/engine/lib/engine/infra/infra_lead_server.ex:1288` (`finalize`)

  `apps/engine/lib/engine/infra/infra_lead_server.ex:1288` (`finalize`)
- **Teste:** `apps/engine/test/engine/infra/workflows_agent_test.exs` ("RN-710: …")
  e `apps/engine/test/engine/infra/infra_lead_server_test.exs` ("RN-710:
  repositório local dispensa o Workflows …") e
  `apps/engine/test/engine/infra/infra_lead_test.exs` ("com_prefixo/1 (AT-396)")
- **Origem:** AT-368, AT-396

<a id="rn-711"></a>

### RN-711 — O conversacional sabe onde está no fluxo, e a restrição técnica do usuário vira decision_record {#rn-711}

- **Regra:** os sete agentes conversacionais (Criativo, PO, Arquiteto, Infra,
  Dev Lead, UX Designer, Staff) recebem em toda chamada de LLM uma mensagem
  `system` EFÊMERA com o fluxo de entrega — as sete etapas na ordem (Criativo →
  PO → Arquiteto → Infra → Dev Lead → dev agents → QA/SecOps → merge manual),
  ONDE o agente está, o PRÓXIMO passo real e QUEM o dispara (humano ×
  sistema) —, pela fachada `EngineApiClient`, depois do ambiente (RN-706) e
  antes do perfil (RN-680) e do idioma (RN-622, sempre o último). A fonte é
  UMA, `Engine.Harness.FluxoDoTime`, conferida por teste contra
  `packages/contracts/fluxo.yml`: todo papel citado existe ali como `active`, e o texto não
  cita etapa fora dele (deploy, pipeline, Dockerfile, InfraAgent). O Criativo
  registra restrição técnica EXPLÍCITA do usuário (linguagem, "nenhuma
  dependência", "sem rede", "um módulo só") como `decision_record`
  (`emit_artifact`, RN-505), sem sermão; o kickoff do Arquiteto lê os
  `artifact.decision_record` da sessão (a mesma leitura por tipo, RN-580) e
  manda respeitá-los, dizendo QUAL e POR QUÊ quando contrariar. O fechamento do
  Arquiteto não pede de novo a confirmação já dada, e a Infra não cola os
  arquivos no chat nem promete deploy.
- **Medição (AT-369/AT-370, 02/10, loja-teste):** o Criativo anunciou o
  Arquiteto como próximo (é o PO); o PO disse que o Arquiteto ia "implementar";
  o Arquiteto, que "dev agents começam" após os ADRs, e pediu "Confirme:
  Arquitetura pronta" depois da confirmação; a Infra despejou ~80 linhas de
  compose no fio. O pedido "Node puro, nenhuma dependência, sem rede, um módulo
  só" não virou artefato e o Arquiteto criou três módulos.
- **Onde:** `apps/engine/lib/engine/harness/fluxo_do_time.ex:120` (`texto`),
  `:97` (`anexar`), `apps/engine/lib/engine/sessions/engine_api_client.ex:647`

  `:97` (`anexar`), `apps/engine/lib/engine/sessions/engine_api_client.ex:754`
  (`llm_turn`), `apps/engine/lib/engine/harness/agents.ex:23` (`identity`),
  `apps/engine/lib/engine/agents/arquiteto_server.ex:408` (`build_kickoff`)
- **Teste:** `apps/engine/test/engine/harness/fluxo_do_time_test.exs`
  ("todo papel citado existe no fluxo.yml como ativo"; caso de falha: "nenhum
  texto cita etapa/agente fora do fluxo"),
  `apps/engine/test/engine/agents/arquiteto_server_test.exs` ("kickoff lê os
  decision_record e manda respeitar \"um módulo só\""),
  `apps/engine/test/engine/harness/agents_test.exs`
- **Lacuna declarada:** a leitura de `decision_record` do Arquiteto é da
  SESSÃO (como as regras e as histórias do kickoff), não do projeto inteiro; e
  nada RECUSA um `create_module_map` que contrarie a restrição — a instrução
  pede a justificativa, não a impõe.
- **Origem:** AT-369, AT-370

<a id="rn-714"></a>

### RN-714 — SAST que não rodou deixa o gate de SecOps pendente, nunca aprovado {#rn-714}

- **Regra:** quando o semgrep do gate de SecOps não roda — binário ausente,
  saída inválida (`:invalid_output`), `:sem_saida`, exceção ou teto de tempo
  —, nenhum veredito é gravado: a PR continua em `awaiting_secops`, o gate
  fica PENDENTE e bloqueia, e a PR não chega ao usuário como aprovada pela
  SecOps. O motivo vai ao fio como `agent.error` de origem `infra`
  ("SAST não rodou: <motivo> — … reexecute o gate depois de corrigir"). O
  contrato externo não muda: continuam os dois vereditos de sempre
  (`approved`/`changes_requested`), um por gate. O gitleaks ausente continua
  só "pulado" no resumo.
- **Reexecução:** o ciclo fica `in_progress` em `gate_states`, e o
  `GateRescuer` o reexecuta no boot do engine e depois do limiar de staleness
  (`gate_rescue_stale_after_seconds`, 15 min). Não há botão de reexecutar
  gate na tela.
- **Sem repetição (AT-386):** o resgate que reencontra o MESMO motivo não
  grava outro `agent.error`: se o último evento do SecOps daquela task
  (`agent.error` ou `artifact.secops_verdict`, lidos por tipo, cauda com teto)
  já é este erro com o mesmo `reason`, fica só a linha de Logger do servidor.
  Motivo diferente, um veredito no meio ou leitura que falha gravam de novo; o
  `agent.error` passa a levar `taskId`.
- **Onde:** `apps/engine/lib/engine/gates/secops_agent_server.ex:116`
  (`run_secops`), `apps/engine/lib/engine/gates/secops_agent_server.ex:144`
  (`sast_nao_rodou`), `apps/engine/lib/engine/gates/secops_agent_server.ex:209`
  (`erro_ja_registrado?`)
- **Teste:** `apps/engine/test/engine/gates/secops_agent_server_test.exs`
  ("sem achados (gitleaks e semgrep limpos): approved"; casos de falha:
  "semgrep com saída inválida: gate pendente, sem veredito, motivo nomeado" e
  "semgrep com binário ausente: gate pendente, sem veredito, motivo nomeado";
  AT-386: "primeiro resgate grava; o segundo, com o mesmo motivo, não",
  "motivo diferente, ou veredito depois do erro, grava de novo", "o SAST que
  volta a rodar aprova como sempre")
- **Revisa:** [RN-707](#rn-707) ("o veredito do gate NÃO muda")
- **Origem:** AT-380

<a id="rn-717"></a>

### RN-717 — O desvio do agente que a Anamnese observa vira sinal do produto, sem dado pessoal {#rn-717}

- **Regra:** laço de agente, turno cancelado pelo usuário e mensagem do
  usuário que repara falha de agente são registrados pela Anamnese como
  `anamnese.agent_deviation` (ferramenta `report_agent_deviation`), nunca como
  perfil da pessoa. O payload é montado no engine por lista de permitidos —
  `agente`, `tipo` (`laco` | `cancelamento_pelo_usuario` |
  `reparo_pelo_usuario`) e `evidenceEventIds` (deduplicados, teto de 20) —,
  sem texto livre e sem id, nome, e-mail ou traço do usuário; campo extra é
  descartado. O tipo não é projetado no grafo do usuário. Tipo fora do
  vocabulário ou sem evidência é recusado, sem gravar.
- **Onde:** `apps/engine/lib/engine/anamnese/tools/report_agent_deviation.ex:73`
  (`payload`), `apps/engine/lib/engine/anamnese/tools/report_agent_deviation.ex:52`
  (`run`), `apps/engine/lib/engine/anamnese/tools.ex`, regra no kickoff
  (`prompts/anamnese-kickoff.md` v4)
- **Teste:** `apps/engine/test/engine/anamnese/report_agent_deviation_test.exs`
  ("reparo do usuário vira anamnese.agent_deviation do AGENTE, só com agente,
  tipo e evidência"; falhas: "tipo fora do vocabulário é recusado e nada é
  gravado", "sem evidência é recusado"),
  `apps/api/test/application/graph-projection/desvio-do-agente-fora-do-grafo.spec.ts`
- **Lacuna declarada:** a api não confere que a evidência existe; a leitura é
  por consulta ao event log, sem tela ([ADR 0205](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0205-desvio-do-agente-como-sinal-do-produto.md)).
- **Origem:** AT-356 (parte 2), decisão do dono de 02/10

## Uma chave de cache, uma pergunta (RN-718)

<a id="rn-719"></a>

### RN-719 — Ferramenta de agente aceita lista enviada como texto JSON, e exceção dentro dela volta ao laço {#rn-719}

**Contexto:** medido ao vivo (02/10, Haiku 4.5 via OpenRouter), o modelo manda
lista e objeto como STRING JSON (`"business_rule_ids": "[\"01M…\"]"`). Três
desfechos: `create_story` descartava os ids calado (história ficava `draft`),
outras ferramentas recusavam e custavam voltas, e `create_c4_diagram` fazia
`Enum.map` numa string e derrubava o turno do Arquiteto com `agent.error`.

**A regra:** toda ferramenta dos sete conversacionais e do `ToolLoop` roda por
UM ponto, `Engine.Harness.ArgumentosDeFerramenta.executar/4`. Argumento cujo
schema declara `array`/`object` e chega como string JSON válida do tipo vira o
valor; string que não é recusa NOMEADA ("o campo X precisa ser uma lista"),
antes de a ferramenta rodar. Campo declarado `string` nunca é tocado. Exceção
levantada dentro da ferramenta vira `tool.result` `ok: false` com
`origem: "codigo"`, e o erro entra no laço como qualquer outro (RN-163): o
turno continua.

- **Onde:** `apps/engine/lib/engine/harness/argumentos_de_ferramenta.ex:26`
  (`executar`), `:73` (`coagir`), `:56` (`falha_interna?`);
  `apps/engine/lib/engine/agents/resultado_de_ferramenta.ex:29` (`payload`);
  `apps/engine/lib/engine/harness/tool_loop.ex:409` (`run_direct`);
  `apps/engine/lib/engine/agents/arquiteto_server.ex:357`
  (`executar_ferramenta`, o mesmo helper nos outros seis servidores)
- **Teste:** `apps/engine/test/engine/harness/argumentos_de_ferramenta_test.exs`
  (`create_story` com ids em string JSON grava os ids; `create_c4_diagram` com
  `actors` em string JSON funciona; string não-JSON num campo array é recusa
  nomeada; ferramenta que lança não encerra o turno do `ToolLoop` e grava
  `tool.result` `ok: false`)
- **Origem:** AT-387

<a id="rn-721"></a>

### RN-721 — O id encurtado de história ou tarefa é resolvido dentro do projeto {#rn-721}

O Arquiteto passava a `assign_story_modules` os 8 primeiros caracteres do id da
história, a api respondia 400 "storyId must be a UUID" e, depois de oito
tentativas, nenhuma história ganhava módulo (loja-teste-2, 02/10). Toda
ferramenta de agente que recebe id de história ou tarefa —
`assign_story_modules` e `create_task` (`story_id`), `assess_implementability`
(`storyId`) e `propose_execution_plan` (`tarefas[].taskId`) — passa o id por
`Engine.Harness.IdDoBacklog` antes de chamar a api:

- UUID completo segue sem consulta.
- Prefixo de no mínimo 8 caracteres hexadecimais é resolvido contra o backlog
  do PROJETO (`list_backlog`): um só id que começa com ele vira o UUID;
  nenhum é recusa nomeada ("nenhuma história do projeto tem id começando com
  …"); mais de um é recusa nomeada ("o prefixo … é ambíguo"). A recusa volta
  ao modelo como resultado da ferramenta (RN-163).
- O que não é nem UUID nem prefixo segue como veio, e quem recusa é a api.

- **Onde:** `apps/engine/lib/engine/harness/id_do_backlog.ex:21` (`resolver`),
  `:43` (`resolver_em`); `apps/engine/lib/engine/agents/dev_lead_tools.ex:180`
  (`resolver_tarefas`)
- **Teste:** `apps/engine/test/engine/harness/id_do_backlog_test.exs` (prefixo
  único resolve; ambíguo e inexistente recusam nomeados)
- **Origem:** AT-390

## A Anamnese não paga duas vezes pela mesma janela, e o resgate de gate não reinicia ciclo que espera alguém (RN-722)

<a id="rn-722"></a>

### RN-722 — A Anamnese fecha a janela que avaliou e só roda com interação nova; o resgate de gate pergunta pela task, respeita a decisão humana pendente e estaciona o ciclo velho {#rn-722}

- **Regra (Anamnese):** (1) a rodada que AVALIOU a janela e encerrou sem
  perfil (`skip_proficiency`) grava `anamnese_runs` com zero perfis, e a
  próxima começa em `window_to` — revisa a cláusula da RN-680/do moduledoc
  "rodada que não conclui não grava": rodada que FALHA (teto, orçamento,
  provider) continua sem gravar, e a que nem chega ao LLM (sem sujeito,
  triagem, teto diário) não fecha nada; (2) os eventos que a própria Anamnese
  escreve (`anamnese.*` e todo evento de ator `agent`/`anamnese`) e os de
  ator `system` ficam fora da janela e da contagem da triagem; (3) decisão do
  dono de 02/10: sujeito é quem tem ao menos **5** interações próprias NOVAS
  (eventos de `actor_kind: "user"` mais decisões, na janela que já começa no
  fim da última tentativa) — revisa o "ao menos UMA" da RN-680 —, e o projeto
  tem no máximo **4** rodadas pagas por dia UTC (concluída, falha ou
  `run_skipped` escrito pelo modelo; o pulo sem sujeito não conta). Abaixo de
  qualquer dos dois, nenhuma chamada ao LLM nem ao RAG; o motivo vai ao log e,
  só na rodada pedida à mão, a `anamnese.run_skipped` (`causa:
  "teto_diario"` ou `"sem_sujeito_elegivel"`).
- **Regra (resgate de gate, revisa a RN-140):** o `GateRescuer` (a) considera
  vivo o ciclo cuja TASK está em voo no lead, perguntando a ele
  (`{:em_voo?, task_id}`), e não mais o processo do projeto — lead ocioso não
  segura o resgate; lead ocupado demais para responder conta como vivo; (b)
  não reinicia ciclo cuja sessão tem `proposed_action` PENDENTE de ator do
  gate (`qa*`, `secops*`, `appsec`) — só registra no log; (c) decisão do dono
  de 02/10: ciclo parado há mais de 2 h desde a ÚLTIMA ATIVIDADE (`updated_at`)
  é ESTACIONADO (`parked_at`) com `gate.rescue_parked` no log da sessão
  (task, gate, idade, motivo), nem no boot nem no tick é retomado, e retomar
  exige gesto humano (`GateRescuer.retomar_estacionado/3`).
- **Onde:** `apps/engine/lib/engine/workers/anamnese_worker.ex:189`
  (`fechar_janela`), `apps/engine/lib/engine/workers/anamnese_worker.ex:104`
  (`dentro_do_teto_diario?`),
  `apps/engine/lib/engine/session_events/event.ex:194`
  (`project_window_query`), `apps/engine/lib/engine/session_events/event.ex:202`
  (`count_anamnese_rounds_since`),
  `apps/engine/lib/engine/anamnese/elegibilidade.ex:67`
  (`min_interacoes_proprias`),
  `apps/api/src/application/use-cases/anamnese/record-proficiency.use-case.ts:160`
  (`fecharJanelaSemPerfil`), `apps/engine/lib/engine/gates/gate_rescuer.ex:379`
  (`task_em_voo?`), `apps/engine/lib/engine/gates/gate_rescuer.ex:403`
  (`aguardando_humano?`), `apps/engine/lib/engine/gates/gate_rescuer.ex:321`
  (`estacionar`), `apps/engine/lib/engine/gates/gate_rescuer.ex:359`
  (`retomar_estacionado`), `apps/engine/lib/engine/gates/qa_lead_server.ex:95`
  (`handle_call`)
- **Teste:** `apps/engine/test/engine/workers/anamnese_worker_test.exs`
  (describe "a janela avaliada fecha (RN-722)": "skip_proficiency grava a
  rodada vazia; a segunda começa em window_to e, sem interação nova, não chama
  o LLM"; falhas: "falha ao fechar a janela não vira falha da rodada", "rodada
  que FALHA não fecha a janela"; describe "piso de interações e teto diário
  (RN-722)"), `apps/engine/test/engine/anamnese/elegibilidade_test.exs`,
  `apps/engine/test/engine/session_events/event_window_test.exs` ("dez
  eventos da Anamnese sozinhos não passam a triagem"),
  `apps/engine/test/engine/gates/gate_rescuer_test.exs` ("lead do projeto vivo
  e OCIOSO não segura o resgate de uma task perdida", "ciclo com ação PENDENTE
  de ator do gate espera o humano", "ação pendente de OUTRO ator não segura o
  resgate", "ciclo parado há mais de 2 h é ESTACIONADO", "ciclo parado há
  MENOS de 2 h segue sendo resgatado"),
  `apps/api/test/application/use-cases/anamnese/record-proficiency.use-case.spec.ts`
  (describe "fecharJanelaSemPerfil (RN-722)")
- **Lacuna declarada:** retomar um ciclo estacionado não tinha tela nem rota
  — era chamada de operador (`bin/engine rpc`); fechou na
  [RN-724](parte-05.md#rn-724) (rota e botão no evento `gate.rescue_parked`). A pendência humana é lida
  pela SESSÃO do ciclo (a `proposed_action` não tem `task_id`)
  ([ADR 0207](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0207-ciclo-de-gate-velho-estaciona.md)).
- **Origem:** AT-391 (uso real de 02/10: ~US$ 8,90 de Anamnese num dia sem
  ninguém pedir; ciclo de gate reiniciado com ação pendente e outro 8 h sem
  resgate), decisões do dono de 02/10

**Revisada pela [RN-923](parte-06.md#rn-923) ([ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md)).** O resgate AUTOMÁTICO (tick) de um ciclo vale uma vez: o segundo estaciona com `motivo: "retomada_automatica_ja_usada"` e espera o "Retomar gate", que zera o contador. O estacionamento de 2 h segue como está.

## Uma chave de cache, uma pergunta (RN-718)

<a id="rn-723"></a>

### RN-723 — A Infra herda a rede que o Arquiteto declarou para o projeto {#rn-723}

Decisão do dono em 02/10 ([ADR 0208](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0208-a-infra-herda-a-rede-do-arquiteto.md)),
revisando a rede literal `none` da subida no aceite da [RN-671](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-671). A
eleição da Infra usa o `network` da `artifact.project_image` mais recente
emitida pelo Arquiteto (`actor_id: "arquiteto"`, qualquer sessão do projeto),
lido localmente pelo engine; sem decisão dele, ou com valor fora de
`none`/`egress`, segue `none`. Vale para a subida do servidor no aceite e para
a tool `propose_container_start` sem `network`. A autonomia semeada não muda:
`egress` sobe sem clique, e o preço (a rede `egress` alcança as portas
publicadas da máquina, ADR 0189) está declarado no ADR.

- **Código:** `apps/engine/lib/engine/session_events/event.ex:139` (`rede_do_arquiteto`),
  `apps/engine/lib/engine/infra/infra_lead_server.ex:803` (`rede_herdada`)
- **Testes:** `apps/engine/test/engine/infra/infra_lead_server_test.exs` —
  "RN-723: a subida herda a rede `egress` que o Arquiteto declarou" e
  "RN-723: rede do Arquiteto fora do vocabulário — a subida segue `none`"
- **Origem:** AT-392
