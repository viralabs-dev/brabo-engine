---
id: rn-engine-parte-08
title: 'Regras de negócio — Engine — parte 8 (desde RN-1529)'
sidebar_label: 'Engine — parte 8 (desde RN-1529)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

<a id="rn-1529"></a>
### RN-1529 — Todo bloqueio leva a causa em uma frase e até 2 ações prontas: o agente as escreve, o sistema as tira do catálogo {#rn-1529}

> **Estende a [RN-059](parte-01.md#rn-059)** (todo desfecho de falha é nomeado e durável) e **a [RN-864](parte-05.md#rn-864)** (a falha de rede volta sozinha, e a explicação diz isso). O lado da api (gravar, validar e devolver a explicação) é a F1 da AT-1021 na api.

- **Regra (AT-1021):** (1) `report_blocked` exige `causa_para_leigo` (uma frase de até 160 caracteres) e `acoes` (1 ou 2, cada uma `{rotulo, orientacao}`, rótulo de até 40). O nome `causa_para_leigo` existe porque `causa` já é o enum de quem tem a culpa (`nao_consegui` e afins). `run/2` valida a regra de linguagem e devolve o erro ao modelo, que reescreve; o hook entrega a explicação ao `DevAgentServer`. (2) Os bloqueios do SISTEMA (cerca de 30 pontos: contexto, push, commit, conflito, orçamento, teto de iterações, crédito, rede, parada sem sinal, instância de QA, sessão encerrada) tiram `{codigo, causa, acoes}` do catálogo `Engine.Dev.ExplicacaoDoBloqueio.de/1`; `AgentIo.block_task/5` e `EngineApiClient.mark_task_blocked/8` recebem a explicação SEM default (esquecer vira erro de compilação, como a origem). (3) Regra de linguagem, em causa e rótulo (nunca em `orientacao`, `diagnosis` ou `detalhe`): até 160 (rótulo 40) caracteres, uma frase, sem UUID nem hash de 12 ou mais hexadecimais, sem crase, nome de arquivo, caminho, identificador `snake_case`, `camelCase`, átomo, constante, código de erro (`ECONNREFUSED`), `host:porta` nem código HTTP solto. (4) A explicação vai em `dev.blocked`, no artefato `task_blocked` (opcional: artefato antigo segue válido) e no corpo do `/block` como `explicacao: {codigo?, causa, acoes: [{id?, rotulo, orientacao}]}`; a ação "Tentar de novo" leva `orientacao` vazia. O texto do agente não é traduzido; o do catálogo é pt-BR e o web traduz pelo `codigo`.
- **Onde:** `lib/engine/dev/explicacao_do_bloqueio.ex` (`de`, `do_agente`, `frase_para_leigo`), `lib/engine/dev/tools/report_blocked.ex` (`spec`, `run`), `lib/engine/dev/hooks/termination.ex` (`call`), `lib/engine/dev/agent_io.ex` (`block_task`), `lib/engine/sessions/engine_api_client.ex` (`mark_task_blocked`), `lib/engine/dev/dev_agent_server.ex` (`explicacao_do_agente`), `lib/engine/gates/qa_automacao_agent.ex` (`run`), `lib/engine/gates/qa_lead_server.ex` (`aplicar`)
- **Teste:** `test/engine/dev/explicacao_do_bloqueio_test.exs` (os negativos reais da 30ª, o catálogo inteiro e `report_blocked`), `test/engine/sessions/engine_api_client_bloqueio_test.exs` (os nomes de campo no corpo), `test/engine/dev/bloqueio_preserva_trabalho_test.exs` (`RN-1529`), `test/engine/gates/qa_automacao_agent_instancia_test.exs` (`qa_instancia_indisponivel`)
- **Origem:** AT-1021 (EP-036), TP-01 30ª, achado 33 (paradas L1 a L10). Decisão do dono em 26/11/2026: o clique retoma direto, o campo livre fica recolhido e o texto do agente não é traduzido.

- **Emenda (AT-1033, [RN-1546](#rn-1546)):** o `rotulo` das ações também passa pela regra de sentido mínimo (`rotulo_para_leigo/1`: 2 palavras ou mais, sem vocabulário interno), e a recusa volta ao modelo.

<a id="rn-1530"></a>
### RN-1530 — A pergunta em aberto pode trazer até 2 opções prontas e um detalhe técnico recolhido {#rn-1530}

> **Estende a [RN-862](parte-05.md#rn-862)** (a pergunta durável do agente). O lado da api (validar e devolver `opcoes` e `detalhe`) é a F1 da AT-1021 na api.

- **Regra (AT-1021):** `declare_open_question` e o `needs_user_decision` do `emit_qa_verdict` aceitam `opcoes` (até 2 `{rotulo, resposta}`; o rótulo passa pela regra de linguagem da [RN-1529](#rn-1529), a `resposta` é livre e vira o texto que responde) e `detalhe` (texto técnico de até 2.000 caracteres). Com `opcoes`, a `pergunta` também passa pelos padrões da regra (sem arquivo, identificador, código de erro nem crase) e a recusa manda o técnico para `detalhe`; sem `opcoes` a pergunta segue como sempre. Os dois campos vão no `artifact.open_question` e, no QA, no corpo do veredito `needs_user_decision`.
- **Onde:** `lib/engine/harness/tools/declare_open_question.ex` (`spec`, `run`), `lib/engine/gates/tools/emit_qa_verdict.ex` (`opcoes_e_detalhe`), `lib/engine/gates/hooks/termination.ex` (`com_decisao_do_usuario`), `lib/engine/gates/qa_lead_server.ex` (`apply_gate_result`), `lib/engine/dev/explicacao_do_bloqueio.ex` (`opcoes`, `detalhe`)
- **Teste:** `test/engine/harness/tools/declare_open_question_test.exs` (`RN-1530`), `test/engine/gates/tools/emit_qa_verdict_test.exs` (`needs_user_decision com opcoes`)
- **Origem:** AT-1021 (EP-036), TP-01 30ª, paradas L1, L6, L8 e L9.

- **Emenda (AT-1033, [RN-1546](#rn-1546)):** o `rotulo` das opções passa pela mesma regra de sentido mínimo e resume a resposta, não o gesto de responder.

<a id="rn-1533"></a>
### RN-1533 — Os conversacionais falam com o usuário sem identificador interno nem número de máquina {#rn-1533}

> **Revisa a [RN-1070](parte-07.md)** (AT-809: o Dev Lead cita o que leu; hoje só no comentário do código, sem RN na `docs/`): ele cita **pelo título**. Estende a [RN-622](parte-04.md#rn-622) (a mensagem `system` efêmera) e a [RN-1529](#rn-1529) (a regra de linguagem para leigo).

- **Regra (AT-1026):** (1) A fachada `EngineApiClient` (`llm_turn/6`, `llm_turn_stream/6`) acrescenta, antes do idioma, uma mensagem `system` EFÊMERA (`Engine.Harness.FalaParaLeigo`, nunca em `state.messages`) só para os sete conversacionais: cite tarefa, pergunta, regra, ADR ou PR pelo título; nunca UUID, `questionId`, `taskId`, hash, similaridade, limiar nem código de saída; o id é só para as ferramentas. Dev agents e gates ficam de fora (escrevem código, PR e parecer). O id continua no texto do turno e em `list_open_questions`. (2) O `@instrucao_ler_antes_de_citar` do Dev Lead manda citar o estado lido pelo título, nunca pelo id. (3) O `pergunte_antes` do PO (regra parecida com uma existente) manda citar só os títulos das duas regras. (4) `ask_structured_questions` recusa (`{:error, motivo}`, o modelo reescreve) `label` ou `options` com UUID, hash de 12 ou mais hexadecimais, "similaridade"/"limiar" seguido de número ou decimal cru de três casas (`0.817`). (6) Emenda (AT-1033, [RN-1547](#rn-1547)): a orientação também manda não citar nome de ferramenta nem de função, variável ou arquivo do código (diga o que fazem, como "a leitura do plano"); o `title` de `create_task` diz o que a tarefa entrega, e função, rota ou arquivo vão em `description`. (5) A regra mora em `Engine.Harness.FraseParaLeigo`, a mesma da RN-1529 (`frase_para_leigo`, `sem_jargao`) mais `sem_identificador`, que só olha id e número de máquina; espelha `brabo-api:src/domain/linguagem/frase-para-leigo.ts`.
- **Onde:** `lib/engine/harness/fala_para_leigo.ex` (`anexar`), `lib/engine/harness/frase_para_leigo.ex` (`sem_identificador`), `lib/engine/sessions/engine_api_client.ex` (`llm_turn`, `llm_turn_stream`), `lib/engine/agents/dev_lead_server.ex` (`@instrucao_ler_antes_de_citar`), `lib/engine/harness/tools/emit_artifact.ex` (`pergunte_antes`), `lib/engine/harness/tools/ask_structured_questions.ex` (`linguagem_invalida`), `lib/engine/dev/explicacao_do_bloqueio.ex` (delega à regra comum)
- **Teste:** `test/engine/harness/fala_para_leigo_test.exs`, `test/engine/harness/tools/ask_structured_questions_test.exs` (`RN-1533`), `test/engine/dev/explicacao_do_bloqueio_test.exs` (a regra da RN-1529 segue verde)
- **Origem:** AT-1026 (EP-036), TP-01 30ª, achados 4, 7 e 27. Defaults aceitos: a cláusula vale só para os conversacionais; pergunta com número de máquina é recusada no engine.

<a id="rn-1546"></a>
### RN-1546 — O rótulo de ação e de opção diz o efeito do clique: duas palavras ou mais, sem vocabulário interno, e a recusa volta ao modelo {#rn-1546}

> **Estende a [RN-1529](#rn-1529)** (rótulo das ações do bloqueio) **e a [RN-1530](#rn-1530)** (rótulo das opções da pergunta): a regra de forma da `frase_para_leigo` não pega sentido.

- **Regra (AT-1033):** (1) Além da forma, o `rotulo` de `acoes[]` do `report_blocked` e de `opcoes[]` do `declare_open_question` e do `emit_qa_verdict` passa por `Engine.Harness.FraseParaLeigo.rotulo_para_leigo/1`: tem 2 palavras ou mais e nenhuma do vocabulário interno (contrato, gravador, casca, lacuna(s), hook, entrypoint, bootstrap, injeção, gate, worktree, branch, commit, push, merge, deploy, endpoint, payload, schema, middleware, pipeline, mock, stub, fixture, suíte), por palavra inteira, sem caixa e sem acento. (2) A recusa é `{:error, texto}` para o modelo reescrever, com a orientação "o que acontece quando o usuário clica, em 2 a 6 palavras do dia a dia, começando por verbo"; a explicação não é descartada. (3) As descrições das três ferramentas dizem o mesmo: o rótulo diz o efeito do clique, e numa pergunta resume a resposta ("Não deixar cancelar", nunca "Recusar"). (4) A regra é só do engine: a api não a repete na fronteira, porque lá a recusa descartaria a explicação inteira ([RN-1527](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-1527)); o engine segue mais estrito que a api, nunca mais permissivo. (5) Todo rótulo fixo do catálogo de causas passa na regra (teste que percorre o catálogo).
- **Onde:** `lib/engine/harness/frase_para_leigo.ex` (`rotulo_para_leigo`, `@vocabulario_interno`), `lib/engine/dev/explicacao_do_bloqueio.ex` (`checar_rotulo`), `lib/engine/dev/tools/report_blocked.ex`, `lib/engine/harness/tools/declare_open_question.ex`, `lib/engine/gates/tools/emit_qa_verdict.ex` (descrições)
- **Teste:** `test/engine/harness/frase_para_leigo_test.exs`, `test/engine/dev/explicacao_do_bloqueio_test.exs` (o catálogo e `report_blocked`), `test/engine/harness/tools/declare_open_question_test.exs`, `test/engine/gates/tools/emit_qa_verdict_test.exs`
- **Origem:** AT-1033 (EP-036), TP-01 31ª, achados 1, 7 e 11. Defaults aceitos: a regra de sentido fica só no engine; o vocabulário é a lista curta acima, sem nomes de módulo por enquanto.

<a id="rn-1547"></a>
### RN-1547 — O Dev Lead nomeia o botão como a tela o mostra ("Tentar de novo"), só convida a tentar de novo quando algo mudou e não volta a falar do plano aprovado {#rn-1547}

> **Revisa a [RN-711](parte-04.md#rn-711)** (a `saida` do Dev Lead no fluxo do time). **Estende a [RN-1335](parte-07.md#rn-1335)** (o Dev Lead consulta e age) **e a [RN-1059](parte-06.md#rn-1059)** (`execution.stalled` acorda o Dev Lead).

- **Regra (AT-1033):** (1) Os textos fixos que vão ao modelo (`aviso_de_parada`, `aviso_de_decisao`, o "plano recusado" do `DevLeadTools`, a descrição do `declare_open_question`) nomeiam a ação como a aba Pendências a mostra, "Tentar de novo", nunca "Desbloquear"; "Rearmar" continua. (2) O `aviso_de_parada` só convida a tentar de novo quando algo mudou desde o bloqueio (contrato publicado, tarefa entregue, decisão dada); senão diz o que falta acontecer antes. (3) A `saida` do Dev Lead no `FluxoDoTime` diz que, aprovado o plano, o trabalho é acompanhar a execução e que ele não volta a falar da aprovação do plano, a não ser que o usuário pergunte; o `aviso_de_parada` deixa de mandar consultar `ler_plano` (a execução parada prova a aprovação) e diz que o plano está aprovado e a execução ativa. O texto segue estático: nenhuma leitura de estado por turno. (4) O `@instrucao_agir` continua com `ler_plano`, que serve antes da aprovação.
- **Onde:** `lib/engine/agents/dev_lead_server.ex` (`aviso_de_parada`, `aviso_de_decisao`), `lib/engine/agents/dev_lead_tools.ex` (plano recusado), `lib/engine/harness/tools/declare_open_question.ex` (`spec`), `lib/engine/harness/fluxo_do_time.ex` (`@etapas`)
- **Teste:** `test/engine/agents/dev_lead_nome_do_botao_test.exs`, `test/engine/harness/fluxo_do_time_test.exs` (`RN-1547`), `test/engine/harness/tools/declare_open_question_test.exs` (`RN-1517`)
- **Origem:** AT-1033 (EP-036), TP-01 31ª, achados 7 e 14. Mesmo molde da AT-1018 (a `saida` do fluxo contradizia o estado). Nas outras telas do web o nome antigo segue (fatia F2 opcional, fora desta).

<a id="rn-1548"></a>
### RN-1548 — O `write_file` recusa o marcador de segredo oculto, e o ambiente do agente diz como usar a variável {#rn-1548}

> **Estende a [RN-706](parte-04.md#rn-706)** (o ambiente do agente) **e a [RN-900](parte-06.md#rn-900)** (guardas do `write_file`). O lado da api (ocultar na saída do `terminal`) é a F1 da AT-1038 na api.

- **Regra (AT-1038):** (1) A saída do `terminal` chega ao agente com senha e chave declaradas trocadas por um marcador que começa em `[oculto` (`[oculto]` na senha de URL, `[oculto: NOME]` no valor declarado). (2) `write_file` recusa (`{:error, texto}`, nada é escrito) conteúdo que contenha `[oculto`: o valor foi ocultado, e copiá-lo gravaria o marcador no lugar do valor; o texto manda ler a variável no shell (`$NOME`) ou gerar o valor. (3) A linha "Segredos" do `AmbienteDoAgente` diz que a saída oculta senhas e chaves declaradas (`[oculto]`) e que se lê a variável no shell; o teto do texto do ambiente sobe de 1.500 para 1.600 caracteres para caber a frase.
- **Onde:** `lib/engine/harness/tools/write_file.ex` (`recusa_do_marcador`), `lib/engine/harness/ambiente_do_agente.ex` (`@teto`, "Segredos")
- **Teste:** `test/engine/harness/tools/write_file_test.exs` (`RN-1548`), `test/engine/harness/ambiente_do_agente_test.exs`
- **Origem:** AT-1038 (EP-036), TP-01 31ª: um `printenv` gravou a URL de conexão no resultado da ação e no log. Defaults aceitos: o marcador exato que a api grava é `[oculto]`; a guarda olha o prefixo `[oculto`.
