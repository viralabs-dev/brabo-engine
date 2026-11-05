# brabo-engine

Engine of Brabo: Elixir/OTP + Phoenix (channels) + Oban (queues in Postgres) — agents, gates, sessions, runners. Part of the monorepo split (ADR 0252).

## Develop

Elixir 1.20.4 / OTP 29.1.1 (ADR 0209). Requires Postgres 16 with pgvector.

```sh
mix deps.get
POSTGRES_HOST=localhost POSTGRES_USER=brabo POSTGRES_PASSWORD=brabo mix test
```

The gate tests use `gitleaks`, `hadolint`, `yamllint` and `actionlint`; without them, these tests are excluded (CI requires all of them).

## Contracts

`contracts/` comes from `viralabs-dev/brabo-contracts` at tag `v1.0.0`. To update it: `scripts/baixar-contratos.sh <tag>`.

## Images

`Dockerfile` (production, `mix release`) and `Dockerfile.dev` (bind-mount of the repo at `/workspace`). App documentation is in `docs/`; prompts are in `prompts/`.

Permanent branches: `dev` and `main`; tags only by workflow.
