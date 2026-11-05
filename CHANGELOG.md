# Changelog

## Unreleased

- Release por tag da imagem `ghcr.io/viralabs-dev/brabo-engine` (AT-704): `carimbo.yml` (tag-release do brabo-ci) e `release.yml` (build, push por digest, Trivy sobre o digest, cosign keyless por digest com verify, `imagem.json` na Release). A 1ª tag final na `main` sai `v1.0.0`.

- `CLAUDE.md`: blocos cortados pelo teto de 40 mil caracteres (persistência e RBAC, runner, broker e containers) passam a regras de caminho em `.claude/rules/`, com o texto integral da fonte.

## v1.0.0 - 2026-11-05

Primeira versão, extraída do monorepo `daneiel/brabo` (EP-033, AT-697, ADR 0252) com o histórico dos caminhos.

- O app `apps/engine` foi para a raiz (com `docs/`), mais `prompts/` e `THIRD_PARTY_NOTICES.md`. `docker/engine/Dockerfile` virou `Dockerfile.dev` e `Dockerfile.prod` virou `Dockerfile`, ajustados ao repositório sozinho (Elixir 1.20.4 / OTP 29.1.1 sobre Alpine 3.24, ADR 0209).
- `contracts/` guarda `areas.json`, `fluxo.yml` e `docker-cli.ts` de `viralabs-dev/brabo-contracts` na tag `v1.0.0`; `scripts/baixar-contratos.sh` os baixa e o CI reprova divergência. Os testes que liam `packages/` passam a ler essa pasta.
- CI próprio (lint, `mix test --cover` com Postgres de serviço, piso de cobertura, build da imagem sem publicar) e política de PR pelo `brabo-ci`.
- Saíram do repositório: os golden-sets `qa_automacao_agent_golden_test.exs` e `rag_golden_test.exs` (com os `floor.json` e os aliases `golden_set.*`), que precisam do seed da api, e o teste de `diretorios_de_dependencia_test.exs` que lia `bootstrap-templates.ts` da api. Vão para o `brabo-qa` (AT-703).
- Lacuna: `lib/engine/agents/areas.ex` segue sendo gerado pela api (`gerar:areas`); a cópia fica aqui até a automação do `brabo-contracts` existir.
