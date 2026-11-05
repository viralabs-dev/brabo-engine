# brabo-engine

Engine do Brabo: Elixir/OTP + Phoenix (canais) + Oban (filas no Postgres) — agentes, gates, sessões, runners. Parte da separação do monorepo (ADR 0252).

## Desenvolver

Elixir 1.20.4 / OTP 29.1.1 (ADR 0209). Precisa de Postgres 16 com pgvector.

```sh
mix deps.get
POSTGRES_HOST=localhost POSTGRES_USER=brabo POSTGRES_PASSWORD=brabo mix test
```

Os testes dos gates usam `gitleaks`, `hadolint`, `yamllint` e `actionlint`; sem eles, esses testes são excluídos (o CI exige todos).

## Contratos

`contracts/` vem do `viralabs-dev/brabo-contracts` na tag `v1.0.0`. Para atualizar: `scripts/baixar-contratos.sh <tag>`.

## Imagens

`Dockerfile` (produção, `mix release`) e `Dockerfile.dev` (bind-mount do repo em `/workspace`). Documentação do app em `docs/`; prompts em `prompts/`.

Branches permanentes: `dev` e `main`; tag só por workflow.
