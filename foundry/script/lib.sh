#!/usr/bin/env bash
# Shared helpers for the foundry script suite. Source me: source "$(dirname "$0")/lib.sh"
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\x1b[0;32m'; RED='\x1b[0;31m'; YELLOW='\x1b[0;33m'; BOLD='\x1b[1m'; DIM='\x1b[2m'; RESET='\x1b[0m'
step_no=0

log_head()  { echo -e "${CYAN}${BOLD}▶ $*${RESET}"; }
log_info()  { echo -e "  ${RESET}$*"; }
log_kv()    { echo -e "  ${DIM}$(printf '%-28s' "$1")${RESET} $2"; }
log_ok()    { echo -e "  ${GREEN}✔${RESET} $*"; }
log_err()   { echo -e "  ${RED}✗ $*${RESET}"; }
log_warn()  { echo -e "  ${YELLOW}!${RESET} $*"; }
die()       { log_err "$*"; exit 1; }

# Wait until the anvil at $RPC answers eth_chainId (up to ~60s).
wait_for_anvil() {
  local rpc="$1" i
  for i in $(seq 1 60); do
    if cast chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
      log_ok "anvil ready at $rpc (chain $(cast chain-id --rpc-url "$rpc"))"
      return 0
    fi
    sleep 1
  done
  die "anvil at $rpc did not come up after 60s"
}

# 64-char zero-padded hex of an integer/decimal string (bash printf overflows > 2^63).
hex64() { python3 -c "print(f'{$1:064x}')"; }

# Poke one ERC-20 balance mapping slot via the anvil RPC (no cheatcode exists on-chain).
poke_storage() { # token, slotIndex, who, amount
  local token="$1" slot="$2" who="$3" amount="$4"
  local key value
  key=$(cast keccak "0x$(hex64 "0x$(echo "$who" | sed 's/0x//' | tr 'A-F' 'a-f')")$(hex64 "$slot")")
  cast rpc anvil_setStorageAt "$token" "$key" "0x$(hex64 "$amount")" --rpc-url "$RPC" >/dev/null
}

# Read a token balance.
bal() { cast call "$1" "balanceOf(address)(uint256)" "$2" --rpc-url "$RPC" 2>/dev/null; }

# Seed `amount` of `token` to `who`: poke the configured mapping slot; if the
# slot is unknown/absent, probe candidate slots 0..12 until the balance sticks.
seed_token() {
  local token="$1" who="$2" amount="$3" slot="${4:-}"
  local i
  if [ -n "$slot" ]; then
    poke_storage "$token" "$slot" "$who" "$amount"
    return 0
  fi
  for i in $(seq 0 12); do
    poke_storage "$token" "$i" "$who" "$amount" 2>/dev/null || true
    if [ "$(bal "$token" "$who")" = "$amount" ]; then
      log_kv "seeded $token" "slot $i (auto-probed) -> $amount"
      return 0
    fi
  done
  die "could not find the balance storage slot for $token (probed 0..12)"
}

# Fund ETH for an account (anvil_setBalance).
fund_eth() {
  cast rpc anvil_setBalance "$1" "0x$(hex64 "${2:-100000000000000000000}")" --rpc-url "$RPC" >/dev/null
}

# Impersonate an account (anvil_impersonateAccount).
impersonate() { cast rpc anvil_impersonateAccount "$1" --rpc-url "$RPC" >/dev/null 2>&1 || true; }
