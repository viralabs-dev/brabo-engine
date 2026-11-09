---
id: rn-engine-parte-01
title: 'Regras de negócio — Engine — parte 1 (desde RN-016)'
sidebar_label: 'Engine — parte 1 (desde RN-016)'
description: 'As RNs hospedadas na raiz engine.'
keywords: [regras de negócio, engine]
---

# Engine — parte 1 (desde RN-016)

## PR Gates

<a id="rn-016"></a>

### RN-016 — O veredito do gate prevalece sobre o enunciado da task {#rn-016}

Se a descrição da task diz uma coisa e o veredito do gate diz
outra, vale o veredito.

Desde a Fase 8b, "o veredito" pode vir de duas especializações — a regra
não muda: cada uma prevalece sobre a task DENTRO do que avalia
(Automação sobre a cobertura de testes; Performance/Segurança sobre os RNFs
de performance e os achados de código). `QaLead.consolidar/1` não arbitra
entre elas e a task: qualquer `changes_requested` de qualquer uma já reprova
o todo (ver [RN-036](#rn-036)).

- **Onde:** prompt de cada especialização em
  `apps/engine/lib/engine/gates/qa_automacao_agent.ex` e
  `qa_performance_seguranca_agent.ex`
- **Origem:** [ADR 0020](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0020-destravar-gates-qa-secops.md) §9

## Psicólogo e Anamnese

<a id="rn-023"></a>

### RN-023 — A causa de término é classificação determinística {#rn-023}

Vem do **motivo** registrado, nunca de julgamento do LLM e nunca por
eliminação. Toda falha registra a origem: `infra | modelo | código | política`.

- **Onde:** `apps/engine/lib/engine/psychologist/termination_classifier.ex`
- **Origem:** [ADR 0022](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0022-fechamento-4b-psicologo.md) §5 e
  [ADR 0020](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0020-destravar-gates-qa-secops.md) §6

## PR Gates

<a id="rn-036"></a>

### RN-036 — QA vira área: o Lead consolida sem mudar o contrato do gate {#rn-036}

A especialização de Automação (o `QAAgent` da Fase 4a) sempre é delegada;
Performance/Segurança só quando a história tem RNF de performance pertinente
(`Engine.Gates.QaLead.rnf_de_performance?/1` — heurística de palavra-chave, não
NLP). A decisão de NÃO delegar é sempre registrada — uma delegação
`dispensed` com justificativa, nunca silêncio.

Consolidação: `approved` só se TODAS as delegações que rodaram aprovaram; qualquer
`changes_requested` reprova o todo, com os `itens` da(s)
especialização(ões) que pediram mudança, cada item prefixado com o
rótulo de quem o levantou (`"[QA de Automação] ..."`) — é assim que a
origem é rastreada SEM mudar `itens` de `string[]` para outro
formato. Falha de delegação (qualquer origem — `infra`, `modelo`, `codigo`,
`politica`) NUNCA vira `changes_requested`: o Lead bloqueia a task
com a origem real (RN-015).

O `qa_verdict` que chega à api é o MESMO artefato e passa
pela MESMA rota de sempre (`RecordGateVerdictUseCase`,
`nextGateStatus`) — nenhum dos dois mudou. O que a api sabe da
área mora só nos eventos `delegation.completed`/`delegation.failed`/
`delegation.dispensed`, que a especialização e o Lead
registram à parte.

- **Onde:** `apps/engine/lib/engine/gates/qa_lead.ex` (`consolidar/1`,
  `rnf_de_performance?/1`), `qa_lead_server.ex` (a fiação);
  `apps/api/src/application/use-cases/execution/record-delegation.use-case.ts`;
  `apps/api/src/db/schema/agents.ts` (tabela `delegations`, enum `failure_origin`)
- **Teste:** `apps/engine/test/engine/gates/qa_lead_test.exs` (a árvore de
  decisão pura), `qa_lead_server_test.exs` (a fiação: decisão →
  delegação → registro → consolidação → a MESMA chamada de sempre) e —
  a prova de que o contrato não mudou —
  `record-gate-verdict.use-case.spec.ts`, `pr-gate-state-machine.spec.ts`
  e `record-infra-gate-verdict.use-case.spec.ts` passam **sem mudança
  nenhuma**
- **Origem:** [ADR 0038](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0038-hierarquia-de-agentes.md)

Do lado do `apps/web` (Fase 8d): o painel do time agrupa `qa`/
`qa-automacao`/`qa-performance-seguranca` como lead + especializações
recolhíveis, a linha do tempo da PR abre o veredito consolidado nas
suas partes (`ProjectApprovalsTab.tsx`, `PrGateTimeline.tsx`), e o
feed narra `delegation.*` — ver `apps/web/src/lib/agents.ts`
(`AREAS`/`areaFor`).

---

<a id="rn-047"></a>

### RN-047 — Circuit breaker do dev agent: N bloqueios consecutivos o param, sem queimar orçamento em laço {#rn-047}

Cada dev agent mantém um contador (`dev_agent_states.consecutive_blocked`)
de quantas tarefas TERMINARAM `blocked` em sequência — localmente (no
ToolLoop) ou remotamente (o teto de correções do gate esgotado). Ao atingir o
teto por projeto (`max_consecutive_blocked`, default 3), o agente para em
`idle_tripped` **sem tentar pegar a próxima tarefa**. Um desfecho terminal
aprovado zera o contador; uma tarefa bloqueada isolada segue o fluxo normal
(devolvida com diagnóstico, disponível para um humano desbloquear) — o
breaker trata da SEQUÊNCIA, não da tarefa.

A única saída de `idle_tripped` é um rearme explícito
(`POST .../agents/:agentId/rearm`, papel `developer`): ele zera o contador e
o agente volta a tentar pegar tarefa. Não há destravamento automático — o
mesmo princípio do `MarkTaskBlockedUseCase`/`unblock`, aplicado à sequência
em vez da tarefa. Rearmar um agente que **não** está travado é **409**, não
sucesso silencioso: o evento `dev.rearmed` é imutável, e registrá-lo para um
rearme que não aconteceu seria uma mentira no event log.

Um bloqueio que vem de FORA do agente (o `QaLeadServer` falhando
internamente, por exemplo) também precisa acordá-lo — é por isso que a
emissão de `task.gate_resolved` mora no `MarkTaskBlockedUseCase`, o funil por
onde todo bloqueio passa, e não no `RecordGateVerdictUseCase`, que só vê
parte deles. Sem isso o agente ficaria em `awaiting_gate` para sempre, com a
tarefa morta e o contador do breaker nunca incrementando.

Reiniciar o engine com um agente em `working` **não** conta para o contador:
a tarefa retida é bloqueada com um diagnóstico de reinício, mas esse
bloqueio não é o agente "queimando o teto" — é a infraestrutura caindo. O
contador só sobe quando o próprio ciclo dev↔gate produz um `blocked` real.

- **Onde:** `apps/engine/lib/engine/dev/dev_agent_server.ex` (`finish_task/2`,
  `resume_state/2`), `apps/api/src/application/use-cases/execution/rearm-dev-agent.use-case.ts`,
  `apps/api/src/db/schema/iam.ts` (`projects.max_consecutive_blocked`)
- **Teste:** `apps/engine/test/engine/dev/dev_agent_server_test.exs`
  (describe `circuit breaker`), `apps/engine/test/engine/dev/dev_rehydrator_test.exs`
  (describe `the four rehydrated states`), `test/application/use-cases/execution/rearm-dev-agent.use-case.spec.ts`
- **Origem:** [ADR 0045](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0045-reagendamento-por-evento-do-dev-agent.md)

<a id="rn-050"></a>

### RN-050 — Sem PR aberta, nenhum gate abre {#rn-050}

O dev agent propõe commit, push e PR e **lê o desfecho de cada um**. Ele só
abre o gate se os três executaram. Se um ficou `pending` — a autonomia do
agente em `require_approval` — ele entra em `awaiting_approval`, **segurando o
worktree**, e não abre gate nenhum.

Sem isso o gate abria de qualquer jeito, e o dano era silencioso: o QA varre
o **worktree**, não a PR; achou os arquivos, aprovou; o SecOps aprovou; a
tarefa fechou como concluída — **sem uma linha commitada e sem PR nenhuma**.
Só depois, ao aprovar o commit, o usuário veria a ação falhar (com
diagnóstico vazio, porque `System.cmd` num diretório apagado devolve
`{"", 2}`).

O que libera o agente é `task.pr_settled`, emitido pela api quando `pr_open`
chega a um desfecho terminal: `opened: true` abre o gate; `opened: false`
(negada ou falha) devolve a tarefa com diagnóstico, em vez de deixar o
agente esperando para sempre por um gate que ninguém vai abrir.

Uma PR negada **não conta para o circuit breaker** da [RN-047](#rn-047): a
decisão foi do usuário, não do agente queimando o teto — o mesmo princípio
da recuperação de reinício.

Essa regra também elimina o D5 (worktree reciclado sob aprovação pendente)
como consequência: o worktree só é liberado em `gate_resolved`, o gate só
abre depois da PR, e a PR só abre depois do commit e do push.

- **Onde:** `apps/engine/lib/engine/dev/agent_io.ex` (`propose/3`),
  `apps/engine/lib/engine/dev/dev_agent_server.ex` (`abrir_gate/1`,
  `aguardar_aprovacao/2`),
  `apps/api/src/application/use-cases/actions/execute-git-action.use-case.ts`
  (`settlePrOpen`)
- **Teste:** `apps/engine/test/engine/dev/dev_agent_server_test.exs`
  (describe `pending approval doesn't open a gate`)
- **Origem:** [ADR 0048](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0048-decisao-no-log-e-a-ordem-do-gate.md)

<a id="rn-059"></a>

### RN-059 — Falha de turno é evento durável com origem, e o agente fala {#rn-059}

Quando um turno de LLM falha, o agente grava **`agent.error`** no event log
com três campos: `origem` (vocabulário do ADR 0020), `mensagem` em português e
o `reason` bruto. E a mensagem aparece **no fio da conversa**, não só no log.

Era o contrário, e o desfecho era o pior possível: os quatro agentes
conversacionais gravavam `agent.response` com conteúdo **vazio** —
indistinguível de sucesso no log imutável — e mandavam o motivo por
`broadcast`, que é efêmero. Quem não estivesse com a aba aberta naquele
segundo nunca saberia que houve erro; quem estivesse, via um balão em branco.

Havia um segundo caminho, pior ainda: quando a api narrava a falha no PRÓPRIO
frame final (budget, credencial ausente, binding faltando), o turno não caía no
ramo de erro e **não emitia evento nenhum** — silêncio absoluto.

Esse mesmo ramo, uma vez corrigido, custou uma segunda rodada: no PO, no
Arquiteto e no Dev Lead ele devolvia `{state, ""}` — uma TUPLA onde todos os
outros ramos de `run_turn` devolvem o `state` (um mapa). O `Map.put/3` de
`TurnoAssincrono.tratar_resultado/2` levantava `BadMapError` dentro do
`handle_info`, e como os quatro conversacionais são `restart: :temporary`, o
agente MORRIA e não voltava. A falha deixava de ser silenciosa e virava uma
queda — com os gatilhos mais corriqueiros que existem. A regra vale inteira: o
agente narra a falha **e continua de pé**. Por isso `tratar_resultado/2` tem
uma segunda barreira, no ponto compartilhado pelos quatro: resultado de turno
que não é mapa vira `agent.error` com origem `codigo`, nunca um processo morto.

A origem NUNCA é adivinhada: cada padrão em `FalhaDeTurno.origem/1` tem um
motivo escrito, e o que não casa com nenhum sai como **`codigo`** — a lacuna é
do nosso classificador, e essa é a origem que aponta a ação certa (ADR 0020).

Os eventos já gravados não se apagam — a tela os NOMEIA como resposta vazia
anterior a esta regra, em vez de mostrar branco.

- **Onde:** `apps/engine/lib/engine/agents/falha_de_turno.ex`,
  `criativo_server.ex`, `po_server.ex`, `arquiteto_server.ex`,
  `dev_lead_server.ex`, `infra_lead_server.ex` (`emit_falha/2`),
  `turno_assincrono.ex` (`tratar_resultado/2`, a segunda barreira),
  `apps/web/src/lib/session-falha.ts`
- **Teste:** `apps/engine/test/engine/agents/criativo_server_test.exs`
  (evento durável com origem; nunca grava resposta vazia; erro narrado no frame
  final também vira evento); `po_server_test.exs` (o frame final com erro não
  derruba o agente — GenServer de VERDADE, com `Process.alive?/1`);
  `arquiteto_server_test.exs` e `dev_lead_server_test.exs` (mesmo caminho, ciclo
  completo); `turno_assincrono_test.exs` (a segunda barreira narra em vez de
  derrubar); `apps/web/src/lib/session-falha.test.ts`
- **Origem:** execução real da FASE 13b

<a id="rn-061"></a>

### RN-061 — Uma falha de FERRAMENTA também é um evento, e volta para o modelo {#rn-061}

O resultado de uma chamada de ferramenta nunca é descartado. Ele vira
`tool.result` no event log (`ok` e, quando falha, `erro`), o agente **diz** o
que aconteceu no fio, e o motivo **volta para o modelo** no papel `tool` —
para ele corrigir e reemitir no turno seguinte. Um erro de ferramenta é
entrada do laço, não fim de linha.

O agente Criativo era o único que o descartava
(`_ = EmitArtifact.run(args, state)`) — o PO e o Arquiteto já o realimentavam.
Numa execução real o modelo emitiu `titulo`/`descricao` contra um schema que
exige `title`/`description`/`origin`: as **quatro regras de negócio da
conversa foram recusadas**, nenhum evento foi gravado, e ele continuava
dizendo "registrei as regras" com o painel vazio.

A descrição da ferramenta agora NOMEIA os campos obrigatórios de cada tipo,
em inglês e com um exemplo preenchido — inclusive que `business_rule.origin`
é uma **lista não vazia** de `seq` das mensagens que originaram a regra, não
texto livre. Sem isso o modelo adivinha, e adivinha no idioma da conversa.

É a mesma regra da [RN-059](#rn-059) aplicada ao outro caminho de falha: duas
políticas para o mesmo problema seriam duas chances de engolir o erro.

- **Onde:** `apps/engine/lib/engine/agents/criativo_server.ex` (`dispatch_tool`,
  `realimentar`), `apps/engine/lib/engine/harness/tools/emit_artifact.ex`
  (`descricao/0`), `apps/engine/lib/engine/harness/artifact_schemas.ex`
  (`required/1`)
- **Teste:** `apps/engine/test/engine/agents/criativo_server_test.exs`
  (`a refused tool becomes a tool.result with an error, and the agent speaks`)
- **Origem:** execução real da FASE 13b

<a id="rn-062"></a>

### RN-062 — Mensagem a agente conversacional REIDRATA o processo {#rn-062}

Uma mensagem endereçada a Criativo, PO ou Arquiteto sobe o processo se ele não
estiver de pé, antes de entregar. O `init` de cada servidor já reconstrói o
histórico do event log; faltava quem o chamasse.

Antes, um restart do engine matava a conversa em silêncio: a sessão sobrevivia
como `active`, o processo do agente não, e a próxima mensagem morria com
`GenServer.call ... exited` — sem evento, sem erro na tela, sem nada. O usuário
via a própria mensagem aparecer e nenhuma resposta chegar, para sempre.

O comentário de `revise/2` dizia que agente morto nesta rota "é um bug". É — e
basta o engine reiniciar para acontecer. É a mesma garantia que a Fase 12b deu
aos dev agents, aplicada aos conversacionais.

- **Onde:** `apps/engine/lib/engine_web/controllers/agent_command_controller.ex`
  (`message/2`)
- **Teste:** coberto pela suite de agentes; a prova de execução está em
  docs/explanation/validacao-real.md
- **Origem:** execução real da FASE 13b

<a id="rn-063"></a>

### RN-063 — Encerrar sem produzir é desfecho, não falha {#rn-063}

A Anamnese tem uma ferramenta para dizer **"não há nada a emitir, e este é o
motivo"** (`skip_proficiency`). A rodada encerra com `anamnese.run_skipped` e o
motivo no payload — nunca com `anamnese.run_failed`.

Antes ela não tinha esse verbo. A única ferramenta era `emit_proficiency`, que
recusa lista vazia (com razão: perfil vazio não é perfil). Numa janela sem
membro elegível a Anamnese descobria isso na PRIMEIRA iteração, escrevia em
prosa "não há membros elegíveis", chamava `emit_proficiency` com `profiles: []`,
era recusada — e repetia até o teto de iterações. Cada volta reenvia o
histórico, que cresce a cada volta.

Numa execução real isso custou **145 mil tokens de entrada e 4× o gasto do
Criativo e do PO somados**, sem produzir nada. E voltava a cada tick do
agendador, a cada 15 minutos, para sempre.

O teto de iterações funcionava — não era laço infinito. O desperdício era **por
rodada, repetido indefinidamente**, que é pior: um laço trava e alguém percebe;
este sangrava devagar.

Narrar `run_failed` para uma rodada que fez a coisa certa também é defeito: quem
lê o log aprende a ignorar o evento de falha.

- **Onde:** `apps/engine/lib/engine/anamnese/tools/skip_proficiency.ex`,
  `apps/engine/lib/engine/anamnese/hooks/termination.ex`,
  `apps/engine/lib/engine/workers/anamnese_worker.ex` (`handle_outcome`)
- **Teste:** `apps/engine/test/engine/workers/anamnese_worker_test.exs`
  (`encerrar sem perfis é DESFECHO: narra run_skipped com o motivo, não falha`)
- **Origem:** execução real da FASE 13b

<a id="rn-069"></a>

### RN-069 — Repetir uma tarefa recria a branch, não falha {#rn-069}

`WorktreeManager.add_worktree/3` usa `git worktree add -B` (cria **ou**
reseta), não `-b`. Ele já removia o diretório do worktree anterior, mas
deixava a branch para trás — e como o nome dela vem do slug da tarefa, a
segunda tentativa na MESMA tarefa sempre caía em `fatal: a branch named
'feature/<slug>' already exists`.

O efeito era permanente: desbloquear a tarefa não ajudava, reativar a
execução não ajudava, e o circuit breaker desarmava sem saída. Numa execução
real a única saída era um `git worktree prune` manual no workspace do
projeto.

Resetar é a escolha certa: o worktree anterior já foi removido, o trabalho
daquela tentativa não vale nada (a tarefa voltou para a fila), e a branch
renasce do ponto atual de `work_dir`.

- **Onde:** `apps/engine/lib/engine/dev/worktree_manager.ex`
- **Teste:** `apps/engine/test/engine/dev/worktree_manager_test.exs`
  (`retrying the SAME task recreates the worktree instead of failing`)
- **Origem:** execução real da FASE 13b

<a id="rn-073"></a>

### RN-073 — Uma aprovação pendente SUSPENDE o laço, não o queima {#rn-073}

Quando uma ferramenta de pipeline devolve `pending`, o ToolLoop **para** e o
dev agent entra em `:awaiting_approval`, segurando a tarefa, o worktree e o
histórico do laço. A decisão do usuário emite `task.action_settled`, que o
acorda: o resultado real ocupa o lugar onde a palavra "pending" estaria, e o
laço retoma de onde parou.

Duas propriedades que o teste trava:

- **Nada é gravado durante a espera.** O espaço da mensagem da ferramenta
  fica vazio. Gravar "pending" ali diria ao modelo que foi isso que o comando
  respondeu — que era exatamente o defeito.
- **Uma recusa é uma resposta.** O motivo ocupa o lugar do resultado e o
  agente aprende que aquele caminho fechou, em vez de esperar para sempre por
  algo que ninguém vai aprovar. É o mesmo princípio de `pr_settled` com
  `opened: false` ([RN-047](#rn-047)), um nível abaixo.
- **O wake tem de CHEGAR.** `task.action_settled` nasce no agregado `task`,
  não na `proposed_action` que o nome da tabela sugere: o drain do engine lê
  uma lista fechada de agregados (`session` e `task`). Emitido fora dessa
  lista, o evento é gravado com sucesso, fica com `processed_at` nulo e nem
  chega a ser lido — sem job, sem erro, sem log, e o agente espera para
  sempre. O contrato atravessa duas linguagens, e é por isso que está fixado
  nos dois lados.

Se o engine **reiniciar** durante a espera, a regra deixa de valer para essa
tarefa: o laço suspenso só existe em memória, então ela volta para a fila
bloqueada com origem `infra`, e a decisão tomada depois não tem onde ser
aplicada. Bloquear com diagnóstico é deliberado — a alternativa era a espera
eterna e silenciosa, que é exatamente o que esta regra existe para acabar.

O que isto conserta: `pending` costumava voltar como o RESULTADO da
ferramenta e o laço seguia em frente. O modelo lia aquilo como a resposta do
comando, não aprendia nada, tentava outra coisa — e cada tentativa queimava
uma iteração até `toolloop.limit_reached {iteration: 8, max_iterations: 8}`,
com a tarefa bloqueada por "limite de iterações atingido" sem uma linha
escrita. As aprovações concedidas chegavam depois de o laço esgotado e não
serviam para nada.

A allowlist de terminal ([RN-068](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-068)) continua valendo, mas deixa de ser
a única defesa: é uma lista de comandos previstos, e o modelo inventa
comandos.

- **Onde:** `apps/engine/lib/engine/harness/hooks/action_pipeline.ex`,
  `harness/tool_loop.ex`, `dev/dev_agent_server.ex`,
  `workers/dev_agent_wake_worker.ex`; emissão em
  `apps/api/src/application/use-cases/actions/{approve,deny}-action.use-case.ts`
- **Teste:** `apps/engine/test/engine/dev/dev_agent_awaiting_approval_test.exs`
  (`pending action STOPS the agent`; `approved: resumes the loop with
  the REAL output`; `restart during the wait BLOCKS the task`) e
  `apps/engine/test/engine/dev/wake_do_outbox_ao_agente_test.exs`, que
  percorre a cadeia inteira — outbox, drain, fila e processo — porque os
  testes por elo estavam todos verdes com a entrega quebrada; o agregado
  está fixado no lado da api em
  `apps/api/test/application/use-cases/actions/approve-deny-action.use-case.spec.ts`
- **Origem:** [ADR 0052](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0052-dev-agent-espera-aprovacao-no-meio-do-laco.md),
  fase A da triagem

<a id="rn-074"></a>

### RN-074 — A saída de terminal tem teto de bytes {#rn-074}

A saída de um comando é cortada em `TERMINAL_OUTPUT_MAX_BYTES` (default 32 KiB)
antes de virar resultado da ferramenta, e o corte deixa uma **marca** dizendo os
dois tamanhos e o que fazer:

```
[saída truncada: 32768 de 1048576 bytes. Refine o comando (head, grep,
-maxdepth) para ver o que falta.]
```

Três propriedades que o teste fixa:

- **O teto é `>`, não `>=`.** Saída que cabe exatamente no limite passa
  intacta — marcá-la faria o modelo refinar um comando que já deu tudo.
- **O corte não parte caractere multibyte.** `binary_part/3` corta por byte;
  cair no meio de um `é` produz binário inválido que quebra a serialização
  JSON antes de o resultado chegar ao modelo.
- **`raw_bytes` continua sendo o tamanho REAL produzido**, não o truncado. É
  medição, e mentir nela esconderia justamente o comportamento que motivou o
  teto. Quem quiser detectar truncagem compara `byte_size(stdout)` com
  `raw_bytes`.

O que isso conserta: a saída de cada comando fica no histórico do laço e viaja
em **todo** turno seguinte. Sem teto, um `find` numa árvore grande basta — a
execução do `hello-limpo` morreu com `{413, "request entity too large"}` no
turno 18, sem uma linha escrita. O estouro é de **bytes da requisição**, não de
janela de contexto: a maior chamada bem-sucedida tinha 28.993 tokens de entrada.

A marca é endereçada ao **modelo**, não ao humano — sem dizer o que fazer, ele
tende a repetir o mesmo comando.

- **Onde:** `apps/engine/lib/engine/actions/terminal_executor.ex`
  (`truncate/2`), teto em `apps/engine/config/runtime.exs`
- **Teste:** `apps/engine/test/engine/actions/terminal_executor_test.exs`
  (describe `teto de bytes da saída`)
- **Origem:** achado S de
  [achados-execucao-real.md](https://github.com/viralabs-dev/brabo/blob/dev/docs/explanation/achados-execucao-real.md), Fase F do
  [backlog](https://github.com/viralabs-dev/brabo/blob/dev/docs/explanation/backlog.md)

<a id="rn-076"></a>

### RN-076 — A credencial de git nunca é escrita em arquivo {#rn-076}

O engine trabalha em repositório remoto pedindo o **remoto de trabalho** à api
(`GET /internal/projects/:projectId/git-remote`), que devolve a origem **limpa**
e o token do owner à parte. O token entra na invocação do git pelo **ambiente do
processo filho** e em nenhum outro lugar:

- **não no `origin`** — é a URL limpa que fica gravada no `.git/config`;
- **não em argv** — `ps` mostra a linha de comando de qualquer processo;
- **não em arquivo** — nem helper persistido, nem `~/.git-credentials`.

O helper de credencial é passado por `-c`, vale só para aquele processo, e vem
depois de um `credential.helper=` vazio: helpers são acumulativos e o primeiro a
responder ganha, então sem zerar antes um helper do host responderia no lugar.

**Por que isso é regra e não preferência.** Escrever
`https://x-access-token:TOKEN@github.com/…` no `origin` — o que quase todo
tutorial ensina — grava a credencial em texto puro **dentro da pasta do
projeto**, exatamente onde a [RN-075](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-075) dá ao dev agent leitura
**auto-aprovada**. Um `cat .git/config` devolveria o token sem passar por
aprovação nenhuma, e ele viajaria ao provider de LLM no histórico do laço. O
escopo de caminho protege contra o agente ler para FORA do projeto; não tem como
proteger contra um segredo que o próprio produto colocou DENTRO.

A credencial é a do **owner do workspace**, pelo mesmo resolvedor da
[RN-058](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-058) — duas regras de "de quem é a credencial" divergiriam.
Provider `local` não tem token nem consulta a api: é resolvido direto do banco,
e é o caminho que o `pnpm dev` e a suite inteira exercitam.

- **Onde:** `apps/engine/lib/engine/actions/git_auth.ex`,
  `engine/projects/project_repository.ex` (`remoto_de_trabalho/1`),
  `apps/api/src/application/use-cases/git/get-project-git-remote.use-case.ts`
- **Teste:** `apps/engine/test/engine/actions/git_auth_test.exs` (o token não
  aparece em argv nem no helper) e
  `apps/api/test/application/use-cases/git/get-project-git-remote.use-case.spec.ts`
  (a origem devolvida não contém o token nem `@`)
- **Origem:** [ADR 0056](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0056-o-engine-trabalha-em-repositorio-remoto.md),
  achado N, Fase B do [backlog](https://github.com/viralabs-dev/brabo/blob/dev/docs/explanation/backlog.md)

<a id="rn-077"></a>

### RN-077 — A origem da falha é sempre uma das quatro {#rn-077}

Todo desfecho de falha nomeia a ORIGEM no vocabulário **fechado** do
[ADR 0020](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0020-destravar-gates-qa-secops.md) —
`infra | modelo | codigo | politica`. Não há quinto valor: `null` e
`"indeterminada"` deixaram de ser possíveis.

Duas garantias estruturais, e nenhuma depende de alguém lembrar:

- **`AgentIo.block_task/4` não tem default para a origem.** Ela era
  "obrigatória em espírito", com `"indeterminada"` de default — e o desfecho
  mais caro da execução real saiu exatamente assim, porque o call site não
  passou nada. Sem default, esquecer vira erro de compilação.
- **`FalhaDeTurno.origem/1` sempre devolve uma das quatro**, e há teste de
  tabela que falha se alguma entrada — inclusive uma forma nunca vista —
  produzir outra coisa.

**Por que `indeterminada` saiu.** Ela existiu com um argumento razoável: não
chutar seria mais honesto que escolher no escuro. O efeito real foi o oposto —
`indeterminada` **não aponta ação nenhuma**, e quem triava a rodada seguinte
recomeçava a investigação do zero. O que ela significava de fato era *o
classificador não reconheceu esta forma*, que é lacuna do nosso código: `codigo`
é a origem que aponta a ação certa (acrescentar a cláusula que falta). O
diagnóstico continua indo verbatim, então nada se perde.

**As origens não são chute.** Cada desfecho do ToolLoop diz quem decidiu parar:
`report_blocked` e teto de iterações são do **modelo** (ele decidiu, ou gastou o
que tinha); orçamento e PR não aprovada são **política** (foi uma decisão, nada
quebrou); restart e falha ao montar contexto são **infra**; e quando há
`last_error`, a origem sai do MESMO erro que o diagnóstico narra — era esse par
que se contradizia, com `diagnosis` dizendo `{413, …}` e `origem` dizendo
"indeterminada" na mesma linha.

- **Onde:** `apps/engine/lib/engine/agents/falha_de_turno.ex`,
  `engine/dev/agent_io.ex` (`block_task/4`, sem default),
  `engine/dev/dev_agent_server.ex` (`origem_da_parada/1`)
- **Teste:** `apps/engine/test/engine/agents/falha_de_turno_test.exs`
  (`o vocabulário é fechado`) e
  `apps/engine/test/engine/dev/dev_agent_server_test.exs`, que afirma a origem
  no evento emitido
- **Origem:** achados P, Q e T de
  [achados-execucao-real.md](https://github.com/viralabs-dev/brabo/blob/dev/docs/explanation/achados-execucao-real.md), Fase G do
  [backlog](https://github.com/viralabs-dev/brabo/blob/dev/docs/explanation/backlog.md)

<a id="rn-079"></a>

### RN-079 — O Psicólogo não analisa sessão sem evento analisável {#rn-079}

Antes de gastar um turno de modelo, a análise pergunta se há o que analisar. Não
havendo, ela **não roda** e o desfecho vira `psychologist.analysis_skipped`.

**Analisável exclui duas coisas, por motivos diferentes:**

- **o rastro dos próprios analistas.** O Psicólogo grava o turno dele no log da
  sessão que está analisando (`agent.response`, `tool.call`, `tool.result`, a
  hipótese). Contar isso faria uma sessão vazia parecer povoada **a partir da
  primeira análise**, e cada retentativa a encheria mais — o critério nunca mais
  reprovaria. Vale igual para a Anamnese;
- **`bootstrap.*`**, que é provisionamento de repositório rodando sozinho: nove
  passos de máquina não dizem nada sobre a pessoa.

Tudo o mais conta, inclusive `proposed_action.*` — o usuário aprovando e negando
sem escrever mensagem nenhuma **é** comportamento, lição que a Anamnese já tinha
aprendido ([RN-063](#rn-063)).

**São duas contagens, e elas não se substituem.** A crua dimensiona o trabalho
(quanto log ler, logo qual tier de triagem, leve ou pesado); a analisável decide
se há trabalho. Confundi-las é o defeito: uma sessão só de bootstrap passava por "20
eventos" sem ter nenhum, ganhava a análise, e o modelo — sem nada para citar —
inventava `seq` inexistentes até a validação de evidência rejeitar e ele
desistir, com o orçamento já gasto.

**Pular vale também para reprocessamento manual.** Reprocessar não fabrica
material: quem clicou recebe o motivo no log em vez de uma hipótese inventada
sobre um log que não existe.

O skip vira **evento**, ao contrário do da Anamnese, que é só log — aquele roda
a cada 15 min e viraria ruído, este roda uma vez por fechamento de sessão, e uma
análise ausente sem nada narrado é indiagnosticável.

- **Onde:** `apps/engine/lib/engine/session_events/event.ex` (`count_analisaveis/1`),
  `apps/engine/lib/engine/psychologist/triage.ex` (`should_run?/1`),
  `apps/engine/lib/engine/workers/psychologist_worker.ex`
- **Teste:** `apps/engine/test/engine/session_events/event_analisaveis_test.exs`
  (inclui a reprodução da sessão do achado: 14 eventos, nenhum analisável),
  `apps/engine/test/engine/workers/psychologist_worker_test.exs`
- **Origem:** achado J, Fase E do [backlog](https://github.com/viralabs-dev/brabo/blob/dev/docs/explanation/backlog.md)

<a id="rn-080"></a>

### RN-080 — Regra de negócio duplicada é recusada na entrada {#rn-080}

`business_rule` cujo título já existe **no projeto** não é gravada. A recusa
volta ao modelo pelo mesmo caminho de um payload inválido, e ele segue para a
próxima regra em vez de parar.

**Na entrada porque não há outro lugar.** Não existe tabela de regras: o
artefato É o evento `artifact.business_rule`, e evento de domínio não é apagado
nem editado. Deixar entrar significa conviver com a duplicata para sempre.

**Escopo de projeto, não de sessão** — é entre sessões que a duplicata nasce.
Rodar o Criativo de novo abre sessão nova, e uma checagem por sessão não veria a
rodada anterior, que é exatamente o caso do achado.

A comparação normaliza caixa, acento e espaço redundante; pontuação fica.
**Duplicata semântica continua passando, e isso é declarado, não esquecido:**
"Saudação com nome" e "Quem chama pode se identificar" seguem sendo duas regras,
porque separá-las é julgamento e não cabe num `if`.
Desde a [RN-681](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-681) a duplicata semântica de TÍTULO é **avisada** por
embedding depois de gravar — continua passando, nunca é recusada aqui.

- **Onde:** `apps/engine/lib/engine/harness/artifact_dedupe.ex`,
  `apps/engine/lib/engine/harness/tools/emit_artifact.ex`,
  `apps/engine/lib/engine/session_events/event.ex` (`titulos_de_regras/1`)
- **Teste:** `apps/engine/test/engine/harness/artifact_dedupe_test.exs`,
  `apps/engine/test/engine/harness/emit_artifact_dedupe_test.exs`
- **Origem:** achado K, Fase E do [backlog](https://github.com/viralabs-dev/brabo/blob/dev/docs/explanation/backlog.md)

<a id="rn-085"></a>

### RN-085 — O teto de iterações é por TIPO de agente {#rn-085}

Quantas voltas um agente pode dar no laço de ferramenta depende do trabalho que
ele faz: **8** para quem conversa, **60** para o dev agent e para os subagentes
de QA. Não há mais um número único.

**O teto de 8 nasceu de agente conversacional e foi herdado por quem trabalha.**
Na validação real da 13b isso apareceu como bloqueio: o dev agent gastou as
oito voltas explorando um repositório recém-provisionado e **nunca escreveu um
arquivo**; com 25, escreveu três e rodou os testes. O desfecho registrado era
`limite de iterações atingido` com origem `modelo` — tecnicamente verdade e
praticamente inútil, porque o modelo nunca chegou a julgar nada.

**Subir o default global seria a correção errada**, e é isso que a regra
protege: o Criativo não precisa de 60 voltas para conversar, e o teto também é
a trava contra laço infinito.

**Quem pode subir não é "quem trabalha muito", é quem tem trava de gasto por
baixo.** O teto de iterações protege contra laço infinito; quem protege o
BOLSO é o `token_budget_micros`. Dev agents e subagentes de QA rodam com o
`task_budget_micros` da task, então afrouxar as voltas não afrouxa a conta.
`infra-workflows` usa ferramenta pesada e mesmo assim **fica em 8**: ele roda
sem budget, e para ele o teto é a única trava que existe.

Duas bordas com teste próprio:

- **`dev-lead` é conversacional**, apesar do prefixo `dev-` que identifica os
  dev agents (`dev-<modulo>`, `dev-<modulo>-2`). O lead decide e delega, e sem
  a cláusula explícita nasceria com o teto do trabalho pesado por acidente de
  nomenclatura.
- **Agente desconhecido cai no teto mais baixo.** Errar para o lado barato:
  quem precisa de mais voltas aparece como `limite de iterações atingido` e é
  corrigido; quem ganha 60 por engano gasta calado.

- **Onde:** `apps/engine/lib/engine/harness/iteracoes.ex`, aplicado em
  `apps/engine/lib/engine/harness/tool_loop.ex` (`init/1`)
- **Teste:** `apps/engine/test/engine/harness/iteracoes_test.exs` e
  `apps/engine/test/engine/harness/tool_loop_test.exs`
  (`o teto vem do TIPO do agente quando o chamador não passa um`,
  `teto explícito do chamador VENCE o do tipo`)
- **Origem:** achado X, [validação real da 13b](https://github.com/viralabs-dev/brabo/blob/dev/docs/explanation/validacao-real.md);
  [ADR 0053](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0053-dev-lead-e-paralelismo-autorizado.md), FASE 14d

<a id="rn-115"></a>

### RN-115 — A Anamnese pode ser pausada globalmente; a pausa é do PRODUTO, nunca apaga dado {#rn-115}

`ANAMNESE_ENABLED` (env var do engine, boolean, default `false` a partir
desta regra) decide se uma rodada NOVA da Anamnese pode acontecer — periódica
(`AnamneseSchedulerWorker`) ou sob demanda (`AnamneseCommandController`).
Decisão de PRODUTO do usuário em 2026-08-10 ("hoje ele não está trazendo
dados de muito valor"), não bug — ver docs/explanation/backlog.md. Desativada,
NENHUM dado existente é tocado: hipóteses, perfis de proficiência e patches
de instrução já gravados continuam intactos e visíveis, e o opt-out POR
MEMBRO (RN-025) continua um conceito separado — a pausa é do SISTEMA, não do
perfilamento individual.

`AnamneseSchedulerWorker.kickoff/0` (chamado uma vez no boot) NÃO agenda o
job periódico quando desativado, em vez de agendar e deixar `perform/1`
no-opar a cada tick — mais barato (a fila do Oban não recebe um job a cada
`ANAMNESE_INTERVAL_SECONDS` só para não fazer nada) e mais claro para quem
inspeciona a fila. **Correção em 2026-08-10** (achado real em execução, não
hipótese): a versão original desta regra deixava `perform/1` incondicional
de propósito, para a corrente entre rodadas não carregar a decisão de
ligar/desligar consigo — mas isso significava que uma corrente já agendada
ANTES de a flag existir (ou de alguém desativá-la) continuava se
reagendando pra sempre, rodando Anamnese de verdade com a flag dizendo
`false`. Foi exatamente o que aconteceu num Postgres de dev mais antigo que
o PR original, remediado manualmente cancelando os jobs agendados.
`perform/1` agora confere `enabled?/0` a cada tick, igual `kickoff/0`: se
desativado, nem `enqueue_projects/0` nem o reagendamento acontecem, e a
corrente morre ali — o que também AUTO-CURA sozinho o cenário de job antigo
que ainda dispara uma vez, sem precisar de intervenção manual.

`AnamneseCommandController.run/2` (rota sob demanda, "reanalisar agora" nas
Configurações) responde **503** com corpo `{"error": "anamnese_desativada"}`
quando desativado — distinto de propósito do 409 vazio que já existia para
"projeto sem sessão" (os dois eram fáceis de confundir num 409 puro, e são
causas bem diferentes). `RunAnamneseUseCase`, do lado api, converte o 503 do
engine em `ServiceUnavailableException` com `reason: "anamnese_disabled"` no
corpo — nunca um 500 genérico nem um 409 reaproveitado. A web
(`ProjectSettingsTab.tsx`) descobre o estado no primeiro clique de "Rodar
agora" (não há hoje uma leitura prévia do estado global) e, a partir daí,
desabilita o botão e mantém a explicação VISÍVEL na tela — não só um toast
que some (RN-088: nunca falha silenciosa ou confusa).

- **Onde:** `apps/engine/lib/engine/workers/anamnese_scheduler_worker.ex`
  (`enabled?/0`, `kickoff/0`),
  `apps/engine/lib/engine_web/controllers/anamnese_command_controller.ex`,
  `apps/engine/config/runtime.exs`,
  `apps/api/src/domain/anamnese/anamnese-disabled.error.ts`,
  `apps/api/src/infrastructure/http-clients/api-to-engine-client.ts`
  (`runAnamnese`), `apps/api/src/application/use-cases/anamnese/run-anamnese.use-case.ts`,
  `apps/web/src/routes/settings/ProficiencySection.tsx`
- **Teste:**
  `apps/engine/test/engine/workers/anamnese_scheduler_worker_test.exs`
  (`kickoff/0` não agenda desativado, agenda ativado, default desligado;
  `perform/1` desativado no meio da corrente não faz fan-out nem reagenda),
  `apps/engine/test/engine_web/controllers/anamnese_command_controller_test.exs`
  (503 distinto de 409, com e sem sessão),
  `apps/api/test/application/use-cases/anamnese/run-anamnese.use-case.spec.ts`,
  `apps/web/src/routes/ProjectSettingsTab.test.tsx` (`ProficiencySection`)
- **Borda:** a flag é GLOBAL (todos os projetos/workspaces), não por projeto
  — ao contrário do teto de paralelismo (RN-083) ou do modelo herdável por
  área (RN-102), que são decisões por escopo. Ligar de volta é
  `ANAMNESE_ENABLED=true` e reiniciar o engine; não há botão na UI para isso
  (é operacional, não uma preferência de projeto).
- **Origem:** sem ADR — decisão de produto reversível, não mudança estrutural
  de arquitetura. Ver docs/explanation/backlog.md.

<a id="rn-116"></a>

### RN-116 — Falha ao CRIAR um handoff não derruba o agente {#rn-116}

`confirm_readiness` (Criativo → PO) e `offer_infra_handoff` (Arquiteto → Infra;
o `offer_dev_handoff`, Arquiteto → Dev Lead, saiu na
[RN-672](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-672), e o handoff ao Dev Lead que a Infra
oferece segue a mesma régua) chamam a api pra criar o handoff DEPOIS de o
turno já ter rodado — no caso do Criativo, depois de o `product_brief` já
estar gravado no event log. Se essa chamada falhar (api fora, 5xx, etc.), o
handoff não existe, mas isso NUNCA derruba o GenServer do agente: a falha vira
`agent.error` durável, com `origem` (`FalhaDeTurno.origem/1`) e uma mensagem
que diz o que JÁ foi salvo (o product_brief, as regras) e o que não foi (o
handoff) — para o usuário saber que confirmar de novo é seguro, não repete
trabalho.

Era o oposto: as três chamadas usavam `{:ok, _handoff} = EngineApiClient.create_handoff(...)`
— um match rígido. `{:error, _}` virava `MatchError`, e como os três agentes
sobem com `restart: :temporary` num `DynamicSupervisor` `:one_for_one`, o
processo simplesmente SUMIA — sem `agent.error`, sem resposta no fio, só
silêncio. Do lado de quem observava: a informação (regras, product brief)
parecia ter "passado" (estava gravada), mas nada iniciava do lado do agente
seguinte, porque o handoff nunca chegou a existir. Reabrir a conversa não
resolvia sozinho — só uma NOVA mensagem reativa o processo (rehidratando do
event log), e só uma nova confirmação de prontidão tenta o handoff de novo.

A mensagem NÃO reusa `FalhaDeTurno.mensagem/1` (a de `RN-059`, "não consegui
completar este turno... nada foi gasto"): nos três call sites o trabalho já
rodou (ou nem precisava rodar, no caso de `offer_dev_handoff`) — dizer "nada
foi gasto" seria falso quando tokens já tinham sido gastos no turno de
consolidação. Reusa só `FalhaDeTurno.origem/1`, que classifica pelo FORMATO
do motivo (status HTTP, exceção de transporte), não por ser turno de LLM.

O `Engine.Harness.Tools.OfferHandoff` (a ferramenta que o PO usa via tool
call, dentro do ToolLoop) já tratava `{:error, reason}` sem crashar — o
defeito era só nestes três handlers server-driven, que chamam
`EngineApiClient.create_handoff/5` DIRETO em vez de passar pela ferramenta.

- **Onde:** `apps/engine/lib/engine/agents/criativo_server.ex`
  (`handle_call(:confirm_readiness, ...)`, `emit_falha_handoff/3`),
  `apps/engine/lib/engine/agents/arquiteto_server.ex`
  (`handle_call(:offer_infra_handoff, ...)`, `emit_falha_handoff/3`);
  `apps/engine/lib/engine/infra/infra_lead_server.ex`
  (`emit_falha_do_handoff_ao_dev_lead/2`, RN-672)
- **Teste:** `apps/engine/test/engine/agents/criativo_server_test.exs`
  ("prontidão: falha ao criar o handoff NÃO derruba o processo, e vira
  agent.error durável"); `apps/engine/test/engine/agents/arquiteto_server_test.exs`
  (`offer_infra_handoff`, sucesso e falha);
  `apps/engine/test/engine/infra/infra_lead_server_test.exs` (o handoff ao Dev
  Lead que a Infra oferece, recusado com 500)
- **Origem:** relato de uso real no projeto `exp-001` (Criativo → PO); a
  mesma falha estrutural foi achada por leitura de código nos dois handoffs
  do Arquiteto, sem reprodução separada para eles

<a id="rn-117"></a>

### RN-117 — O Psicólogo pode ser pausado globalmente; a pausa é do PRODUTO, nunca apaga dado {#rn-117}

`PSYCHOLOGIST_ENABLED` (env var do engine, boolean, default `false`) decide
se uma rodada NOVA do Psicólogo pode acontecer — automática (fechamento de
sessão, roteado pelo `Engine.Outbox.Drain`) ou sob demanda
(`PsychologistCommandController.reanalyze/2`). Mesma decisão de PRODUTO do
usuário em 2026-08-10 já aplicada à Anamnese (RN-115, "hoje ele não está
trazendo dados de muito valor") — não bug, ver docs/explanation/backlog.md.
Desativado, NENHUM dado existente é tocado: análises e hipóteses já
emitidas continuam intactas e visíveis.

Diferente da Anamnese (cujo gatilho automático é um TICK periódico que a
própria flag decide se reagenda), o gatilho automático do Psicólogo é o
fechamento de sessão — o `Engine.Outbox.Drain` roteia
`session.closed`/`session.closed_abnormally` pra `PsychologistWorker` só
quando `PsychologistWorker.enabled?/0` é true (`Drain.handlers_for/1`);
desativado, só `SessionLifecycleWorker` roda, e o job do Psicólogo nem
nasce. `PsychologistWorker.perform/1` continua incondicional de propósito —
mas NÃO é mais "o mesmo padrão" do `AnamneseSchedulerWorker` (ver a correção
de 2026-08-10 na RN-115 acima): lá `perform/1` passou a conferir a flag
porque ele PRÓPRIO reagenda a corrente a cada tick, e um job antigo
disparando incondicionalmente reabria a Anamnese com a flag desligada. O
Psicólogo não tem corrente nenhuma que se reagende sozinha — cada job nasce
de UM evento (`session.closed`), e quem decide é o `Drain` no momento em que
RECEBE o evento, não o worker no momento em que RODA; um job de Psicólogo
já enfileirado antes de desligar a flag é, no máximo, a última rodada
pendente, nunca uma corrente infinita. Por isso a suite pré-existente de
`PsychologistWorker` (que chama `perform/1` direto) não precisou mudar.

`PsychologistCommandController.reanalyze/2` (rota sob demanda,
"Reanalisar" na aba Insights) responde **503** com corpo
`{"error": "psicologo_desativado"}` quando desativado, sem sequer criar o
job. `ReanalyzeSessionUseCase`, do lado api, converte o 503 do engine em
`ServiceUnavailableException` com `reason: "psychologist_disabled"` no
corpo — nunca um 500 genérico. Isto descobre a pausa quando já existe uma
análise para reprocessar; a tela SEM hipótese nenhuma tem uma leitura
prévia própria, que não existia aqui — ver [RN-454](parte-02.md#rn-454).

- **Onde:** `apps/engine/lib/engine/workers/psychologist_worker.ex`
  (`enabled?/0`), `apps/engine/lib/engine/outbox/drain.ex`
  (`handlers_for/1`),
  `apps/engine/lib/engine_web/controllers/psychologist_command_controller.ex`,
  `apps/engine/config/runtime.exs`,
  `apps/api/src/domain/psychologist/psychologist-disabled.error.ts`,
  `apps/api/src/infrastructure/http-clients/api-to-engine-client.ts`
  (`reanalyzeSession`),
  `apps/api/src/application/use-cases/execution/reanalyze-session.use-case.ts`,
  `apps/web/src/routes/ProjectInsightsTab.tsx`
- **Teste:**
  `apps/engine/test/engine/outbox/drain_test.exs` (`session.closed` só
  enfileira o Psicólogo quando ativado),
  `apps/engine/test/engine_web/controllers/psychologist_command_controller_test.exs`
  (503 sem criar job, 202 com job enfileirado quando ativado),
  `apps/api/test/application/use-cases/execution/reanalyze-session.use-case.spec.ts`,
  `apps/web/src/routes/ProjectInsightsTab.test.tsx`
- **Borda:** a flag é GLOBAL (todos os projetos/workspaces), como a da
  Anamnese. Ligar de volta é `PSYCHOLOGIST_ENABLED=true` e reiniciar o
  engine; não há botão na UI para isso.
- **Origem:** sem ADR — decisão de produto reversível, não mudança estrutural
  de arquitetura. Ver docs/explanation/backlog.md.

## Session

<a id="rn-122"></a>

### RN-122 — O botão "Parar" cancela o turno DE VERDADE, matando a task que segura a chamada de LLM {#rn-122}

Até aqui não havia cancelamento em lugar nenhum. A raiz era estrutural:
`agent_command_controller.ex` tratava a mensagem do usuário com
`GenServer.call(pid, {:user_message, texto}, ...)` — SÍNCRONO — e o
turno inteiro (tool loop + chamada SSE ao LLM) rodava DENTRO do `handle_call`. O
processo do agente ficava bloqueado até o turno acabar e não tratava NENHUMA outra
mensagem nesse meio-tempo — nem um futuro comando de cancelar.

A correção: o `handle_call`/`handle_cast` de turno dos quatro agentes
conversacionais (Criativo, PO, Arquiteto, Dev Lead) dispara um
`Task.Supervisor.async_nolink/2` (`Engine.Agents.TurnoAssincrono`, novo,
compartilhado pelos quatro) com o trabalho pesado e devolve `{:noreply, state}` —
a resposta ao `GenServer.call` original fica ADIADA até a task
terminar (`GenServer.reply/2`, disparado quando `{ref, resultado}` chega ao
`handle_info`). Como o processo do agente DEIXA de ficar bloqueado, um novo
`handle_cast(:cancel, state)` chega e é tratado enquanto o turno roda:
`Task.shutdown/2` no modo `:brutal_kill` mata a task, o que derruba a
conexão HTTP (SSE) que ela mantém com a api — é isso que faz o cancelamento
economizar tokens de fato, e não só parar de renderizar no cliente. O
`from` original recebe `{:error, :cancelado}`, e um `agent.error` TERMINAL é
registrado com origem `"politica"` (a mesma origem de
orçamento/credencial/vínculo — cancelar é decisão do usuário de parar de gastar
tokens, não um quinto valor no vocabulário fechado do ADR 0020) — sem ele,
o `GetSessionPendingWorkUseCase` veria `agent.activated` sem
`agent.response`/`agent.error` depois, e a sessão ficaria pendurada
no sinal de trabalho pendente.

Duas mensagens concorrentes para o mesmo agente (o usuário manda de novo enquanto um turno
já roda) nunca disparam uma segunda task:
`TurnoAssincrono.iniciar/3` responde `{:error, :turno_em_andamento}`
na hora.

> **Revisada pela [RN-578](parte-03.md#rn-578) (ADR 0163):** a resposta ao
> `GenServer.call` original não fica mais adiada até a task terminar — ela sai
> no ACEITE, assim que a task sobe, e cancelar não responde a ninguém (quem
> chamou já tem `:ok`). `{:error, :turno_em_andamento}` deixou de ser
> descartado pelo controller: é um 409 nomeado e um `agent.error` durável.

- **Onde:** `apps/engine/lib/engine/agents/turno_assincrono.ex` (o
  mecanismo), `apps/engine/lib/engine/agents/{criativo,po,arquiteto,dev_lead}_server.ex`
  (os quatro `handle_call`/`handle_cast` de turno), `apps/engine/lib/engine_web/controllers/agent_command_controller.ex:373`
  (`cancel/2`), `apps/engine/lib/engine_web/router.ex` (`POST
  /internal/sessions/:sessionId/agent/cancel`),
  `apps/api/src/application/use-cases/agents/cancel-agent-turn.use-case.ts`,
  `apps/api/src/interfaces/http/agents/agents.controller.ts` (`POST
  /projects/:projectId/sessions/:sessionId/agents/:agent/cancel`),
  `apps/web/src/routes/SessionPage.tsx` (`handleCancel`, botão "Parar" no
  composer)
- **Teste:** `apps/engine/test/engine/agents/turno_assincrono_test.exs` (a
  task morre DE VERDADE — `Process.alive?/1` antes e depois — e não só
  "deixou de importar o resultado"), `apps/api/test/application/use-cases/agents/cancel-agent-turn.use-case.spec.ts`
- **Caso de borda:** cancelar sem turno em andamento é NO-OP
  idempotente — não há task para matar nem `from` pendente para responder.
  O cancelamento NÃO desfaz efeito colateral que já rodou ANTES de a task
  morrer (por exemplo, uma ferramenta que já tinha sido despachada e registrado o seu
  evento) — só interrompe o que ainda não aconteceu.
- **Origem:** investigação desta sessão; sem ADR próprio (mudança de padrão de
  concorrência DENTRO do harness, não de fronteira de camada/banco).

<a id="rn-129"></a>

### RN-129 — O ToolLoop nunca grava `agent.response` vazio; falha de transporte vira `agent.error` durável {#rn-129}

A [RN-059](#rn-059) fechou o balão vazio para os quatro agentes
conversacionais, mas eles não passam pelo `Engine.Harness.ToolLoop` — cada um
chama `EngineApiClient.llm_turn_stream/6` no próprio módulo. O `ToolLoop`
(usado por dev agents, QA Automação/Performance-Segurança, Infra-Workflows,
Anamnese e Psicólogo) tinha o MESMO defeito num caminho diferente: emitia
`agent.response` a cada iteração, mesmo quando o modelo só chamou ferramenta
sem texto, ou terminou o turno sem produzir nada — e a falha de transporte
(provider fora do ar, timeout) virava `agent.response` com `content` ausente,
igualmente indistinguível de sucesso.

Achado ao vivo numa sessão de execução real (dev agents): duas bolhas com o
texto de compatibilidade da RN-059 ("resposta vazia — evento anterior...")
apareceram numa sessão criada minutos antes — não eram eventos antigos, eram
o mesmo defeito acontecendo de novo, só que na aba de execução.

Duas correções, no ponto ESTRUTURAL comum a todo consumidor do `ToolLoop`,
não módulo por módulo:

1. **Conteúdo vazio nunca vira `agent.response`.** Iteração que só chamou
   ferramenta já está narrada por `tool.call`/`tool.result`; iteração que não
   produziu nada (nem texto, nem tool call) deixa o desfecho para quem chamou
   o loop decidir — `ctx.last_error`/`{:ok, ctx}` carregam a informação, e
   quem consome (ex.: `DevAgentServer.handle_outcome/4`) já grava o evento
   durável do PRÓPRIO domínio (`dev.blocked`, com `origem`).
2. **Falha de transporte vira `agent.error` durável**, com `origem`
   (`Engine.Agents.FalhaDeTurno.origem/1` — o MESMO helper que os quatro
   agentes conversacionais usam, sem duplicar classificação) e `mensagem` em
   português — nunca mais `agent.response` sem `content`.

- **Onde:** `apps/engine/lib/engine/harness/tool_loop.ex` (`loop/1`,
  `emit_falha/2`)
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs`
  ("iteração só com tool call (sem texto) não grava agent.response vazio",
  "modelo termina o turno sem texto e sem tool call...", "falha de
  transporte... grava agent.error durável com origem")
- **Origem:** RN-059 (regra que esta estende) — achado ao vivo numa sessão de
  execução real com dev agents

## PR Gates

<a id="rn-140"></a>

### RN-140 — Um ciclo de gate que morre no meio retoma sozinho, sem intervenção manual {#rn-140}

`QaLeadServer`/`SecOpsAgentServer` são `restart: :temporary`, e as
transições intermediárias do gate (`DevAgentServer.correct/3`,
`Dispatcher.run_secops/2`) são chamadas diretas em memória — feitas DEPOIS
de o `record_gate_verdict` já ter avançado de forma durável o `gate_status` na
api. Uma queda entre as duas prendia a PR para sempre em
`awaiting_qa`/`awaiting_secops`: nada sabia que aquele passo tinha ficado
pendente, e nenhum restart do engine resolvia — o próprio [ADR 0057](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0057-o-gate-espera-a-aprovacao.md)
já declarava a suspensão em `{:awaiting, ...}` como limite
conhecido, e investigar de novo mostrou que a janela entre um veredito
registrado e uma chamada de despacho é, na prática, mais fácil de acertar.

`gate_states` (schema `engine`, chave `{project_id, task_id, gate}`)
registra o ciclo em voo nos MESMOS pontos em que as transições
já aconteciam — `"in_progress"` antes de qualquer subagente/scanner rodar,
`"dispatch_pending"` logo depois de o `record_gate_verdict` devolver
`correct`/`run_secops` e antes da chamada em processo.
`Engine.Gates.GateRescuer` varre linhas paradas há mais de 15 minutos
(configurável, `GATE_RESCUE_STALE_AFTER_SECONDS`) — generoso de propósito,
porque o ToolLoop de um subagente de QA roda legitimamente até
`TOOL_LOOP_MAX_ITERATIONS_GATE` (60) iterações, e um limiar curto
resgataria (e duplicaria) um ciclo só lento — e retoma:
`"in_progress"` reinicia a área inteira (sem retomada cirúrgica do
`ctx`, que não sobrevive a um restart, a mesma escolha do dev
agent); `"dispatch_pending"` reenvia exatamente a chamada perdida. Chamado no
boot e por um tick do Oban que se reagenda a cada 5 minutos
(`GATE_RESCUE_INTERVAL_SECONDS`),
`Engine.Workers.GateRescueSchedulerWorker` — o mesmo idioma de
`ModelSyncSchedulerWorker`/`AnamneseSchedulerWorker`.

Duas guardas contra trabalho duplicado: processo vivo NO MESMO nó
(`Registry.lookup`) nunca é perturbado, e o limiar de staleness
cobre o que a guarda local não alcança (réplica remota — o `Registry`
é local ao nó, a mesma ressalva do `Engine.Dev.Wake` desde o
[ADR 0045](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0045-reagendamento-por-evento-do-dev-agent.md)). O
pior desfecho de uma corrida residual é trabalho duplicado e barato — a api
rejeita um segundo `record_gate_verdict` para um gate que não é mais dono do
`gate_status` (`nextGateStatus`), e `DevAgentServer.correct/3` já é
idempotente por guarda de estado desde o ADR 0052 — nunca
dado inconsistente.

- **Onde:** `apps/engine/lib/engine/gates/gate_state.ex`,
  `gate_rescuer.ex`, os pontos de escrita em `qa_lead_server.ex`
  (`run_area/3`, `apply_gate_result/6`) e `secops_agent_server.ex`
  (`run_secops/3`, `apply_verdict/6`), e
  `apps/engine/lib/engine/workers/gate_rescue_scheduler_worker.ex`
- **Teste:** `apps/engine/test/engine/gates/gate_rescuer_test.exs` — mata um
  `QaLeadServer` real com o ciclo em voo
  (`DynamicSupervisor.terminate_child/2`, a linha durável sobrevivendo ao
  processo) e prova que `GateRescuer.run/0` reconecta a área sozinho
  até um desfecho real; o cenário do enunciado (`run_secops`
  perdido) e o retorno `correct` perdido, ambos com processo e
  despacho REAIS, sem `FakeGateDispatcher`; e as duas guardas (processo
  local vivo não é perturbado; linha recente não é tocada)
- **Origem:** [ADR 0067](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0067-o-gate-sobrevive-ao-restart.md), que
  estende o [ADR 0057](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0057-o-gate-espera-a-aprovacao.md)

---

<a id="rn-141"></a>

### RN-141 — O conteúdo lido por `read_file` também tem teto de bytes {#rn-141}

A [RN-074](#rn-074) travou a saída do **terminal** contra
`{413, "request entity too large"}`, mas deixou aberta a mesma porta pelo
`read_file`: ele lia o arquivo INTEIRO, sem teto, e esse conteúdo entrava no
histórico do laço e viajava em todo turno seguinte. Um PR com arquivo grande
(lockfile, bundle, arquivo gerado) bastava pra travar dev agents E o QA de
Performance/Segurança — que só tem `ReadFile`/`SearchWorkspace` (sem
`Terminal`, de propósito) pra investigar uma PR, então não tinha rota de
escape nenhuma quando o arquivo era grande demais.

O conteúdo é cortado em `READ_FILE_MAX_BYTES` (default 32 KiB, mesmo valor da
RN-074 por coincidência de contexto, não por acoplamento — as duas variáveis
são independentes) antes de virar resultado da ferramenta, com marca dizendo
o arquivo e os dois tamanhos:

```
[arquivo package-lock.json truncado: mostrando 32768 de 1048576 bytes. Use
search_workspace para localizar um trecho específico em vez de reler o
arquivo inteiro.]
```

Mesmas três propriedades da RN-074 (teto é `>` não `>=`; corte não parte
caractere multibyte; a marca é endereçada ao modelo, dizendo o que fazer). A
truncagem mora na FERRAMENTA (`Engine.Harness.Tools.ReadFile`), não em
`Engine.Harness.WorkspaceFiles.read_file/2` — essa é a base genérica de
acesso a arquivo, compartilhada por `write_file`/`search_workspace`, e
truncar ali cortaria conteúdo de quem não precisa desse teto.

`search_workspace` não teve o mesmo tratamento: ele devolve só os PATHS que
bateram (`matched_content` é booleano), nunca o conteúdo do arquivo — o vetor
de estouro que motivou esta RN não se aplica a ele.

- **Onde:** `apps/engine/lib/engine/harness/tools/read_file.ex`
  (`truncate/2`), teto em `apps/engine/config/runtime.exs`
  (`read_file_max_bytes`)
- **Teste:** `apps/engine/test/engine/harness/tools/read_file_test.exs`
  (describe `teto de bytes do conteúdo`)
- **Origem:** achado ao vivo no event log de uma execução real — os 4 dev
  agents de um projeto e os QA de Automação/Performance-Segurança bloqueados
  com `{413, "request entity too large"}`, mesma causa raiz da RN-074, porta
  diferente

## Session

<a id="rn-142"></a>

### RN-142 — Confirmar prontidão SEM nenhuma regra de negócio é recusado pelo engine, não só escondido na UI {#rn-142}

Antes, clicar em "Estou pronto para produzir" — ou chamar a rota direto —
SEMPRE criava o `product_brief` e oferecia o handoff ao PO, mesmo
numa conversa em que zero regras de negócio tinham sido capturadas.
`business_rule_refs(state)` já existia em `criativo_server.ex`, mas
só para PREENCHER o campo `"rules"` do brief — nunca como condição
de bloqueio. Na UI, `SessionPage.tsx` desabilitava o botão só durante o
`streaming`, sem olhar a contagem de regras.

A garantia real tinha de morar no servidor, não na tela: quem
chama a rota direto (ou um cliente futuro que não seja este frontend)
não pode furar o guardrail só porque o botão está desenhado
desabilitado. `CriativoServer.handle_call(:confirm_readiness, ...)` agora confere
`business_rule_refs(state)` ANTES de disparar a `Task` do
`Engine.Agents.TurnoAssincrono` ([RN-122](#rn-122)) — vazio, ele
recusa ali mesmo, sem rodar o turno de consolidação, sem
`product_brief`, sem handoff.

A recusa não vira HTTP 4xx:
`agent_command_controller.ex#readiness/2` IGNORA o retorno deste `GenServer.call`
e sempre responde 202, o mesmo padrão que o `message/2` já usa
desde a RN-122 ("esta resposta é só o recebimento" — o desfecho
real mora no log de eventos). Por isso a recusa é narrada como um
`agent.error` DURÁVEL (RN-059), com origem `"politica"` (é uma
decisão de produto, não falha de infra/modelo/turno) — e uma mensagem
explicando por quê; o fio da sessão já sabe renderizar esse tipo de
evento (`lerFalhaDeTurno`, o mesmo balão vermelho de qualquer outra falha de turno).

A UX complementar, em `SessionPage.tsx`: o botão nasce `disabled`
(com um `title` explicando por quê) enquanto `events` não tem
`artifact.business_rule` — a MESMA fonte que já alimenta o
painel "Regras de negócio" (`ContextAside`), sem segunda leitura que pudesse
divergir da primeira.

- **Onde:** `apps/engine/lib/engine/agents/criativo_server.ex`
  (`handle_call(:confirm_readiness, ...)`, `emit_falha_sem_regra/1`),
  `apps/web/src/routes/SessionPage.tsx` (`hasBusinessRule`, o botão "Estou pronto
  para produzir")
- **Teste:**
  `apps/engine/test/engine/agents/criativo_server_test.exs` ("readiness:
  refuses when NO business rule was captured" — sem turno, sem brief, sem
  handoff; a recusa narrada com origem `"politica"`),
  `apps/web/src/routes/SessionPage.readiness-exige-regra.test.tsx` (botão
  desabilitado sem regra, habilitado com 1+)
- **Caso de borda:** a sessão já tinha `readiness.confirmed` registrado pela
  api ANTES de sinalizar o engine (`ConfirmReadinessUseCase`) — isso
  não muda: é o registro do CLIQUE do usuário, um fato que aconteceu
  independente de o engine aceitar ou recusar depois.
- **Origem:** investigação de código confirmando um relato de usuário — sem ADR (guardrail
  novo num fluxo que já existia, sem mudança de fronteira de camada/banco).

---

<a id="rn-150"></a>

### RN-150 — `search_workspace` tem teto de QUANTIDADE de hits e de BYTES, cada um com sua marca {#rn-150}

Achado numa revisão de PR: `search_workspace` (dev agents e os dois agentes
de QA/gate, `qa_tools.ex` e `qa_performance_seguranca_agent.ex` — este
último só tem `read_file`/`search_workspace`, sem `Terminal`, de propósito)
devolvia TODOS os resultados da busca, sem teto nenhum — mesma classe do
achado S (`Engine.Actions.TerminalExecutor.truncate/2`) e da correção de
`read_file` (`Engine.Harness.Tools.ReadFile.truncate/2`): o resultado fica
no histórico do laço e viaja em todo turno seguinte, e uma árvore grande
basta pra estourar `{413, "request entity too large"}` do provider.

Dois tetos independentes, porque a busca estoura de duas formas diferentes:

1. **Quantidade de hits** — uma árvore com milhares de arquivos batendo o
   termo produz milhares de linhas `- caminho` mesmo que nenhum arquivo
   individual seja grande. Truncar só por BYTES no fim ainda pagaria o custo
   de escanear e ler o conteúdo de cada um desses arquivos antes de montar a
   string. Por isso o teto de quantidade (`SEARCH_WORKSPACE_MAX_HITS`,
   default 500) vive em `WorkspaceFiles.search/3`, que já PARA de consumir a
   busca assim que encontra hit suficiente — o pipeline roda sobre um
   `Stream`, e `Enum.take(stream, max_hits + 1)` só lê da fonte o que
   precisa pra produzir os `max_hits + 1` primeiros resultados. O "+1" é o
   que permite dizer que HAVIA mais sem continuar escaneando o resto pra
   contar o total exato — contar o total pagaria de novo o I/O que o teto
   existe pra evitar, então a marca diz "mostrando os N primeiros" e nunca
   inventa um total.
2. **Bytes do texto final** — mesmo com hits limitados, caminhos muito
   longos podem produzir uma string grande. Teto de bytes
   (`SEARCH_WORKSPACE_MAX_BYTES`, default 32.768), mesmo padrão de
   `terminal_output_max_bytes`/`read_file_max_bytes` — variável PRÓPRIA,
   não reaproveita as outras duas: mesma classe de estouro, divergir uma não
   deve exigir tocar as outras.

A marca de truncagem é dirigida ao MODELO, não ao humano: diz o que foi
cortado (hits e/ou bytes) e instrui a refinar o termo da busca — mesmo
espírito das marcas de `TerminalExecutor`/`ReadFile`.

- **Onde:** `apps/engine/lib/engine/harness/workspace_files.ex`
  (`search/3`, `take_capped/2`),
  `apps/engine/lib/engine/harness/tools/search_workspace.ex`
  (`truncate/3`, `marca_de_truncagem/5`),
  `apps/engine/config/runtime.exs` (`search_workspace_max_hits`,
  `search_workspace_max_bytes`)
- **Teste:** `apps/engine/test/engine/harness/workspace_files_test.exs`
  (`search/3` com `max_hits` corta a QUANTIDADE e marca truncagem só
  quando há mais que o teto),
  `apps/engine/test/engine/harness/search_workspace_test.exs` (busca com
  poucos resultados não é alterada; busca com mais hits que o teto é
  truncada com aviso claro; texto final maior que o teto de bytes também é
  cortado)
- **Origem:** achado de revisão de PR — segunda causa real do 413 em
  revisões, depois da correção de `read_file`

---

<a id="rn-162"></a>

### RN-162 — Perguntas estruturadas do Criativo {#rn-162}

O Criativo pode, quando faz VÁRIAS perguntas na mesma resposta, emitir a
lista em formato ESTRUTURADO em vez de deixar o usuário responder item por
item em texto livre — ferramenta nova `ask_structured_questions`
(`apps/engine/lib/engine/harness/tools/ask_structured_questions.ex`,
`:direct`), registrada ao lado de `emit_artifact`. Schema:
`{ questions: [{ id, label, type?, options? }] }` — `id` único e não-vazio,
`label` não-vazio, `type` ∈ `text|textarea|select` (default `text`),
`options` obrigatório e não-vazio quando `type: select`. Grava
`chat.structured_question`.

O frontend (`StructuredQuestionCard`, `SessionPage.tsx`) renderiza um
formulário com um campo por pergunta — `Input`/`Textarea`/`Select` do
design system, conforme `type`. `POST .../agents/:agent/structured-
question/:questionSetId/answer` (`AnswerStructuredQuestionUseCase`) valida
que toda pergunta tem resposta não-vazia, grava
`chat.structured_question_answered` (referenciando `questionSetId` = id do
evento da pergunta) e REUSA `SendAgentMessageUseCase` — as respostas viram
uma mensagem concatenada ("1. {label}: {resposta}\n2. ..."), como se o
usuário tivesse digitado no fio; não há canal novo de "o agente lê a
resposta estruturada". Um conjunto de perguntas só pode ser respondido
UMA vez: reenvio é recusado com 409, e o formulário nem chega a
reaparecer — o card vira somente leitura assim que existe um
`chat.structured_question_answered` posterior com o mesmo `questionSetId`.

- **Onde:** `apps/engine/lib/engine/harness/tools/ask_structured_questions.ex`,
  `apps/engine/lib/engine/agents/criativo_server.ex`,
  `apps/api/src/application/use-cases/agents/answer-structured-question.use-case.ts`,
  `apps/api/src/interfaces/http/agents/agents.controller.ts`,
  `apps/web/src/routes/SessionPage.tsx` (`StructuredQuestionCard`)
- **Teste:** `apps/engine/test/engine/harness/tools/ask_structured_questions_test.exs`,
  `apps/engine/test/engine/agents/criativo_server_test.exs`,
  `apps/api/test/application/use-cases/agents/answer-structured-question.use-case.spec.ts`,
  `apps/web/src/routes/SessionPage.perguntas-estruturadas.test.tsx`
- **Origem:** pedido do usuário — sem precedente de input estruturado no chat

<a id="rn-163"></a>

### RN-163 — O Criativo cumpre a promessa de tentar de novo {#rn-163}

Cada turno do Criativo roda um **laço bounded de tool use**, com teto de **12**
idas ao modelo — o mesmo desenho que o PO e o Arquiteto já tinham. Antes o
modelo era chamado UMA vez por turno: o resultado da ferramenta era anexado ao
histórico em memória e ninguém mais o lia, então a frase *"vou corrigir e
tentar de novo"* — literal no código — só se cumpria se o usuário mandasse
outra mensagem. Para quem usava, o Criativo simplesmente parava de responder
depois de dizer que ia corrigir.

Quatro consequências, e cada uma é uma regra:

1. **Erro de ferramenta é entrada, não fim de linha.** O motivo volta ao modelo
   como mensagem `tool` e o laço chama o modelo de novo, que reemite corrigido
   DENTRO do mesmo turno.
2. **Nada se anuncia que o código não vá executar.** A frase de retentativa é
   decidida depois de despachar as ferramentas e sabendo quantas voltas
   sobraram: com volta disponível, o agente diz que vai corrigir; sem volta, ele
   não promete.
3. **A falha de ferramenta virou `agent.error` durável, com origem**
   ([RN-059](#rn-059)) — era `agent.response`, indistinguível no event log de
   uma resposta normal. `origem: infra` quando a api recusou o `append_event`;
   `origem: modelo` para o payload que o modelo escreveu (chave errada,
   `origin` que não é lista, regra duplicada, tipo system-emitted). O payload
   carrega `tool` e `retentativa`.
4. **Teto esgotado não termina em silêncio.** Vira `agent.error` com
   `reason: "limite_de_iteracoes"` e `origem: modelo`, a mesma leitura do
   `toolloop.limit_reached` do `ToolLoop`. O nome do evento NÃO é reusado: este
   agente não roda dentro do `ToolLoop`, e o evento mentiria sobre quem o
   produziu.

Duas fronteiras do laço, ambas deliberadas: `ask_structured_questions`
bem-sucedida **encerra** o turno (a bola está com o usuário, e as respostas
voltam num turno futuro — [RN-162](#rn-162)); e um turno que teve falha em
alguma volta fecha com um desfecho CONSOLIDADO no fio, para a última palavra
não ser o erro de uma volta que já foi corrigida depois.

- **Onde:** `apps/engine/lib/engine/agents/criativo_server.ex`
  (`run_turn_capturing/3`, `continuar/4`, `emit_falha_de_ferramenta/4`,
  `emit_falha_limite/2`)
- **Teste:** `apps/engine/test/engine/agents/criativo_server_test.exs`
  (laço que corrige de verdade, teto esgotado narrado, origem `infra` vs
  `modelo`, pergunta estruturada que encerra o turno)
- **Origem:** uso real no projeto `exp001` — "o Criativo não respondeu depois
  de dizer que iria corrigir e tentar de novo"

<a id="rn-164"></a>

### RN-164 — O PO LÊ o que já existe, escopado ao projeto {#rn-164}

O PO ganhou duas ferramentas de LEITURA — `listar_regras_de_negocio` e
`listar_backlog` (`:direct`, sem parâmetro nenhum) — servidas por duas rotas
internas escopadas ao **projeto**: `GET /internal/projects/:projectId/business-rules`
e `GET /internal/projects/:projectId/backlog`.

A primeira devolve todo `artifact.business_rule` das sessões do projeto com a
`description` inteira, quais histórias já citam cada regra e o
`uncoveredCount`; a segunda devolve a MESMA árvore épico → história → tarefa
da aba Backlog, pelo mesmo `ListBacklogUseCase` (três leituras por projeto,
nunca N+1). O texto que volta ao modelo põe as regras DESCOBERTAS primeiro e
os épicos ÓRFÃOS antes da árvore — é o que gera trabalho.

O que a regra corrige: até aqui o PO tinha **quatro ferramentas e todas de
escrita**. O contexto dele era montado uma vez, no kickoff, a partir dos 200
últimos eventos da **sessão** — dali em diante ele não sabia quais regras
existiam, quais já tinha coberto, nem o que já havia criado. O escopo é o
projeto e não a sessão de propósito: regra capturada numa sessão anterior é
exatamente o que a leitura por sessão escondia.

Ler **não** vira `proposed_action` (não é efeito externo), mas é CONTIDA no
sentido do ADR 0060: nenhuma das duas rotas aceita parâmetro além do id do
projeto — sem busca, sem paginação, sem filtro —, o custo por chamada é
constante, e o texto entregue ao modelo tem teto de linhas dizendo o total
real quando trunca.

- **Onde:** `apps/engine/lib/engine/harness/tools/listar_regras_de_negocio.ex`,
  `apps/engine/lib/engine/harness/tools/listar_backlog.ex`,
  `apps/engine/lib/engine/agents/po_server.ex`,
  `apps/engine/lib/engine/sessions/engine_api_client.ex`,
  `apps/api/src/application/use-cases/backlog/list-business-rules.use-case.ts`,
  `apps/api/src/interfaces/http/internal/internal-projects.controller.ts`
- **Teste:** `apps/engine/test/engine/harness/tools/listar_regras_de_negocio_test.exs`,
  `apps/engine/test/engine/harness/tools/listar_backlog_test.exs`,
  `apps/engine/test/engine/agents/po_server_test.exs`,
  `apps/api/test/application/use-cases/backlog/list-business-rules.use-case.spec.ts`
- **Origem:** uso real no projeto `exp001` — "crie ferramenta para o PO
  conseguir listar as regras de negócio"

---

<a id="rn-165"></a>

### RN-165 — Épico sem história é cobrado, e o PO pergunta quando não sabe {#rn-165}

Quando o PO encerra um turno tendo criado um épico e **nenhuma história para
ele**, isso vira desfecho EXPLÍCITO: evento durável
`backlog.epic_without_story` (com `origem: "modelo"`, os ids e títulos dos
épicos e a mensagem) mais o broadcast `agent.error` — o padrão da
[RN-059](#rn-059): o log é o que sobrevive, o broadcast é o agente dizendo no
fio. A cobrança é por OCORRÊNCIA: reportada uma vez, a lista de pendências é
esvaziada, e não vira alarme que repete a cada turno.

O que conta é a criação que **deu certo**: um `create_story` recusado pela api
(`business_rule_id` inexistente, por exemplo) não quita o épico. Tratá-lo como
se quitasse seria trocar um silêncio por outro. Os épicos pendentes vivem no
state do `PoServer` e NÃO são reidratados: a cobrança é sobre a obrigação
assumida no turno, e reconstruí-la do event log reabriria épico antigo que o
usuário já resolveu de outro jeito.

Junto vieram as duas peças que faltavam para o PO ter uma saída além de parar:
`ask_structured_questions` — a MESMA ferramenta do Criativo
([RN-162](#rn-162)), só passada a advertisar no `po_server` — e a instrução de
kickoff dizendo, com todas as letras, que épico sem história trava a execução
e que **faltando informação se PERGUNTA**, nunca se para nem se inventa. A
instrução anterior não dizia uma palavra sobre o que fazer diante de uma
lacuna, e diante de uma lacuna sem instrução um modelo escolhe entre inventar
e parar.

- **Onde:** `apps/engine/lib/engine/agents/po_server.ex`
  (`anotar_obrigacao/4`, `encerrar_turno/1`, `obrigacoes/0`),
  `apps/engine/lib/engine/harness/tools/create_epic.ex` (`id_no_resultado/1`),
  `apps/web/src/lib/activity.ts`
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs`
  (describe "RN-165"), `apps/web/src/lib/activity.test.ts`
- **Origem:** uso real no projeto `exp001` — backlog sem história, logo sem
  tarefa, logo execução travada sem erro visível

---

<a id="rn-166"></a>

### RN-166 — O teto de iterações do PO deixa rastro {#rn-166}

Esgotado o teto de iterações do laço de ferramentas do `PoServer` (12), o
turno emite `toolloop.limit_reached` com `{iteration, max_iterations}` —
o MESMO tipo e o mesmo payload que o `Engine.Harness.ToolLoop` já emitia
desde a Fase 3. Antes, a cláusula devolvia o state e pronto: de fora, um laço
esgotado era indistinguível de um turno que simplesmente acabou.

Reusar o identificador em vez de criar um `po.*` é deliberado: é o mesmo fato
(o laço bateu no teto), e quem lê o event log não deve precisar aprender um
segundo nome por causa de o agente conversacional ter laço próprio em vez de
usar o `ToolLoop`.

- **Onde:** `apps/engine/lib/engine/agents/po_server.ex` (`run_turn/2`,
  cláusula `remaining <= 0`)
- **Teste:** `apps/engine/test/engine/agents/po_server_test.exs`
  ("teto de iterações emite toolloop.limit_reached")
- **Origem:** investigação do travamento do `exp001` — o laço terminava em
  silêncio

---

<a id="rn-171"></a>

### RN-171 — A pergunta de lista tem saída por texto livre, por default {#rn-171}

Pergunta `type: "select"` de `ask_structured_questions` (RN-162) aceita
resposta **fora da lista**. O campo é `allowOther`, e o **default é `true`**:
quem não declara nada oferece a saída. Fechar a lista exige
`allowOther: false` explícito, e só faz sentido quando ela é genuinamente
fechada ("Sim"/"Não").

O default aberto não é preferência de estilo. Uma lista fechada por
ESQUECIMENTO do modelo trava a conversa inteira e o usuário não tem como
destravá-la de fora — foi exatamente o que o uso real encontrou: o modelo
ofereceu uma opção do tipo "Escreva você mesmo" e o formulário não tinha onde
escrever, porque o schema do tool não sabia expressar "além destas, o que
você quiser". Uma lista aberta por engano, no pior caso, oferece um campo a
mais. Os dois erros não custam a mesma coisa. Pelo mesmo motivo a descrição
do tool **proíbe** criar uma opção "Outro" dentro de `options`: o formulário
já a oferece sozinha, e duas escapatórias na mesma lista confundem.

`allowOther` só existe em `select` — em `text`/`textarea` o campo já é texto
livre, e o engine normaliza esses dois para `false` em vez de gravar estado
sem significado no event log. Na tela, escolher "Outra (escrever)" troca o
`Select` por um `Input`: o sentinela de interface (`__outra__`) **nunca**
viaja para o backend, e o que vai é o TEXTO digitado. O botão de envio
continua exigindo TODAS as perguntas preenchidas — `AnswerStructuredQuestion
UseCase` recusa com 400 listando o que falta, então habilitar com campo vazio
só produziria um erro do servidor —, e estar em "Outra" com o texto ainda em
branco NÃO conta como preenchido.

O card também deixou de ser o único item do fio alinhado a nada: ele passa a
ser centralizado com o mesmo teto de 560px do `ApprovalCard` na variante
`chat` ([RN-173](https://github.com/viralabs-dev/brabo-web/blob/dev/docs/business-rules/web.md#rn-173)) e ganha o avatar e a cor do agente, que é o que o
faz ler como FALA de alguém em vez de formulário órfão. Antes ele nascia
encostado à esquerda com teto de 480px, enquanto as bolhas começam 45px
adentro.

- **Onde:** `apps/engine/lib/engine/harness/tools/ask_structured_questions.ex`
  (schema, validação e `normalizar/1`), `apps/web/src/lib/api-types.ts`
  (`StructuredQuestion.allowOther`), `apps/web/src/routes/SessionPage.tsx`
  (`StructuredQuestionCard`, `OUTRA_RESPOSTA`, `permiteOutra`),
  `apps/web/src/routes/SessionPage.module.css` (`.structuredQuestionCard`,
  `.structuredQuestionCabecalho`)
- **Teste:** `apps/engine/test/engine/harness/tools/ask_structured_questions_test.exs`
  (default aberto, `false` explícito, `allowOther` não booleano recusado),
  `apps/web/src/routes/SessionPage.perguntas-estruturadas.test.tsx`
  (describe "saída por texto livre no select")
- **Origem:** uso real no `exp001` — "sempre dê a opção de input do usuário
  quando ele seleciona Escreva"

<a id="rn-175"></a>

### RN-175 — Toda resposta de agente diz com qual modelo foi gerada {#rn-175}

`agent.response` carrega `modelName` nos **três** produtores do evento, e não
só nos quatro agentes conversacionais:

| produtor | quem passa por ali | antes |
|---|---|---|
| os quatro conversacionais (`criativo`/`po`/`arquiteto`/`dev_lead`) | chat | já gravava, desde a [RN-146](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-146) |
| `Engine.Harness.ToolLoop` | TODO agente de execução e de gate — `dev-*`, QA, SecOps, Infra-Workflows, Psicólogo, Anamnese | **nunca gravou** |
| `SendChatMessageUseCase` (api) | chat sem agente ativo, em que quem responde é o modelo | **nunca gravou** |

Nenhuma chamada nova: `RunLlmTurnUseCase` já devolve `modelName` no corpo e
`StreamLlmTurnUseCase` já o põe no frame `final` — o valor é o nome do modelo
do **binding resolvido** (`model.name`), não o eco do provider. Ele é `null`
quando o turno falhou antes de resolver o binding, e ausente em evento gravado
antes desta regra.

Na tela, o modelo deixou de ser a palavra solta `modelo` em mono 10px
`--text-muted` ao lado do nome do agente — que se lê como se o modelo se
CHAMASSE "modelo", e que reprova o contraste de texto de leitura. Virou um
**chip** com o ícone de modelo, `--text-secondary` sobre `--surface-2`, e o
rótulo de desconhecido passou a ser "modelo não registrado". A tela **não**
adivinha o modelo pelo binding ATUAL do agente quando o dado falta: atribuir a
uma resposta antiga um modelo que talvez nem existisse quando ela foi gerada
seria inventar procedência, e procedência inventada é pior que ausente — o
mesmo argumento do preço congelado em `token_usage` ([RN-044](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-044)).

Fora do escopo, declarado: `agent.error` continua sem o modelo nos quatro
servidores, mesmo quando a api o mandou no frame de erro (budget estourado, por
exemplo). É mudança de outro evento, com outra pergunta a responder.

- **Onde:** `apps/engine/lib/engine/harness/tool_loop.ex`,
  `apps/api/src/application/use-cases/llm/send-chat-message.use-case.ts`,
  `apps/web/src/routes/SessionPage.tsx` (o chip em `agent.response`),
  `apps/web/src/routes/SessionPage.module.css` (`.messageModelo`)
- **Teste:** `apps/engine/test/engine/harness/tool_loop_test.exs`,
  `apps/api/test/application/use-cases/llm/send-chat-message.use-case.spec.ts`,
  `apps/web/src/routes/SessionPage.arquiteto-modelo-icone.test.tsx`,
  `apps/web/src/design-contraste.test.ts` (o par do chip)
- **Origem:** uso real no `exp001` — "PO não mostrou o modelo que estava
  utilizando; todos os agentes devem apresentar o seu modelo ao lado do nome"

## Auditoria fluxo.yml × código — o plano do Dev Lead vira aprovação de verdade (RN-284, ADR 0086)

Não é fase planejada: é a correção de uma divergência que a auditoria de
`packages/contracts/fluxo.yml` × código encontrou (`docs/explanation/auditoria-fluxo-vs-codigo.md`,
achado A2) — o fluxo já declarava a saída `plano-de-paralelismo` do `dev-lead`
como `via: proposed_action`, e o código nunca foi ajustado para bater.

<a id="rn-284"></a>

### RN-284 — O turno do agente conversacional pode SUSPENDER esperando aprovação humana {#rn-284}

> **Revisada pela [RN-677](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-677) (ADR 0194):** `propose_execution_plan`
> ganhou pipeline de execução — aprovar o plano grava o módulo das tarefas
> ([RN-678](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-678)) e ATIVA a execução; a ação termina `executed` ou
> `failed`, e é esse desfecho que o Dev Lead lê ao retomar. O item 1 abaixo
> ("não tem execute-* pipeline") deixou de valer para este tipo.

> **Revisada pela [RN-578](parte-03.md#rn-578) (ADR 0163):** o turno de TODO
> conversacional deixou de segurar o `GenServer.call` — o `from` é respondido
> no aceite, e a suspensão aqui descrita mudou só o FECHO do turno
> (`awaiting_approval` em vez de `agent.done`), não mais o momento da resposta.
> A `user_message` recusada durante a suspensão passa a ser 409 no clique.

Primeira vez que um agente conversacional (Criativo, PO, Arquiteto, Dev Lead —
todos rodam turno síncrono via `GenServer.call` de até 180s, mediado por
`Engine.Agents.TurnoAssincrono`) suspende esperando uma decisão humana. O
padrão já existia para o dev agent ([RN-073](#rn-073), ADR 0052) e os gates de
QA/Infra (ADR 0057), mas os dois são disparados por `cast` e nunca esperavam
resposta síncrona — é exatamente esse ponto que este mecanismo resolve, e o
teto de paralelismo que fez o Dev Lead existir ([RN-083](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-083)) é a razão
de a primeira aprovação suspensa ser a dele.

**O mecanismo, em quatro peças:**

1. `Engine.Agents.DevLeadTools.run/2`
   (`apps/engine/lib/engine/agents/dev_lead_tools.ex:81-107`) chama
   `EngineApiClient.propose_action/5` em vez de `append_event/3`, e devolve
   `{:ok, texto}` (status `executed`/`auto_approved`/`approved` — os três
   contam como sucesso, porque `propose_execution_plan` não tem execute-*
   pipeline própria e a aprovação manual fica em `"approved"` para sempre),
   `{:pending, action_id}` ou `{:error, texto}`.
2. `Engine.Agents.DevLeadServer.run_turn/2`
   (`apps/engine/lib/engine/agents/dev_lead_server.ex`, bloco de despacho de
   `tool_calls`) usa `Enum.reduce_while` para PARAR no primeiro `:pending`,
   sem processar as chamadas seguintes nem recursar — e devolve o `state` com
   a chave `:aguardando_aprovacao` setada
   (`%{action_id:, tool_call_id:, tool_name:, remaining:}`, o `remaining`
   já descontando a iteração suspensa contra o teto). A mensagem `role:
   "tool"` NÃO entra em `state.messages` nesse momento — gravar "pending" ali
   mentiria pro modelo que o comando já respondeu isso (mesmo raciocínio do
   dev agent, `Engine.Harness.Hooks.ActionPipeline`).
3. `Engine.Agents.TurnoAssincrono.tratar_resultado/2`
   (`apps/engine/lib/engine/agents/turno_assincrono.ex`) responde ao `from`
   do mesmo jeito e na mesma hora de sempre — é o que rompe o bloqueio
   síncrono no momento certo —, mas em vez de `finalizar/1` (que emite
   `agent.done` e `agent.status: idle`) chama `suspender/1`: só
   `agent.status: awaiting_approval`, sem `agent.done`, porque o turno não
   terminou. A checagem é pelo VALOR da chave (`Map.get/2`, truthy), nunca
   pela presença dela — o Dev Lead carrega `aguardando_aprovacao: nil` desde
   o `init/1`, então a chave em si está sempre presente.
4. `Engine.Sessions.LiveBroadcast.agent_status/4`
   (`apps/engine/lib/engine/sessions/live_broadcast.ex:38-39`) ampliou a
   guarda de `["working", "idle"]` para incluir `"awaiting_approval"` — sem
   isto o `agent.status` do passo 3 nem seria persistido.

**A retomada.** `Engine.Agents.DevLeadServer` assina
`Engine.Dev.Wake.subscribe(project_id, "dev-lead")` no `init/1` — o MESMO
módulo que `Engine.Gates.QaLeadServer` já reusa para os subagentes de QA,
apesar do nome ser "dev": a entrega de `{:action_settled, ...}` é por AGENTE,
roteada pelo `agentId` do payload (`apps/engine/lib/engine/workers/dev_agent_wake_worker.ex`),
não por tipo de agente. Quando a decisão chega, um `handle_info` monta a
mensagem `role: "tool"` com o resultado REAL (`texto_do_desfecho/1`, mesmo
vocabulário do dev agent e do `QaLeadServer`), zera `aguardando_aprovacao` e
retoma com `TurnoAssincrono.iniciar(state, nil, fn -> run_turn(state,
pendente.remaining) end)`.

**Enquanto suspenso, uma segunda `user_message` não inicia turno novo** — um
guard em `handle_call({:user_message, _text}, _from, %{aguardando_aprovacao:
%{}})`, testado ANTES da cláusula genérica, emite `agent.error` (origem
`politica`) explicando que há uma decisão pendente em Aprovações, sem subir
task nenhuma.

**Lacuna aceita, declarada — restart durante a espera.** Ao contrário do dev
agent (que reidrata `laco_pendente` via `handle_continue` no `init/1`, ADR
0052), o Dev Lead NÃO reidrata `aguardando_aprovacao` — é só em memória. Se o
engine reiniciar enquanto ele está suspenso, a decisão continua registrada e
visível em Aprovações (é durável na api), mas o Dev Lead não narra o desfecho
automaticamente: o processo que assinou o `Wake` morreu, e o próximo restart
sobe um Dev Lead novo, sem inscrição para aquela ação. Fechar isto exigiria o
mesmo mecanismo do ADR 0052 — fora do escopo desta mudança, que só faz o
comportamento bater com o que `packages/contracts/fluxo.yml` já declarava.

- **Onde:** `apps/engine/lib/engine/agents/dev_lead_tools.ex`,
  `dev_lead_server.ex`; `apps/engine/lib/engine/agents/turno_assincrono.ex`
  (compartilhado pelos quatro conversacionais); `apps/engine/lib/engine/sessions/live_broadcast.ex`;
  `apps/api/src/domain/actions/decide.ts` (`propose_execution_plan`)
- **Teste:** `apps/engine/test/engine/agents/dev_lead_tools_test.exs`,
  `dev_lead_server_test.exs` (describe "suspensão em aprovação"),
  `turno_assincrono_test.exs` (describe "resultado com :aguardando_aprovacao"),
  `live_broadcast_test.exs`, `wake_do_outbox_ao_dev_lead_test.exs` (a
  corrente INTEIRA — outbox → drain → worker → `Engine.Dev.Wake` → o
  processo do Dev Lead, mesmo padrão de `Engine.Dev.WakeDoOutboxAoAgenteTest`),
  `apps/api/test/domain/actions/decide.spec.ts` (describe "plano de
  execução do Dev Lead")
- **ADR:** [0086](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0086-dev-lead-plano-suspende-para-aprovacao.md)
  (revisa parte do [ADR 0053](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0053-dev-lead-e-paralelismo-autorizado.md);
  precedente direto: [ADR 0052](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0052-dev-agent-espera-aprovacao-no-meio-do-laco.md)
  e [ADR 0057](https://github.com/viralabs-dev/brabo/blob/dev/docs/adr/0057-o-gate-espera-a-aprovacao.md))

---

## UX Designer — o quinto agente conversacional (RN-285..287, ADR 0087)

Não é gatilho de separação disparado (`packages/contracts/fluxo.yml` sempre declarou "quando
o projeto GERENCIADO tiver interface própria a desenhar" como critério) — é
decisão consciente do dono do produto de antecipar o papel. `teste-de-
usabilidade` (exige usuário humano real) fica fora de alcance; `metricas-de-
uso` segue lacuna, porque depende do papel `analytics`, que continua
`proposto`.

<a id="rn-285"></a>

### RN-285 — O UX Designer é conversacional SOLO, sem área {#rn-285}

`Engine.Agents.UxDesignerServer` (`apps/engine/lib/engine/agents/ux_designer_server.ex:40`)
espelha `Engine.Agents.ArquitetoServer`/`DevLeadServer`: GenServer por sessão,
laço bounded de tool use próprio com teto 14 (mesmo calibre de Arquiteto/Dev
Lead — agente de raciocínio, não conversação leve como Criativo/PO). Ativado
por handoff `accepted` endereçado a "ux-designer" — mecanismo GENÉRICO já
existente (`ActivateAgentUseCase`/`canActivateAgent` na api não ganharam
linha nenhuma: qualquer agente com handoff aceito já é ativável).

O kickoff (`build_kickoff/1`, `ux_designer_server.ex:222`) lê a
`artifact.product_brief` mais recente da sessão — a MESMA "necessidade de
negócio" que o Criativo produz, sem artefato novo. O sistema de design
(`design/tokens.css`, `design/COMPONENTS.md`) é DESCRITO na identidade
(`Engine.Harness.Agents`, entrada `"ux-designer"`), texto estático, porque os
agentes conversacionais não têm ferramenta de leitura de arquivo do repo — é
a única camada do prompt presente em TODO turno, não só no kickoff.

Sem área, sem subagentes: `packages/contracts/fluxo.yml` já classificava o papel como
`camada_produto`, ao lado de Criativo e PO, nenhum dos quais tem área.

<a id="rn-286"></a>

### RN-286 — `propose_prototype` grava artefato sem tabela e sem caso de uso dedicado, e oferece DOIS handoffs sobre o MESMO artefato {#rn-286}

`artifact.prototipo_navegavel` segue o desenho sem tabela de
`artifact.project_image`/`artifact.c4_diagram` ([RN-149](https://github.com/viralabs-dev/brabo-api/blob/dev/docs/business-rules/api.md#rn-149)) — o event
log é o registro —, mas por um caminho DIFERENTE do que os dois usam.
`choose_project_image`/`create_c4_diagram` precisam de caso de uso NA API
(`DecidirImagemDoProjetoUseCase`/`CreateC4DiagramUseCase`) porque têm
conteúdo DERIVADO de outro artefato (o Container level vem do `module_map`
vigente) ou recusa de domínio compartilhada por mais de um consumidor (teto
de recursos da imagem). `propose_prototype`
(`Engine.Agents.UxDesignerTools.run/2`,
`apps/engine/lib/engine/agents/ux_designer_tools.ex:122`) não tem nenhum dos
dois motivos — é conteúdo AUTOCONTIDO que só o próprio UX Designer escreve e
só ele lê de volta —, então a validação de FORMA mora no engine
(`Engine.Harness.ArtifactSchemas`, tipo `"prototipo_navegavel"`,
`artifact_schemas.ex:49/135` — personas e jornadas não-vazias, ao menos uma
tela) e a gravação usa o caminho GENÉRICO que a api já expõe para qualquer
tipo de evento (`EngineApiClient.append_event_returning/3`), o mesmo
mecanismo do `artifact.product_brief` do Criativo. Nenhuma rota nova na api.

Depois de gravar, `gravar_e_ofertar_handoffs/2` (`ux_designer_tools.ex:149`)
oferece DOIS handoffs sobre o MESMO artefato — `create_handoff` para "po" e
para "dev-lead", os dois com o `artifactId` do protótipo. Nunca um segundo
artefato para "spec-visual" (`packages/contracts/fluxo.yml`): o PO lê `resumo`/`prototipo`
para desenhar o backlog, o Dev Lead lê as MESMAS `telas`/`anotacoes` como
referência visual de implementação — duplicar o conteúdo arriscaria as duas
cópias divergirem na revisão seguinte, o mesmo argumento por trás do C4 não
redigitar o `module_map`.

Falha ao ofertar UM dos dois handoffs não desfaz o artefato já gravado nem o
outro handoff (RN-116) — o motivo volta como texto do tool-result, entrada do
laço e não fim de linha (RN-163): o modelo lê e pode reportar ao usuário na
resposta seguinte.

Um `propose_prototype` BEM-SUCEDIDO encerra o turno
(`ux_designer_server.ex:120`, mesma guarda de `propose_execution_plan` no Dev
Lead) — sem isso o laço voltaria ao modelo, que poderia propor de novo e
produzir dois protótipos com o mesmo total. Só existe UMA ferramenta aqui
(não há um segundo tool call a encadear como no Arquiteto), então "para no
primeiro sucesso" não perde nada.
