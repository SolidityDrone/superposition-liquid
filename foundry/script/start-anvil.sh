#!/usr/bin/env bash
# Spin the anvil FORK like a normal node and fund the demo wallets.
# Everything embedded — no helper scripts.
#
#   ./start-anvil.sh [base|arbitrum|ethereum]
#
# Then (Terminal 2):
#   export CHAIN=base
#   forge script script/DeployAndSetup.s.sol --fork-url http://localhost:8545 --broadcast
#   forge script script/base/AaveScenario.s.sol --fork-url http://localhost:8545 --broadcast
#
# Ctrl+C stops the node (like a normal anvil).
set -euo pipefail

CHAIN="${1:-base}"
case "$CHAIN" in
  base)     PORT="${PORT:-8545}"; FORK_RPC="https://mainnet.base.org" ;;
  arbitrum) PORT="${PORT:-8546}"; FORK_RPC="https://arb1.arbitrum.io/rpc" ;;
  ethereum) PORT="${PORT:-8547}"; FORK_RPC="https://ethereum-rpc.publicnode.com" ;;
  *) echo "unknown chain '$CHAIN'"; exit 1 ;;
esac
RPC="http://localhost:$PORT"
MAKER=0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7
TAKER=0x0376AAc07Ad725E01357B1725B5ceC61aE10473c
FUNDING_KEY=0x1c9f4a2f9c6b3d7e8a5f0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e

if cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; then
  echo "  ! a node is already on :$PORT — killing it"
  fuser -k "$PORT/tcp" 2>/dev/null || pkill -9 -x anvil 2>/dev/null || true
  sleep 2
fi

# background worker: fund once the node answers, then stay quiet
(
  waited=0
  until cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; do
    waited=$((waited + 1)); [ "$waited" -ge 120 ] && { echo "node did not come up"; exit 1; }
    sleep 1
  done

  hex() { python3 -c "print(f'{$1:064x}')"; }
  poke() { # token, mappingSlot, who, amount
    local key
    key=$(cast keccak "0x$(hex "0x${3#0x}")$(hex "$2")")
    cast rpc anvil_setStorageAt "$1" "$key" "0x$(hex "$4")" --rpc-url "$RPC" >/dev/null
  }
  eth() { cast rpc anvil_setBalance "$1" "0x$(python3 -c "print(f'{100000000000000000000:x}')")" --rpc-url "$RPC" >/dev/null; }

  eth "$MAKER"; eth "$TAKER"
  case "$CHAIN" in
    base)
      WETH=0x4200000000000000000000000000000000000006; USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
      poke "$WETH" 3 "$MAKER" 210000000000000000000   # exactly the Aave+Morpho deposits
      poke "$USDC" 9 "$MAKER" 530000000000            # Aave+Morpho+Stargate deposits
      poke "$USDC" 9 "$TAKER" 1000000000
      poke "$WETH" 3 "$TAKER" 1000000000000000000
      ;;
    arbitrum)
      USDC=0xaf88d065e77c8cC2239327C5EDb3A432268e5831
      WETH=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
      poke "$USDC" 9 "$MAKER" 20000000000
      poke "$USDC" 9 "$TAKER" 10000000000
      # arbitrum WETH is proxied: wrap REAL ETH with the funding key
      cast rpc anvil_setBalance "$(cast wallet address --private-key "$FUNDING_KEY")" "0x$(python3 -c "print(f'{250000000000000000000:x}')")" --rpc-url "$RPC" >/dev/null
      cast send "$WETH" "deposit()" --value 105000000000000000000 --private-key "$FUNDING_KEY" --rpc-url "$RPC" >/dev/null
      cast send "$WETH" "transfer(address,uint256)(bool)" "$MAKER" 105000000000000000000 --private-key "$FUNDING_KEY" --rpc-url "$RPC" >/dev/null
      cast send "$WETH" "deposit()" --value 2000000000000000000 --private-key "$FUNDING_KEY" --rpc-url "$RPC" >/dev/null
      cast send "$WETH" "transfer(address,uint256)(bool)" "$TAKER" 2000000000000000000 --private-key "$FUNDING_KEY" --rpc-url "$RPC" >/dev/null
      # seed the maker's expired-PT bag by probing the token's balance slot
      PT=0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c
      for S in $(seq 0 24); do
        poke "$PT" "$S" "$MAKER" 12000000000000000000000
        [ "$(cast call "$PT" "balanceOf(address)(uint256)" "$MAKER" --rpc-url "$RPC" 2>/dev/null || echo 0)" = "12000000000000000000000" ] && break
      done
      ;;
    ethereum)
      USDC=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
      USDT=0xdAC17F958D2ee523a2206206994597C13D831ec7
      poke "$USDC" 9 "$MAKER" 250000000000
      poke "$USDC" 9 "$TAKER" 10000000000
      # USDT has a non-standard storage layout: probe the balance slot
      for S in $(seq 0 24); do
        poke "$USDT" "$S" "$MAKER" 1000000000000   # 1,000,000 USDT
        [ "$(cast call "$USDT" "balanceOf(address)(uint256)" "$MAKER" --rpc-url "$RPC" 2>/dev/null || echo 0)" = "1000000000000" ] && break
      done
      for S in $(seq 0 24); do
        poke "$USDT" "$S" "$TAKER" 10000000000      # 10,000 USDT
        [ "$(cast call "$USDT" "balanceOf(address)(uint256)" "$TAKER" --rpc-url "$RPC" 2>/dev/null || echo 0)" = "10000000000" ] && break
      done
      PT=0xb253Eff1104802b97aC7E3aC9FdD73AecE295a2c   # PT-wstETH (active market)
      for S in $(seq 0 24); do
        poke "$PT" "$S" "$MAKER" 100000000000000000000
        [ "$(cast call "$PT" "balanceOf(address)(uint256)" "$MAKER" --rpc-url "$RPC" 2>/dev/null || echo 0)" = "100000000000000000000" ] && break
      done
      ;;
  esac
  echo "── wallets funded on $CHAIN — deploying + arming the stack ──"
  CHAIN="$CHAIN" forge script script/DeployAndSetup.s.sol \
    --fork-url "$RPC" --broadcast --skip-simulation 2>&1 | grep -E "ONCHAIN|deployed|setup|Error" || true
  echo "── ready: pick a scenario ──"
  echo "   forge script script/$CHAIN/AaveScenario.s.sol --fork-url $RPC --broadcast"

  # watchdog: fills consume the taker's payments — keep the wallets armed so
  # scenarios are re-runnable any number of times
  while true; do
    sleep 4
    case "$CHAIN" in
      base)
        poke 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 9 "$TAKER" 1000000000
        ;;
      arbitrum)
        poke 0xaf88d065e77c8cC2239327C5EDb3A432268e5831 9 "$TAKER" 10000000000
        ;;
      ethereum)
        poke 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 9 "$TAKER" 10000000000
        ;;
    esac
  done
) > "/tmp/anvil-setup-$CHAIN.log" 2>&1 &

exec anvil --fork-url "$FORK_RPC" --port "$PORT"
