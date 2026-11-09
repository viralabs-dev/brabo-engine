# Changelog

## Unreleased

- CI: repina o brabo-ci na release final `v1.4.0` (`5320046`), para a promoção `dev → main` de 09/11/2026.

- Doc (AT-875): a `parte-06.md` ganha uma linha em branco antes de cada `<a id="rn-NNN"></a>` colado ao item de lista da RN anterior (14 âncoras, RN-880 e RN-1010 a RN-1070), para o `user-content-rn-NNN` sair em parágrafo próprio no GitHub e no site, sem id repetido. Só linhas em branco: nenhum texto muda.

- Doc (AT-871): cada parte de RN (`docs/business-rules/*/parte-NN.md`) ganha `<a id="rn-NNN"></a>` antes de cada RN, pelo `ancorar-rn.mjs` do brabo, para o link `parte-NN.md#rn-NNN` abrir na RN também no GitHub. Só acréscimo de âncoras: o texto das RNs e as refs `caminho:N` ficam iguais.

- Doc (AT-868): os links das páginas de RN que só resolviam no site (`../adr/…`, `../explanation/…`, `api.md`) apontam para o arquivo no GitHub do repo dono, na `dev` (`https://github.com/viralabs-dev/<repo>/blob/dev/<caminho>`). O site converte de volta para link relativo, então nada muda para quem lê por lá.
- Docs (AT-873): a tabela "Onde se encaixa" do README linka cada repo no GitHub (o do próprio README fica sem link), gerada pelo `mapa-dos-repos.ts` do brabo-ci repinado em `a571e82` (`v1.4.0-dev.28`, ci#63).
- Doc (AT-862): `docs/business-rules/engine.md` vira o índice (mesma URL e âncoras `#rn-NNN`) e as 205 RNs saem para `docs/business-rules/engine/parte-01.md` a `parte-06.md` (até ~90 KB cada), pelo `partir-rn.mjs` do brabo (ADR 0287). Os links cruzados entre partes e as refs `caminho:N` ficam conferidos.

- Doc (AT-867): a linha de badges logo abaixo do título separa o CI (`ci.yml`) e a versão da `dev` (última tag `-dev`) e da `main` (release final), e mantém licença, documentação e Ko-fi.

- Doc (AT-848): o bloco "Onde se encaixa" do README é regenerado do `repos.yml` do brabo com o formato `{arquivo, trecho}` e a aresta `brabo → brabo-contracts` (brabo#84); o check `mapa-alinhado` volta a passar.
- CI (AT-848): todos os `uses:` e `ci_ref` repinam em `6390ef5` (`v1.4.0-dev.17`, brabo-ci#53), que aceita a prova `{arquivo, trecho}` do `mapa-dos-repos.ts`.
- Doc (AT-845): as âncoras `#rn-727` e `#rn-689` de `docs/business-rules/engine.md` apontam para a RN no `api.md` (`api.md#rn-727`, `api.md#rn-689`); as RNs moram na api e o `docs:build` do `brabo` reprovava a âncora (brabo#73).

- Doc (AT-845): as refs `apps/api/src/application/use-cases/execution/get-dev-task-context.use-case.ts` (`:195` e `:182`) de `docs/business-rules/engine.md` passam para `:220` e `:207`, as linhas atuais no `brabo-api` `dev` (check `refs`).
- Dev: o `NoopDevAgentServer` trata `{:merge_conflict, _}` (RN-715) bloqueando a task com motivo nomeado (o Noop não readota) e ganha uma cláusula final de `handle_info` com `Logger.debug`; antes morria com `FunctionClauseError` e deixava a task órfã (AT-844).
- Docs: o `README.md` segue o esqueleto de 8 seções do `brabo-ci` (AT-826): para que existe, onde se encaixa (bloco gerado do mapa), como é usado, como desenvolver, o que o CI garante, documentação, como replicar, apoie e licença. O workflow `readme.yml` liga os checks `readme-esqueleto` e `mapa-alinhado` do `brabo-ci` (pinados em `v1.4.0-dev.13`), informativos.
- Dev: o `NoopDevAgentServer` trata `{:action_settled, _}` (ignora, como o agente real) e não morre mais com `FunctionClauseError` quando o `git_push`/`pr_open` pendentes são aprovados (AT-839, qa#38).
- Agentes: o `propose_adr` aceita `supersedes` (slug da ADR mergeada que a nova substitui), escreve `Substitui:` no topo do `content` e devolve o 400 `adr_supersedes_invalido` ao modelo; a instrução do Arquiteto explica quando usar (AT-806, RN-1069, TP-01 27ª achado 6).
- Agentes: o PO e o Dev Lead ganham `update_task`, que corrige título/descrição de tarefa `todo` pela rota nova da api; o 409 volta ao modelo e o Gravado neste turno conta "tarefa corrigida" (AT-805, RN-1068, TP-01 27ª achado 5).
- CI: o check `Dependências de merge` (AT-787) entra pelo `dependencias.yml`, que chama o reutilizável `dependencias-de-merge.yml` do `brabo-ci` pinado em `b75c803` (`v1.4.0-dev.11`). A PR declara `Depende-de: viralabs-dev/<repo>#<n>` no corpo e o check fica amarelo (`esperando …`) até cada PR citada estar mergeada. Sem linha `Depende-de` o check fica verde ("Sem dependências declaradas"). Não é exigido por ruleset ainda.
- Contratos: `scripts/baixar-contratos.sh` sobe de `v1.1.1-dev.3` para `v1.2.0` e baixa `docker-cli.json` no lugar de `docker-cli.ts` (o teste do `RunnerRouter` lê o JSON com `Jason`); o `ci.yml` passa a chamar o `contracts-alinhado` do `brabo-ci` (pin `0a9eba8`, AT-770 R2b, RN-1038).
- Agentes: a instrução do `decision_record` (idêntica nos 5 conversacionais) pede `afeta.modulos` e a citação `modules/<módulo>`; o contexto do dev agent chama a seção de "Decisões registradas para esta tarefa/módulo" (AT-812, parte do engine; a api amplia o alvo em outra PR).
- Agentes: o Dev Lead ganha `listar_adrs_propostas`, a regra "não afirme estado sem ler" no prompt e a spec do `propose_execution_plan` pede tarefa pelo título no `porque` (AT-809, RN-1070, TP-01 27ª achado 9).
- CI: o `ci.yml` chama o reutilizável `cadeia.yml` do `brabo-ci` (actionlint, `pins` e `pins-do-brabo-ci`, `ci_ref` obrigatório, AT-819; não é check obrigatório) e todos os `uses:`, actions `vinculos` e `ci_ref` repinam em `0a9eba8` (`v1.4.0-dev.5`, brabo-ci#39), com o comentário de versão no formato `vX.Y.Z-dev.N`. Sem achados do actionlint/shellcheck a corrigir na origem.
- Dev: o dev agent `noop` não exige container do projeto para reivindicar tarefa (exceção da RN-502 em `AgentIo.try_claim/2`); o `DevAgentServer` real segue exigindo (AT-833, ensaio da qa#30).
- Execução: `ExecucaoParadaWorker` grava `execution.stalled` e acorda o Dev Lead quando todos os dev agents estão parados, há tarefa pendente e há tarefa bloqueada ou agente travado (AT-800, RN-1059, TP-01 27ª achado 14; a parte da web é outra PR).
- Agentes: as perguntas abertas vêm antes das decisões no texto do turno, com corte por linha inteira e aviso do total; ferramenta nova `list_open_questions` nos quatro perguntadores, e a frase do fluxo manda listar e fechar "todas" (AT-804, RN-1058, TP-01 27ª achado 4).
- Dev: o engine conclui o merge do conflito de integração (AT-798, RN-1010/RN-715/RN-706). A guarda do `report_done` olha só os marcadores (não mais o `MERGE_HEAD`), o commit do merge é do sistema (`GitExecutor.commit/1`), a readoção depois de conflito de merge integra a `main` atual (`WorktreeManager.adopt_integrando/3`) e nenhuma mensagem ao agente manda rodar git no `terminal` (o container de execução não tem git; TP-01 27ª, achado 15).
- CI: o regressivo do brabo-qa roda em toda PR para a `dev` (AT-769): o job `imagem-hotfix` do `ci.yml` publica a `sha-<12>` assinada também com `base_ref == 'dev'` (mesma guarda de fork, sem Dependabot); o `limpeza-ghcr.yml` apaga toda `sha-*` de PR fechada e as de mais de 7 dias (eram 14); o `qa-e2e.yml` passa a `branches: [dev, main]` (PR para a `dev` = `Regressivo do brabo-qa`, nunca exigido; PR para a `main` segue com o `E2E do brabo-qa`). CLAUDE.md e `.claude/agents/analista.md` ganham a regra do card.
- CI: o run do `release.yml` ganha `run-name` com a origem e o passo `Vínculos` (helper do `brabo-ci`, origem pela linha `Carimbo:` da tag; AT-773, RN-1044).


- CI: repina o `brabo-ci` em `2d9ec1b` (merge da ci#28: o `HEAD` do `brabo-ci` deixa de sombrear o `dev` em `qa-e2e-disparar.ts`, então o portão da `main` volta a rodar) em todos os pins, `uses:` e `ci_ref:` (AT-789).
- CI: repina os reutilizáveis do `brabo-ci` em `384b5d1` (merge da ci#22: o job `disparar` do `qa-e2e-gatilho.yml` agora instala as dependências) em todos os pins, `uses:`, `ci_ref:` e checkout do `brabo-ci` (AT-785).

- Check `refs` no PR (AT-782): o `refs.yml` chama o `refs-com-simbolo` do `brabo-ci` (pin `64a1e15`) e reprova a ref `caminho:N` (`símbolo`) de RN que o PR quebra; o artefato `refs-patch` traz a reancoragem. Não é check obrigatório.

- Teste: o `agent_command_controller_test.exs` para os agentes conversacionais da sessão no `on_exit`, antes de soltar o env. O turno órfão de um teste entregava um `agent.error` ao teste seguinte e reprovava a linha 267 em ~16% dos runs do CI (AT-781).

- As mensagens de capacidade do runner (`Engine.Runners.Capacidades`) mandam atualizar o binário rodando de novo o `install.sh`, no lugar de `npm install -g @brabo/runner`: o runner sai só como binário da Release (AT-774).

- CI: repina os reutilizáveis do `brabo-ci` em `13f3697` (merge da ci#17, que inclui a ci#16): `ubuntu-26.04`, `client-id` no lugar de `app-id`, rótulo de família criado antes de aplicar, linha `Carimbo:` na tag e helper `vinculos` (AT-772, AT-773).
- O CI reprova quando um teste falha (AT-776): o `mix test --cover | tee` agora roda com `pipefail` (antes o job fechava verde com 8 testes vermelhos). Os 8 vermelhos foram consertados pela causa: os testes que leem um repo irmão (`brabo-api`, `brabo-runner`) usam `Engine.Irmaos` (variável `BRABO_<REPO>_DIR` ou `../brabo-<repo>`) e o CI faz o checkout dos irmãos na `dev`; o `test_helper.exs` sobe o `epmd` para os testes de cluster (`:peer`); o teste do `GitCmd` não depende mais do texto do `rev-parse` de cada versão do git; o teste do recorte do QA confere o texto vigente da AT-612 (`só processos desta pasta`).

- CI: todo `runs-on` do repositório passa de `ubuntu-latest` para `ubuntu-26.04` explícito (AT-772). O `mix compile --warnings-as-errors --force` do app já sai limpo; os avisos de `catch` vêm da dependência `yamerl`.

- Ko-fi do mantenedor: `.github/FUNDING.yml` (botão Sponsor) e seção Apoie no README (AT-768).

- Imagem a cada carimbo `-dev` e no hotfix, com limpeza do GHCR (AT-765): o `release.yml` reage também a `vX.Y.Z-dev.N` (publica, escaneia, assina; o `imagem.json` vai como artefato do run, sem Release); o `ci.yml` ganha o job `imagem-hotfix` (`:sha-<12>` em PR `hotfix/*` para a `main`, com Trivy e cosign); o `limpeza-ghcr.yml` apaga o `sha-` da PR fechada e guarda as 10 `-dev.*` mais novas, sem tocar em `vX.Y.Z`.
- Docs: a documentação do repositório volta a ser em pt-BR por padrão (decisão do dono de 06/11/2026, revertendo o ADR 0260; AT-766). `docs/business-rules/engine.md` sai do inglês e perde o `idioma_original: en` (âncoras `{#rn-NNN}`, refs de código e links intactos), `README.md` e `prompts/README.md` voltam ao pt-BR, o README ganha a seção "Repositórios do Brabo" e passa a citar a tag de contratos que o `scripts/baixar-contratos.sh` de fato usa (`v1.1.1-dev.3`), e o `CLAUDE.md` troca a regra de doc em inglês por pt-BR. O seeder de prompts é apontado no `brabo-infra`, onde ele mora.
- Depois que a pasta do projeto avança para a `main`, o engine pede à api para reiniciar o processo do app no lugar (AT-617, RN-1028): um reinício por rajada de merges (job único, atraso de 20 s), registrado como `app.restarted`, `app.restart_skipped` (`sem_app`) ou `app.restart_failed` (`motivo`, `exitCode`, nunca texto de log). Sem avanço, sem reinício; uma falha nunca faz a pasta voltar.
- A pasta do projeto também avança por fast-forward para a `main` no modo `runner` (AT-617, RN-1027): as mesmas recusas do caminho local, pelo canal `exec` do runner; com o runner desligado o worker registra `workspace.checkout_not_advanced` com `runner_offline`, e o avanço é reaplicado quando o runner entra e no `container.running`. A recusa de projeto legado agora cita `pnpm migrar-projeto-para-trunk`.
- **Quebra de compatibilidade:** o repositório do projeto é trunk. A branch de trabalho é a `main` (base do claim, base do worktree, alvo do `pr_open`, diff do gate, textos dos prompts); depois de cada merge nela, o evento de outbox `project.trunk_merged` faz o engine avançar a pasta do projeto (`container`/`mounted`) por fast-forward e registrar `workspace.checkout_advanced` ou `workspace.checkout_not_advanced` com o motivo. Projeto cuja `dev` está à frente da `main` recusa o claim até o script de migração da api rodar. RN-1021, RN-1023 (AT-617, engine).
- Ferramenta nova `retire_business_rule` para o Criativo e o PO: eles retiram sozinhos uma regra de negócio obsoleta, citando `replaced_by` ou `question_id`; as recusas da api voltam como texto, e as listas de regras que o engine monta a partir do log de eventos ignoram as regras retiradas. RN-1020 (AT-755).
- A mensagem de ambiente do agente permite `git fetch` e `git merge` no worktree da task e mantém proibidos o push e todo outro git (AT-754, RN-1019 revisa a RN-706). Ressalva conhecida: uma imagem de projeto sem `git` ainda responde `git: not found`.
- Toda mensagem `assistant` do turno agora guarda os próprios `thinkingBlocks` (não só a última), então o prefixo enviado ao provider só cresce e o cache de prompt da Anthropic segue servindo os agentes que raciocinam. RN-1013 (AT-749, engine).
- O PO acha o caminho para corrigir uma história `ready` (AT-752 parte A, RN-859/RN-874): as decisões do seu turno levam `questionId` e as histórias afetadas, a descrição de `complete_story` cobre o caso `ready` com `question_id`, e o prompt do PO a cita.
- O Dev Lead não cria mais uma task só para o relatório JUnit; o dev agent configura o reporter na primeira task de código do módulo, com saída em `.brabo-qa/junit.xml` ignorada pelo git. RN-1016 revisa a RN-996 (AT-750).
- `propose_execution_plan` recusa, antes de propor, uma task que cita rota que o contrato atual declara em outro módulo, nomeando o módulo dono e como corrigir (mover a task ou separar a parte de domínio com `create_task`). RN-1011 (AT-748, lane a).
- Uma task bloqueada por `report_blocked` agora acorda o Dev Lead pelo Wake, que pode pedir ao Arquiteto o contrato que falta com a ferramenta nova `pedir_ao_arquiteto` (`chat.message` durável de ator `dev-lead`); `declare_module_contracts` acorda o Dev Lead quando uma versão nova é publicada. RN-1012 (AT-748, ADR 0261).
- Conflito ao integrar a `dev` atual no claim não bloqueia mais a task: o merge fica em curso e a task vai para o agente com os arquivos conflitados e uma instrução fixada para resolver e rodar `git commit --no-edit`; `report_done` com o merge não resolvido (`MERGE_HEAD` ou marcadores) o aborta e bloqueia como antes, e `preservar_em` aborta um merge em curso antes do commit de WIP. RN-1010, revisa a RN-779 (AT-747).
- Docs: `THIRD_PARTY_NOTICES.md` agora está em inglês (AT-745). Ele vai dentro da imagem, então a cópia no `Dockerfile` e o conteúdo do aviso que os testes conferem (`ADR 0119`, o caminho na imagem, `checksums.txt`) não mudam.
- Contratos: `scripts/baixar-contratos.sh` passa a `v1.1.1-dev.3` (saída `tarefa-de-fundacao` do Dev Lead no `fluxo.yml`).
- `create_task` do Dev Lead manda `agentRole: "dev_lead"` no corpo de `POST /internal/sessions/:id/tasks`; o do PO segue sem o campo (a api assume `po`). O histórico da sessão deixa de atribuir ao PO a tarefa criada pelo Dev Lead. RN-1006 (AT-742).
- Dev Lead: ganha `create_task` (restrito à história cujo `moduleIds` contém o módulo), vê o `dependsOn` no module_map e o kickoff manda criar a tarefa de fundação do módulo de que outro depende antes do plano. RN-1006 (AT-742, ADR 0259).
- Perguntas em aberto: ferramenta `answer_open_question` nos quatro perguntadores (Criativo, PO, Arquiteto, Dev Lead) fecha a pergunta que o usuário respondeu pelo chat, só com resposta inequívoca; as perguntas abertas com `questionId` e sugestão chegam ao turno dos quatro. RN-1003 (AT-741).
- Dev Lead e `ToolLoop`: a chamada irmã que vem depois da pendente de aprovação recebe `tool` de recusa e `tool.result` `ok: false`; a retomada deixa de mandar `tool_use` sem `tool_result` (400 da Anthropic). RN-999 revisa RN-284 e RN-593 (AT-739).
- `politica.yml`: pins do `brabo-ci` sobem para `b030fbf` (dispensa da PR do bot, ADR 0255; AT-733).
- Release por tag da imagem `ghcr.io/viralabs-dev/brabo-engine` (AT-704): `carimbo.yml` (tag-release do brabo-ci) e `release.yml` (build, push por digest, Trivy sobre o digest, cosign keyless por digest com verify, `imagem.json` na Release). A 1ª tag final na `main` sai `v1.0.0`.

- `CLAUDE.md`: blocos cortados pelo teto de 40 mil caracteres (persistência e RBAC, runner, broker e containers) passam a regras de caminho em `.claude/rules/`, com o texto integral da fonte.

## v1.0.0 - 2026-11-05

Primeira versão, extraída do monorepo `daneiel/brabo` (EP-033, AT-697, ADR 0252) com o histórico dos caminhos.

- O app `apps/engine` foi para a raiz (com `docs/`), mais `prompts/` e `THIRD_PARTY_NOTICES.md`. `docker/engine/Dockerfile` virou `Dockerfile.dev` e `Dockerfile.prod` virou `Dockerfile`, ajustados ao repositório sozinho (Elixir 1.20.4 / OTP 29.1.1 sobre Alpine 3.24, ADR 0209).
- `contracts/` guarda `areas.json`, `fluxo.yml` e `docker-cli.ts` de `viralabs-dev/brabo-contracts` na tag `v1.0.0`; `scripts/baixar-contratos.sh` os baixa e o CI reprova divergência. Os testes que liam `packages/` passam a ler essa pasta.
- CI próprio (lint, `mix test --cover` com Postgres de serviço, piso de cobertura, build da imagem sem publicar) e política de PR pelo `brabo-ci`.
- Saíram do repositório: os golden-sets `qa_automacao_agent_golden_test.exs` e `rag_golden_test.exs` (com os `floor.json` e os aliases `golden_set.*`), que precisam do seed da api, e o teste de `diretorios_de_dependencia_test.exs` que lia `bootstrap-templates.ts` da api. Vão para o `brabo-qa` (AT-703).
- Lacuna: `lib/engine/agents/areas.ex` segue sendo gerado pela api (`gerar:areas`); a cópia fica aqui até a automação do `brabo-contracts` existir.
