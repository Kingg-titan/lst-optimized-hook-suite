#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "missing .env (copy from .env.example)"
  exit 1
fi

source .env

if [[ -z "${RPC_URL_BASE_SEPOLIA:-}" || -z "${PRIVATE_KEY:-}" ]]; then
  echo "set RPC_URL_BASE_SEPOLIA and PRIVATE_KEY in .env"
  exit 1
fi

forge script script/10_DeployLSTSuite.s.sol:DeployLSTSuite \
  --rpc-url "$RPC_URL_BASE_SEPOLIA" \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvv
