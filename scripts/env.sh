#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "[env] missing .env"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$ENV_FILE"
}

resolve_private_key() {
  if [[ -n "${PRIVATE_KEY:-}" ]]; then
    printf "%s" "$PRIVATE_KEY"
    return
  fi
  if [[ -n "${SEPOLIA_PRIVATE_KEY:-}" ]]; then
    printf "%s" "$SEPOLIA_PRIVATE_KEY"
    return
  fi
  echo "[env] missing PRIVATE_KEY or SEPOLIA_PRIVATE_KEY"
  exit 1
}

resolve_rpc_url() {
  local candidates=()

  if [[ -n "${RPC_URL_BASE_SEPOLIA:-}" ]]; then
    candidates+=("$RPC_URL_BASE_SEPOLIA")
  fi
  if [[ -n "${unichain_SEPOLIA_RPC_URL:-}" ]]; then
    candidates+=("$unichain_SEPOLIA_RPC_URL")
  fi
  if [[ -n "${SEPOLIA_RPC_URL:-}" ]]; then
    candidates+=("$SEPOLIA_RPC_URL")
  fi
  candidates+=("https://sepolia.unichain.org")

  local rpc=""
  for rpc in "${candidates[@]}"; do
    if cast chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
      printf "%s" "$rpc"
      return
    fi
  done

  echo "[env] no reachable Unichain Sepolia RPC found in configured candidates"
  exit 1
}

resolve_pool_manager() {
  if [[ -n "${POOL_MANAGER:-}" ]]; then
    printf "%s" "$POOL_MANAGER"
    return
  fi
  if [[ -n "${POOL_MANAGER_ADDRESS:-}" ]]; then
    printf "%s" "$POOL_MANAGER_ADDRESS"
    return
  fi
  echo "[env] missing POOL_MANAGER or POOL_MANAGER_ADDRESS"
  exit 1
}

resolve_explorer_tx_base() {
  if [[ -n "${UNICHAIN_SEPOLIA_EXPLORER_TX_BASE:-}" ]]; then
    printf "%s" "$UNICHAIN_SEPOLIA_EXPLORER_TX_BASE"
    return
  fi
  printf "%s" "https://sepolia.uniscan.xyz/tx/"
}

upsert_env_var() {
  local key="$1"
  local value="$2"
  local tmp_file="${ENV_FILE}.tmp"

  awk -v k="$key" -v v="$value" '
    BEGIN { replaced = 0 }
    $0 ~ "^" k "=" {
      print k "=" v
      replaced = 1
      next
    }
    { print }
    END {
      if (replaced == 0) {
        print k "=" v
      }
    }
  ' "$ENV_FILE" > "$tmp_file"

  mv "$tmp_file" "$ENV_FILE"
}

tx_url() {
  local tx_hash="$1"
  local base
  base="$(resolve_explorer_tx_base)"
  printf "%s%s" "$base" "$tx_hash"
}
