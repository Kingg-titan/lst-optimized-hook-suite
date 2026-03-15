#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPECTED="${1:-${EXPECTED_COMMITS:-}}"
ACTUAL="$(git rev-list --count HEAD)"

echo "[verify-commits] actual=$ACTUAL"

if [[ -z "$EXPECTED" ]]; then
  echo "[verify-commits] no expected count provided; pass-through mode"
  exit 0
fi

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "[verify-commits] mismatch: expected=$EXPECTED actual=$ACTUAL"
  exit 1
fi

echo "[verify-commits] count matches expected=$EXPECTED"
