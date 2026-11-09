---
id: rn-engine-parte-06
title: 'Regras de negócio — Engine — parte 6 (desde RN-880)'
sidebar_label: 'Engine — parte 6 (desde RN-880)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

# Engine — parte 6 (desde RN-880)

## A Anamnese não paga duas vezes pela mesma janela, e o resgate de gate não reinicia ciclo que espera alguém (RN-722)

<a id="rn-880"></a>

### RN-880 — O entregável responde CORS configurável, com `servers` relativo e swagger-ui pinado {#rn-880}

- **Regra:** na mesma cláusula, a API do entregável responde CORS com origens
  de `CORS_ORIGINS` (padrão `http://localhost:<porta>` e
  `http://127.0.0.1:<porta>`), `OPTIONS` 204 e `Access-Control-Allow-*` com
  `Authorization` e `Content-Type`; o `/openapi.json` declara `servers` só
  relativo (`/`) — URL absoluta criaria o erro de CORS quando a página é aberta
  por outro host —, e o swagger-ui de CDN vai com versão exata, nunca `@5`. O
  QA prova com um preflight de outra origem (`curl -X OPTIONS`) e reprova sem
  os cabeçalhos, com `servers` absoluto ou com o CDN flutuante.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:698` (`clausula_de_openapi`);
  `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:122` (`secao_do_ponto_de_entrada`)
- **Teste:** os mesmos da RN-879 (caminho feliz e falha nos dois arquivos)
- **Origem:** AT-532

<a id="rn-881"></a>

### RN-881 — O engine imprime as outras decisões do projeto para o dev e o QA {#rn-881}

- **Regra:** o `decisoesDoProjeto` que a api devolve no `dev-context`
  (RN-872, ADR 0215, já com teto) vira a seção "Outras decisões do projeto",
  separada e DEPOIS das decisões da tarefa, na unidade da story do dev e no
  recorte do QA. Vazio ou ausente não escreve nada; o engine não aplica teto
  próprio.
- **Onde:** `apps/engine/lib/engine/dev/context_builder.ex:133` (`secao_de_decisoes_do_projeto`);
  `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:20` (`texto`)
- **Teste:** `apps/engine/test/engine/dev/context_builder_test.exs` ("RN-881:
  decisoesDoProjeto vira a seção..." e "RN-881 falha: sem decisoesDoProjeto a
  seção some"); `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs`
  ("RN-881: outras decisões do projeto")
- **Origem:** AT-526 (fatia F4, lado do engine)

<a id="rn-885"></a>

### RN-885 — O CORS do entregável usa a porta PUBLICADA, e o QA confere o header nas duas origens {#rn-885}

- **Regra:** revisa a RN-880 (que continua valendo no resto). O padrão de
  `CORS_ORIGINS` do entregável usa a porta PUBLICADA — `APP_PORT`, que o
  compose passa ao app —, nunca a interna `PORT`: no TP-01 (16ª) o padrão saiu
  com `PORT=3000` e, com o compose publicando 8080, nenhuma origem real recebia
  `Access-Control-Allow-Origin` (medido com curl: `:3000` recebe, `:8080` não;
  no Chrome, `Failed to fetch`). O QA faz o preflight contra a porta PUBLICADA,
  uma vez para `http://localhost:<APP_PORT>` e outra para
  `http://127.0.0.1:<APP_PORT>`, e reprova sem o header
  `Access-Control-Allow-Origin` — 204 sozinho não basta, e CORS só na porta
  interna é ITEM.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:698` (`clausula_de_openapi`);
  `apps/engine/lib/engine/gates/recorte_da_tarefa.ex:122` (`secao_do_ponto_de_entrada`)
- **Teste:** `apps/engine/test/engine/dev/report_done_instrucao_test.exs`
  ("RN-885: o padrão do CORS usa a porta PUBLICADA, nunca a interna"; falha:
  "RN-879/880 falha: tarefa sem rota não recebe CORS nem PUBLIC_BASE_URL");
  `apps/engine/test/engine/gates/recorte_da_tarefa_test.exs` ("RN-885: o
  preflight é na porta PUBLICADA, nas duas origens, e confere o header")
- **Origem:** AT-535

<a id="rn-890"></a>

### RN-890 — O QA cobra o código de saída do comando de linha, na recusa também {#rn-890}

- **Regra:** a instrução do QA de Automação manda conferir, no teste que
  prova um comando de linha da entrega (CLI, script do `package.json`), o
  código de saída 0 no caminho feliz e diferente de 0 quando o comando recusa
  a entrada; teste sem essa conferência na recusa é regra sem cobertura e vai
  para `itens`. A instrução da QA-estratégia pede, em `criteriosExecutaveis`,
  esses dois critérios para todo comando que recusa entrada. É instrução de
  agente: nenhum gate novo, nenhuma mudança de veredito ou de estrutura.
- **Onde:** `apps/engine/lib/engine/gates/qa_automacao_agent.ex:250`
  (`instrucao_de_codigo_de_saida`),
  `apps/engine/lib/engine/gates/qa_estrategia_agent.ex:130`
  (`instrucao_de_codigo_de_saida`)
- **Teste:** `apps/engine/test/engine/gates/qa_automacao_agent_test.exs` ("a
  instrução cobra código de saída 0 no feliz e diferente de 0 na recusa");
  `apps/engine/test/engine/gates/qa_estrategia_agent_test.exs` ("os arquivos
  da entrega entram na mensagem")
- **Origem:** AT-542 (TP-01, 17ª: `npm run user:create` recusava a senha e
  saía com 0)

<a id="rn-893"></a>

### RN-893 — O PO declara a borda do valor informado no RF e no DoD {#rn-893}

- **Regra:** a instrução de kickoff do PO (com ou sem event log) traz uma
  terceira obrigação: todo RF que recebe um valor informado pelo usuário
  (data, número, texto, lista, limite) declara, no RF e no DoD, se a borda —
  passado/futuro, zero, vazio, negativo, o próprio limite — é ACEITA ou
  RECUSADA (com o status HTTP/erro); o exemplo é a expiração no passado. Sem
  saber, o PO chama `declare_open_question` com `afeta.historias` e uma
  sugestão, nunca inventa nem omite. Régua de PROMPT, no molde da
  [RN-790](parte-05.md#rn-790): nenhuma ferramenta recusa história sem borda. O PO NÃO
  passa a reescrever `business_rule`; Criativo, QA, schema e gate não mudam.
- **Onde:** `apps/engine/lib/engine/agents/po_server.ex:708` (`obrigacoes`)
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs:438` (a
  instrução de kickoff traz a obrigação da borda) e `:460` (sem event log, o
  kickoff ainda a carrega)
- **Origem:** AT-541 (TP-01 de 14/10: o entregável aceitou `expiresAt` no
  passado e o link nasceu expirado, 410; o RF da história só dizia que a
  expiração é opcional), decisão do dono de 15/10

<a id="rn-895"></a>

### RN-895 — A recusa de argumento diz o que chegou e o formato esperado {#rn-895}

- **Regra:** revisa a [RN-719](parte-04.md#rn-719) e a [RN-725](parte-05.md#rn-725). Campo declarado `array`/`object` que chega como texto fora de JSON, ou como número/booleano/tipo trocado, é recusado antes da ferramenta com "o campo X chegou como <tipo>; envie <formato>", com exemplo (`["item 1","item 2"]`, `{"chave":"valor"}`), nunca com o valor. A frase do `emit_plano_de_teste` passou a pôr as chaves entre crases, e por isso a recusa leva as chaves recebidas.
- **Onde:** `apps/engine/lib/engine/harness/argumentos_de_ferramenta.ex:84` (`coagir`); `apps/engine/lib/engine/gates/tools/emit_plano_de_teste.ex:73` (`run`)
- **Teste:** `apps/engine/test/engine/harness/argumentos_de_ferramenta_test.exs:193` e `:201` (o formato e o tipo recebido) e `:210` (as chaves recebidas)
- **Origem:** AT-583 (TP-01 18ª e 19ª: o `dod` chegou como checklist markdown e o plano de teste foi recusado 4 vezes sem dizer o que veio)

<a id="rn-896"></a>

### RN-896 — O `epic_id` é validado antes da api {#rn-896}

- **Regra:** `create_story` recusa `epic_id` que não é UUID ("epic_id inválido; …"). Quando o PO já criou épicos neste processo (`epicos_conhecidos`) e o id não é um deles, relê o backlog UMA vez (`list_backlog`): se o id está lá, aceita; senão recusa listando `id=título` do backlog (teto de 20 linhas, dizendo o total se truncar, ADR 0060). Mapa vazio ou leitura do backlog que falha é "não sei" e não recusa — a api decide.
- **Onde:** `apps/engine/lib/engine/harness/tools/create_story.ex:57` (`epico_valido`)
- **Teste:** `apps/engine/test/engine/harness/argumentos_de_ferramenta_test.exs:224` e `:233`
- **Origem:** AT-584 (o qwen mandou `EPIC_ID_PLACEHOLDER_NAO_USAR_AQUI` e a api respondeu com o nome do DTO)

<a id="rn-897"></a>

### RN-897 — O corte do provider por `max_tokens` num gate é origem `modelo` {#rn-897}

- **Regra:** o `agent.error` dos gates `qa-estrategia`, `qa-automacao`, `qa-performance-seguranca` e `appsec` classifica "Tool calls cutoff by max_tokens" como `modelo` (o raciocínio comeu o teto, RN-059); qualquer outro erro de LLM segue `infra`.
- **Onde:** `apps/engine/lib/engine/gates/origem_do_erro.ex:10` (`de_llm`)
- **Teste:** `apps/engine/test/engine/gates/origem_do_erro_test.exs:7`
- **Origem:** AT-586 (BaseTen 502 gravado como `infra`)

<a id="rn-898"></a>

### RN-898 — Resposta cortada pelo teto, sem texto algum, fecha o turno dita {#rn-898}

- **Regra:** o turno de agente conversacional cuja última resposta de LLM foi
  cortada pelo teto de saída ([RN-737](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-737)) e que não escreveu texto em
  volta nenhuma NÃO fecha calado: a linha "Resposta cortada pelo limite de
  tamanho." (en: "Response cut off by the length limit.") vira o fecho de uma
  `agent.response` com `modelName`, e a bolha mostra "Continuar de onde
  parou" ([RN-749](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-749)). Vale para os sete conversacionais, que gravam o
  fecho por `payload_do_turno/2`. Fere a [RN-059](parte-01.md#rn-059) e a
  [RN-163](parte-01.md#rn-163) quando falta.
- **Onde:** `apps/engine/lib/engine/agents/texto_do_turno.ex:65`
  (`payload_do_turno`)
- **Teste:** `apps/engine/test/engine/harness/resposta_cortada_test.exs:104`
- **Origem:** AT-570 (TP-01 18ª: a 3ª chamada do PO saiu 8192/8192 e o turno
  fechou em `idle` sem `agent.response`)

<a id="rn-899"></a>

### RN-899 — Resposta vazia sem corte vira agent.error de origem modelo {#rn-899}

- **Regra:** o fecho do laço conversacional sem texto, sem ferramenta e sem
  corte grava `agent.error` com origem `modelo` e a frase "o modelo não
  devolveu resposta" (`FalhaDeTurno`), nos sete servidores. É fala do agente
  para o heartbeat ([RN-581](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-581)): a sessão com turno calado fechava por
  `heartbeat_timeout` 26 s depois de o usuário sair da tela. Presença por aba
  do projeto NÃO entra ([RN-064](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-064)).
- **Onde:** `apps/engine/lib/engine/agents/falha_de_turno.ex:63` (`origem`),
  `apps/engine/lib/engine/agents/po_server.ex:327` (`gravar_texto_do_turno`)
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs:194` e
  `apps/engine/test/engine/agents/texto_do_turno_test.exs:96`
- **Origem:** AT-572 (TP-01 18ª, achado 4)

<a id="rn-900"></a>

### RN-900 — `write_file` recusa reescrever o README e apagar a seção de uso da Infra {#rn-900}

- **Regra:** `write_file` substitui o arquivo inteiro. Quando o `path` é um
  README (`README*`), o arquivo atual tem a seção `## Rodar na sua máquina` e o
  conteúdo novo não a traz, a ferramenta recusa com erro nomeado e não escreve
  nada. Trocar um trecho exige reescrever o README completo, com a seção. O
  título é uma constante só (`titulo_secao_de_uso/0`), usada também pelos
  prompts da Infra e do dev, para que a recusa e a instrução não divirjam. Não
  é gate: a recusa é da própria ferramenta, e não cobre escrita pelo `terminal`
  (`cat >`, `sed -i`).
- **Onde:** `apps/engine/lib/engine/harness/tools/write_file.ex:62`
  (`recusa_de_secao_perdida`)
- **Teste:** `apps/engine/test/engine/harness/tools/write_file_test.exs:41`
  (a reescrita sem a seção é recusada e o arquivo fica intacto); o caminho
  feliz (README com a seção reescrito com a seção, e arquivo que não é README)
  está nas primeiras duas provas do mesmo arquivo
- **Origem:** AT-571 (TP-01 18ª de 19/10: o dev agent reescreveu o README ao
  corrigir um parecer do QA e a seção de uso que a Infra escrevera sumiu; nenhum
  gate notou)

<a id="rn-903"></a>

### RN-903 — O 429 do provider é limite de uso do modelo, não falha de rede {#rn-903}

- **Regra:** a task que o dev agent bloqueia porque o modelo respondeu 429
  (código `rate_limit`, ou texto com `(429)` ou "limite de uso") diz no motivo
  "limite de uso do modelo atingido (429)", e a retomada automática diz que,
  se repetir, é para trocar o modelo do dev agent. Nunca diz "falha
  passageira de rede". A origem segue `infra` e a retomada da RN-864 não muda
  (até 3, depois de 1, 3 e 10 min; pausa de 60 s, que o `dev.idle` nomeia como
  "depois de limite de uso do modelo"). A falha de rede segue com o texto de
  sempre.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:1222`
  (`limite_de_uso?`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1218`
  (`motivo_da_parada`), `apps/engine/lib/engine/dev/dev_agent_server.ex:1075`
  (`bloquear_passageira`), `apps/engine/lib/engine/dev/agent_io.ex:302`
  (`pausar_por_rede`)
- **Teste:** `apps/engine/test/engine/dev/dev_agent_server_test.exs` ("429 do
  provider: o motivo diz limite de uso do modelo, não rede"; falha: "falha de
  rede continua com o texto de rede, não de limite")
- **Origem:** AT-594 (TP-01 20ª, 19/10: o 429 do `laguna-s-2.1:free` bloqueou
  as tarefas com "falha passageira de rede", e o diagnóstico dizia limite de
  uso)

<a id="rn-904"></a>

### RN-904 — O corte do teto de saída não repete a chamada com o catálogo inteiro {#rn-904}

- **Regra:** quando o Jev restringe o menu e o modelo responde SEM ferramenta,
  o passo é repetido UMA vez com o catálogo inteiro (RN-625) — exceto quando a
  resposta veio CORTADA pelo teto de saída (`truncated`). O corte não é erro de
  menu: a volta com o catálogo inteiro só aumentaria o prompt e gastaria outro
  teto de saída. Vale nas duas fachadas (`llm_turn` e `llm_turn_stream`, esta
  só sem texto já entregue). Quem trata o corte é a retentativa da RN-780 no
  `ToolLoop`, que não muda.
- **Onde:** `apps/engine/lib/engine/harness/roteamento_de_ferramenta.ex:126` (`repetir_com_catalogo_inteiro?`)
- **Teste:** `apps/engine/test/engine/harness/roteamento_de_ferramenta_test.exs:274`
  (resposta vazia cortada não repete, nos dois caminhos; sem corte, repete)
- **Origem:** AT-578 (EP-026, levantamento de 21/10): o 1º turno do PO na 18ª
  rodada gastou duas voltas de 8192 tokens de saída.

<a id="rn-905"></a>

### RN-905 — O teto de passos diz o que foi gravado e o que falta, e oferece continuar {#rn-905}

- **Regra:** quando um agente conversacional para no limite de passos, o evento
  do teto (`toolloop.limit_reached`; no Criativo, o `agent.error` com
  `reason: "limite_de_iteracoes"`) leva `gravado`, a linha da RN-731 lida ANTES
  de o texto do turno ser gravado (ela sai ali e não na `agent.response`, nunca
  nas duas). O PO leva também `regrasSemHistoria`, o `uncoveredCount` que
  `fechar_handoff` já lê; a leitura que falha deixa a chave ausente, nunca erro.
  O fio mostra o motivo sem jargão, a linha gravada, as regras sem história e o
  botão "Continuar de onde parou" (RN-749, mensagem do usuário, que a fila da
  RN-673 absorve com turno em curso) só para os sete conversacionais com a
  sessão ativa; `dev-*`/`qa-*` ganham o texto, sem botão. O botão nunca continua
  sozinho.
- **Onde:** `apps/engine/lib/engine/agents/po_server.ex:254` (`run_turn`);
  `apps/web/src/routes/session-timeline-montagem.tsx:1101` (`conversacional`)
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs:548` (gravado e
  regrasSemHistoria; sem a leitura, sem a chave);
  `apps/web/src/routes/session-timeline-montagem.falha-de-turno.test.tsx:108`
  (bolha, botão para o mesmo agente; sem botão em `dev-*` e sessão inativa)
- **Origem:** AT-590 (EP-031).

<a id="rn-908"></a>

### RN-908 — O kickoff do PO pede o backlog em lote, depois de ler, em camadas {#rn-908}

- **Regra:** o kickoff do PO manda, nesta ordem: ler `listar_regras_de_negocio` e `listar_backlog` na mesma resposta, sem escrita junto; depois todos os épicos numa resposta só; depois todas as histórias, com o `epic_id` devolvido; depois todas as tarefas, com o `story_id` devolvido. Nunca recria épico que já existe, e no máximo cerca de 10 chamadas de ferramenta por resposta. Motivo medido: sem o pedido de lote, o nemotron faz 1 ferramenta por resposta e o qwen faz 3; com ele, 9 em cada (`parallel_tool_calls` não mudou nada). Ler primeiro é o que impede o qwen de criar épicos sem ler o backlog. Não altera o teto `@max_iterations` (RN-166).
- **Onde:** `apps/engine/lib/engine/agents/po_server.ex:622` (`build_kickoff`)
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs:518` (leitura antes da escrita; lote em camadas épicos → histórias → tarefas)
- **Origem:** sonda da AT-591 (21/10), implementada na AT-596 (EP-026).

<a id="rn-913"></a>

### RN-913 — Falha igual repetida de ferramenta no turno corrige na 2ª e para na 3ª {#rn-913}

- **Regra:** em cada turno, o harness conta as falhas IGUAIS de ferramenta (mesma ferramenta e mesmos argumentos, `tool.result` `ok: false`). Na 2ª, o resultado devolvido ao modelo ganha a correção "esta chamada já falhou igual… mude os argumentos ou use outra abordagem". Na 3ª, o laço PARA e grava `agent.error` com origem `modelo` (`reason: falha_repetida_de_ferramenta`), nunca em silêncio (RN-059, RN-163). Falhas diferentes não somam, e o contador zera a cada turno. Vale para os sete conversacionais e para o `ToolLoop`, pelo despacho único da RN-719; cada laço para pelo desfecho que já tinha (os conversacionais pelo caminho do teto de iterações, com o `agent.error` no lugar do `toolloop.limit_reached`; o `ToolLoop` devolvendo `{:ok, ctx}` com `last_error`).
- **Onde:** `apps/engine/lib/engine/harness/argumentos_de_ferramenta.ex:26` (`executar`), `apps/engine/lib/engine/harness/falha_repetida.ex:30` (`registrar`), `:51` (`parou?`), `:56` (`narrar`), `apps/engine/lib/engine/harness/tool_loop.ex:123` (`parou_ou_loop`)
- **Teste:** `apps/engine/test/engine/harness/falha_repetida_test.exs` (2ª corrige, 3ª para no `ToolLoop`, falhas diferentes não somam, zera entre turnos)
- **Origem:** AT-588 (EP-026), decisão do dono de 22/10 (K=2 corrige, K=3 para).

<a id="rn-918"></a>

### RN-918 — O agente escreve o próprio plano com `registrar_plano`, e o último `agent.plan` é o vigente {#rn-918}

- **Regra:** `registrar_plano` grava `agent.plan` com o objetivo (até 200 caracteres) e de 1 a 12 passos de até 160 caracteres, cada um `pendente`, `em_curso`, `feito` ou `descartado`. Cada chamada manda o plano INTEIRO e substitui o anterior (o vigente é o último `agent.plan` do ator). Acima do teto a ferramenta RECUSA nomeando o limite, nunca corta. Não é `proposed_action` (escrever o plano não é efeito externo) nem artefato (fora de `ferramentas_de_artefato/0`) e a descrição não nomeia idioma (RN-667). Têm a ferramenta os seis conversacionais com o Infra Lead, o dev e os subagentes de QA e AppSec; ficam fora o subagente de validação de arquivo da Infra e o `context-manager`. A `Reidratacao` mostra só o último plano de cada ator, como uma nota, e pula o `tool.call`/`tool.result` da ferramenta.
- **Onde:** `apps/engine/lib/engine/harness/tools/registrar_plano.ex:84` (`run`), `apps/engine/lib/engine/agents/reidratacao.ex:182` (`so_o_ultimo_plano_de_cada_ator`)
- **Teste:** `apps/engine/test/engine/agents/diario_vivo_test.exs` (`registrar_plano`: grava, substitui, recusa acima do teto; `Reidratacao`: só o último plano)
- **Origem:** AT-582 (EP-031), decisão do dono de 27/10; [ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md).

<a id="rn-919"></a>

### RN-919 — O diário é a projeção do log mais o plano, sem tabela, e diz o que está confirmado e o que ficou sem desfecho {#rn-919}

- **Regra:** `Engine.Agents.Diario` lê a cauda do log do agente, a partir do marco do turno (`agent.status: working`, o `dev.working` da tarefa ou o `agent.turn_resumed` do subagente de gate), e devolve o plano vigente, os efeitos confirmados (`tool.result` ok, `proposed_action.executed`, artefatos, commit preservado), as chamadas sem desfecho, as ações pendentes (`proposed_action.created` sem decisão), a última atividade e se a retomada automática já foi usada. A fonte de verdade continua o event log. `RetomadaDoTurno` transforma o diário numa mensagem `system` EFÊMERA (teto de 2 000 caracteres, depois de `DecisoesDoProjeto` e antes de `PerfilDoAutor`; no `ToolLoop`, por `ctx[:retomada]`): onde parou, o plano, o que não repetir, o que conferir antes e as ações pendentes que não se propõem de novo. Nunca é mensagem falsa do usuário. Push e PR são repetíveis (a PR aberta é reaproveitada, RN-812); merge NUNCA na retomada (RN-418); o engine não reexecuta chamada sem desfecho, quem decide é o modelo, depois de conferir o estado.
- **Onde:** `apps/engine/lib/engine/agents/diario.ex:85` (`de_eventos`), `:255` (`retomada_usada?`), `apps/engine/lib/engine/harness/retomada_do_turno.ex:69` (`texto`)
- **Teste:** `apps/engine/test/engine/agents/diario_vivo_test.exs` (`Diario.de_eventos/2`, `RetomadaDoTurno`, marco por opção e retomada usada)
- **Origem:** AT-582 (EP-031); [ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md).

<a id="rn-920"></a>

### RN-920 — O turno conversacional que o reinício matou é retomado UMA vez no boot, se recente {#rn-920}

- **Regra:** revisa a [RN-586](parte-03.md#rn-586). A varredura de boot (`TurnoOrfao.varrer/2`) retoma o turno órfão cujo agente teve atividade há no máximo 900 s (`:retomada_automatica_janela_segundos`, a mesma régua da [RN-823](parte-05.md#rn-823), medida pela última atividade do agente e não pelo `working`) e que ainda não foi retomado: grava `agent.error` (`turno_interrompido_por_reinicio`, `retomada: "automatica"`), `agent.status: idle` e `agent.turn_resumed` (`automatica: true`) e acorda o agente, cujo `init/1` agenda `:retomar_turno_interrompido` ANTES da entrega da fila (RN-673). O teto é durável no log: um `agent.turn_resumed` do agente entre o último status não-`working` e o `working` órfão. Turno velho ou já retomado é só fechado, com a frase apontando o botão (RN-921). O `fechar_ao_subir/3` do `init/1` continua só fechando, e nó mudo conta como vivo (na dúvida nem fecha nem retoma). Resíduo declarado: dois nós subindo juntos, sem se enxergarem, podem retomar o mesmo turno duas vezes.
- **Onde:** `apps/engine/lib/engine/agents/turno_orfao.ex:90` (`varrer`), `:181` (`retomar`), `apps/engine/lib/engine/agents/turno_assincrono.ex:430` (`retomada_ao_subir`), `:253` (`tratar_resultado`)
- **Teste:** `apps/engine/test/engine/agents/diario_vivo_test.exs` (`TurnoOrfao.varrer/2: retomada automática 1× no boot`, `TurnoAssincrono: retomada no init`); `apps/engine/test/engine/agents/reidratacao_dos_seis_test.exs`
- **Origem:** AT-582 (EP-031), decisão do dono de 27/10; [ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md).

<a id="rn-922"></a>

### RN-922 — O dev agent que cai dentro da janela retoma do commit da MESMA tarefa, uma vez {#rn-922}

- **Regra:** revisa a [RN-742](parte-05.md#rn-742) (e cita a [RN-778](parte-05.md#rn-778), que continua só fechando o dev sem linha durável). O dev `working` reidratado, com a última atividade há no máximo 900 s e sem `dev.working` `cause: "retomada"` nesta tarefa, preserva o worktree como commit (RN-743), readota a MESMA tarefa (a branch dela, RN-779), grava `dev.working` com `cause: "retomada"` e o commit, e roda o laço com a mensagem do diário. A tarefa nunca sai de `in_progress`. A 2ª queda, a queda fora da janela, o `awaiting_approval` e qualquer falha da retomada bloqueiam como antes, e o "desbloquear" manual vira o "retomar do commit". Merge nunca ocorre aqui (RN-418). O contador de falha passageira da RN-864 é outra régua e não muda.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex:1318` (`retomada_do_commit`), `:1344` (`retomar_do_commit`)
- **Teste:** `apps/engine/test/engine/dev/retomada_do_commit_test.exs` (queda recente retoma; 2ª queda, fora da janela e `awaiting_approval` bloqueiam)
- **Origem:** AT-582 (EP-031), decisão do dono de 27/10; [ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md).

<a id="rn-923"></a>

### RN-923 — O resgate automático de gate vale uma vez por ciclo, no boot e no tick, e o "Retomar gate" zera o contador {#rn-923}

- **Regra:** revisa a [RN-823](parte-05.md#rn-823) e a [RN-722](parte-04.md#rn-722). `engine.gate_states.auto_resumes` conta os redespachos automáticos do ciclo (no boot e no tick); com 1 já usada, o segundo resgate ESTACIONA (`gate.rescue_parked`, `motivo: "retomada_automatica_ja_usada"`) e espera o "Retomar gate" ([RN-724](parte-05.md#rn-724)), que não tem teto e ZERA o contador. O contador fica fora do `on_conflict` do upsert (sobrevive aos passos do ciclo) e some com a linha quando o ciclo termina. O estacionamento de 2 h não muda. Os subagentes de gate ganham `registrar_plano`; no redespacho o `ToolLoop` recebe `ctx[:retomada]` com o plano do último `agent.turn_resumed` do subagente, e a área continua sendo redespachada inteira. Resíduo declarado: um ciclo novo pode pegar um marco pendente com menos de 15 min, e o subagente de gate não abre `working`, então a retomada dele leva só o plano.
- **Onde:** `apps/engine/lib/engine/gates/gate_rescuer.ex:212` (`retomar_ou_estacionar`), `:359` (`retomar_estacionado`), `apps/engine/lib/engine/gates/gate_state.ex:37` (`auto_resumes`)
- **Teste:** `apps/engine/test/engine/gates/gate_rescuer_test.exs:501` (`teto de 1 retomada automática` no tick e no boot, e o manual zerando)
- **Origem:** AT-582 (EP-031), decisões do dono de 27 e 28/10; [ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md).

<a id="rn-924"></a>

### RN-924 — A correção de gate que chega ao Infra Lead com turno em curso é durável {#rn-924}

- **Regra:** revisa a [RN-617](parte-03.md#rn-617), no molde da fila da [RN-673](parte-04.md#rn-673). `InfraLeadServer.correct/3` grava `infra.correction_queued` (`id`, `gate`, `reason`, diagnóstico até 2 000 caracteres) ANTES do cast e, sem processo, acorda o agente; `iniciar_correcao/2` grava `infra.correction_delivered` (`id`). O `init/1` reconstrói as pendentes (queued menos delivered) e as entrega depois do turno retomado e da fila de mensagens, e o `Rehydrator` acorda o Infra Lead que tem correção pendente no boot. Entregue não é reentregue. O Infra Lead também tem `registrar_plano` e a retomada da RN-920.
- **Onde:** `apps/engine/lib/engine/infra/infra_lead_server.ex:1649` (`correct`), `:408` (`iniciar_correcao`), `:200` (`init`)
- **Teste:** `apps/engine/test/engine/infra/infra_lead_server_test.exs:1980` (`correct/3 grava infra.correction_queued antes do cast`; a pendente sobrevive ao reinício e a entregue não é reentregue)
- **Origem:** AT-582 (EP-031); [ADR 0226](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0226-diario-vivo-e-retomada-dos-agentes.md).

<a id="rn-940"></a>

### RN-940 — O gate de QA-automação sobe uma instância de QA efêmera, testa nela e a remove {#rn-940}

- **Regra:** em `container`/`mounted`, antes do laço o `QaAutomacaoAgent` propõe `qa_environment_start` (semeada `auto_approve`); a subida que falha termina o gate com desfecho nomeado de origem `infra` (RN-059). O `terminal` do QA leva `alvo: {qa: true, taskId}` vindo do ctx do agente, nunca do modelo, e roda na instância; os demais agentes não mudam. A instância é removida em sucesso, falha, exceção e teto esgotado, salvo laço parado esperando decisão. `runner` segue sem instância. O boot e o tick do `GateRescuer` chamam o `sweep` com as tarefas de `gate_states` `qa` não estacionadas; falha só loga. `run.qa` é validado no engine com a mesma régua da api (RN-935).
- **Onde:** `apps/engine/lib/engine/gates/qa_automacao_agent.ex:78` (`subir_instancia`), `apps/engine/lib/engine/gates/qa_automacao_agent.ex:120` (`com_remocao`), `apps/engine/lib/engine/harness/hooks/action_pipeline.ex:46` (`maybe_put_alvo`), `apps/engine/lib/engine/gates/gate_rescuer.ex:102` (`varrer_instancias_de_qa`), `apps/engine/lib/engine/infra/instrucoes_de_execucao.ex:133` (`qa`).
- **Teste:** `apps/engine/test/engine/gates/qa_automacao_agent_instancia_test.exs`, `apps/engine/test/engine/infra/instrucoes_de_execucao_qa_test.exs`.
- **Origem:** AT-612 (EP-030), ADR 0229; depende da api (#1146).

<a id="rn-944"></a>

### RN-944 — O QA de automação recebe o pedido da volta anterior, o plano é lido por tipo e o dev sabe onde o `write_file` escreve {#rn-944}

- **Regra:** (a) o `changes_requested` mais recente do ator `qa` para a MESMA task entra no `dev_context` como `:pedido_anterior`, e o `QaAutomacaoAgent` acrescenta à mensagem a lista de itens e a instrução de dizer no `resumo` se cada um foi atendido; sem pedido anterior (primeira volta, `approved`, outra task, lista vazia) a mensagem é a de sempre. É insumo, nunca régua nova de veredito (molde do ADR 0192): o teto de correções (RN-015) e o `qa_verdict` único por ciclo não mudam. (b) `plano_ja_emitido/3` lê por tipo (`Reidratacao.eventos_do_tipo/3`), não a janela dos 200 mais recentes: o plano da task não sai da janela nem é pago de novo (cumpre a RN-674). (c) O ambiente de `dev-*`/`qa-*` diz que `write_file`/`read_file` usam caminho relativo à raiz do repositório e que `cd` no `terminal` não persiste (cada chamada é `sh -c` novo em `System.cmd ... cd: dir`, `terminal_executor.ex`).
- **Onde:** `apps/engine/lib/engine/gates/qa_lead_server.ex:784` (`pedido_anterior`), `apps/engine/lib/engine/gates/qa_lead_server.ex:743` (`plano_ja_emitido`), `apps/engine/lib/engine/gates/qa_automacao_agent.ex:323` (`com_o_pedido_anterior`), `apps/engine/lib/engine/harness/ambiente_do_agente.ex:102` (`montar`).
- **Teste:** `apps/engine/test/engine/gates/qa_automacao_agent_test.exs`, `apps/engine/test/engine/gates/qa_lead_server_test.exs`, `apps/engine/test/engine/harness/ambiente_do_agente_test.exs`.
- **Origem:** AT-616 (EP-030), TP-01 (21ª) de 30/10/2026.

<a id="rn-945"></a>

### RN-945 — Os agentes de QA nomeiam o corte pelo teto de saída em vez de "o modelo parou" {#rn-945}

- **Regra:** estende a RN-780 aos dois agentes de QA: quando o `ToolLoop` devolve `corte_pelo_teto: true`, `QaEstrategiaAgent` e `QaAutomacaoAgent` narram, com origem `modelo`, que a resposta foi só raciocínio e o teto de saída a cortou duas vezes (texto único em `Engine.Gates.MotivoDoCorte`). Sem o marcador, o diagnóstico antigo ("parou sem chamar ...") continua. A falha do plano segue sem segurar a revisão (RN-674) e o teto de iterações não muda.
- **Onde:** `apps/engine/lib/engine/gates/qa_estrategia_agent.ex:265` (`diagnostico_de_parada`), `apps/engine/lib/engine/gates/qa_automacao_agent.ex:427` (`diagnostico_de_parada`), `apps/engine/lib/engine/gates/motivo_do_corte.ex:8` (`texto`).
- **Teste:** `apps/engine/test/engine/gates/qa_estrategia_agent_test.exs`, `apps/engine/test/engine/gates/qa_automacao_agent_test.exs`.
- **Origem:** AT-618 parte 1 (EP-030), TP-01 (21ª) de 30/10/2026.

<a id="rn-946"></a>

### RN-946 — O corte pelo teto no meio do texto também é nomeado pelos agentes de QA {#rn-946}

- **Regra:** estende a RN-945/RN-780: resposta `truncated` COM texto e sem chamada (o raciocínio comeu o teto e o texto saiu cortado) não é "o modelo parou": o `ToolLoop` devolve `corte_com_texto: true`, chave PRÓPRIA (não `corte_pelo_teto`, que o dev agent e a RN-780 casam), e `QaEstrategiaAgent` e `QaAutomacaoAgent` narram, com origem `modelo`, que o teto cortou a resposta no meio do texto antes da ferramenta de término (`MotivoDoCorte.texto_com_texto`). Não há retentativa nova (mudaria laço e custo); resposta não cortada com texto segue "parou sem chamar ...". A mesma lacuna no dev agent fica fora.
- **Onde:** `apps/engine/lib/engine/harness/tool_loop.ex:256` (`parada_sem_chamada`), `apps/engine/lib/engine/gates/qa_estrategia_agent.ex:265` (`diagnostico_de_parada`), `apps/engine/lib/engine/gates/qa_automacao_agent.ex:427` (`diagnostico_de_parada`), `apps/engine/lib/engine/gates/motivo_do_corte.ex:9` (`texto_com_texto`).
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs`, `apps/engine/test/engine/gates/qa_estrategia_agent_test.exs`, `apps/engine/test/engine/gates/qa_automacao_agent_test.exs`.
- **Origem:** AT-620 (EP-030), TP-01 (22ª) de 31/10/2026.

<a id="rn-955"></a>

### RN-955 — GET interno com conexão envenenada do pool é repetido UMA vez {#rn-955}

- **Regra:** complementa a [RN-742](parte-05.md#rn-742) (AT-428). A resposta atrasada de um pedido que estourou o `receive_timeout` fica no socket de uma conexão do pool do Finch; o GET seguinte que a pega lê a resposta ANTIGA e lança `CaseClauseError {:status, ref, _}`, que a checagem de trabalho pendente da [RN-064](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-064) lia como "api fora do ar" e encerrava a sessão ativa. O `req_get` repete o MESMO GET uma vez quando o erro é esse (o Finch já descartou a conexão); só GET, porque POST pode ter tido efeito. Erro de transporte verdadeiro NÃO é repetido, e a RN-064 não muda.
- **Onde:** `apps/engine/lib/engine/sessions/engine_api_client.ex:2258` (`get_repetindo`).
- **Teste:** `apps/engine/test/engine/sessions/engine_api_client_isolado_test.exs` (repete e devolve; falha na segunda não tem terceira; timeout verdadeiro não repete).
- **Origem:** AT-642 (EP-030).

<a id="rn-956"></a>

### RN-956 — `readiness` e `offer-infra-handoff` sobem o agente antes de chamar, como `message` {#rn-956}

- **Regra:** depois do fechamento e da reabertura ([RN-649](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-649)) os conversacionais não estão de pé, e as duas rotas chamavam o servidor sem `start_agent`: o `:noproc` virava 500 mascarado por "Stale conn". Agora recebem `projectId` e sobem o Criativo/Arquiteto antes (idempotente); sem `projectId`, 400 nomeado.
- **Onde:** `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:348` (`readiness`), `:355` (`offer_infra_handoff`).
- **Teste:** `apps/engine/test/engine_web/controllers/agent_command_controller_test.exs` (agente parado sobe; sem `projectId` é 400).
- **Origem:** AT-642 (EP-030).

<a id="rn-957"></a>

### RN-957 — "aborted" é falha de origem `infra` {#rn-957}

- **Regra:** complementa a [RN-059](parte-01.md#rn-059) e a [RN-810](parte-05.md#rn-810). "aborted" é o socket da resposta do provider morrendo no meio do stream; o frame final sem `errorCode` caía em `codigo`. `FalhaDeTurno.origem/1` o classifica `infra` (sem tocar `falha_de_rede?`; a retentativa segue pela [RN-864](parte-05.md#rn-864)).
- **Onde:** `apps/engine/lib/engine/agents/falha_de_turno.ex:87` (`origem`), `:110`.
- **Teste:** `apps/engine/test/engine/agents/falha_de_turno_test.exs` ("RN-957").
- **Origem:** AT-642 (EP-030).

<a id="rn-962"></a>

### RN-962 — O compose do entregável usa volume nomeado, nunca bind-mount relativo {#rn-962}

- **Regra:** o Infra Lead pede VOLUME NOMEADO para dados persistentes e `.env.example` só com as variáveis obrigatórias, sem valor. `propose_infra_pr` recusa, ANTES de abrir a PR, arquivo de compose com bind-mount relativo (`- ./pasta:/destino` ou `source: ./pasta`): a pasta nasce `root` na primeira subida e o app non-root não grava nela. A recusa é resultado de ferramenta (entra no laço, RN-163) e registra `tool.result` com `ok: false`.
- **Onde:** `apps/engine/lib/engine/infra/infra_lead_server.ex:669` (`recusa_de_bind_mount_relativo`).
- **Teste:** `apps/engine/test/engine/infra/infra_lead_server_test.exs` (volume nomeado passa; formas curta, com aspas e longa são recusadas).
- **Origem:** AT-644 (EP-031).

<a id="rn-982"></a>

### RN-982 — As fontes de uma resposta são as leituras ok do próprio turno, registradas pelo servidor, nunca pelo texto do modelo {#rn-982}

- **Regra:** irmã da [RN-731](parte-05.md#rn-731). O servidor anota cada leitura `ok` do turno (listagens de regras, backlog, métricas, ADRs e contratos, `read_file` e os trechos do `rag_search`) e o `agent.response` leva `fontes` FORA do `content`: `{tipo, rotulo, ref?, searchId?, chunkId?}`, teto de 10, com `fontesTotal` quando corta (ADR 0060). Sem leitura, o campo não existe. Leitura com falha não é fonte. A tela diz "consultado", nunca "usado": é o que o agente leu, não o que ele aproveitou. Não muda o `content`, a reidratação (RN-580), o `tool.result` (RN-589) nem o voto do RAG (RN-479..481).
- **Onde:** `apps/engine/lib/engine/agents/fontes_do_turno.ex:37` (`anotar`), `apps/engine/lib/engine/agents/texto_do_turno.ex:65` (`payload_do_turno`), `apps/engine/lib/engine/harness/tool_loop.ex:419` (`anotar`).
- **Teste:** `apps/engine/test/engine/agents/fontes_do_turno_test.exs`, `apps/engine/test/engine/harness/tool_loop_test.exs` ("RN-982"), `apps/engine/test/engine/agents/retomada_dos_seis_test.exs` e `apps/engine/test/engine/infra/infra_lead_server_test.exs` (a ferramenta nos sete).
- **Conversacionais (fatia 2):** os SETE agentes conversacionais oferecem o MESMO `rag_search` dos dev agents (`Engine.Harness.Tools.RagSearch`, escopo do projeto, sem parâmetro de escopo, teto de `top_k` da ferramenta, ADR 0060), despachado por `ArgumentosDeFerramenta.executar/4` (RN-719) e com o resultado no `tool.result` (RN-589). Entra na spec e no despacho de cada servidor: `criativo_server.ex:121`/`:469`, `po_server.ex:153`/`:437`, `arquiteto_server.ex:125`/`:402`, `dev_lead_server.ex:187`/`:580`, `ux_designer_server.ex:121`/`:350`, `staff_server.ex:121`/`:304`, `infra/infra_lead_server.ex:239`/`:1149`.
- **Origem:** AT-716 fatias 1 e 2 (EP-031).

<a id="rn-985"></a>

### RN-985 — A citação inline é marcada pelo modelo e validada contra as fontes do próprio turno; índice inventado não é mostrado {#rn-985}

- **Regra:** quando o turno já tem fonte (RN-982), uma mensagem `system` EFÊMERA no fim da chamada (mesmo caminho da RN-622, nunca em `state.messages`, sem nomear idioma, RN-667) lista as fontes como `[n] rótulo` (até 10, na ordem de `fontes`) e pede "cite com [n]; não cite o que não está na lista" (teto de 250 tokens; 10 fontes medem ~55). No fecho, o servidor extrai os `[n]` do texto e grava `citacoes` no `agent.response` só com os que existem em `fontes` (`1 <= n <= fontes.length`), sem repetição e em ordem. O `content` NÃO é reescrito (RN-731): o marcador inválido fica no texto e a tela o descarta. Sem fontes, ou sem marcador válido, o campo não existe.
- **Onde:** `apps/engine/lib/engine/harness/citacao_das_fontes.ex:22` (`anexar`) e `:43` (`marcar`), `apps/engine/lib/engine/sessions/engine_api_client.ex:754` (`llm_turn`), `apps/engine/lib/engine/agents/texto_do_turno.ex:65` (`payload_do_turno`), `apps/engine/lib/engine/harness/tool_loop.ex:206` (`marcar`).
- **Teste:** `apps/engine/test/engine/harness/citacao_das_fontes_test.exs`, `apps/engine/test/engine/harness/tool_loop_test.exs` ("RN-985").
- **Origem:** AT-716 fatia 3 (EP-031).

<a id="rn-990"></a>

### RN-990 — A imagem anexada vai ao LLM só no turno em que a mensagem chegou {#rn-990}

- **Regra:** o `anexos` do `agent/message` (`[{id, nome, mime, tamanho}]`, até 4 por mensagem) entra no turno e na fila de mensagens (RN-673) JUNTO com o texto: o `chat.message_queued` guarda os anexos, e as pendentes que viram UM turno juntam os anexos na ordem. Na PRIMEIRA chamada de LLM do turno, o `content` da última mensagem `user` vira a lista de partes (`text` + uma `{type:'anexo',id}` por anexo); a chamada CONSOME os anexos, então as iterações seguintes do laço de ferramentas e os turnos seguintes mandam só o texto com o rótulo `[anexos: a.png, b.txt]` (teto de 300 caracteres), que é também o que a reidratação devolve a partir do `payload.anexos` do `chat.message`. A imagem nunca é reenviada (custo × iterações × turnos; decisão do dono, 02/11). O caminho é UM só para os sete conversacionais (`TurnoAssincrono` + `Reidratacao`), sem código por servidor; mensagem sem anexos continua `string`.
- **Onde:** `apps/engine/lib/engine/harness/anexos_do_turno.ex:56` (`anexar`), `apps/engine/lib/engine/agents/turno_assincrono.ex:324` (`receber_mensagem`), `apps/engine/lib/engine/agents/reidratacao.ex:461` (`usuario`), `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:545` (`autor_do_turno`).
- **Teste:** `apps/engine/test/engine/agents/anexos_do_turno_test.exs`.
- **Origem:** AT-715 fatia 1, lane L3 (EP-031), ADR 0246.

<a id="rn-996"></a>

### RN-996 — O parecer de QA leva o resultado por teste lido do relatório JUnit pelo engine; sem relatório, diz por quê {#rn-996}

- **Regra:** `emit_qa_verdict` aceita `relatorioDeTestes` (caminho relativo, em geral `.brabo-qa/junit.xml`). O ENGINE lê o arquivo (nunca o modelo declara), o apaga e põe `execucaoDeTestes` no `qa_verdict` do subagente e no consolidado: `{fonte: "junit", total, passaram, falharam, pulados, duracaoMs, suites, casosOmitidos}`, ou `{indisponivel: "sem_relatorio" | "relatorio_invalido" | "modo_runner", origem, detalhe?}`. Sem relatório NUNCA vira "0 testes" (RN-470), e falha ao ler nunca muda o veredito (ADR 0054; só registra, a régua de aprovação segue `exit 0` mais a matriz). Teto (ADR 0060): 200 casos gravados, falhas primeiro; 20 mensagens de 500 caracteres; nomes de 200; contadores do relatório inteiro, `casosOmitidos` por subtração. O parser (SAX do `:xmerl`) recusa DOCTYPE/ENTITY (XXE), lê no máximo 2 MiB e 20 000 casos. Em `runner` o arquivo vem pelo canal do runner (o `exec` já existente, sem operação nova). Quem instala o reporter é o dev agent; o QA só lê. *(A parte "como TAREFA que o Dev Lead inclui no módulo" foi superada pela [RN-1016](#rn-1016): o reporter é configurado dentro da primeira tarefa de código do módulo, nunca como tarefa própria.)*
- **Onde:** `apps/engine/lib/engine/gates/relatorio_junit.ex:34` (`ler`), `apps/engine/lib/engine/gates/relatorio_junit.ex:111` (`parse`), `apps/engine/lib/engine/gates/hooks/termination.ex:49` (`com_execucao_de_testes`).
- **Teste:** `apps/engine/test/engine/gates/relatorio_junit_test.exs` (vitest, pytest, XXE recusado, teto de tamanho/casos/gravação, arquivo ausente/inválido/apagado), `apps/engine/test/engine/gates/hooks/termination_test.exs`, `apps/engine/test/engine/gates/qa_lead_test.exs`.
- **Origem:** AT-687 (EP-031), lane engine.

<a id="rn-999"></a>

### RN-999 — A chamada irmã da pendente recebe recusa, para todo `tool_use` ter o seu `tool_result` {#rn-999}

> **Revisa a [RN-284](parte-01.md#rn-284) e a [RN-593](parte-03.md#rn-593).** Elas diziam que o laço PARA na chamada pendente "sem processar as chamadas seguintes". Parar continua; o que mudou é que as seguintes não ficam mudas.

- **Regra:** quando o modelo pede várias ferramentas na mesma resposta e uma delas fica pendente de aprovação (`{:pending, …}` no Dev Lead, `aguardando_aprovacao` no `ToolLoop` dos dev agents e dos QAs), cada chamada IRMÃ que veio DEPOIS dela não roda, mas recebe, antes de suspender, uma mensagem `tool` com "não executada: o turno parou esperando a aprovação de <ferramenta>; repita se ainda precisar" e um `tool.result` `ok: false` com o mesmo texto, pelo `ResultadoDeFerramenta` ([RN-589](parte-03.md#rn-589)). A pendente continua sem mensagem até o desfecho ([RN-593](parte-03.md#rn-593)).
- **Por quê:** a Anthropic recusa com 400 a retomada que traz `tool_use` sem o `tool_result` correspondente (achado 1 do TP-01 de 05/11: `propose_execution_plan` mais `declare_open_question`). A irmã não é executada, então a recusa diz isso e deixa o modelo repetir.
- **Onde:** `apps/engine/lib/engine/agents/dev_lead_server.ex:605` (`recusar_irmas`), `apps/engine/lib/engine/harness/tool_loop.ex:225` (`recusar_irmas`), `apps/engine/lib/engine/agents/resultado_de_ferramenta.ex:44` (`recusa_de_irma`).
- **Teste:** `apps/engine/test/engine/agents/dev_lead_server_test.exs` ("irmã da pendente recebe recusa") e `apps/engine/test/engine/harness/tool_loop_test.exs` ("irmã da chamada pendente recebe recusa"); mutação provada: sem a recusa os dois reprovam.
- **Origem:** AT-739 (achado 1), Rodada 191, lane L1.

<a id="rn-1003"></a>

### RN-1003 — O agente fecha a pergunta em aberto que o usuário já respondeu no chat, só quando a resposta é inequívoca {#rn-1003}

> **Estende a [RN-862](parte-05.md#rn-862).** Até aqui só a api fechava uma pergunta em aberto, pelo botão; o agente não tinha como.

- **Regra:** os quatro perguntadores (Criativo, PO, Arquiteto, Dev Lead) têm a ferramenta `answer_open_question` (`questionId`, `resposta` opcional; sem ela, vale a sugestão do próprio agente). Ela chama `POST /internal/projects/:projectId/open-questions/:questionId/answer` com `{sessionId, agentId, resposta?}`. Quem fecha é a api (o mesmo núcleo do clique: `decision_record` mais `open_question.answered`, rearmando o gate, RN-860), então o engine não grava evento. `already_answered` volta ao modelo como sucesso ("já fechada"); um 404 vira recusa nomeada (a pergunta não é deste projeto) e um 400, recusa citando a api. A frase central em `FluxoDoTime` manda o modelo fechar só quando a resposta do usuário no chat é INEQUÍVOCA, e manter a pergunta aberta caso contrário. Para isso ser possível, as perguntas abertas (com `questionId` e a sugestão) passam a chegar ao turno dos quatro perguntadores, não só ao do PO (`DecisoesDoProjeto`, a mesma leitura local com teto, ADR 0060).
- **Por quê:** achado do TP-01 de 05/11: o usuário respondeu quatro perguntas no chat, o Criativo registrou as regras, e as perguntas ficaram na fila com "Aceitar sugestão". Decisão do dono (AT-741): o agente fecha.
- **Onde:** `apps/engine/lib/engine/harness/tools/answer_open_question.ex:43` (`run`), `apps/engine/lib/engine/harness/fluxo_do_time.ex:109` (`@frase_da_pergunta`), `apps/engine/lib/engine/harness/decisoes_do_projeto.ex:23` (`@agentes`).
- **Teste:** `apps/engine/test/engine/harness/tools/answer_open_question_test.exs` e `apps/engine/test/engine/harness/decisoes_do_projeto_test.exs`; mutação provada: quebrar a cláusula do 404, o `already_answered`, o campo `agentId`, a frase da resposta inequívoca, a lista de perguntadores ou o registro de um agente reprova um teste.
- **Origem:** AT-741 (lado do engine), Rodada 193, lane L3; o lado da api é a RN-1002.

<a id="rn-1006"></a>

### RN-1006 — O Dev Lead cria a task de fundação do módulo de que outros dependem {#rn-1006}

> **Revisa a [RN-678](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-678)** (o papel do Dev Lead). ADR 0259.

- **Regra:** o Dev Lead ganha `create_task` (o `Engine.Harness.Tools.CreateTask` do PO, com um `module` obrigatório a mais). Ele manda `agentRole: "dev_lead"` no corpo de `POST /internal/sessions/:id/tasks` para o histórico da sessão creditar o Dev Lead; o PO não manda o campo e a api assume `po`. Só roda para história cujo `moduleIds` contém `module`; fora disso a chamada é recusada com mensagem nomeada ("a história não lista o módulo em `moduleIds`") e nada é criado. O `module_map_vigente` mostra o `dependsOn` de cada módulo, e o kickoff diz ao Dev Lead que módulo de que outro depende precisa de uma task de FUNDAÇÃO (esqueleto, `package.json`, entrypoint, contrato exposto) e que, se ninguém a tem, ele deve criá-la com `create_task` ANTES de propor o plano. A api recusa plano que deixa um módulo desses sem task ("X depende de Y, que não tem task: crie a task de fundação de Y", RN-1004); a recusa chega ao Dev Lead como qualquer outro erro de `propose_execution_plan`, então o laço segue.
- **Por quê:** achado do TP-01 de 05/11: o plano deixou `persistencia` e `api-http` sem task e as tasks dependentes bloqueadas. O PO cria tasks antes de o `module_map` existir, então só o Dev Lead consegue ver a lacuna. Decisão do dono (AT-742).
- **Onde:** `apps/engine/lib/engine/agents/dev_lead_tools.ex` (`spec_create_task`, `run_create_task`, `module_map_vigente`), `apps/engine/lib/engine/agents/dev_lead_server.ex` (`tool_specs`, `run_tool("create_task")`, `build_kickoff`).
- **Teste:** `apps/engine/test/engine/agents/dev_lead_tools_test.exs` ("create_task do Dev Lead") e `apps/engine/test/engine/agents/dev_lead_server_test.exs` (kickoff `dependsOn`, `create_task` nas specs); mutação provada: tirar o `dependsOn`, a spec ou a checagem de módulo reprova um teste.
- **Origem:** AT-742 (lado do engine), Rodada 194, lane L2; o lado da api são as RN-1004 e RN-1005.

<a id="rn-1010"></a>

### RN-1010 — Conflito ao integrar a `dev` no claim vai para o agente; só o que ele não resolve bloqueia {#rn-1010}

> **Revisa a [RN-779](parte-05.md#rn-779)** (o conflito abortava e bloqueava) e espelha a [RN-715](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-715) (conflito de merge na PR).

- **Regra:** quando a integração da `dev` atual no worktree da task conflita em arquivos, o engine NÃO aborta: o merge fica em curso com os marcadores nos arquivos, e `add_worktree` devolve `{:error, {:conflito_de_integracao, worktree, files, reason}}`. O `run_task` segue então para o `implement` normal (registra `dev.working` com `cause: "integration_conflict"`) com UMA mensagem fixada a mais entre o prompt da task e o retrato do worktree: resolver os arquivos listados mantendo o que a task anterior fez e o que a `dev` trouxe, editando os arquivos com `write_file`; NÃO rodar git no `terminal` (o container não tem git; AT-798); o commit do merge é do SISTEMA, no `report_done` (`GitExecutor.commit/1`, commit de dois pais); só então implementar a task. A readoção da RN-715 (`adopt_integrando`) integra a `main` atual do mesmo jeito e devolve a mesma tupla; a mensagem de correção diz que a `main` já foi integrada e quais arquivos têm marcadores. Conflito sem arquivo conflitado mantém o comportamento antigo (aborta, string nomeada, bloqueia).
- **Guardas:** (1) no `report_done`, se algum dos arquivos conflitados ainda tem linha `<<<<<<< ` / `>>>>>>> ` (o `=======` não é checado: é sublinhado de título em Markdown), (o `MERGE_HEAD` NÃO conta: sem marcador, segue para a entrega e o sistema conclui o merge) o merge é abortado e a task bloqueia com o motivo da RN-779 ("conflito ao integrar a dev atual no worktree da task", origem `codigo`), com o diagnóstico dizendo que o agente não resolveu; `report_blocked` bloqueia como antes. (2) `preservar_em` aborta um merge em curso ANTES do commit de WIP ([RN-743](parte-05.md#rn-743)), então um bloqueio no meio do conflito (teto, orçamento, `report_blocked`) nunca commita marcador; o caminho da RN-715 também fica protegido.
- **Por quê:** 26ª rodada do TP-01 (06/11): duas tasks bloquearam no mesmo segundo pedindo ao usuário que integrasse a `dev` à mão, e desbloquear só repetia o ciclo. O conflito acontece ANTES do trabalho da task, então é o laço da task, não o de correção; os gates seguem julgando a branch no fim.
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex` (`integrar_trabalho`, `conflito_nao_resolvido?`, `abortar_merge_em_curso`, `preservar_em`), `apps/engine/lib/engine/dev/dev_agent_server.ex` (`run_task`, `conflito_message`, `handle_outcome` do `report_done`).
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs` ("conflito deixa o merge em curso com os marcadores", "preservar_em com merge em curso aborta e não commita marcador") e `apps/engine/test/engine/dev/conflito_de_integracao_test.exs` (git real e `terminal` SEM git, exit 127: o agente resolve com `write_file`, chega a `awaiting_gate` e o HEAD tem dois pais; a readoção da RN-715 idem; sem resolver, bloqueia sem marcador commitado; as mensagens não citam git); mutação provada (AT-798): devolver o `MERGE_HEAD` à guarda, recolocar `not adotando?` ou tirar a guarda do `report_done` reprova um teste cada; e também: restaurar o abort, tirar a guarda do `preservar_em`, a cláusula do `run_task` ou a guarda do `report_done` reprova um teste cada.
- **Origem:** AT-747, Rodada 203, lane L2.

<a id="rn-1011"></a>

### RN-1011 — O plano do Dev Lead é recusado quando uma task cita rota que o contrato declara em outro módulo {#rn-1011}

> **Complementa a [RN-792](parte-05.md#rn-792)** (rotas da história contra o contrato) e a [RN-678](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-678) (a task é do módulo que o Dev Lead atribui). ADR 0200.

- **Regra:** `propose_execution_plan` lê o contrato de módulos vigente (`list_module_contracts`) e o backlog (`list_backlog`) depois de resolver os ids das tasks e ANTES do `propose_action`. Para cada task planejada, extrai as rotas `MÉTODO /caminho` do título e da descrição da task (`RotasDoContrato.extrair/1`); os donos de uma rota são os módulos cujo contrato a declara. Se o módulo atribuído à task não está entre os donos, a chamada devolve erro nomeando a task, a rota e o(s) módulo(s) dono(s), e mandando o Dev Lead mover a task para o dono ou separar a parte de domínio numa task do módulo de domínio com `create_task`. Rota ausente do contrato é ignorada (a RN-792 cobre). Falha ao ler o contrato ou o backlog não recusa: o plano segue e o resultado leva um aviso.
- **Por quê:** 26ª rodada do TP-01 (06/11): o Dev Lead atribuiu "Implementar POST /horarios" a `scheduling`, mas o contrato v3 declara essa rota em `api`; o agente dev-scheduling bloqueou por falta de um validador de auth que só `api` consome. A recusa vem antes da proposta porque, no modo automático, o plano roda assim que é proposto.
- **Onde:** `apps/engine/lib/engine/harness/rotas_do_contrato.ex` (`donos_divergentes/3`), `apps/engine/lib/engine/agents/dev_lead_tools.ex` (`conferir_donos`).
- **Teste:** `apps/engine/test/engine/harness/rotas_do_contrato_test.exs` e `apps/engine/test/engine/agents/dev_lead_tools_test.exs` ("tarefa que cita rota de OUTRO módulo"); mutação provada: comparar com qualquer módulo, ignorar os donos ou tirar a checagem do `run/2` reprova um teste.
- **Origem:** AT-748 (lane a), Rodada 203, lane L5.

<a id="rn-1012"></a>

### RN-1012 — Task bloqueada pelo modelo acorda o Dev Lead, que pede ao Arquiteto o contrato que falta {#rn-1012}
- **Regra:** quando um dev agent encerra uma task com `report_blocked` (origem `modelo`), o engine entrega `{:tarefa_bloqueada, %{task_id, modulo, reason, diagnosis}}` ao Dev Lead pelo `Engine.Dev.Wake`. Conflito de merge (`codigo`), gates esgotados (`politica`), crédito/infra e o teto de iterações NÃO o acordam. O Dev Lead transforma o aviso em mensagem de sistema: com o Dev Lead ocioso, um turno começa; com turno em curso, aprovação de plano pendente ou fila não vazia, o aviso vai para a fila de mensagens (limitada pelo teto da RN-673) e é lido quando o turno termina. O aviso manda conferir o contrato e o mapa de módulos (`read_backlog`), pedir ao Arquiteto com `pedir_ao_arquiteto` e criar a task no módulo dono com `create_task`, ou dizer ao usuário o que falta.
- **`pedir_ao_arquiteto`:** grava o pedido como evento durável `chat.message` de ator `dev-lead` na sessão (a mesma sessão do Arquiteto; a `Reidratacao` lê `chat.message` de qualquer ator) e o entrega ao Arquiteto como mensagem prefixada `[Pedido do Dev Lead]`. É um canal de agente para agente que não é handoff (handoff para agente ativo é recusado com 409). Com o Arquiteto ocupado, a mensagem entra na fila dele.
- **Contrato publicado:** `declare_module_contracts`, numa versão aceita pela api, entrega `{:contrato_publicado, version}` ao Dev Lead, que então cria a task no módulo dono e repropõe o plano. Recusa da api não entrega nada.
- **Limite (atalho):** o Wake entrega no máximo uma vez (ADR 0045): sem processo do Dev Lead vivo (reinício do engine, ou fase de arquitetura) o aviso se perde, e resta o caminho humano (a lista de tasks bloqueadas no chat, RN-826). Desbloquear a task parada depois que a dependência é mergeada segue humano (RN-826/RN-777).
- **Por quê:** 26ª rodada do TP-01 (06/11): o dev bloqueou, corretamente, e ninguém agiu até o condutor pedir ao Arquiteto e ao Dev Lead à mão.
- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex` (`avisar_dev_lead`), `apps/engine/lib/engine/agents/dev_lead_server.ex` (`handle_info` de `:tarefa_bloqueada` e `:contrato_publicado`, `avisar`), `apps/engine/lib/engine/harness/tools/pedir_ao_arquiteto.ex`, `apps/engine/lib/engine/harness/tools/declare_module_contracts.ex`.
- **Teste:** `apps/engine/test/engine/dev/dev_agent_server_test.exs`, `apps/engine/test/engine/agents/dev_lead_server_test.exs`, `apps/engine/test/engine/harness/tools/pedir_ao_arquiteto_test.exs`, `apps/engine/test/engine/harness/tools/declare_module_contracts_test.exs`; mutação provada: tirar o `Wake.deliver` do `report_blocked`, movê-lo para `block_task/4` (todas as origens), sempre começar o turno, apagar a cláusula do `handle_info`, tirar o `append_event` da ferramenta e tirar o `Wake.deliver` do contrato reprova um teste cada.
- **Origem:** AT-748 (b), Rodada 203, lane L6.

<a id="rn-1013"></a>

### RN-1013 — Cada mensagem assistant do turno guarda os próprios blocos de raciocínio, e o prefixo enviado só cresce {#rn-1013}
- **Regra:** `Engine.Agents.RaciocinioDoTurno` guarda os `thinkingBlocks` da Anthropic de TODA chamada de LLM do turno, indexados pelo id do primeiro `toolCall` da mensagem `assistant` daquela chamada. `anexar_blocos/1` dá a cada mensagem `assistant` com `toolCalls` os blocos da chamada que a produziu, não só os da última. Nada do que já foi enviado muda entre duas chamadas do mesmo laço: o prefixo da chamada N é prefixo exato da chamada N+1. Os blocos ficam em memória (nunca no log nem na `Reidratacao`, RN-993) e `descarregar/0` os limpa no fim do turno.
- **Por quê:** 26ª rodada do TP-01 (06/11): agentes que raciocinam tinham de 19% a 46% de cache de prompt, os que não raciocinam tinham de 62% a 82%. Os blocos iam só na última mensagem `assistant`, então a anterior os perdia na chamada seguinte e toda entrada de cache gravada depois de uma rodada de raciocínio deixava de valer.
- **Onde:** `apps/engine/lib/engine/agents/raciocinio_do_turno.ex` (`registrar`, `anexar_blocos`), chamado por `apps/engine/lib/engine/sessions/engine_api_client.ex` (`llm_turn`, `llm_turn_stream`).
- **Teste:** `apps/engine/test/engine/agents/raciocinio_do_turno_test.exs` ("3 chamadas seguidas"); mutação provada: guardar só os blocos da última chamada, ou não anexá-los às mensagens `assistant` anteriores, reprova um teste.
- **Origem:** AT-749 (engine), Rodada 205, lane L2.

<a id="rn-1016"></a>

### RN-1016 — O reporter JUnit é configurado na primeira task de código do módulo, nunca numa task própria {#rn-1016}

> **Revisa a [RN-996](#rn-996)** (quem instala o reporter e como o quê).

- **Regra:** o kickoff do Dev Lead (`build_kickoff`) manda NÃO criar task só para o relatório JUnit. O `initial_message/2` do dev agent diz ao dev que, se o módulo ainda não produz relatório JUnit, ele configura o reporter nesta mesma task, com saída em `.brabo-qa/junit.xml` (vitest `--reporter=junit --outputFile=.brabo-qa/junit.xml`, pytest `--junitxml=.brabo-qa/junit.xml`), põe `.brabo-qa/` no `.gitignore` e nunca commita o relatório. `.brabo-qa/junit.xml` é o caminho que o QA lê e apaga (RN-996).
- **Por quê:** 26ª rodada do TP-01 (06/11): cinco tasks "configurar JUnit no módulo X" rodaram em paralelo com as tasks de código sobre o mesmo `package.json`, lock e README; a PR de scheduling foi refeita duas vezes por conflito e a de auth esgotou o ciclo de correção versionando `test-results/junit.xml`.
- **Onde:** `apps/engine/lib/engine/agents/dev_lead_server.ex` (`build_kickoff`), `apps/engine/lib/engine/dev/dev_agent_server.ex` (`initial_message/2`).
- **Teste:** `apps/engine/test/engine/agents/dev_lead_server_test.exs` ("o kickoff proíbe tarefa só para o relatório JUnit") e `apps/engine/test/engine/dev/report_done_instrucao_test.exs` ("RN-1016"); mutação provada: restaurar o parágrafo antigo ou tirar a frase do dev reprova um teste.
- **Origem:** AT-750, Rodada 205, lane L3.

<a id="rn-1020"></a>

### RN-1020 — O Criativo e o PO retiram sozinhos uma regra de negócio obsoleta, citando a substituta ou a resposta do usuário {#rn-1020}
- **Regra:** a ferramenta `retire_business_rule` (`rule_id`, `reason`, `replaced_by` e `question_id` opcionais) só existe nos catálogos do Criativo e do PO. Ela chama `POST /internal/projects/:projectId/business-rules/:ruleId/retire` com `{sessionId, agentRole, reason, replacedBy?, questionId?}`; a api valida e grava `artifact.business_rule_retired` (RN-1018 da api). O agente retira por conta própria, sem perguntar ao usuário nem ao condutor, e sempre cita `replaced_by` ou `question_id`. Toda recusa da api (`papel_nao_retira_regra`, `retirada_sem_citacao`, `substituta_invalida`, `pergunta_nao_respondida`, `regra_ja_retirada`, `historia_ficaria_sem_regra`, `historia_com_tarefa_em_execucao`, 404) volta ao modelo como `reason — message`. Os prompts de identidade dos dois agentes dizem isso.
- **Leitores no engine:** as listas de regras que o engine monta a partir do log de eventos da sessão (`CriativoServer.business_rule_refs`, os kickoffs do PO e do Arquiteto) também leem `artifact.business_rule_retired` e descartam os ids retirados (`Reidratacao.sem_regras_retiradas/1`). Os leitores que vêm da api (`listar_regras_de_negocio`, backlog) já filtram.
- **Onde:** `apps/engine/lib/engine/harness/tools/retire_business_rule.ex`, `apps/engine/lib/engine/sessions/engine_api_client.ex` (`retire_business_rule`), `apps/engine/lib/engine/agents/criativo_server.ex` (`tool_specs`, `dispatch_tool`, `business_rule_refs`), `apps/engine/lib/engine/agents/po_server.ex` (`tool_specs`, `run_tool`, `kickoff_instruction`), `apps/engine/lib/engine/agents/arquiteto_server.ex` (`kickoff_instruction`), `apps/engine/lib/engine/agents/reidratacao.ex` (`sem_regras_retiradas`), `apps/engine/lib/engine/harness/agents.ex`.
- **Teste:** `apps/engine/test/engine/harness/tools/retire_business_rule_test.exs`; mutação provada: registrar a ferramenta em outro agente, tirar o papel ou o `replacedBy` do corpo, engolir a recusa da api e não filtrar os ids retirados reprova um teste cada.
- **Origem:** AT-755, Rodada 205, lane L8.

<a id="rn-1021"></a>

### RN-1021 — Depois de um merge na `main` do projeto, a pasta do projeto avança até ela {#rn-1021}
> **Revisa as [RN-664](parte-04.md#rn-664), [RN-729](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-729), [RN-779](parte-05.md#rn-779), [RN-787](parte-05.md#rn-787), [RN-797](parte-05.md#rn-797), [RN-811](parte-05.md#rn-811) e [RN-1010](#rn-1010):** o repositório do projeto é trunk, então a branch de trabalho que elas chamam de `dev` é a `main`.

- **Regra:** a branch de trabalho do repositório de um projeto é a `main` (`ProjectRepository.@branch_de_trabalho`): o claim, a base do worktree, o alvo do `pr_open` e o diff do gate a usam. Quando a api mergeia uma PR nela (evento de outbox `project.trunk_merged`, agregado `project`, payload `{projectId, sessionId, mergedSha}`), o `Engine.Outbox.Drain` o encaminha ao `Engine.Workers.TrunkMergedWorker`, que chama `WorktreeManager.avancar_pasta/1`: sob o mesmo lock `:global` do `fetch` do claim, `git fetch origin` e `git merge --ff-only origin/main` na pasta do projeto (modos `container` e `mounted`). Nunca roda `reset`, `checkout -f`, `stash` nem merge de verdade. Para projetos `runner` passa pelo runner ([RN-1027](#rn-1027)); é no-op para pasta sem a marca de pronto (o merge da infra vem antes do primeiro claim).
- **Recusas (a pasta não é tocada):** branch atual não é `main` (`other_branch`); árvore rastreada suja (`dirty_tree`, arquivos não rastreados ignorados); `main` local não é ancestral de `origin/main` (`diverged`); o próprio git recusa porque um arquivo não rastreado seria sobrescrito (`untracked_conflict`); ou o `fetch` falha (`fetch_failed`). Cada uma é registrada na sessão `sessionId` como `workspace.checkout_not_advanced` com `reason`, `branch` e `detail`; o sucesso é `workspace.checkout_advanced` com `from` e `to`.
- **Por quê:** a pasta ficava no commit da infra enquanto o trabalho andava (21ª e 22ª rodadas do TP-01); um usuário que seguisse o README rodava código velho.
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:254` (`avancar_em`), `apps/engine/lib/engine/dev/worktree_manager.ex:217` (`avancar_pasta`), `apps/engine/lib/engine/workers/trunk_merged_worker.ex:21` (`perform`), `apps/engine/lib/engine/outbox/drain.ex:26` (`run_once`), `apps/engine/lib/engine/actions/workspace.ex:183` (`pronto?`).
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs` ("trunk: guarda de projeto legado e avanço da pasta"), `apps/engine/test/engine/workers/trunk_merged_worker_test.exs`, `apps/engine/test/engine/outbox/drain_test.exs` ("project.trunk_merged"); mutação provada: tirar o merge `--ff-only`, a checagem de árvore suja, de branch ou de divergência, a recusa de não rastreado, a cláusula do drain ou os eventos do worker reprova um teste cada.
- **Origem:** AT-617, Rodada 208, lane L1.

<a id="rn-1023"></a>

### RN-1023 — Projeto cuja `dev` está à frente da `main` recusa o claim, nomeando a migração {#rn-1023}
- **Regra:** em `WorktreeManager.create/3`, depois do `fetch`, se `origin/dev` existe e `origin/main` é ancestral estrito dela (a `dev` tem commits que faltam na `main`), o claim falha com "projeto em gitflow antigo … Rode o script de migração para trunk da api (`pnpm migrar-projeto-para-trunk`, no `brabo-api`) antes de continuar." e nenhum worktree é criado. `dev` ausente, igual, atrás ou divergente da `main` não recusa. O script de migração mora na api (RN-1022).
- **Por quê:** com a branch de trabalho fixada em `main`, um projeto criado no gitflow antigo seria pego de uma `main` que nunca recebeu o trabalho mergeado: um erro silencioso.
- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex:186` (`recusar_projeto_legado`), `apps/engine/lib/engine/dev/worktree_manager.ex:149` (`criar`).
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs` ("RN-1023"); mutação provada: tirar a checagem de "à frente", a de ancestral ou a recusa reprova um teste.
- **Origem:** AT-617, Rodada 208, lane L1.

<a id="rn-1027"></a>

### RN-1027 — No modo `runner` a pasta do projeto avança pelo canal do runner, e o avanço é reaplicado quando o runner entra {#rn-1027}
> **Estende a [RN-1021](#rn-1021):** o mesmo fast-forward e as mesmas recusas, agora também para `execution_mode: runner`.

- **Regra:** `WorktreeManager.avancar_pasta/1` de um projeto `runner` chama `RunnerGit.avancar_pasta/2`, que manda os comandos git pelo `RunnerRouter.exec/5` do canal `terminal:<projectId>` (sem mensagem nova; o `brabo-runner` não muda): o `fetch` com credencial da RN-676 (ADR 0193), depois a decisão. A decisão é `WorktreeManager.decidir_avanco/1`, uma função sobre um transporte `git` injetado e compartilhado com o caminho local, então os dois nomeiam as mesmas recusas (`other_branch`, `dirty_tree`, `diverged`, `untracked_conflict`) e `fetch_failed`, todas sob o mesmo lock `:global` do `fetch` do claim. Sem runner pronto (`RunnerReadiness` diferente de `:pronto`) devolve `{:recusado, :runner_offline, nil}` sem levantar exceção, e o worker registra `workspace.checkout_not_advanced` com `reason: runner_offline`. O avanço é idempotente ("levar a pasta até `origin/main`"), então o `EngineWeb.TerminalChannel` o reenfileira (`TrunkMergedWorker.reaplicar/1`, único por projeto por 30 s) quando o runner entra, e o `Engine.Outbox.Drain` também encaminha `container.running` ao `TrunkMergedWorker`. A reaplicação não leva `sessionId`, então não registra evento.
- **Por quê:** a pasta da máquina do runner ficava no commit da infra como a do servidor (AT-617); com o runner desligado nada podia ser feito na hora do merge, então o avanço espera por ele.
- **Onde:** `apps/engine/lib/engine/actions/workspace/runner_git.ex:231` (`avancar_pasta`), `apps/engine/lib/engine/dev/worktree_manager.ex:252` (`decidir_avanco`), `apps/engine/lib/engine/dev/worktree_manager.ex:217` (`avancar_pasta`), `apps/engine/lib/engine/workers/trunk_merged_worker.ex:53` (`reaplicar`), `apps/engine/lib/engine_web/channels/terminal_channel.ex:261`, `apps/engine/lib/engine/outbox/drain.ex:106` (`handlers_for`).
- **Teste:** `apps/engine/test/engine/dev/avancar_pasta_runner_test.exs`, `apps/engine/test/engine/workers/trunk_merged_worker_test.exs`, `apps/engine/test/engine/outbox/drain_test.exs` ("container.running"), `apps/engine/test/engine_web/channels/terminal_channel_test.exs` ("RN-1027"); mutação provada: tirar a checagem de árvore suja, de branch ou de divergência, o merge `--ff-only`, a resposta `runner_offline`, o despacho `runner`, o fetch, o enfileiramento na entrada, a cláusula do drain ou a unicidade reprova um teste cada.
- **Origem:** AT-617, Rodada 208, lane L7.

<a id="rn-1028"></a>

### RN-1028 — Depois que a pasta do projeto avança, o processo do app é reiniciado no lugar, uma vez por rajada de merges {#rn-1028}
> **Estende as [RN-1021](#rn-1021) e [RN-1027](#rn-1027):** o reinício só acontece depois que a pasta de fato andou.

- **Regra:** o `TrunkMergedWorker` agenda o `Engine.Workers.ReiniciarAppWorker` só quando `avancar_pasta` devolveu `{:avancou, from, to}` e o evento leva `sessionId`; recusa, pasta já atualizada, no-op ou reaplicação (`container.running`, entrada do runner) nunca reiniciam e não registram evento `app.*`. O job é único por projeto (`unique` em `projectId`) e atrasado 20 s, então merges em sequência viram UM reinício, feito com a pasta já na `main` mais recente. O worker chama `EngineApiClient.reiniciar_app/1` (`POST /internal/projects/:projectId/app/restart`, corpo vazio, sempre 200; o cliente HTTP espera 130 s porque a api espera até 100 s) e registra na sessão do job: `app.restarted`; `app.restart_skipped` com `{motivo: "sem_app"}` (sem `run.app`, ou modo `runner`); ou `app.restart_failed` com `{motivo, exitCode?}`. O payload é uma lista fechada (`sem_container`, `tempo_esgotado`, `falha_no_exec`, `app_saiu` com o seu `exitCode`; qualquer outro vira `desconhecido`; chamada que falha é `falha_na_chamada`): NUNCA leva texto de log, porque o comando do app pode conter segredo. Falha só avisa: a pasta nunca é revertida.
- **Por quê:** o app que o usuário testa roda a partir da pasta do projeto; sem reinício, ele segue servindo o código velho depois de um merge (AT-617).
- **Onde:** `apps/engine/lib/engine/workers/trunk_merged_worker.ex:21` (`perform`), `apps/engine/lib/engine/workers/reiniciar_app_worker.ex:20` (`agendar`), `apps/engine/lib/engine/workers/reiniciar_app_worker.ex:30` (`perform`), `apps/engine/lib/engine/sessions/engine_api_client.ex:2090` (`reiniciar_app`).
- **Teste:** `apps/engine/test/engine/workers/reiniciar_app_worker_test.exs`; mutação provada: agendar sem o casamento `:avancou`, tirar a unicidade ou chaveá-la na sessão, tirar a cláusula `sem_app`, ou deixar texto livre no payload de falha reprova um teste cada.
- **Origem:** AT-617, Rodada 208, lane L8.

<a id="rn-1058"></a>

### RN-1058 — As perguntas abertas têm precedência no texto do turno, nunca somem caladas, e os perguntadores as listam com `list_open_questions` {#rn-1058}

> **Revisa a [RN-874](parte-05.md#rn-874) (ordem e corte) e a [RN-1003](#rn-1003) (a frase).**

- **Regra:** no texto de `DecisoesDoProjeto` as perguntas abertas vêm ANTES das decisões. O orçamento de 3 000 caracteres serve primeiro as abertas (até 10, com o `questionId` inteiro) e depois as decisões, as mais recentes primeiro; o corte é por LINHA inteira, nunca no meio de um `questionId`. Com pergunta fora do texto (pelo teto de itens ou de caracteres) o texto diz "Há N perguntas abertas no total; M listadas acima; use `list_open_questions` para ver todas", e o cabeçalho das abertas traz o total. A ferramenta `list_open_questions` (sem parâmetros; Criativo, PO, Arquiteto e Dev Lead) lê LOCAL o event log e devolve todas as abertas do projeto, de qualquer autor, mais antigas primeiro, até 50, cada uma com `questionId`, pergunta, sugestão e autor, terminando em "total: N" (ou "nenhuma pergunta aberta"). A frase central do fluxo manda listar e fechar "todas" com `answer_open_question`, de qualquer autor. Os tetos da RN-874 não mudam (ADR 0060).
- **Por quê:** TP-01 27ª (07/11): com "aceito todas as 7", o Arquiteto fechou 5. O corte de 3 000 caracteres caiu dentro da linha da quinta pergunta, em silêncio, e duas ficaram fora do texto.
- **Onde:** `apps/engine/lib/engine/harness/decisoes_do_projeto.ex:116` (`montar`), `apps/engine/lib/engine/harness/decisoes_do_projeto.ex:76` (`abertas`), `apps/engine/lib/engine/harness/tools/list_open_questions.ex:34` (`run`), `apps/engine/lib/engine/harness/fluxo_do_time.ex:109` (`@frase_da_pergunta`).
- **Teste:** `apps/engine/test/engine/harness/decisoes_do_projeto_test.exs` ("as 7 do TP-01 27ª", "com mais abertas do que cabe"), `apps/engine/test/engine/harness/tools/list_open_questions_test.exs`, `apps/engine/test/engine/harness/tools/answer_open_question_test.exs` ("os quatro perguntadores anunciam a ferramenta"); mutação provada: pôr as decisões antes das abertas reprova um teste; tirar `open_question.answered` da leitura da ferramenta reprova um teste.
- **Origem:** AT-804, Rodada 250, lane L1.

<a id="rn-1059"></a>

### RN-1059 — A execução com todos os dev agents parados e tarefa pendente atrás de bloqueio ou de agente travado grava `execution.stalled` e acorda o Dev Lead {#rn-1059}

> **Estende a [RN-1012](#rn-1012)** (o aviso ao Dev Lead passa a cobrir o bloqueio de origem `codigo` e o disjuntor, mas só quando a execução INTEIRA parou, nunca por tarefa) e **preserva a [RN-047](parte-01.md#rn-047)** (o disjuntor segue gesto humano).

- **Regra:** o `AgentIo` enfileira o `Engine.Workers.ExecucaoParadaWorker` depois de `dev.idle`, `dev.idle_tripped` e `dev.credit_exhausted`: um job por sessão (`unique` em `projectId` e `sessionId`), com espera de 5 s para juntar a rajada. O `perform` só age se TODAS as condições valem: (1) a sessão tem dev agents e todos estão `idle` ou `idle_tripped` (um `working`, `awaiting_gate` ou `awaiting_approval` basta para não fazer nada); (2) o backlog tem tarefa com `status != done`; (3) há tarefa `blocked` ou agente `idle_tripped`. PR esperando merge sem bloqueio nem disjuntor não conta (AT-810). Então grava `execution.stalled` (`actorKind: "system"`, `actorId: "execucao"`) com `{agentesOciosos: [agentId], agentesTravados: [{agentId, module}], tarefasBloqueadas: [{taskId, title, module, reason}] (até 10, reason até 200), tarefasPendentes: N}` (contrato com a web) e entrega `{:execucao_parada, payload}` ao Dev Lead pelo `Engine.Dev.Wake`, que abre turno (ou entra na fila) com o aviso que nomeia o que segura a execução e manda dizer ao usuário o que destrava. Não repete: se o último evento da sessão entre `execution.stalled`, `dev.working`, `dev.rearmed` e `backlog.task_unblocked` é um `execution.stalled` com os mesmos ids de tarefa e de agente, nada é gravado. Falha de leitura vira log. O Dev Lead não ganha ferramenta de rearm nem de desbloqueio.
- **Por quê:** TP-01 27ª (07/11): o disjuntor do `dev-catalogo` abriu e os outros quatro agentes ficaram `idle` por 57 min sem nenhum aviso na sessão; cada agente decide sozinho e ninguém olhava o conjunto.
- **Limite (atalho):** o job `unique` cobre os estados incompletos, então um `dev.idle` que chega durante o `perform` não gera job novo; sem processo do Dev Lead vivo o aviso a ele se perde (RN-1012), mas o evento na sessão não depende dele. A parte da web (feed e Rearmar/Desbloquear) é outra PR.
- **Onde:** `apps/engine/lib/engine/workers/execucao_parada_worker.ex:38` (`agendar`), `apps/engine/lib/engine/workers/execucao_parada_worker.ex:51` (`perform`), `apps/engine/lib/engine/dev/agent_io.ex:178` (`claim_e_rodar`), `apps/engine/lib/engine/dev/agent_io.ex:273` (`finish_task`), `apps/engine/lib/engine/dev/agent_io.ex:279` (`pausar_por_credito`), `apps/engine/lib/engine/agents/dev_lead_server.ex:379` (`handle_info`).
- **Teste:** `apps/engine/test/engine/workers/execucao_parada_worker_test.exs`, `apps/engine/test/engine/dev/dev_agent_server_test.exs` ("sem task pegável"), `apps/engine/test/engine/agents/dev_lead_server_test.exs` ("execucao_parada"); mutação provada: tirar a condição dos agentes parados, a deduplicação, o `Wake.deliver` ou o enfileiramento do `AgentIo` reprova um teste cada.
- **Origem:** AT-800 (engine), Rodada 250, lane L1.

<a id="rn-1070"></a>

### RN-1070 — O Dev Lead lê o estado de ADR, PR e tarefa antes de afirmá-lo, e cita tarefa pelo título no `porque` {#rn-1070}

> **Estende a [RN-772](parte-05.md#rn-772)** (`listar_adrs_propostas` deixa de ser só do Arquiteto) e **aplica ao Dev Lead a regra da [RN-849](parte-05.md#rn-849)** (o estado muda fora da conversa; a leitura vale mais que a lembrança).

- **Regra:** o menu do Dev Lead ganha `listar_adrs_propostas` (a mesma ferramenta do Arquiteto, lida local do Postgres, sem rota nova na api). O prompt dele traz, depois da instrução do `decision_record`, "Não afirme estado de ADR, PR ou tarefa sem ler `listar_adrs_propostas`/`read_backlog` no mesmo turno; se não leu, diga que não sabe." A descrição do campo `porque` do `propose_execution_plan` manda citar tarefas pelo TÍTULO e deixar os ids só em `tarefas[].taskId`, que o sistema já confere (`IdDoBacklog`, RN-699). Não há parser de prosa nem marcação de afirmação sem leitura no resumo do turno.
- **Por quê:** TP-01 27ª (07/11, achado 9): o Dev Lead escreveu "e72dc064 (e97dc064)" no `porque` (texto livre que nada valida) e afirmou uma ADR como mergeada sem ter como lê-la, porque a ferramenta só estava no menu do Arquiteto.
- **Onde:** `apps/engine/lib/engine/agents/dev_lead_server.ex:770` (`system_prompt`), `apps/engine/lib/engine/agents/dev_lead_server.ex:644` (`run_tool`), `apps/engine/lib/engine/agents/dev_lead_server.ex:905` (`tool_specs`), `apps/engine/lib/engine/agents/dev_lead_tools.ex:98` (`spec`).
- **Teste:** `apps/engine/test/engine/agents/dev_lead_server_test.exs` ("lê o estado da ADR por listar_adrs_propostas", "pede tarefa pelo título no porque"); mutação provada: tirar a ferramenta do menu, a cláusula do `run_tool`, a regra do prompt ou a frase do `porque` reprova um teste cada.
- **Origem:** AT-809, Rodada 271, lane L3.

**AT-812 (parte do engine).** A instrução do `decision_record`, idêntica nos cinco conversacionais (PO, Arquiteto, Dev Lead, UX Designer, Staff), passa a pedir, quando a decisão orienta o dev de um módulo, `afeta: {modulos: ["<módulo>"]}` e a citação `modules/<módulo>`; a api usa isso para pôr a decisão na lista da tarefa daquele módulo (EP-030). No contexto do dev agent, a seção das decisões da tarefa tem o cabeçalho "Decisões registradas para esta tarefa/módulo — vencem RF/DoR quando conflitam", porque agora também leva decisão de agente. O teste é `apps/engine/test/engine/agents/instrucao_decision_record_test.exs`; mutação provada: tirar `afeta.modulos` de um dos servidores ou voltar o cabeçalho reprova um teste cada.

**AT-805 (parte do engine, RN-1068 da api).** O PO e o Dev Lead ganham `update_task` (`apps/engine/lib/engine/harness/tools/update_task.ex:47`, `run`): corrige título e/ou descrição de tarefa `todo` por `POST /internal/sessions/:sessionId/tasks/:taskId/update`, com o `agentId` `po` ou `dev-lead`. O prefixo do `task_id` vira uuid antes da chamada ([RN-721](parte-04.md#rn-721)); o 409 nomeado (`tarefa_em_execucao`, `historia_arquivada`, `historia_nao_draft`) volta ao modelo pelo texto de `RecusaDeHistoria` ([RN-727](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-727)); `GravadoNoTurno` conta "tarefa corrigida" ([RN-731](parte-05.md#rn-731)). Teste: `apps/engine/test/engine/harness/tools/update_task_test.exs`.

**AT-806 (parte do engine, RN-1069 da api).** O `propose_adr` aceita `supersedes` (o slug da ADR mergeada que a nova substitui; `docs/adr/<slug>.md` é normalizado), repassa ao `payload.supersedes` do `open_adr_pr` e escreve `Substitui: docs/adr/<slug>.md` no topo do `content` (`apps/engine/lib/engine/harness/tools/propose_adr.ex:79`, `propor`). O 400 `adr_supersedes_invalido` da api volta ao modelo como texto. A spec da ferramenta e a instrução do Arquiteto mandam ler `list_open_questions` e `listar_adrs_propostas` antes de substituir ([RN-1058](#rn-1058), [RN-772](parte-05.md#rn-772)). Teste: `apps/engine/test/engine/harness/tools/propose_adr_supersedes_test.exs`.

**AT-839 (exceção da AT-833 na [RN-502](parte-02.md#rn-502)).** O `NoopDevAgentServer` ganha a cláusula `{:action_settled, _}` (ignora, como o agente real em `apps/engine/lib/engine/dev/dev_agent_server.ex:308`): o `git_push` e o `pr_open` nascem `pending` ([RN-689](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-689)) e, aprovados, entregam `action_settled` (ADR 0052); sem a cláusula o Noop morria com `FunctionClauseError` e nunca chegava a `dev.awaiting_gate`. Teste: `apps/engine/test/engine/dev/noop_dev_agent_server_test.exs` ("pending -> action_settled -> pr_settled").

**AT-844 (lacuna do Noop na [RN-715](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-715)).** O `NoopDevAgentServer` não tinha cláusula para `{:merge_conflict, _}`: o wake `task.merge_conflict` o derrubava com `FunctionClauseError` e a task ficava `in_progress` sem dono. Agora ele bloqueia a task (`mark_task_blocked`, origem `codigo`) com o motivo "conflito de merge: o NoopDevAgent não readota a branch", já que não tem LLM para resolver; o agente real segue readotando. Uma cláusula final de `handle_info` ignora com `Logger.debug` qualquer outra mensagem. Teste: `apps/engine/test/engine/dev/noop_dev_agent_server_test.exs` ("merge_conflict bloqueia a task", "mensagem desconhecida").
