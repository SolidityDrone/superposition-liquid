# Superposition-Liquid

**A 1inch Aqua liquidity position backed 100% by yield protocols — looking like a plain ETH/USDC pool to the outside world.**

Makers ship an ETH/USDC strategy on 1inch Aqua, but their capital never sits idle: it
lives inside a yield protocol (Aave, Morpho, Euler, Lido, Pendle, Stargate). Every fill
cycles capital atomically inside the swap transaction itself:

```
taker buys ETH (pays USDC)
  │
  ├─ preTransferOut hook    ──▶ JIT: withdraw/unwrap/redeem from the maker's
  │                            yield position → tokens land in the maker wallet
  ├─ default transfer       ──▶ Aqua delivers to the taker
  │
taker buys USDC (pays ETH)
  │
  └─ postTransferIn hook    ──▶ the received tokens are re-deployed into the
                               yield protocol for the maker, same transaction
```

The maker wallet only holds tokens for the duration of one transaction. Idle balance is
always **zero**: 100% of capital earns the backing protocol's yield **on top of swap fees**
on the same capital.

Built for ETHGlobal **ETHOnline 2026**. Bounties: **1inch Aqua** (primary, "Build an Aqua
App"), **Chainlink Data Feeds** (secondary).

---

## The idea in one table: five risk profiles, one AMM surface

The adapter layer is the product: any yield protocol plugs in per-maker, and the strategy
(the AMM program, the hooks, the Aqua position) does not change.

| Adapter | Capital sits in | Maker's yield | Status |
|---|---|---|---|
| `AaveV3Adapter` | aWETH/aUSDC | variable supply APY | shipped + fork-proven |
| `ERC4626Adapter` | any ERC-4626 vault (Morpho, Euler, …) | vault yield | shipped + fork-proven |
| `WstETHAdapter` | Lido wstETH (appreciating wrapper) | staking APY | shipped + fork-proven |
| `PendlePTAdapter` | Pendle PT (expired = 1:1 claim / active = fixed income) | **fixed APY** | shipped + fork-proven (both states) |
| `StargateAdapter` | Stargate V2 pool LP, staked | bridge reward stream | shipped + fork-proven |

Same AMM, same hooks, same position surface — the maker picks their risk profile by
pointing `MakerConfig` at an adapter.

## How it works

**The router** — a modified SwapVM redeploy (explicitly allowed by the 1inch bounty
rules; the only way to run custom instructions). It inherits the deployed v1.0.2 stack
and **appends three opcodes** at the end of the dispatch table (append-only, so all
existing opcodes keep their indices):

| Byte | Opcode | What it does |
|---|---|---|
| 34 | `YieldAdjustedRateXD` | scales the swap registers by `rate(now)/rate(ship)` from the lending protocol — quotes stay accurate in underlying terms while capital sits in yield tokens; the ship-time rate is baked into the immutable strategy args |
| 35 | `ChainlinkGuardXD` | MEV protection: reverts if the implied swap price deviates beyond a bound (default 2%) from the Chainlink reference, or if a feed is stale (per-feed staleness: stablecoin feeds update on ~12h heartbeats) |
| 36 | `MakerCapitalGuardXD` | makes `quote()` a complete fill-oracle: reverts unless an ACTUAL withdrawal of the delivery amount would succeed right now (simulated via the adapter: maker position AND protocol liquidity, not just `balanceOf`) |

**The hooks** — the router doubles as the maker-hooks target:

- `preTransferOut`: JIT-withdraws from the yield protocol into the maker wallet
  (withdraw / unwrap / redeem / unstake — protocol-specific); the default transfer then
  delivers to the taker. Both hooks are **direction-agnostic** (the 2D strategy trades
  both ways).
- `postTransferIn`: re-deploys the received tokens into the yield protocol for the maker
  (and stakes, where the protocol separates the two — Stargate).

**The invariants** (enforced by the design, tested):

- **real capital ≥ virtual balance** at all times: quoting against more than the
  yield-backed capital can cover only fails a fill, never oversells.
- **maker idle balance = 0** before, during and after every fill.
- **`quote() == swap()`** for the same state (the VM's core guarantee, extended by our
  opcodes — a passing quote is a fillability oracle; a failing quote returns the exact
  on-chain revert reason).

---

## Verification: 99 tests, including 7 real-protocol fork proofs

```
foundry/  →  forge test        # 99/99 green
```

| Layer | What it proves |
|---|---|
| `test/unit/` | TDD unit tests: every adapter against protocol-faithful mocks (Aave pool, MetaMorpho/Euler vaults, wstETH, Pendle PY-system, Stargate pool+staking), both custom opcodes, config |
| `test/unit/invariants/` | Fuzz (256 runs): across randomized fill sequences — idle capital stays 0, `real ≥ virtual`, `quote == swap` |
| `test/fork/BaseFork.t.sol` | **Base mainnet fork, zero mocks**: real Aqua registry, real Aave v3 (aWETH/aUSDC), real Chainlink feeds — full ship → quote → swap JIT cycle |
| `test/fork/BaseForkErc4626.t.sol` | **Real Morpho + Euler vaults** (Gauntlet WETH Core, Steakhouse Prime USDC, EVK eWETH-1): round-trips + full JIT cycle with capital 100% in Morpho shares |
| `test/fork/MainnetForkWstETH.t.sol` | **Real Lido wstETH + real Curve stETH/ETH pool** (Ethereum fork): staking rate ≈ 1.24 makes the yield opcode visibly work — full JIT cycle |
| `test/fork/ArbitrumForkPendle.t.sol` | **Real expired Pendle PT** (PT-aUSDC-27JUN2024, Arbitrum fork): fixed-income USDC side, redemption chain with zero swap legs |
| `test/fork/MainnetForkPendleActive.t.sol` | **Real ACTIVE Pendle PT-wstETH** (Ethereum fork): PT at the implied-yield discount, delivery through the market's AMM swap callback, rate from the PendlePYLpOracle TWAP |
| `test/fork/BaseForkStargate.t.sol` | **Real Stargate V2 pool + staking** (Base fork): USDC deposited AND staked, JIT unstake → redeem, credit-capped via the pool's own `redeemable()` |

Real-vault fork testing caught two bugs invisible in mocks: a unit mismatch (shipping
virtual balances in share counts while fill flows move underlying units — fixed with the
`rate(now)/rate(ship)` design) and Pendle's callback conventions (negative `ptToAccount`
= owe; callback only fires with non-empty `data`).

---

## Demo

```bash
cd foundry

# full E2E as a forge test (Base fork: real Aqua, Aave, Chainlink)
forge test --match-contract BaseForkTest -vvvv

# scripted walkthrough with per-step capital logs, both fill directions
anvil --fork-url https://mainnet.base.org --port 8545 &
forge script script/Demo.s.sol --rpc-url http://localhost:8545
```

`Demo.s.sol` prints the maker's capital state at every step (deploy → setup → ship →
fill #1 → fill #2): idle balances stay 0 throughout. Funding uses the `deal` cheatcode,
so it runs without `--broadcast` — every swap, deposit, withdrawal and fee still flows
through the real deployed contracts on the fork.

---

## Repo layout

```
foundry/
  src/
    SupercazzolaRouter.sol          # SwapVM fork + JIT hooks + custom opcode table
    config/MakerConfig.sol          # per-maker adapter configuration (msg.sender-owned)
    adapters/
      AaveV3Adapter.sol             # Aave v3 (v3.2 displayed-balance aware)
      ERC4626Adapter.sol            # generic: Morpho MetaMorpho, Euler v2, any 4626 vault
      WstETHAdapter.sol             # liquid staking: JIT unwrap + Curve swap leg
      pendle/PendlePTAdapter.sol    # fixed income: expired redemption / active AMM path
      stargate/StargateAdapter.sol  # bridge liquidity: pool LP, staked
      swappers/CurveStethSwapper.sol
    interfaces/                     # ILendingAdapter, AggregatorV3Interface
    opcodes/
      YieldAdjustedRateOpcode.sol   # byte 34: registers × rate(now)/rate(ship)
      ChainlinkGuardOpcode.sol      # byte 35: price deviation + staleness guard
      MakerCapitalGuardOpcode.sol   # byte 36: simulated-withdrawal fill oracle
      SupercazzolaOpcodes.sol       # AquaOpcodes table + the three appended opcodes
  script/
    BaseChain.s.sol                 # verified Base mainnet addresses
    Deploy.s.sol                    # deploys MakerConfig → adapter → router
    Demo.s.sol                      # one-shot fork walkthrough
  test/                             # unit + invariants + fork (see table above)
  lib/                              # submodules: swap-vm v1.0.2, aqua v1.0.0, aave-v3-core,
                                    # openzeppelin v5.4.0, solidity-utils 6.9.7, forge-std
docs/
  SPEC.md                           # full design + decision log (B1.1 … B10.3)
  pendle-adapter.md                 # Pendle deep-dive (both paths, on-chain gotchas)
  stargate-adapter.md               # Stargate deep-dive
  ROADMAP.md                        # what is not built yet, with design sketches
```

## Dependency versions

| Package | Pinned | Why |
|---|---|---|
| `1inch/swap-vm` | **v1.0.2** | matches the source the deployed router is built from (per 1inch guidance). The v1.0.2 diff only touches the Aqua protocol-fee opcodes (best-effort collection), which Superposition does not use |
| `1inch/aqua` | **v1.0.0** | latest tag; interface proven compatible with the live Base registry by the fork E2E |
| `openzeppelin/contracts` | **v5.4.0** | |
| `@1inch/solidity-utils` | **6.9.7** | matches swap-vm's dependency |
| `aave/aave-v3-core` | latest (interfaces only) | IPool/DataTypes |
| Solidity | **0.8.30** | same as swap-vm |

## Base addresses (verified on-chain, see `script/BaseChain.s.sol`)

| Contract | Address |
|---|---|
| Aqua registry | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` |
| Deployed SwapVM router (reference) | `0x111111338c5091E8440b67B168bAe16a668AC0De` |
| Aave v3 Pool | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| WETH / aWETH | `0x4200…0006` / `0xD4a0…8bb7` |
| USDC / aUSDC | `0x8335…2913` / `0x4e65…c0AB` |
| Morpho Gauntlet WETH Core | `0x6b13c060F13Af1fdB319F52315BbbF3fb1D88844` |
| Morpho Steakhouse Prime USDC | `0xBEEFE94c8aD530842bfE7d8B397938fFc1cb83b2` |
| Euler EVK eWETH-1 | `0x859160DB5841E5cfB8D3f144C6b3381A85A4b410` |
| Stargate V2 PoolUSDC / Staking | `0x27a16dc786820B16E5c9028b75B99F6f604b5d26` / `0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80` |
| Chainlink ETH/USD | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` |
| Chainlink USDC/USD | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` |

---

## Why these design choices (full decision log in [SPEC.md](SPEC.md))

- **B1.2 — hooks cannot skip the default transfer**: SwapVM always transfers after the
  pre-hook, so the design is "JIT-unwrap into the maker wallet, then let the default
  transfer deliver". Discovered by reading the source before designing around it.
- **B3.3/B3.4 — Chainlink for the guard, not for the rate**: no Chainlink feed exists for
  aToken rates, and Aave's own index is the only correct source. Data Feeds instead power
  a real MEV-protection opcode (deviation + staleness guard on the swap price).
- **B7.1 — Aave v3.2 changed the balance model**: on modern markets `aToken.balanceOf` is
  already index-accrued; the adapter handles both models generically.
- **B10.1 — Stargate LP is 1:1 static**: the yield is the reward stream (staking), not
  share appreciation; the staking leg ships with the adapter, and the JIT is verified
  instant in the source (no lock/cooldown).

## What is not built yet

See [docs/ROADMAP.md](docs/ROADMAP.md) — the off-chain resolver/indexer (making the
position discoverable by aggregators), UI, real deployment, Stargate reward claiming,
the wstETH re-stake leg, and the delta-neutral borrow profile (designed, needs
health-factor management). Each has enough design detail to be picked up directly.
