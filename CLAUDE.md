# brabo-engine

Engine do Brabo: Elixir/OTP + Phoenix (canais) + Oban. Roda os agentes (Harness), a máquina de sessão, os gates, o runner-router e as filas no Postgres.

> Partido do `CLAUDE.md` do monorepo `daneiel/brabo` (hoje `brabo-legacy`, `dev` @ `1586158973`) na AT-708 (EP-033, ADR 0252). Copiado, não resumido: o que era de outro repo foi cortado e os caminhos do monorepo viraram a raiz deste repo (ou `brabo-<x>:caminho`). Caminhos sem prefixo que não existem aqui (`docker/`, `deploy/`, `install.sh`, `e2e/`, `scripts/dev/`, `scripts/ci/` fora do `brabo-ci`) moram no `brabo-infra`, no `brabo-qa` ou no `brabo-ci`. O resto das regras mora no `CLAUDE.md` da pasta-mãe (`brabo-workspace`, clonado em `~/dev/brabo/CLAUDE.md`) e no de cada repo irmão.

## Stack (decidida — não proponha alternativas)
- este repo: Elixir/OTP + Phoenix (canais) + Oban (filas no Postgres) —
  Elixir 1.20.4 / OTP 29.1.1 sobre Alpine 3.24 (builder 3.24.2, runtime 3.24.3, a mesma musl 1.2.6) em dev, produção e CI (ADR
  0209): OTP abaixo de 29.1 aborta no boot sob musl ≥ 1.2.6 em host com AMX
  (`sys_sigaltstack`, erlang/otp#11349) — não desça o OTP sem descer a musl
- Contratos: `areas.json` e `fluxo.yml` vêm do `brabo-contracts` por TAG (o Elixir baixa da mesma tag); a cópia daqui é conferida contra ela. `prompts/` e as fixtures `golden_set_*` moram aqui. Testes: ExUnit; o CI reprova com um teste vermelho (`pipefail`, AT-776). Os testes que conferem espelho com a api/runner leem o clone irmão (`Engine.Irmaos`: `BRABO_API_DIR`/`BRABO_RUNNER_DIR` ou `../brabo-<repo>`; o CI faz o checkout). Sem os irmãos ao lado, esses 4 testes falham por ambiente local.

## Repositório, branches e PR (vale para todo repo `brabo-*`)
- Branches permanentes: dev, main — um branch, um ambiente; a esteira é
  `dev → main`. A `qa` foi APOSENTADA por hora (ADR 0235, só no repositório do
  Brabo; arquivada em `refs/archive/qa`, segue em `PROTECTED_BRANCHES` do
  produto e em `NUNCA_ARQUIVAR`). `rc` saiu
  da política (ADR 0030) e o bootstrap parou de criá-la, mas continua em
  `PROTECTED_BRANCHES` DE PROPÓSITO: a lista decide o que a trava de merge
  RECUSA, e repositórios bootstrapados por versões anteriores ainda têm a
  branch. Proteger uma branch que não existe não custa nada; desproteger
  uma que existe custa caro. Não "limpe" essa lista.
  Trabalho nasce de dev com a taxonomia da política (breaking/,
  feature/, bugfix/, perf/, refactor/, chore/, docs/, test/);
  hotfix/ nasce de main. Os AGENTES seguem a mesma régua desde a RN-664: o
  worktree do dev agent nasce de `dev`, a PR dele e a de ADR miram `dev`, e o
  gate julga o diff contra `dev` — os três juntos, nunca um só (o gate
  julgaria um diff que não é o da PR); repositório sem `dev` falha nomeado,
  sem queda para a default. A PR de INFRA (`open_infra_pr`) segue a
  mesma régua desde a RN-729: `feature/infra-setup` nasce de `dev`, mira `dev`
  e leva o autor `infra[bot]`. Formato funcao/descritivo,
  regex ^.{0,30}/\S{0,32}$. EXCEÇÃO nomeada: `dependabot/…` é branch
  PERMITIDA sem critério de caracteres (sem limite de tamanho, qualquer número
  de barras), mas só quando o AUTOR é o próprio Dependabot
  (`ehBranchDoDependabot` em `scripts/ci/pr-police.ts`) — humano com esse
  prefixo reprova em `FUNCAO-DESCONHECIDA`, senão o prefixo vira a porta para
  escapar do formato. Commits em conventional commits, pt-BR.
  A FUNÇÃO da branch decide a VERSÃO (scripts/ci/version.ts): breaking/
  sobe MAJOR, feature/ sobe MINOR, todo o resto é PATCH. Mudança que
  exige ação do operador antes do deploy nasce em breaking/ mesmo quando
  o conteúdo é correção — o v2.5.1 saiu patch porque a chave obrigatória
  do OAuth nasceu em bugfix/, e um patch diz "atualize sem pensar".
  Versão não se corrige à mão depois: o valor de ela ser calculada vem de
  não ser negociada caso a caso.
- Toda mudança entra por PR — push direto em permanente é bloqueado;
  únicas exceções de push: tags (bot de release) e .release/gate.json
  (bot do gate).
- Toda branch cujo PR é mergeado é ARQUIVADA automaticamente, SEM carência, por checagem
  SEMANAL (segunda 09:00 de Brasília, AT-661) (`.github/workflows/archive-merged-branch.yml`,
  AT-557): sem PR aberta e sem commit depois do merge; branch sem PR mergeada
  não é tocada — move de
  `refs/heads/<nome>` para `refs/archive/<nome>`, nunca apaga: histórico
  intacto, recuperável com um `git push` de volta. Exceções: dev/qa/main
  (aparecem como `head` de todo PR de promoção), `gh-pages` (deploy do
  site, não é branch de feature) e branch de fork. A política mora em
  `scripts/ci/archive-branch.ts` (testado), ver
  scripts/ci/docs/explanation/branching-policy.md, seção "Merged branches get
  archived".
- PR do Dependabot entra pela `dev`, nunca direto na `main`; na `dev` ele não espera aprovação humana (ADR 0236) e a `main` segue com a escada inteira. Dependência de linguagem só por segurança (`open-pull-requests-limit: 0`), `github-actions` e `docker` semanais, `target-branch: dev`. O `dependabot-para-dev.yml` do `brabo-ci` fecha ou redireciona o PR de segurança que o GitHub abre contra a `main`.
- Merge em branch protegida (`dev`/`main`) é SEMPRE manual do usuário, sem opção de automatizar. A política de PR, escada, promoção e carimbo de tag vem dos workflows reutilizáveis do `brabo-ci`, fixados por SHA com `# vX` no `uses:`. Imagem de terceiro por digest com a tag inline. Segredo nunca é impresso; teste nunca roda contra o Postgres da instalação.
- PR que toca uma funcionalidade do catálogo (`brabo-qa/funcionalidades.yml`, mapa por caminho) ajusta o regressivo dela no `brabo-qa` contra a `dev`, ou diz no card por que não precisa. Na PR para a `dev` o check `Regressivo do brabo-qa` só atesta (nunca obrigatório); na PR para a `main` o `E2E do brabo-qa` roda o catálogo inteiro e bloqueia, salvo `/qa-aceitar`. A PR para a `dev` publica a imagem `sha-<12>` assinada (job `imagem-hotfix` do `ci.yml`, fora de fork e Dependabot); o `limpeza-ghcr.yml` a apaga ao fechar a PR ou em 7 dias (AT-769).
- Ref de doc quebrada reprova no próprio PR: o check `refs` (reutilizável `refs-com-simbolo` do `brabo-ci`, não obrigatório) confere cada `caminho:N` (`símbolo`) das RNs, e o artefato `refs-patch` traz a reancoragem (`gh run download <id> -n refs-patch && git apply refs.patch`) (AT-782).

## Convenções (repositório, dados e domínio)
- Comunicação api ↔ engine: eventos via Postgres (transactional outbox
  na api, Oban no engine) + HTTP interno com service token para
  comandos síncronos.
- Todo evento de domínio é imutável: nunca UPDATE em tabelas de eventos.
- Estados de sessão são máquina de estados explícita:
  created → active → closing → closed | closed_abnormally
  Estado TERMINAL recusa CONVERSA com 409 nomeado (`sessao_encerrada`,
  RN-581), e "conversa" é TIPO de conversa OU ATOR conversacional — nunca uma
  lista de permitidos por tipo: o Psicólogo e a Anamnese escrevem numa sessão
  fechada com o MESMO vocabulário do Criativo, e a decisão humana sobre ação
  pendente continua entrando. O heartbeat não fecha sessão com conversacional
  esperando o usuário, mas essa é a ÚNICA pendência com teto (8h do fim do
  turno, causa `conversation_idle_timeout`); os outros sinais da RN-064
  continuam sem teto e vencem. Fechar a sessão PARA os conversacionais dela
  em todos os nós (`SessionLifecycleWorker`), sem gravar o turno em curso —
  e, desde a RN-763, os dev agents dela e os gates do projeto, com a task em
  curso bloqueada e o worktree preservado (`Engine.Dev.EncerramentoDaSessao`);
  "Parar execução" na aba Executores é esse MESMO fechamento, sem estado novo.
  Os terminais têm UMA saída desde o ADR 0183 (RN-649/650): a REABERTURA,
  para `active`, por rota e checagem PRÓPRIAS (`reopen`, `canReopen`) — a
  transição genérica continua recusando `closed → active`, e `closing →
  active` segue proibido por qualquer caminho. Não ponha `active` em
  `ALLOWED_TRANSITIONS` dos terminais. O fechamento anterior vira o evento NOVO
  `session.reopened` (a coluna é limpa, o evento guarda quando e por quê), o
  `kind` não muda, e sessão com `execution.activated` NÃO reabre (409
  `sessao_com_execucao`); papel `developer` (o mesmo de encerrar), sem prazo e
  essa recusa são decisão do dono desde o ADR 0184 (AT-337), não mais padrão
  provisório. O `SessionLifecycleWorker` ignora o
  fechamento que a reabertura já desfez (lê o `status` da sessão).
- A sessão tem DUAS classificações, e elas não se sobrescrevem: `kind`
  (`consultiva|criativa`) é a INTENÇÃO de criação, gravada e imutável; o
  evento `execution.activated` é o ESTADO de execução, e continua sendo
  ele que `findActiveExecutionSession` procura. `execution.activated` em
  sessão consultiva é 409, nunca conversão silenciosa (ADR 0061, RN-097).
  Não faça a derivação por evento olhar `kind`
- O repositório de projeto CRIADO nasce no aceite do handoff ao ARQUITETO
  (RN-582, ADR 0165), dentro de `AcceptHandoffUseCase`, ANTES de
  `activateAgent` — criar projeto não provisiona (RN-541). O aceite ao Dev Lead
  repete a chamada como SEGUNDA PORTA idempotente (a saída do projeto que
  passou pelo Arquiteto sem repositório); não a remova. E
  `execution/activate` sem repositório é 409 antes de qualquer efeito —
  RECUSA, nunca provisiona: provisionar ali esconderia um efeito de git na
  ativação e deixaria Arquiteto e Infra, que trabalham antes dela, sem onde
  escrever. Desde o ADR 0186 (RN-660) esse aceite tem um SEGUNDO autor: a
  oferta `po → arquiteto` é aceita pelo SISTEMA quando o backlog está coberto
  (≥ 1 regra, nenhuma sem história, a mesma `computeCoverage` da aba Backlog),
  o repositório é `local` e o projeto não tem conexão de git — sempre por
  `AcceptHandoffUseCase` e com o ator `handoff-auto-accept` no log. Não
  estenda a outro par de agentes nem a repositório remoto sem ADR
- Toda ação com efeito externo (git, terminal, gasto) nasce como
  proposed_action e respeita permissions.json; deny sempre vence allow.
  LER não é efeito externo e NÃO vira proposed_action — encheria a fila de
  ruído até ninguém mais ler as de verdade. O que a leitura deve é ser
  CONTIDA e ter TETO: caminho vindo do cliente passa pela checagem central
  (RN-092/RN-095), e leitura composta que chama o provider N vezes tem
  orçamento e cache, senão vira amplificador de tráfego (ADR 0060).

## Convenções (agentes, telas e testes)
- Agentes rodam SEMPRE dentro de um Harness; nenhuma chamada de LLM ou
  ferramenta fora dele.
  Argumento de ferramenta passa por `ArgumentosDeFerramenta.executar/4`:
  lista/objeto em string JSON vira valor (RN-719), texto com `\uXXXX`
  literal é decodificado (e só então `\n`/`\t`/`\"`/`\\` da mesma string —
  texto sem `\u` fica intacto, senão o `write_file` corromperia código), e
  recusa "exige X" leva as CHAVES recebidas, nunca os valores (RN-725).
- Agente que ESCREVE tem de poder LER o que já existe, e tem de poder
  PERGUNTAR quando falta informação. As duas são a mesma lição (RN-164/165):
  um agente só com ferramenta de escrita age sobre um retrato tirado uma vez,
  no kickoff, e diante de uma lacuna escolhe entre inventar e parar. Leitura
  de agente é escopada ao PROJETO quando o recurso é do projeto, e CONTIDA
  (ADR 0060): sem parâmetro onde o modelo escreva o que quiser, custo constante
  por chamada, teto de linhas declarando o total real quando trunca.
- Laço de agente NÃO termina calado. O teto de iterações emite
  `toolloop.limit_reached` — o mesmo tipo para o `ToolLoop` e para os agentes
  conversacionais, que têm laço próprio (RN-166) — e obrigação não cumprida
  vira desfecho explícito no padrão da RN-059, durável e com origem.
- Handoff externo endereça só LEAD de área ou agente sem área;
  delegação interna é privada da área; falha de subagente NUNCA é
  silenciosa — reporta origem ao lead, que decide e registra evento.
- O contrato externo dos gates é estável: quem consome vê um veredito
  por gate, independente da estrutura interna da área.
- Commits de agentes usam identidade "<agente>[bot]" com o usuário
  como co-author.
- Todo desfecho de falha de agente registra a ORIGEM da falha
  (infra | modelo | código | política) — nunca diagnóstico por
  eliminação (lição do ADR 0020). Falha NUNCA vira resposta vazia no
  event log, e o motivo NUNCA fica só em broadcast: `agent.error` é
  durável e o agente diz o que houve no fio (RN-059). Falha de UMA
  ferramenta no meio do laço segue a mesma régua (RN-163).
  Toda ferramenta de agente roda por `Engine.Harness.ArgumentosDeFerramenta.executar/4`
  (RN-719): lista/objeto que chega como string JSON é normalizado contra a
  spec (inválido é recusa nomeada), e exceção dentro da ferramenta vira
  `tool.result` `ok: false` com origem `codigo` e ENTRA no laço — servidor novo
  despacha por ele, nunca chamando `run/2` direto.
- Os SETE agentes conversacionais rodam laço bounded de tool use, com
  teto PRÓPRIO no servidor de cada um (Criativo e PO 12, Arquiteto, Dev
  Lead, UX Designer, Staff e Infra Lead 14 — raciocínio, não conversa
  leve) — não o teto do `ToolLoop` (`Engine.Harness.Iteracoes`), que é dos
  agentes de execução e de gate. O Infra Lead é o sétimo desde a RN-617
  (ADR 0175): conversa pelo composer, com os mesmos `TurnoAssincrono`,
  `Reidratacao` e `TurnoOrfao` dos outros, e a correção de gate que chega com
  turno em curso entra numa FILA (`correcoes_pendentes`) em vez de se perder.
  Erro de ferramenta é ENTRADA do laço, não fim de
  linha; teto esgotado é narrado, nunca silêncio, nos SETE (RN-163;
  RN-459 fechou os quatro que ainda terminavam calados — só PO e
  Criativo tinham corrigido antes; o Infra Lead, na RN-617); e o agente não anuncia ação que o
  código não vá executar — o que se promete é decidido pelo teto, nunca
  por texto fixo (RN-163). E o número do que foi
  gravado no turno é do SERVIDOR: o fecho do Criativo, do PO e do Arquiteto
  ganha "Gravado neste turno: …" derivado das escritas `ok` do próprio turno
  (`Engine.Agents.GravadoNoTurno`, RN-731), no idioma do turno (pt-BR, senão
  en), nunca reescrevendo o texto do modelo. O Staff é o único SEM `kickoff/1` — sobe e
  fica ocioso até a primeira `user_message`, porque não há artefato de
  sessão para sintetizar uma abertura (ADR 0088). Durante o turno, a
  tela de Sessão narra em tempo real o que o agente está fazendo numa
  faixa acima do composer — o fio só recebe a bolha de resposta depois
  que o turno termina (RN-460). Os sete reconstroem o histórico por UM
  caminho, `Engine.Agents.Reidratacao` (RN-580) — não reintroduza
  `rehydrate/2` por servidor: lê a CAUDA (`latest`, teto 200 do ADR 0060),
  traz pergunta estruturada e as PRÓPRIAS ferramentas como texto (nunca
  `role: "tool"`: o evento não tem id de chamada), pula
  `chat.structured_question_answered` (a resposta já vem no `chat.message`) e,
  quando a conversa não cabe, abre com o número de omitidos por SUBTRAÇÃO do
  `seq`. Leitura de kickoff é POR TIPO (`eventos_do_tipo/3`), nunca filtro em
  memória sobre a leitura geral. O `tool.result` dos sete leva o TEXTO que a
  ferramenta devolveu (`resultado`, 2.000 caracteres, `resultadoTotal` quando
  corta — RN-589), montado por `Engine.Agents.ResultadoDeFerramenta`; não grave
  o evento à mão num servidor. O Infra Lead passa pelo mesmo módulo, e o Dev
  Lead suspenso grava na RETOMADA (`action_settled`), nunca na suspensão
  (RN-593).
  que o turno termina (RN-460).
- O idioma chega ao modelo por UM caminho (RN-622): a fachada
  `EngineApiClient` (`llm_turn/5`, `llm_turn_stream/6`) acrescenta, no FIM de
  toda chamada de LLM, uma mensagem `system` EFÊMERA montada por
  `Engine.Harness.IdiomaDaResposta` — nunca em `state.messages`, nunca em
  `agent_instructions`, nunca por servidor. Turno COM autor usa o idioma que a
  api resolveu para ele (`idiomaDaResposta` no `agent/message`, posto no
  dicionário só durante o `handle_call` e herdado pela Task do turno); turno
  SEM autor usa `projects.language`; o `context-manager` fica fora. Falha na
  resolução = turno SEM orientação, nunca queda e nunca o idioma do projeto no
  lugar do da pessoa. Teto de 50 tokens de entrada por chamada (AT-169).
  Desde a RN-623 (AT-245), num turno COM autor cuja chamada leva ferramenta
  que grava artefato compartilhado (`ferramentas_de_artefato/0`, lista por
  NOME — ferramenta nova de artefato entra nela no mesmo PR), e com o idioma
  do projeto DIFERENTE do do autor, a MESMA mensagem ganha a cláusula
  "artefatos no idioma do projeto"; só com os dois códigos na forma curta
  (`idioma[-Escrita][-Região]`), que é o que segura o teto. Não mova isso para
  a descrição de cada ferramenta. E descrição de ferramenta NUNCA nomeia idioma
  (RN-667): o "em pt-BR" do `label` de `ask_structured_questions` era uma
  segunda orientação, fixa, que punha o formulário em português para autor
  `en`; ela diz "no idioma da sua resposta", e um teste reprova as 22
  ferramentas do harness se alguma voltar a fixar um.
- O AMBIENTE do agente de execução chega pelo MESMO caminho (RN-706):
  `Engine.Harness.AmbienteDoAgente.com_ambiente/2` roda no `ToolLoop` e a
  fachada acrescenta a mensagem `system` efêmera (pasta real do `terminal`,
  `/work/...` só com container `running`, imagem e rede do
  `artifact.project_image`, git só tipado, o módulo e seus contratos) para
  `dev-*` e `qa-*`. Não repita esses fatos em prompt de servidor.
- O FLUXO do time chega aos sete conversacionais pelo MESMO caminho (RN-711),
  depois do ambiente e antes do perfil e do idioma: `Engine.Harness.FluxoDoTime`
  é a fonte ÚNICA (etapas, próximo passo, quem dispara), conferida por teste
  contra `docs/fluxo.yml`. Não narre o fluxo em prompt de servidor; etapa nova
  ou passagem que muda entra ali. Restrição técnica explícita do usuário vira
  `decision_record` do Criativo, e o kickoff do Arquiteto a lê.
- O idioma DETECTADO nunca troca preferência sozinho (RN-624): a api só
  PERGUNTA (`detectionQuestion` na leitura do idioma da sessão), e só a
  resposta `confirm` grava `users.detected_language`; `decline` grava em
  `detected_language_declines` e o idioma não volta a ser perguntado. A
  detecção roda na LEITURA, fora do envio da mensagem, e falha vira "sem
  pergunta". A heurística tem UMA casa,
  `brabo-api:src/domain/iam/heuristica-de-idioma.ts` — sem `import` de
  propósito, porque `scripts/idioma/` a REEXPORTA (type stripping, com
  tsconfig próprio sem `verbatimModuleSyntax`) para medir o mesmo código; não
  a copie de volta para o instrumento, e não a transforme em `.mts` (quebra o
  `ts-node` da api). Os limiares
  (`PARAMETROS_PROVISORIOS`) são PROVISÓRIOS, do corpus sintético, até o dono
  medir o real.
- O clique que dispara turno de agente conversacional responde ao ACEITAR,
  nunca no fim do turno (ADR 0163, RN-578): `TurnoAssincrono.iniciar/3`
  devolve `{:reply, :ok, _}` assim que a Task sobe — DEPOIS de persistir
  `agent.status: working`, e essa ordem é contrato (é ela que deixa a tela,
  lendo a cauda do log depois do aceite, saber que o `agent.status` mais
  recente é do turno novo). O desfecho vai pelo canal e pelo `agent.error`
  durável, NUNCA pelo HTTP (nos SETE conversacionais — o Infra Lead desde a
  RN-617, que tirou o turno dele de dentro do `handle_call`); a recusa ANTES de o turno subir é síncrona e
  NOMEADA (409 `turno_em_andamento`/`aguardando_aprovacao`, 422
  `sem_regra_de_negocio`) e o controller do engine não descarta mais o
  retorno — era esse descarte que fazia mensagem recusada virar 202 calado.
  Na tela, "a chamada resolveu" deixou de significar "o turno acabou": depois
  do aceite chama-se `acompanharTurnoPeloLog`, nunca `finalizarTurnoDoAgente`.
  Não volte a segurar o request pelo turno.
  Desde a RN-673 (ADR 0191) a MENSAGEM do usuário não recebe mais
  `turno_em_andamento`: com turno em curso ela entra na FILA do agente
  (`TurnoAssincrono.receber_mensagem/4`, 202 com `entrega: "enfileirada"`), e
  no fim do turno as pendentes viram UM turno, na ordem. O estado mora no LOG
  (`chat.message_queued`/`_delivered`/`_cancelled`, todos com o id do
  `chat.message`), nunca em tabela — o `init/1` reconstrói a fila e o boot
  acorda quem tem pendente. Teto de 10 por agente e sessão (409
  `fila_de_mensagens_cheia`); quem ENVIOU cancela enquanto pende. A fila é
  UMA, em `TurnoAssincrono` — servidor novo só fornece `turno_de_mensagem/2`,
  nunca fila própria. `turno_em_andamento` segue para o que não é fala
  (revisão, prontidão, oferta de handoff), e o Dev Lead suspenso segue
  recusando com `aguardando_aprovacao`.
  O turno que o REINÍCIO do engine matou no meio (o `working` fica gravado, o
  processo e a Task somem) fecha por evento NOVO — `agent.error` origem `infra`
  + `agent.status: idle` — no boot (`Rehydrator`) e no `init/1` dos sete
  (`Engine.Agents.TurnoOrfao`, RN-586; o Infra Lead desde a RN-617), e só
  fecha o que não tem processo vivo em nenhum nó. Desde o ADR 0226 (RN-920) o
  turno RECENTE (≤ 900 s da última atividade) é retomado UMA vez no boot, com
  a mensagem `system` efêmera do `Diario`/`RetomadaDoTurno` e o `agent.plan`
  que o modelo escreveu (`registrar_plano`), nunca com mensagem falsa do
  usuário; o velho ou já retomado só fecha, e o botão "Retomar" (RN-921) é sem
  teto. Dev e gate seguem o mesmo teto 1× (RN-922/923); merge nunca. Sem
  isso a faixa da tela e o sinal de trabalho pendente da RN-064 ficavam presos
  para sempre.
- O turno de um agente conversacional pode SUSPENDER esperando aprovação
  humana (ADR 0086, RN-284) — hoje só o Dev Lead, no `propose_execution_plan`.
  Desde o ADR 0163 o `from` já foi respondido no aceite (como em todo turno);
  o que a suspensão muda é o FECHO: `agent.status: awaiting_approval` em vez
  de `agent.done` quando o `state` devolvido carrega `:aguardando_aprovacao`
  com valor não-nulo. Enquanto suspenso, `user_message` não inicia turno novo
  — vira `agent.error` explicando a pendência, e 409 no clique. Sem tabela de estado própria: restart do engine
  durante a espera perde a inscrição no `Engine.Dev.Wake`, lacuna aceita e
  declarada (a decisão continua registrada em Aprovações).
- A execução é ATIVADA pela APROVAÇÃO do plano do Dev Lead, nunca pelo
  aceite do handoff a ele (RN-677, ADR 0194, revisa a RN-161): aceitar o Dev
  Lead só o traz para PLANEJAR, e o web não encadeia mais
  `execution/activate`. Aprovar (ou auto-aprovar) `propose_execution_plan`
  roda `ExecuteExecutionPlanUseCase`, que grava o módulo das tarefas e chama o
  MESMO `ActivateExecutionUseCase` do botão — não escreva uma segunda régua de
  ativação: o 409 sem repositório, o 409 de sessão consultiva e
  `findActiveExecutionSession` moram ali. O botão explícito "Ativar execução"
  (card do Dev Lead e Visão Geral) continua como gesto próprio. A tarefa tem
  MÓDULO (`tasks.module`, RN-678), atribuído pelo Dev Lead em
  `tarefas: [{ taskId, modulo }]` e validado contra o `module_map` vigente na
  proposta (400 `plano_de_execucao_invalido`) e de novo na aprovação; o claim é
  pelo módulo da TAREFA (`daTarefaDoModulo`, o mesmo predicado na contagem),
  e tarefa sem módulo só é pegável quando a história tem UM módulo — não
  alargue essa ponte para "qualquer módulo da história", que é o defeito que a
  regra fecha.
- Métrica de execução de agentes é extraída do event log/token_usage
  por script, nunca anotada manualmente (lição da Fase 10/13). A busca do RAG
  segue a mesma régua e acrescenta uma (RN-479..481): quando o instrumento de
  medição não cabe no event log, ele vira TABELA, e a tabela — nunca o evento —
  é a fonte. `session_events.session_id` é `NOT NULL`, e a busca vinda da aba é
  de PROJETO: medir pelo evento perderia justamente as buscas com julgamento
  humano. O evento (`rag.search`/`rag.feedback`, só quando há sessão) é
  NARRAÇÃO da timeline. E o que o instrumento mede vai CONGELADO na linha — os
  pesos da busca, como o preço no metering (ADR 0042) e a `image_version` em
  `project_containers` —, senão a primeira calibração reescreve calada o
  significado de toda medição anterior. Gravar medição NUNCA derruba o que ela
  mede, e também não falha calada: origem `infra` no log e um `null` explícito
  na resposta, que a tela distingue de "não achei nada".

## Container, broker e runner (o que o engine implementa)
- FASE 25b DEIXOU de ser corte no compose LOCAL (RN-512, ADR 0146 ponto 3): o
  broker sai do `profiles` ali e sobe com `pnpm dev`, e permanece sob
  `profiles: ["container-broker"]` só em PRODUÇÃO — os dois composes divergem
  de propósito, não uniformize. A justificativa original ("nada o chama... em
  troca de nada", ADR 0130) morreu: são quatro chamadores reais desde os ADRs
  0133/0136, e o ADR 0144 fez `mounted` subir PELO broker, então com o profile
  desligado o modo padrão terminava em `BrokerIndisponivelError`. A assimetria
  é o que o socket significa de cada lado: quem roda `pnpm dev` já o tem (está
  rodando `docker compose`), em produção ele é fronteira de privilégio e o
  operador não é o desenvolvedor. Isso muda QUANDO o broker roda, nunca O QUE
  ele aceita — as cinco camadas de contenção seguem intactas. Consequência:
  `DOCKER_GID` passa a importar para toda máquina de desenvolvimento, e
  `preflight.mjs` RELATA o estado dele a cada subida (errar não quebra o boot,
  quebra o uso, e o sintoma aparece só no `container_start`). Desde a RN-599
  o compose de DEV também dá default a `BROKER_URL` (`http://broker:8090`, o
  serviço do mesmo arquivo) — produção e instalação seguem `${BROKER_URL:-}`,
  e essa divergência também é a decisão, não uniformize —, e o preflight
  RELATA a pasta gerenciada no mesmo molde do `DOCKER_GID`: sem
  `PROJECT_WORKSPACES_HOST_DIR` o broker fica sem
  `PROJECT_WORKSPACES_HOST_ROOT` e o modo `container` não sobe container; o
  `~` é acusado porque o Compose o expande no bind-mount e NÃO na variável do
  broker. Relata, nunca recusa nem grava o `.env`. Em PRODUÇÃO, sem
  o profile ligado, `container_start` continua terminando `failed` com
  `BrokerIndisponivelError`. Na INSTALAÇÃO por Release
  (`docker-compose.install.yml`) o serviço `broker` EXISTE desde o ADR 0162
  (RN-575), desligado sob o MESMO profile, e quem o liga é o `install.sh`,
  PERGUNTANDO — só um "s" digitado liga, o `DOCKER_GID` é MEDIDO de dentro de
  um container com a própria imagem do broker (recusa nomeada, nunca o 999 de
  palpite), e `COMPOSE_PROFILES`/`BROKER_URL`/`DOCKER_GID`/
  `PROJECT_WORKSPACES_HOST_ROOT` vão juntos para o `.env` ou nenhum vai. É o
  argumento da RN-512 (quem instala na PRÓPRIA máquina já tem o socket), com
  consentimento no lugar do "sobe por padrão" do dev porque quem instala nunca
  leu este repositório. `BRABO_BROKER_IMAGE` é obrigatória ligado ou não — o
  Compose interpola o arquivo inteiro antes de filtrar por profile (medido). E
  desde o ADR 0161 (RN-573/574) a TELA sabe se há broker: `brokerConfigurado`
  (`ContainerBrokerPort.configurado()`, a mesma fonte do estado observado) vem
  em `GET .../projects-base` e em cada linha de `GET .../containers`, o
  assistente para de pré-selecionar `mounted` sem broker confirmado e a
  `/containers` recusa antes do clique a subida de `container`/`mounted`. As
  duas metades são a MESMA decisão do mantenedor ("os dois"). O
  que mudou (ADR 0133, RN-491) é que o MECANISMO deixou de ser corte:
  `container_start` é `proposed_action` de verdade (`maintainer`) — e desde
  o ADR 0190 (RN-671) é SEMEADA `auto_approve` no aceite do handoff da Infra,
  com o SERVIDOR do Infra Lead propondo a primeira subida sozinho no kickoff
  quando há roteamento — com a rede HERDADA da `artifact.project_image` do
  Arquiteto (`egress` incluído, sem clique; `none` sem decisão dele — ADR
  0208, RN-723, preço declarado na borda 5 do ADR 0189) (`container`/`mounted`; `runner` segue pelo modelo e
  com aprovação) —, e
  `ExecuteContainerStartUseCase` chama `ContainerBrokerPort.start` de
  verdade quando aprovada — o Infra Lead elege uma das candidatas do
  roteamento do Arquiteto (`artifact.module_routing`, ADR 0131) e a eleição
  emite nova versão de `artifact.project_image` (reusando
  `DecidirImagemDoProjetoUseCase`, `decidedBy: 'infra-lead'`), porque o
  broker compõe a partir DESSE artefato, nunca do roteamento. Das cinco
  operações do ADR 0128/0130, agora as CINCO têm chamador — `inspect` (a
  rota de ciclo de vida, observado ao lado do registrado), `start` e, desde
  o ADR 0134 (RN-492), `exec`: quando há um container `running` REGISTRADO,
  o comando de terminal do dev agent atravessa engine → api → broker e roda
  DENTRO dele, via `docker exec`, em vez de `System.cmd` local — a lacuna
  que a RN-491 tinha deixado declarada ("dev agents NÃO passam a trabalhar
  dentro do container") fechou. Desde o ADR 0136 (RN-495, PR 1.8), `stop` e
  `remove` também têm chamador: a página global de containers
  (`/containers`) propõe `container_stop`/`container_remove` — dois tipos
  novos, sempre um HUMANO clicando "Parar"/"Remover" numa linha da tela,
  nunca um agente. `container_stop` segue o calibre de
  `container_start` (`maintainer`, pode ser configurado auto-aprovável), mas
  NUNCA é semeado — a semente do ADR 0190 é só a da subida; `container_remove` — o mais destrutivo dos três, descarta
  o container e exige reprovisionar do zero — entra no MESMO teto absoluto
  de git push/comando privilegiado (RN-418): nunca auto-aprovável, "sempre
  permitir" recusado na fonte. A tela em si tem seu próprio teto: perguntar
  o OBSERVADO ao broker é uma chamada de rede por projeto, então só linhas
  `provisioning`/`running` são elegíveis, com um teto explícito de 20
  chamadas por carregamento (`TETO_DE_VERIFICACOES_POR_CARGA`) — o que fica
  de fora diz por quê (`naoVerificado`), nunca confundido com o broker ter
  sido perguntado e recusado (`naoObservado`).
  `RegistrarTransicaoDeContainerUseCase` ganhou o primeiro chamador fora de
  teste, transicionando `provisioning → running` (ou direto para `running`
  a partir de `stopped`, que a máquina de estados do ADR 0081 não deixa
  reprovisionar) — `container_remove` acrescenta o segundo hop real,
  `running → stopped → removed`, refletindo que `ContainerBrokerPort.remove`
  já era `docker rm --force` (remove mesmo `running`, numa chamada só) sem
  alargar a máquina de estados com um atalho `running → removed` que só
  existiria para este caso. O que seguia cortado até o ADR 0137 (RN-497,
  PR 1.3): `mounted`/`runner` continuavam sem container nenhum subindo NO
  SERVIDOR — o portão dos três modos fechou (RN-494/ADR 0135, PR 1.7: os
  três modos agora exigem imagem decidida para a aba Code, e
  `RegistrarTransicaoDeContainerUseCase` não recusa mais por modo), mas quem
  impedia `mounted`/`runner` de chegar em `running` era só o broker
  (`ModoDeExecucaoNaoSuportadoError`). O ADR 0137 fechou essa metade DO OUTRO
  LADO: `mounted`/`runner` sobem container de verdade NA MÁQUINA DO USUÁRIO,
  pelo `brabo-runner`. E o ADR 0144 (RN-503) fechou a metade que faltava para
  `mounted`, do lado do SERVIDOR: a base única do ADR 0141 tornou aquela pasta
  alcançável pelo daemon do host, então `mounted` passa a subir pelo BROKER
  como `container` — a ramificação vira por DESTINO (`container` e `mounted` →
  broker, `runner` → runner), e as três ações de ciclo de vida mudam juntas. O
  broker ganhou uma SEGUNDA raiz (`BRABO_PROJECTS_HOST_BASE`) e a api passou a
  mandar um localizador DISCRIMINADO em vez de um nome solto, sem que nenhum
  caminho absoluto atravesse a rede. `runner` é o único modo que segue sem
  container NO SERVIDOR — a pasta dele mora numa máquina que o broker não
  enxerga. A pergunta "quantos módulos, um container só" segue como está,
  `project_id UNIQUE` em `project_containers`, sem mudança aqui. O que
  faltava fechar era o OUTRO fallback: até a RN-507 (ADR 0145), um projeto
  `runner` verificado e conectado tinha comando roteado ao CLI mesmo SEM
  container `running` de pé — o runner caía sozinho no host puro,
  silenciosamente. `Engine.Runners.RunnerReadiness` unifica os TRÊS modos sob
  o MESMO predicado, e `container_start` deixa de atender `runner` (o
  payload dela, com eleição de imagem, nunca fazia sentido pra um caminho
  sem roteamento contra o qual eleger) — `container_start_via_runner` é o
  tipo novo, exclusivo desse modo

## Documentação é parte da definição de pronto (permanente)
- A doc deste repo mora em `docs/` (em pt-BR por padrão, como o README e o CHANGELOG — decisão do dono de 06/11/2026, que reverte o ADR 0260; sem `idioma_original` e sem traduções em `docs/i18n/`, só o `brabo` é multilíngue). Ao alterar código, atualize a doc da área NA MESMA mudança e mostre o diff dela junto com o do código. Não pergunte se deve: faça. NUNCA crie `website/docs/`: o site é agregado pelo `brabo`, que lê a `docs/` de cada repositório.
- Mudança de comportamento observável → entrada em `CHANGELOG.md` (Unreleased). Versão própria a partir da 1.0.0, e toda tag nasce de workflow (nunca versionar à mão).
- Regra de negócio nova → RN-XXX com `caminho:N` (`símbolo`) e o teste que a cobre, na `docs/business-rules*` deste repo; a numeração é UMA só no produto (nunca reinicie), a âncora `{#rn-NNN}` é o contrato e não muda quando a RN muda de arquivo. Aloque o número varrendo as branches locais e o remoto (colide com frente paralela).
- Mudança estrutural (fronteira de camada, banco, modelo de consistência, dependência pesada) → ADR novo com o próximo número; ADR aceito NUNCA é editado (o novo o referencia). Os ADRs moram no repo `brabo` (a porta de entrada do produto).
- Nunca inventar conteúdo de doc: sem informação suficiente, use `> **TODO(humano):** <pergunta específica>.`. Diagramas em Mermaid no próprio Markdown, nunca imagem.
- Este arquivo também é doc: toda mudança verifica se ele precisa mudar (Stack, convenções, "O que NÃO fazer"). Ele é lido em toda sessão e não passa de 40 mil caracteres (`wc -m`, nunca `wc -c`); o que só vale para uma área sai daqui para `.claude/rules/` com `paths:`.

## Estado, decisões abertas e lacunas que são DESTE repo
- **O Infra Lead propunha `container_start` às cegas; desde a RN-566 ele
  recusa por MODO, desde a RN-610 por ESTADO, e o que sobra da lacuna é a
  IMAGEM em `container`/`mounted`, de propósito.** A metade fechada:
  `dispatch_container_start/2` consulta LOCALMENTE o `execution_mode`
  (`Project.get/1`, mesmo processo BEAM, sem HTTP — rede no laço do agente
  era o que a correção não podia custar) antes de chamar `propose_action`, e
  projeto `runner` é recusado NOMEANDO `container_start_via_runner`. Não
  nasceu régua nova: a tool irmã já recusava (RN-508) e a `/containers` já
  ramificava por DESTINO (RN-521, `acaoDeSubidaDoModo`) — as duas tools
  passam pela MESMA `recusa_local_de_subida/2`, com uma CLÁUSULA cada, e a de
  `container_start` é lista de PERMITIDOS como a do broker (modo novo no enum
  nasce recusado). O custo que ESTE arquivo declarava — *"corrigir exigiria
  tocar o prompt/instrução do Infra Lead"* — foi MEDIDO e não se confirmou:
  nenhuma linha de prompt mudou, e o texto da recusa é o que o modelo lê como
  resultado de ferramenta (entrada do laço, RN-163, nunca `agent.error`).
  Desde a RN-610 (AT-142) o agente recusa também por ESTADO, na ordem da
  `/containers` e com as mesmas leituras locais (Postgres direto e o registro
  de runners, nunca HTTP): as DUAS tools recusam container já REGISTRADO
  `running`/`provisioning`, e `container_start_via_runner` recusa sem imagem
  decidida (ela não elege, sobe a decidida) e com pasta nunca confirmada
  (`workspace_verified_at` nulo), antes da checagem de runner conectado que já
  fazia. `GetInfraContextUseCase` NÃO mudou — a decisão foi recusa no
  despacho, não contexto. **O que SEGUE ABERTO, de propósito:** propor
  `container_start` SEM imagem decidida continua possível em
  `container`/`mounted`, porque ali a recusa por imagem inverteria a ordem —
  eleger a imagem é o que essa proposta FAZ (RN-491); não "complete" a régua
  da tela ali. Broker ausente na instalação e papel/sessão também não são
  checados pelo agente (o primeiro a api recusa ao propor, RN-591). O ADR 0137 (RN-497) segue valendo: aprovar `container_start` em
  `mounted` pode dar certo de verdade, pelo broker. Desde a RN-591 a instalação SEM
  broker também é dita: a api recusa a proposta com 409
  `sem_broker_na_instalacao` (a fonte é `ContainerBrokerPort.configurado()`; o
  engine NÃO lê `BROKER_URL`, e o texto da recusa chega ao modelo), a conversão
  de modo e "Parar"/"Remover" ficam inertes com o motivo em texto — só a
  ausência CONFIRMADA bloqueia a conversão, "não sei" não Desde a RN-577 o mesmo
  molde vale para a PR: `propose_infra_pr` (e o `propose_adr` do Arquiteto)
  recusam LOCALMENTE, antes de propor, projeto SEM repositório — o predicado é
  o MESMO de `ExecuteAdrPrUseCase`/`ExecuteInfraPrUseCase` (linha em
  `project_repositories`, lida direto do Postgres por
  `ProjectRepository.recusa_de_pr_sem_repositorio/2`), e no Infra Lead a
  pergunta vem ANTES do HALT, para não gastar o laço do Workflows numa PR
  impossível. A recusa deixa `tool.call` e `tool.result` (`ok: false`, com o
  motivo) no event log. ONDE o repositório nasce NÃO foi decidido ali (é a
  AT-092): o texto da recusa descreve o gatilho de hoje, o aceite do handoff
  ao Dev Lead (RN-522)
- Restart do engine com Dev Lead suspenso perde a inscrição no Wake (decisão
  segue visível em Aprovações) — ADR 0086
- Ciclo de gate parado há mais de 2 h ESTACIONA (`gate.rescue_parked`, ADR
  0207, RN-722, decisão do dono) em vez de ser retomado sozinho no boot ou no
  tick, e o resgate não reinicia ciclo cuja sessão tem ação pendente de ator do
  gate. Retomar o estacionado é o botão "Retomar gate" no aviso do fio
  (`POST /projects/:projectId/tasks/:taskId/gates/:gate/resume`, `developer`,
  409 `gate_nao_estacionado` — RN-724), que chama
  `GateRescuer.retomar_estacionado/3` pelo engine. O ciclo RECENTE que o
  próprio reinício matou não espera os 15 min: o boot o retoma quando nenhum
  nó do cluster o tem em voo (`:erpc`, nó mudo = vivo) e grava
  `gate.interrupted`, que o fio mostra (RN-823); o tick segue com o limiar
- A chamada ao broker tem teto POR OPERAÇÃO desde a RN-604 (`tetoDaOperacao`,
  `container-broker.client.ts`), e a cadeia do `exec` é broker < api <
  engine — mexer no teto de um salto sem o de cima reabre o defeito, e os
  testes dos dois lados conferem a ordem. Desde a RN-757 (AT-440) a cadeia
  tem um QUARTO salto, o de fora: a ação `terminal` auto-aprovada é executada
  dentro do `propose_action`, e o engine a espera por
  `TERMINAL_ACTION_TIMEOUT_MS` (agora 120s, era 15s) + 120s — broker (T) <
  api (T + 45s) < `container-exec` (T + 90s) < `propose_action` (T + 120s),
  abaixo dos 300s do `fetch`; o estouro chega ao modelo nomeando o teto, e
  esse teto passar de ~180s reabre o corte. O estouro do `exec` é decidido pelo RELÓGIO, não
  pelo `killed` — o cliente `docker exec` sai 0 ao receber o SIGTERM —, e o
  grupo do comando é morto DENTRO do container pelo PID que o embrulho grava
  (RN-807); não volte a confiar só em `killed`. Segue aberto, por DECISÃO do
  mantenedor (AT-234, opção D, RN-605): imagem grande não sobe na primeira
  tentativa. O pull é passo explícito do `start` (`image inspect` → `pull`)
  sob o MESMO `TIMEOUT_DE_CONTROLE_MS` de 30s, e o estouro é
  `PullExcedeuTetoError` (504, origem `infra`) — antes saía "código -1" com
  `origem: null`. Matar o CLI CANCELA o pull (medido): a imagem NÃO segue
  baixando por trás. Não suba o teto de passagem: as outras três saídas
  (teto próprio, `start` assíncrono, pull antecipado) foram medidas e
  recusadas. Os tetos de quem espera o `start` contam as SEIS chamadas de
  controle (`CHAMADAS_DE_CONTROLE_NO_START`): 195s na api, 185s no
  `RunnerRouter`, 225s no `propose_action` do engine para as ações de
  container que a api executa auto-aprovadas. E `timeoutMs` acima de ~255s
  esbarra nos 300s de cabeçalhos do `fetch` do Node

## O que NÃO fazer
- Não usar Redis (filas no Postgres via Oban).
- Não instalar libs sem justificar no plano. Não refatorar código de fase concluída sem pedido explícito. Gate novo e área nova de agente são decisão de produto, com ADR.
- Não corrigir de passagem os achados ABERTOS em `docs/` do `brabo-api` (`explanation/achados-execucao-real.md`): Z/AD e AE são decisão de produto.

## Onde está o que não coube aqui
O teto de 40 mil caracteres tirou deste arquivo blocos que viraram regras de CAMINHO em `.claude/rules/` (texto integral da fonte `brabo-legacy`, `dev` @ `1586158973`), carregadas quando a sessão lê os arquivos do `paths:`:
- `persistencia-e-rbac.md` — schema por agregado, evento imutável, papel de projeto sobre o de workspace.
- `runner.md` e `broker-e-containers.md` — o runner e o ciclo de vida do container.
Telas moram no `brabo-web`; o resto no `CLAUDE.md` da pasta-mãe (`brabo-workspace`).
