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

<a id="rn-1530"></a>
### RN-1530 — A pergunta em aberto pode trazer até 2 opções prontas e um detalhe técnico recolhido {#rn-1530}

> **Estende a [RN-862](parte-05.md#rn-862)** (a pergunta durável do agente). O lado da api (validar e devolver `opcoes` e `detalhe`) é a F1 da AT-1021 na api.

- **Regra (AT-1021):** `declare_open_question` e o `needs_user_decision` do `emit_qa_verdict` aceitam `opcoes` (até 2 `{rotulo, resposta}`; o rótulo passa pela regra de linguagem da [RN-1529](#rn-1529), a `resposta` é livre e vira o texto que responde) e `detalhe` (texto técnico de até 2.000 caracteres). Com `opcoes`, a `pergunta` também passa pelos padrões da regra (sem arquivo, identificador, código de erro nem crase) e a recusa manda o técnico para `detalhe`; sem `opcoes` a pergunta segue como sempre. Os dois campos vão no `artifact.open_question` e, no QA, no corpo do veredito `needs_user_decision`.
- **Onde:** `lib/engine/harness/tools/declare_open_question.ex` (`spec`, `run`), `lib/engine/gates/tools/emit_qa_verdict.ex` (`opcoes_e_detalhe`), `lib/engine/gates/hooks/termination.ex` (`com_decisao_do_usuario`), `lib/engine/gates/qa_lead_server.ex` (`apply_gate_result`), `lib/engine/dev/explicacao_do_bloqueio.ex` (`opcoes`, `detalhe`)
- **Teste:** `test/engine/harness/tools/declare_open_question_test.exs` (`RN-1530`), `test/engine/gates/tools/emit_qa_verdict_test.exs` (`needs_user_decision com opcoes`)
- **Origem:** AT-1021 (EP-036), TP-01 30ª, paradas L1, L6, L8 e L9.

