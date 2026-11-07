# brabo-engine

Engine do Brabo: Elixir/OTP + Phoenix (canais) + Oban (filas no Postgres) — agentes, gates, sessões e runners.

## Desenvolver

Elixir 1.20.4 / OTP 29.1.1 sobre Alpine (ADR 0209), as mesmas versões do `Dockerfile` e do CI. Precisa de Postgres 16 com pgvector.

```sh
mix deps.get
POSTGRES_HOST=localhost POSTGRES_USER=brabo POSTGRES_PASSWORD=brabo mix test
```

Os testes dos gates usam `gitleaks`, `hadolint`, `yamllint` e `actionlint`; sem eles, esses testes são excluídos (o CI exige todos).

## Contratos

`contracts/` (`areas.json`, `fluxo.yml`, `docker-cli.ts`) vem do [brabo-contracts](https://github.com/viralabs-dev/brabo-contracts) na tag fixada em `scripts/baixar-contratos.sh` (hoje `v1.1.1-dev.3`). Para atualizar: `scripts/baixar-contratos.sh <tag>`. O CI baixa de novo e reprova divergência.

## Imagens

`Dockerfile` (produção, `mix release`) e `Dockerfile.dev` (bind-mount do repositório em `/workspace`). O CI só constrói a imagem de produção; a imagem `ghcr.io/viralabs-dev/brabo-engine` é publicada pelo `release.yml` quando sai uma tag final (`vX.Y.Z`).

Documentação do app em `docs/` (regras de negócio em `docs/business-rules/engine.md`); templates de prompt em `prompts/`.

Branches permanentes: `dev` e `main`; tag só por workflow.

## Repositórios do Brabo

O Brabo é dividido em repositórios por camada (ADR 0252), e a documentação central está no [brabo](https://github.com/viralabs-dev/brabo) e em https://viralabs-dev.github.io/brabo/prd/.

- **Depende de:** [brabo-contracts](https://github.com/viralabs-dev/brabo-contracts) e [brabo-ci](https://github.com/viralabs-dev/brabo-ci).
- **É usado por:** [brabo](https://github.com/viralabs-dev/brabo), [brabo-infra](https://github.com/viralabs-dev/brabo-infra) e [brabo-qa](https://github.com/viralabs-dev/brabo-qa) (os golden-sets rodam dentro do engine).

| Repositório | Papel |
|---|---|
| [brabo](https://github.com/viralabs-dev/brabo) | Porta de entrada do produto: documentação, ADRs, `install.sh` e release do produto |
| [brabo-api](https://github.com/viralabs-dev/brabo-api) | API NestJS: domínio, banco e autenticação |
| [brabo-engine](https://github.com/viralabs-dev/brabo-engine) | Engine Elixir/OTP: agentes, gates, sessões e filas |
| [brabo-web](https://github.com/viralabs-dev/brabo-web) | Interface web em React |
| [brabo-runner](https://github.com/viralabs-dev/brabo-runner) | CLI que roda na máquina do usuário |
| [brabo-broker](https://github.com/viralabs-dev/brabo-broker) | Único processo com acesso ao socket do Docker |
| [brabo-contracts](https://github.com/viralabs-dev/brabo-contracts) | Contratos compartilhados entre os repositórios |
| [brabo-infra](https://github.com/viralabs-dev/brabo-infra) | Composes, Kubernetes e o `make dev` que sobe tudo |
| [brabo-ci](https://github.com/viralabs-dev/brabo-ci) | Workflows reutilizáveis e política de PR |
| [brabo-qa](https://github.com/viralabs-dev/brabo-qa) | Testes de ponta a ponta, golden-sets e smoke das imagens |
| [brabo-workspace](https://github.com/viralabs-dev/brabo-workspace) | Pasta-mãe que clona os repositórios lado a lado |

## Apoie

Se o projeto te ajuda, você pode [pagar um café no Ko-fi](https://ko-fi.com/daneiel).
