# Foundry scripts — per-chain scenario runner

Every scenario is a standalone `forge script` for one adapter, split by chain.
Run against a **funded anvil fork**: `script/start-anvil.sh <chain>`
spins the node and seeds the demo wallets' ETH + tokens.

```
script/
├── AnvilScenario.s.sol      # shared logic: approvals, deploy, setSides, ship, fills, logs
├── Deploy.s.sol             # multi-chain: deploys config + router + ALL adapters of the chain
├── base/
│   ├── AaveScenario.s.sol          # Aave v3: 1000 USDC -> WETH, then reverse
│   ├── Erc4626Scenario.s.sol       # Morpho Gauntlet WETH / Steakhouse USDC vaults
│   └── StargateScenario.s.sol      # Stargate pool + staking: 0.05 WETH -> USDC
├── arbitrum/
│   └── PendleExpiredScenario.s.sol # PT-aUSDC expired: 1:1 redemption chain
└── ethereum/
    └── PendleActiveScenario.s.sol  # PT-wstETH active: market AMM swap -> SY -> wstETH
```

## The two-terminal flow

**Terminal 1 — the node** (one per chain; ports: base `8545`, arbitrum `8546`,
ethereum `8547`):

```bash
cd foundry/script
./start-anvil.sh base        # anvil in the FOREGROUND, full un-suppressed output
```

A background worker seeds the demo wallets (maker `0xA11CE`, taker `0xB0B`)
with ETH and tokens as soon as the node answers. Ctrl+C stops the node.

**Terminal 2** — your own forge scripts, in any order:

```bash
cd foundry

# 1) deploy once per chain: config + router + EVERY adapter
CHAIN=base forge script script/Deploy.s.sol \
  --fork-url http://localhost:8545 --broadcast --skip-simulation

# 2) run any scenario against the deployed stack
forge script script/base/AaveScenario.s.sol \
  --fork-url http://localhost:8545 --broadcast --skip-simulation
```

## Per-chain command sheet

### Base (port 8545)

```bash
CHAIN=base forge script script/Deploy.s.sol --fork-url http://localhost:8545 --broadcast --skip-simulation
forge script script/base/AaveScenario.s.sol      --fork-url http://localhost:8545 --broadcast --skip-simulation
forge script script/base/Erc4626Scenario.s.sol   --fork-url http://localhost:8545 --broadcast --skip-simulation
forge script script/base/StargateScenario.s.sol  --fork-url http://localhost:8545 --broadcast --skip-simulation
```

- `AaveScenario`: taker sells 1000 USDC → 0.397 WETH, then the reverse fill —
  capital cycles JIT through Aave, maker wallet stays idle-zero, the USDC side
  grows by fees + yield.

### Arbitrum (port 8546)

```bash
CHAIN=arbitrum forge script script/Deploy.s.sol --fork-url http://localhost:8546 --broadcast --skip-simulation
forge script script/arbitrum/PendleExpiredScenario.s.sol --fork-url http://localhost:8546 --broadcast --skip-simulation
```

- `PendleExpiredScenario`: the maker's USDC is backed by a REAL expired PT
  (PT-aUSDC-27JUN2024) — the JIT hook redeems PT → aUSDC → USDC through pure
  Pendle mechanics, no swap legs.

### Ethereum (port 8547)

```bash
CHAIN=ethereum forge script script/Deploy.s.sol --fork-url http://localhost:8547 --broadcast --skip-simulation
forge script script/ethereum/PendleActiveScenario.s.sol --fork-url http://localhost:8547 --broadcast --skip-simulation
```

- `PendleActiveScenario`: the maker locks a fixed yield with a REAL ACTIVE
  market (PT-wstETH, Dec 2027); the JIT delivery swaps PT on the market's AMM
  (callback pattern) then redeems SY → wstETH.

## Verbosity

Every scenario script respects the forge verbosity flags — add `-vv` for
console logs, `-vvvv` for full stack traces:

```bash
forge script script/base/AaveScenario.s.sol \
  --fork-url http://localhost:8545 --broadcast --skip-simulation -vvvv
```

## Top-ups and troubleshooting

- Funds are consumed by the fills — top the wallets back up any time:
  `script/fund.sh <chain>` (idempotent).
- The scenario needs the deployment artifact of its chain
  (`deployments/supercazzola-<chain>.json`) — run `Deploy.s.sol` first.
- The anvil node log lives at `/tmp/anvil-<chain>.log`.
- A "SCENARIO ASSERTION FAILED" means the live fork drifted (prices moved)
  or an approval is missing — the full log is in the executor's output.
