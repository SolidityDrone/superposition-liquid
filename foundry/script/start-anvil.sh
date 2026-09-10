#!/usr/bin/env bash
# Spin the anvil FORK like a normal node — full, un-suppressed output — and
# make the demo wallets' funds available (background worker: as soon as the
# node answers, it seeds ETH + tokens).
#
#   ./start-anvil.sh [base|arbitrum|ethereum]
#
# The user then runs their own forge scripts against the node, e.g.
#   forge script script/Deploy.s.sol --fork-url http://localhost:8545 --broadcast
# Ctrl+C stops the node (like a normal anvil).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

CHAIN="${1:-base}"
case "$CHAIN" in
  base)     PORT="${PORT:-8545}"; FORK_RPC="https://mainnet.base.org" ;;
  arbitrum) PORT="${PORT:-8546}"; FORK_RPC="https://arb1.arbitrum.io/rpc" ;;
  ethereum) PORT="${PORT:-8547}"; FORK_RPC="https://ethereum-rpc.publicnode.com" ;;
  *) die "unknown chain '$CHAIN'" ;;
esac
RPC="http://localhost:$PORT"

if cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; then
  log_warn "a node is already listening on :$PORT — killing it for a clean state"
  pkill -x anvil 2>/dev/null || true; sleep 2
fi

# ---- background worker: fund the demo wallets once the node answers ----------
(
  wait_for_anvil "$RPC"
  export RPC
  "$SCRIPT_DIR/fund.sh" "$CHAIN"
  echo -e "${BOLD}── wallets funded: run your forge scripts against $RPC ──${RESET}"
) > "/tmp/anvil-setup-$CHAIN.log" 2>&1 &

# ---- foreground: the anvil itself, like a normal node -------------------------
exec anvil --fork-url "$FORK_RPC" --port "$PORT"
