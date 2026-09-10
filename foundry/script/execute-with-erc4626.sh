#!/usr/bin/env bash
# Terminal 2 - run the 'erc4626' scenario against a running anvil (base).
# Funds come from ./start-anvil.sh (or re-run ./fund.sh base to top up).
#
#   VERB=0 summary | VERB=1 default (balances+assertions) | VERB=2 stack traces
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."   # forge needs the foundry root
source "$SCRIPT_DIR/lib.sh"

SCEN="erc4626"
CHAIN="${1:-base}"
VERB="${VERB:-1}"

case "$VERB" in
  0) FORGE_V=""        ; FILTER='^(>>|SCENARIO|Error|revert)' ;;
  1) FORGE_V="-vv"     ; FILTER='^(>>|   \[ok\]|   maker|   quote|   swap|   LP|SCENARIO|assertion|Error|revert)' ;;
  2) FORGE_V="-vvvv"   ; FILTER='' ;;
  *) die "VERB must be 0, 1 or 2 (got $VERB)" ;;
esac

echo -e "${BOLD}══ Terminal 2 - scenario '$SCEN' on $CHAIN (RPC ${RPC:-http://localhost:$PORT}) - verbosity $VERB ══${RESET}"

if [ -n "$FILTER" ]; then
  SCENARIO="$SCEN" \
    forge script script/AnvilScenario.s.sol --fork-url "${RPC:-http://localhost:$PORT}" --broadcast --skip-simulation $FORGE_V 2>&1 \
    | tee /tmp/scenario-$SCEN.log \
    | grep -E "$FILTER"
else
  SCENARIO="$SCEN" \
    forge script script/AnvilScenario.s.sol --fork-url "${RPC:-http://localhost:$PORT}" --broadcast --skip-simulation $FORGE_V 2>&1 \
    | tee /tmp/scenario-$SCEN.log
fi

echo ""
if grep -q "SCENARIO PASS" /tmp/scenario-$SCEN.log; then
  echo -e "${GREEN}${BOLD}══ SCENARIO '$SCEN' PASS ══${RESET}"
else
  echo -e "${RED}${BOLD}══ SCENARIO '$SCEN' FAILED - full log: /tmp/scenario-$SCEN.log ══${RESET}"
  exit 1
fi
