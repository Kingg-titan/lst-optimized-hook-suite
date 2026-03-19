#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source scripts/env.sh
load_env

PRIVATE_KEY_RESOLVED="$(resolve_private_key)"
RPC_URL_RESOLVED="$(resolve_rpc_url)"
POOL_MANAGER_RESOLVED="$(resolve_pool_manager)"
EXPLORER_TX_BASE="$(resolve_explorer_tx_base)"
EXPECTED_CHAIN_ID="${SEPOLIA_CHAIN_ID:-1301}"
TESTNET_GAS_PRICE_WEI="${TESTNET_GAS_PRICE_WEI:-1000000000}"
LIFECYCLE_COOLDOWN_SECONDS="${LIFECYCLE_COOLDOWN_SECONDS:-5}"
LIFECYCLE_HYSTERESIS_SECONDS="${LIFECYCLE_HYSTERESIS_SECONDS:-2}"
LIFECYCLE_ADVANCE_TXS="${LIFECYCLE_ADVANCE_TXS:-30}"

if [[ "$LIFECYCLE_ADVANCE_TXS" -lt 20 ]]; then
  echo "[demo-testnet] lifecycle advance tx count too low ($LIFECYCLE_ADVANCE_TXS); using 30 for reliable cooldown expiry proof"
  LIFECYCLE_ADVANCE_TXS=30
fi

export PRIVATE_KEY="$PRIVATE_KEY_RESOLVED"
export SEPOLIA_PRIVATE_KEY="$PRIVATE_KEY_RESOLVED"
export RPC_URL_BASE_SEPOLIA="$RPC_URL_RESOLVED"
export POOL_MANAGER="$POOL_MANAGER_RESOLVED"
export POOL_MANAGER_ADDRESS="$POOL_MANAGER_RESOLVED"
export MINT_DEMO_SUPPLY="${MINT_DEMO_SUPPLY:-false}"
export TRY_POOL_INITIALIZE="${TRY_POOL_INITIALIZE:-false}"
export LIFECYCLE_COOLDOWN_SECONDS
export LIFECYCLE_HYSTERESIS_SECONDS
export LIFECYCLE_ADVANCE_TXS

if [[ -z "${OWNER_ADDRESS:-}" ]]; then
  OWNER_ADDRESS="$(cast wallet address --private-key "$PRIVATE_KEY_RESOLVED")"
  export OWNER_ADDRESS
  upsert_env_var "OWNER_ADDRESS" "$OWNER_ADDRESS"
fi

CHAIN_ID_ACTUAL="$(cast chain-id --rpc-url "$RPC_URL_RESOLVED")"
if [[ "$CHAIN_ID_ACTUAL" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "[demo-testnet] chain id mismatch: expected=$EXPECTED_CHAIN_ID actual=$CHAIN_ID_ACTUAL"
  exit 1
fi

echo "[phase 0/6] preflight"
echo "[context] rpc=$RPC_URL_RESOLVED"
echo "[context] chain_id=$CHAIN_ID_ACTUAL"
echo "[context] pool_manager=$POOL_MANAGER_RESOLVED"
echo "[context] owner=$OWNER_ADDRESS"
echo "[context] explorer_tx_base=$EXPLORER_TX_BASE"
echo "[context] gas_price_wei=$TESTNET_GAS_PRICE_WEI"
echo "[context] lifecycle_cooldown_seconds=$LIFECYCLE_COOLDOWN_SECONDS"
echo "[context] lifecycle_advance_txs=$LIFECYCLE_ADVANCE_TXS"

tmp_deploy="$(mktemp)"
tmp_config="$(mktemp)"
tmp_lifecycle="$(mktemp)"
tmp_local_demo="$(mktemp)"
trap 'rm -f "$tmp_deploy" "$tmp_config" "$tmp_lifecycle" "$tmp_local_demo"' EXIT

need_deploy=0
for v in CONTROLLER_ADDRESS HOOK_ADDRESS MOCK_REBASING_LST_ADDRESS MOCK_NON_REBASING_LST_ADDRESS; do
  if [[ -z "${!v:-}" ]]; then
    need_deploy=1
  fi
done

print_tx_urls_from_broadcast() {
  local label="$1"
  local broadcast_file="$2"
  local found=0
  local tx=""

  if [[ ! -f "$broadcast_file" ]]; then
    echo "[$label] broadcast file not found: $broadcast_file"
    return
  fi

  while IFS= read -r tx; do
    [[ -z "$tx" ]] && continue
    found=1
    echo "[$label] tx=$tx"
    echo "[$label] url=$(tx_url "$tx")"
  done < <(jq -r '.transactions[].hash // empty' "$broadcast_file")

  if [[ "$found" -eq 0 ]]; then
    echo "[$label] no tx hash found in broadcast file"
  fi
}

print_lifecycle_phase_tx_summary() {
  local broadcast_file="$1"
  local tx=""

  if [[ ! -f "$broadcast_file" ]]; then
    echo "[lifecycle-phase] broadcast file not found: $broadcast_file"
    return
  fi

  echo "[lifecycle-phase] tx summary (phase-level proof)"

  tx="$(jq -r '.transactions[13].hash // empty' "$broadcast_file")"
  [[ -n "$tx" ]] && echo "[lifecycle-phase] normal_swap_before=$tx" && echo "[lifecycle-phase] normal_swap_before_url=$(tx_url "$tx")"

  tx="$(jq -r '.transactions[15].hash // empty' "$broadcast_file")"
  [[ -n "$tx" ]] && echo "[lifecycle-phase] normal_swap_after=$tx" && echo "[lifecycle-phase] normal_swap_after_url=$(tx_url "$tx")"

  tx="$(jq -r '.transactions[16].hash // empty' "$broadcast_file")"
  [[ -n "$tx" ]] && echo "[lifecycle-phase] rebase_tx=$tx" && echo "[lifecycle-phase] rebase_tx_url=$(tx_url "$tx")"

  tx="$(jq -r '.transactions[18].hash // empty' "$broadcast_file")"
  [[ -n "$tx" ]] && echo "[lifecycle-phase] constrained_swap_before=$tx" && echo "[lifecycle-phase] constrained_swap_before_url=$(tx_url "$tx")"

  tx="$(jq -r '.transactions[22].hash // empty' "$broadcast_file")"
  [[ -n "$tx" ]] && echo "[lifecycle-phase] oversized_swap_blocked=$tx" && echo "[lifecycle-phase] oversized_swap_blocked_url=$(tx_url "$tx")"

  tx="$(jq -r '.transactions[54].hash // empty' "$broadcast_file")"
  [[ -n "$tx" ]] && echo "[lifecycle-phase] post_cooldown_before=$tx" && echo "[lifecycle-phase] post_cooldown_before_url=$(tx_url "$tx")"

  tx="$(jq -r '.transactions[56].hash // empty' "$broadcast_file")"
  [[ -n "$tx" ]] && echo "[lifecycle-phase] post_cooldown_after=$tx" && echo "[lifecycle-phase] post_cooldown_after_url=$(tx_url "$tx")"

  tx="$(jq -r '.transactions[18].hash // empty' "$broadcast_file")"
  [[ -n "$tx" ]] && echo "[lifecycle-phase] yield_delta_recorded_on=$tx" && echo "[lifecycle-phase] yield_delta_recorded_on_url=$(tx_url "$tx")"
}

parse_logged_address() {
  local label="$1"
  local log_file="$2"
  grep -E "^[[:space:]]*$label[[:space:]]+0x[0-9a-fA-F]{40}" "$log_file" | tail -n1 | grep -Eo "0x[0-9a-fA-F]{40}" || true
}

wait_for_tx() {
  local tx_hash="$1"
  local attempts="${2:-45}"
  local i=0

  while (( i < attempts )); do
    if cast receipt "$tx_hash" --rpc-url "$RPC_URL_RESOLVED" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done

  echo "[demo-testnet] tx not mined after $attempts attempts: $tx_hash"
  return 1
}

wait_for_stable_account_nonce() {
  local min_nonce="$1"
  local attempts="${2:-45}"
  local i=0

  while (( i < attempts )); do
    local latest_nonce
    local pending_nonce

    latest_nonce="$(cast nonce "$OWNER_ADDRESS" --rpc-url "$RPC_URL_RESOLVED" --block latest)"
    pending_nonce="$(cast nonce "$OWNER_ADDRESS" --rpc-url "$RPC_URL_RESOLVED" --block pending)"

    if [[ "$latest_nonce" -ge "$min_nonce" && "$pending_nonce" -eq "$latest_nonce" ]]; then
      return 0
    fi

    sleep 2
    i=$((i + 1))
  done

  echo "[demo-testnet] account nonce did not stabilize at or above $min_nonce"
  return 1
}

if [[ "$need_deploy" -eq 1 ]]; then
  echo "[phase 1/6] deploy suite to Unichain Sepolia"
  forge script script/10_DeployLSTSuite.s.sol:DeployLSTSuite \
    --rpc-url "$RPC_URL_RESOLVED" \
    --private-key "$PRIVATE_KEY_RESOLVED" \
    --with-gas-price "$TESTNET_GAS_PRICE_WEI" \
    --slow \
    --broadcast -vvv | tee "$tmp_deploy"

  CONTROLLER_ADDRESS="$(parse_logged_address "controller" "$tmp_deploy")"
  HOOK_ADDRESS="$(parse_logged_address "hook" "$tmp_deploy")"
  MOCK_REBASING_LST_ADDRESS="$(parse_logged_address "mockRebasingLST" "$tmp_deploy")"
  MOCK_NON_REBASING_LST_ADDRESS="$(parse_logged_address "mockNonRebasingLST" "$tmp_deploy")"

  if [[ -z "$CONTROLLER_ADDRESS" || -z "$HOOK_ADDRESS" || -z "$MOCK_REBASING_LST_ADDRESS" || -z "$MOCK_NON_REBASING_LST_ADDRESS" ]]; then
    echo "[demo-testnet] failed to parse one or more deployed addresses from forge output"
    exit 1
  fi

  TOKEN_A="$MOCK_REBASING_LST_ADDRESS"
  TOKEN_B="$MOCK_NON_REBASING_LST_ADDRESS"

  upsert_env_var "CONTROLLER_ADDRESS" "$CONTROLLER_ADDRESS"
  upsert_env_var "HOOK_ADDRESS" "$HOOK_ADDRESS"
  upsert_env_var "MOCK_REBASING_LST_ADDRESS" "$MOCK_REBASING_LST_ADDRESS"
  upsert_env_var "MOCK_NON_REBASING_LST_ADDRESS" "$MOCK_NON_REBASING_LST_ADDRESS"
  upsert_env_var "TOKEN_A" "$TOKEN_A"
  upsert_env_var "TOKEN_B" "$TOKEN_B"

  echo "[phase 1/6] deployed addresses saved to .env"
  print_tx_urls_from_broadcast "deploy" "broadcast/10_DeployLSTSuite.s.sol/${CHAIN_ID_ACTUAL}/run-latest.json"
else
  CONTROLLER_ADDRESS="${CONTROLLER_ADDRESS}"
  HOOK_ADDRESS="${HOOK_ADDRESS}"
  MOCK_REBASING_LST_ADDRESS="${MOCK_REBASING_LST_ADDRESS}"
  MOCK_NON_REBASING_LST_ADDRESS="${MOCK_NON_REBASING_LST_ADDRESS}"
  TOKEN_A="${TOKEN_A:-$MOCK_REBASING_LST_ADDRESS}"
  TOKEN_B="${TOKEN_B:-$MOCK_NON_REBASING_LST_ADDRESS}"
  echo "[phase 1/6] using existing deployment addresses from .env"
fi

export CONTROLLER_ADDRESS
export HOOK_ADDRESS
export MOCK_REBASING_LST_ADDRESS
export MOCK_NON_REBASING_LST_ADDRESS
export TOKEN_A
export TOKEN_B
export POOL_FEE="${POOL_FEE:-3000}"
export TICK_SPACING="${TICK_SPACING:-60}"

echo "[phase 2/6] configure pool/controller parameters"
forge script script/11_ConfigPool.s.sol:ConfigPool \
  --rpc-url "$RPC_URL_RESOLVED" \
  --private-key "$PRIVATE_KEY_RESOLVED" \
  --with-gas-price "$TESTNET_GAS_PRICE_WEI" \
  --slow \
  --broadcast -vvv | tee "$tmp_config"
print_tx_urls_from_broadcast "config" "broadcast/11_ConfigPool.s.sol/${CHAIN_ID_ACTUAL}/run-latest.json"

POOL_ID="$(grep -E "^[[:space:]]*poolId[[:space:]]+0x[0-9a-fA-F]{64}" "$tmp_config" | tail -n1 | grep -Eo "0x[0-9a-fA-F]{64}" || true)"
if [[ -n "$POOL_ID" ]]; then
  echo "[phase 2/6] pool_id=$POOL_ID"
fi

echo "[phase 3/6] user perspective: index baseline and rebase tx"
INDEX_BEFORE="$(cast call "$MOCK_REBASING_LST_ADDRESS" "index()(uint256)" --rpc-url "$RPC_URL_RESOLVED")"
echo "[user] index_before=$INDEX_BEFORE"

REBASE_NONCE="$(cast nonce "$OWNER_ADDRESS" --rpc-url "$RPC_URL_RESOLVED" --block pending)"
REBASE_TX="$(
  cast send "$MOCK_REBASING_LST_ADDRESS" "rebaseByBps(uint16)" 100 \
    --private-key "$PRIVATE_KEY_RESOLVED" \
    --rpc-url "$RPC_URL_RESOLVED" \
    --gas-price "$TESTNET_GAS_PRICE_WEI" \
    --nonce "$REBASE_NONCE" \
    --json | jq -r '.transactionHash'
)"
echo "[user] rebase_tx=$REBASE_TX"
echo "[user] rebase_tx_url=$(tx_url "$REBASE_TX")"
wait_for_tx "$REBASE_TX"
wait_for_stable_account_nonce "$((REBASE_NONCE + 1))"

INDEX_AFTER="$(cast call "$MOCK_REBASING_LST_ADDRESS" "index()(uint256)" --rpc-url "$RPC_URL_RESOLVED")"
echo "[user] index_after=$INDEX_AFTER"

echo "[phase 4/6] protocol proof: onchain lifecycle tx sequence"
forge script script/12_RunLifecycleTxDemo.s.sol:RunLifecycleTxDemo \
  --rpc-url "$RPC_URL_RESOLVED" \
  --private-key "$PRIVATE_KEY_RESOLVED" \
  --with-gas-price "$TESTNET_GAS_PRICE_WEI" \
  --skip-simulation \
  --non-interactive \
  --slow \
  --broadcast -vvv | tee "$tmp_lifecycle"
LIFECYCLE_BROADCAST_FILE="broadcast/12_RunLifecycleTxDemo.s.sol/${CHAIN_ID_ACTUAL}/run-latest.json"
print_tx_urls_from_broadcast "lifecycle" "$LIFECYCLE_BROADCAST_FILE"
print_lifecycle_phase_tx_summary "$LIFECYCLE_BROADCAST_FILE"

echo "[phase 5/6] protocol proof: run deterministic lifecycle simulation locally"
forge test --match-test testDemoLifecycleSummary -vv | tee "$tmp_local_demo"

echo "[phase 6/6] summary"
echo "[summary] controller=$CONTROLLER_ADDRESS"
echo "[summary] hook=$HOOK_ADDRESS"
echo "[summary] mock_rebasing_lst=$MOCK_REBASING_LST_ADDRESS"
echo "[summary] mock_non_rebasing_lst=$MOCK_NON_REBASING_LST_ADDRESS"
echo "[summary] token_a=$TOKEN_A"
echo "[summary] token_b=$TOKEN_B"
echo "[summary] .env updated at $ROOT_DIR/.env"
