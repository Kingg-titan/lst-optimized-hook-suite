#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET_PERIPHERY_COMMIT="3779387"

echo "[bootstrap] init/update submodules"
git submodule sync --recursive
git submodule update --init --recursive

PERIPHERY_DIR="lib/uniswap-hooks/lib/v4-periphery"
CORE_DIR="lib/uniswap-hooks/lib/v4-core"

if [[ ! -d "$PERIPHERY_DIR/.git" && ! -f "$PERIPHERY_DIR/.git" ]]; then
  echo "[bootstrap] missing $PERIPHERY_DIR"
  exit 1
fi

if [[ ! -d "$CORE_DIR/.git" && ! -f "$CORE_DIR/.git" ]]; then
  echo "[bootstrap] missing $CORE_DIR"
  exit 1
fi

echo "[bootstrap] pinning v4-periphery to $TARGET_PERIPHERY_COMMIT"
git -C "$PERIPHERY_DIR" fetch --all --tags --prune
git -C "$PERIPHERY_DIR" checkout "$TARGET_PERIPHERY_COMMIT"

TARGET_CORE_COMMIT="$(git -C "$PERIPHERY_DIR" ls-tree "$TARGET_PERIPHERY_COMMIT" lib/v4-core | awk '{print $3}')"
if [[ -z "$TARGET_CORE_COMMIT" ]]; then
  echo "[bootstrap] could not resolve v4-core commit from v4-periphery@$TARGET_PERIPHERY_COMMIT"
  exit 1
fi

echo "[bootstrap] pinning v4-core to $TARGET_CORE_COMMIT"
git -C "$CORE_DIR" fetch --all --tags --prune
git -C "$CORE_DIR" checkout "$TARGET_CORE_COMMIT"

ACTUAL_PERIPHERY="$(git -C "$PERIPHERY_DIR" rev-parse --short HEAD)"
ACTUAL_CORE="$(git -C "$CORE_DIR" rev-parse --short HEAD)"

if [[ "$ACTUAL_PERIPHERY" != "$TARGET_PERIPHERY_COMMIT" ]]; then
  echo "[bootstrap] mismatch: expected v4-periphery=$TARGET_PERIPHERY_COMMIT got=$ACTUAL_PERIPHERY"
  exit 1
fi

EXPECTED_CORE_SHORT="${TARGET_CORE_COMMIT:0:7}"
if [[ "$ACTUAL_CORE" != "$EXPECTED_CORE_SHORT" ]]; then
  echo "[bootstrap] mismatch: expected v4-core=$EXPECTED_CORE_SHORT got=$ACTUAL_CORE"
  exit 1
fi

echo "[bootstrap] OK: v4-periphery=$ACTUAL_PERIPHERY v4-core=$ACTUAL_CORE"
