# Changelog

## Unreleased

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
