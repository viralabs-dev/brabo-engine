---
id: rn-engine-parte-07
title: 'Regras de negócio — Engine — parte 7 (desde RN-1132)'
sidebar_label: 'Engine — parte 7 (desde RN-1132)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

# Engine — parte 7 (desde RN-1132)

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
