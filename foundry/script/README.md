# Foundry scripts — per-chain scenario runner

Every scenario is a standalone `forge script` for one adapter, split by chain.
`script/start-anvil.sh <chain>` spins a funded anvil fork **and** deploys + arms
the stack, so a judge goes straight to a scenario.

```
script/
├── AnvilScenario.s.sol          # shared runner: per-scenario setup, setSides, ship, fills, asserts
├── DeployAndSetup.s.sol         # multi-chain: deploy config + router + ALL adapters, then arm
├── base/
│   ├── AaveScenario.s.sol          # Aave v3: 1000 USDC -> WETH, then reverse
│   ├── Erc4626Scenario.s.sol       # Morpho Gauntlet WETH / Steakhouse USDC vaults
│   └── StargateScenario.s.sol      # Stargate pool + staking: 0.05 WETH -> USDC
├── arbitrum/
│   └── PendleExpiredScenario.s.sol # PT-aUSDC expired: 1:1 redemption chain
└── ethereum/
    ├── PendleActiveScenario.s.sol       # PT-wstETH active: market AMM swap -> SY -> wstETH
    └── SuperpositionScenario.s.sol      # USDC/USDT one-sided hook buckets (ERC-1155 LP)
```

## The two-terminal flow

**Terminal 1 — the node** (one per chain; ports: base `8545`, arbitrum `8546`,
ethereum `8547`):

```bash
cd foundry/script
./start-anvil.sh base        # anvil in the FOREGROUND, full un-suppressed output
```

A background worker, as soon as the node answers, seeds the demo wallets (maker
`0xA11CE`, taker `0xB0B`), deploys the chain's full stack (artifact in
`deployments/supercazzola-<chain>.json`) and arms the maker (MAX approvals +
capital in every adapter). Wait for `── ready: pick a scenario ──`.
Ctrl+C stops the node.

**Terminal 2** — run any scenario as many times as you like (the worker keeps the
taker funded):

```bash
cd foundry
forge script script/base/AaveScenario.s.sol \
  --fork-url http://localhost:8545 --broadcast --skip-simulation
```

`DeployAndSetup.s.sol` stays runnable by hand (idempotent: it skips the deploy
when the stack is already live and just re-arms):

```bash
CHAIN=base forge script script/DeployAndSetup.s.sol \
  --fork-url http://localhost:8545 --broadcast --skip-simulation
```

## Per-chain command sheet

### Base (port 8545)

```bash
forge script script/base/AaveScenario.s.sol      --fork-url http://localhost:8545 --broadcast --skip-simulation
forge script script/base/Erc4626Scenario.s.sol   --fork-url http://localhost:8545 --broadcast --skip-simulation
forge script script/base/StargateScenario.s.sol  --fork-url http://localhost:8545 --broadcast --skip-simulation
```

- `AaveScenario`: taker sells 1000 USDC → ~0.397 WETH, then the reverse fill —
  capital cycles JIT through Aave, maker wallet stays idle-zero, the USDC side
  grows by fees + yield.
- `Erc4626Scenario`: same shape through Morpho Gauntlet WETH / Steakhouse USDC.
- `StargateScenario`: maker provides Stargate bridge liquidity (USDC deposited +
  staked); the fill JIT-unstakes → redeems to pay USDC for the taker's 0.05 WETH.

### Arbitrum (port 8546)

```bash
forge script script/arbitrum/PendleExpiredScenario.s.sol --fork-url http://localhost:8546 --broadcast --skip-simulation
```

- `PendleExpiredScenario`: the maker's USDC is backed by a REAL expired PT
  (PT-aUSDC-27JUN2024) — the JIT hook redeems PT → aUSDC → USDC through pure
  Pendle mechanics, no swap legs.

### Ethereum (port 8547)

```bash
forge script script/ethereum/PendleActiveScenario.s.sol --fork-url http://localhost:8547 --broadcast --skip-simulation
forge script script/ethereum/SuperpositionScenario.s.sol --fork-url http://localhost:8547 --broadcast --skip-simulation
```

- `PendleActiveScenario`: the maker locks a fixed yield with a REAL ACTIVE
  market (PT-wstETH, Dec 2027); the JIT delivery swaps PT on the market's AMM
  (callback pattern) then redeems SY → wstETH.
- `SuperpositionScenario`: the maker LPs USDC + USDT as one-sided buckets on the
  Superposition v4 hook (ERC-1155 LP, Aave yield) and rides a full JIT fill. The
  worker self-deploys the hook; see [docs/superposition-uni-adapter.md](../../docs/superposition-uni-adapter.md).

## Verbosity

```bash
forge script script/base/AaveScenario.s.sol \
  --fork-url http://localhost:8545 --broadcast --skip-simulation -vvvv
```

## Tests

The suite lives in `foundry/test/` — `unit/` (offline, 84 tests), `fork/`
(live-RPC integration, 8 tests) and `Baseline.t.sol` (1 test):

```bash
cd foundry

forge test                              # everything (fork tests need network)
forge test --match-path 'test/unit/*'   # offline: adapters, router, opcodes, invariants
forge test --match-path 'test/fork/*'   # live forks: Base, Arbitrum, Mainnet
forge test --match-test test_swap -vvvv # one test, full trace
```

- Fork tests read `RPC_URL_BASE` (default `BaseChain.RPC_URL`) for Base; Arbitrum
  and Mainnet use their public endpoints. `MainnetForkPendleActive` can fail with
  an archive-403 on free endpoints — override with a paid `--fork-url`.
- `forge test` runs against the `out/` artifacts — keep them fresh
  (`rm -rf out cache && forge build` after removing source files).

## Troubleshooting

- **Run each scenario on a fresh node** — scenarios ship an Aqua strategy with
  fixed balances, so re-shipping the same strategy on a dirty state reverts
  (`StrategiesMustBeImmutable`). Restart `start-anvil.sh`.
- **A scenario needs its chain's artifact** (`deployments/supercazzola-<chain>.json`):
  the worker writes it; run `DeployAndSetup.s.sol` first if you skipped the worker.
- **Stale artifacts** (`out/`, `cache/`) after removing source files make `forge
  script` panic with `type check failed for "offset (usize)"` — `rm -rf out cache`
  and rebuild.
- The scenario needs the artifact of its chain — run `DeployAndSetup.s.sol` first.
- A "SCENARIO ASSERTION FAILED" means the live fork drifted (prices moved) — the
  full trace is in the script output.
