#!/usr/bin/env bash
# Baixa de `viralabs-dev/brabo-contracts`, na TAG fixada, os arquivos que os testes do engine leem.
# Uso: scripts/baixar-contratos.sh [tag]. O CI roda e confere `git diff --exit-code contracts/`.
set -euo pipefail
tag="${1:-v1.0.0}"
cd "$(dirname "$0")/.."
base="https://raw.githubusercontent.com/viralabs-dev/brabo-contracts/${tag}/packages"
curl -fsSL "$base/contracts/areas.json" -o contracts/areas.json
curl -fsSL "$base/contracts/fluxo.yml" -o contracts/fluxo.yml
curl -fsSL "$base/docker-port/src/docker-cli.ts" -o contracts/docker-cli.ts
