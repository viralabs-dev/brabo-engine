# Changelog

## Unreleased

- After the project folder advances to `main`, the engine asks the api to restart the app process in place (AT-617, RN-1028): one restart per burst of merges (unique job, 20 s delay), recorded as `app.restarted`, `app.restart_skipped` (`sem_app`) or `app.restart_failed` (`motivo`, `exitCode`, never log text). No advance, no restart; a failure never rolls the folder back.
- The project folder also fast-forwards to `main` in `runner` mode (AT-617, RN-1027): same refusals as the local path, through the runner `exec` channel; with the runner off the worker records `workspace.checkout_not_advanced` with `runner_offline`, and the advance is re-applied when the runner joins and on `container.running`. The legacy-project refusal now cites `pnpm migrar-projeto-para-trunk`.
- **Breaking:** the project's repository is trunk. The work branch is `main` (claim base, worktree base, `pr_open` target, gate diff, prompt texts); after each merge into it the outbox event `project.trunk_merged` makes the engine fast-forward the project folder (`container`/`mounted`) and record `workspace.checkout_advanced` or `workspace.checkout_not_advanced` with the reason. A project whose `dev` is ahead of `main` refuses the claim until the api migration script runs. RN-1021, RN-1023 (AT-617, engine).
- New tool `retire_business_rule` for the Criativo and the PO: they retire an obsolete business rule on their own, citing `replaced_by` or `question_id`; the api refusals come back as text, and the rule lists the engine builds from the event log ignore retired rules. RN-1020 (AT-755).
- The agent environment message allows `git fetch` and `git merge` in the task worktree and keeps push and every other git forbidden (AT-754, RN-1019 revises RN-706). Known caveat: a project image without `git` still answers `git: not found`.
- Every `assistant` message of the turn now keeps its own `thinkingBlocks` (not only the last), so the prefix sent to the provider only grows and the Anthropic prompt cache keeps serving reasoning agents. RN-1013 (AT-749, engine).
- The PO finds the way to correct a `ready` story (AT-752 part A, RN-859/RN-874): the decisions in its turn carry `questionId` and the affected stories, the `complete_story` description covers the `ready` case with `question_id`, and the PO prompt cites it.
- The Dev Lead no longer creates a task just for the JUnit report; the dev agent configures the reporter in the module's first code task, with output at `.brabo-qa/junit.xml` ignored by git. RN-1016 revises RN-996 (AT-750).
- `propose_execution_plan` refuses, before proposing, a task that cites a route the current contract declares in another module, naming the owner module and how to fix it (move the task or split the domain part with `create_task`). RN-1011 (AT-748, lane a).
- A task blocked by `report_blocked` now wakes the Dev Lead through the Wake, which can ask the Architect for the missing contract with the new `pedir_ao_arquiteto` tool (durable `chat.message` of actor `dev-lead`); `declare_module_contracts` wakes the Dev Lead when a new version is published. RN-1012 (AT-748, ADR 0261).
- A conflict integrating the current `dev` at claim no longer blocks the task: the merge stays in progress and the task goes to the agent with the conflicted files and a pinned instruction to resolve and `git commit --no-edit`; `report_done` with the merge unresolved (`MERGE_HEAD` or markers) aborts it and blocks as before, and `preservar_em` aborts a merge in progress before the WIP commit. RN-1010, revises RN-779 (AT-747).
- Docs: `THIRD_PARTY_NOTICES.md` is now in English (AT-745). It ships inside the image, so the `Dockerfile` copy and the notice contents that tests check (`ADR 0119`, the in-image path, `checksums.txt`) are unchanged.
- `README.md` and `prompts/README.md` are English-only (AT-745); the `prompts/*.md` templates stay in pt-BR, since they are product text.
- `docs/business-rules/engine.md` passa a ser só em inglês (`idioma_original: en`) e `docs/i18n/` (en, ru, zh-Hans) sai; a doc do repositório não tem mais traduções (AT-745).
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
