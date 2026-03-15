#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p shared/abis

copy_abi() {
  local src="$1"
  local out="$2"
  if [[ ! -f "$src" ]]; then
    echo "[export-abis] missing artifact: $src"
    exit 1
  fi
  jq '.abi' "$src" > "$out"
  echo "[export-abis] wrote $out"
}

copy_abi "out/LSTOptimizedHook.sol/LSTOptimizedHook.json" "shared/abis/LSTOptimizedHook.json"
copy_abi "out/YieldDistributionController.sol/YieldDistributionController.json" "shared/abis/YieldDistributionController.json"
copy_abi "out/MockRebasingLST.sol/MockRebasingLST.json" "shared/abis/MockRebasingLST.json"
copy_abi "out/MockNonRebasingLST.sol/MockNonRebasingLST.json" "shared/abis/MockNonRebasingLST.json"
