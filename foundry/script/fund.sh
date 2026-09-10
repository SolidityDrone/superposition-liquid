#!/usr/bin/env bash
# Fund the demo wallets (maker 0xA11CE, taker 0xB0B) with ETH + tokens.
# Idempotent: safe to run before every scenario.
#   ./fund.sh [base|arbitrum|ethereum]
# RPC is taken from the env (exported by start-anvil.sh worker) or defaults.
source "$(dirname "$0")/lib.sh"

CHAIN="${1:-base}"
RPC="${RPC:-http://localhost:8545}"

MAKER=0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7
TAKER=0x0376AAc07Ad725E01357B1725B5ceC61aE10473c

case "$CHAIN" in
  base)
    WETH=0x4200000000000000000000000000000000000006; USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
    fund_eth "$MAKER" 100000000000000000000;  fund_eth "$TAKER" 100000000000000000000
    seed_token "$WETH" "$MAKER" 105000000000000000000 3
    seed_token "$USDC" "$MAKER" 262500000000 9
    seed_token "$USDC" "$TAKER" 1000000000 9
    seed_token "$WETH" "$TAKER" 1000000000000000000 3
    log_ok "base wallets funded"
    ;;
  arbitrum)
    USDC=0xaf88d065e77c8cC2239327C5EDb3A432268e5831; WETH=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
    fund_eth "$MAKER" 100000000000000000000;  fund_eth "$TAKER" 100000000000000000000
    seed_token "$USDC" "$MAKER" 20000000000 9
    seed_token "$USDC" "$TAKER" 10000000000 9
    # arbitrum WETH is a proxied token with a shifted storage layout: the
    # honest way to fund it is WRAPPING REAL ETH (maker + taker hold ETH)
    python3 script/wrap.py "$RPC" "$WETH" 0xA11CE 99000000000000000000
    python3 script/wrap.py "$RPC" "$WETH" 0xB0B 1500000000000000000
    # the PT side: impersonate the market (the biggest expired-PT holder) and
    # move the maker's fixed-income position
    cast rpc anvil_impersonateAccount 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5 --rpc-url "$RPC" >/dev/null
    cast rpc anvil_setBalance 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5 0x1BC16D674EC80000 --rpc-url "$RPC" >/dev/null # gas for the impersonated transfer
    cast send 0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c "transfer(address,uint256)(bool)" "$MAKER" 12000000000 --unlocked --from 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5 --rpc-url "$RPC" >/dev/null
    log_ok "arbitrum wallets funded"
    ;;
  ethereum)
    USDC=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    PT=0xb253Eff1104802b97aC7E3aC9FdD73AecE295a2c   # PT-wstETH (active market)
    fund_eth "$MAKER" 100000000000000000000;  fund_eth "$TAKER" 100000000000000000000
    seed_token "$USDC" "$MAKER" 250000000000 9
    seed_token "$PT" "$MAKER" 100000000000000000000     # slot auto-probed
    seed_token "$USDC" "$TAKER" 10000000000 9
    log_ok "ethereum wallets funded"
    ;;
  *) die "unknown chain '$CHAIN'" ;;
esac
