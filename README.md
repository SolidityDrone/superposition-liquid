<p align="center">
  <img src="app/public/logo.png" alt="Superposition-Liquid" width="160" />
</p>

# Superposition-Liquid

**A meta-layer for 1inch Aqua / SwapVM: appended opcodes + maker hooks — not a new pricing curve. It plugs into any of them, so liquidity whose virtual units are yield-bearing tokens behaves like a plain ETH/USDC pool.**

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
| `SuperpositionUniAdapter` | [Superposition](docs/superposition-uni-adapter.md) v4 hook buckets (USDC/USDT, ERC-1155 LP) | Aave yield + v4 fees | shipped + fork-proven (Ethereum) |

Same AMM, same hooks, same position surface — the maker picks their risk profile by
pointing `MakerConfig` at an adapter.

## Architecture

**Superposition does not implement new pricing curves.** It is a meta-layer on
top of SwapVM: two composable layers that sit above any SwapVM strategy —
**capital adapters** (JIT withdraw/deposit hooks backing liquidity with
yield-bearing protocols) and **meta-opcodes** (oracle-anchored guards and
balance adjustments that compose with any pricing opcode). The pricing curve
is explicitly out of scope: makers ship `xyk`, curved, flat-price or custom
curves, and Superposition wraps around all of them without modifying them.

```
        Meta-Opcodes        (oracle guards, yield-rate scaling, capital checks)
              ↓
   [Any SwapVM pricing opcode - xyk, curved, flat, custom]
              ↓
        Capital Adapters    (Aave, Morpho/Euler, Stargate, Pendle, Lido)
              ↓
        Maker's wallet      (always in yield-bearing tokens, never idle)
```

### Layer 1 — Capital Adapters

Every maker configures, per token, which protocol holds their capital — a
one-registry lookup the hooks perform at fill time:

```solidity
struct SideConfig {
    address underlying;   // e.g. WETH, USDC
    address adapter;      // the protocol holding THIS side's capital
    AdapterKind kind;     // AaveV3 | ERC4626 | Stargate | PendlePT | SuperpositionUniHook
    bool autoManaged;     // JIT-deploy on receive, JIT-withdraw on send
}
```

| Adapter | Protocol | Capital held |
|---|---|---|
| `AaveV3Adapter` | Aave v3 | aTokens (`aWETH`, `aUSDC`) — supply APY |
| `ERC4626Adapter` | Morpho (MetaMorpho), Euler, any ERC-4626 vault | vault shares — vault yield |
| `StargateAdapter` | Stargate v2 | LP tokens staked in the pool's staking — bridge fees + rewards |
| `PendlePTAdapter` | Pendle | PT tokens — fixed yield (expired = 1:1 redemption, active = AMM exit) |
| `WstETHAdapter` | Lido (branch `adapter-in-out-config`) | `wstETH` — staking yield, with a Curve swap leg |
| `SuperpositionUniAdapter` | Superposition (Uniswap v4 hook) | one-sided ERC-1155 bucket shares — Aave yield + v4 fees |

The adapters are **pull-less**: the router executes each adapter's `pullPlan`
(token, exact count, destination) with its **own** allowance — the maker
approves the router once per token, and switching protocols never re-approves.
`withdraw(...)` burns the shares already pulled (Aave withdraw, 4626 redeem,
Stargate unstake+redeem, Pendle redeem/swap); `deposit(...)` deploys the
received revenue straight into the protocol, minting the maker's shares.

### Layer 2 — Meta-Opcodes

Custom SwapVM opcodes appended to the dispatch table (append-only — every
existing opcode keeps its index). They are **curve-agnostic**: they run
before or after the pricing opcode and adjust context, gate execution, or
scale balances — they never replace pricing logic.

| Opcode | What it does |
|---|---|
| `YieldAdjustedRateXD` | scales the swap registers by `rate(now)/rate(ship)` — quotes stay accurate in underlying terms while capital sits in yield tokens; adapters are resolved from the maker's registry, the ship-time rate is baked into the program |
| `MakerCapitalGuardXD` | makes `quote()` a complete fill-oracle: reverts unless an ACTUAL withdrawal of the delivery amount would succeed right now (maker position AND protocol liquidity) |

All three compose with any pricing opcode — `_xycSwapXD`, `_curvedSwapXD`,
flat-price, or a third-party curve dropped into the same program.

### Layer 3 — Hook Orchestration

The router is both the modified SwapVM executor **and** the maker-hooks
target. Inside one atomic fill:

```
preTransferOut  → pullPlan (exact yield-token count, buffered per protocol)
                → adapter.withdraw   → real tokens ready → taker
[Aqua transfers: maker ⇄ taker]
postTransferIn  → router pulls the received tokens to the adapter
                → adapter.deposit    → capital immediately redeployed
```

The invariants (enforced by the design, tested): **real capital ≥ virtual
balance** (over-quoting only fails a fill, never oversells), **maker idle
balance = 0** around every fill, and **`quote() == swap()`** — a passing
quote is a fillability oracle, a failing one returns the exact revert reason.

### What Superposition does NOT do

- **No AMM curves.** It implements no pricing math — it wraps any SwapVM curve.
- **No pricing logic.** Price discovery is entirely the strategy program's.
- **No swap routing.** Discovery and routing stay with 1inch's resolver network;
  Superposition ships an open off-chain resolver as a demo, not infrastructure.
- **No custody.** Capital lives in the maker's wallet or in the protocol the
  maker chose — the adapter only moves tokens inside the maker's own fill.

### Income streams

A maker earns three independent streams simultaneously:

1. **Adapter yield** — Aave supply APY, ERC-4626 vault returns, Stargate
   bridge rewards, Pendle fixed yield (whatever the configured protocol pays).
2. **Swap fees** — the maker's fee opcode takes basis points of every fill
   (0.3% flat in the demo).
3. **Side deployment** — fill revenue is immediately re-deployed into the
   receiving side's own protocol, so *both* sides of the position keep
   accruing. Additional streams (e.g. an LP-position adapter earning range
   fees) fit the same `SideConfig` registry without touching the router.

---

## Verification: 103 tests, including 7 real-protocol fork proofs

```
foundry/  →  forge test        # 103/103 green
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
| `test/fork/BaseForkMixedAdapters.t.sol` | **One maker, TWO protocols** (Base fork): WETH capital in Aave + USDC capital in a Morpho vault — the per-token registry end to end |

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

## Testnet support

Chain configuration files for public testnets are in `foundry/script/`:

| Testnet | Chain ID | Config file | RPC |
|---|---|---|---|
| Ethereum Sepolia | 11155111 | `SepoliaChain.s.sol` | `https://ethereum-sepolia.publicnode.com` |
| Base Sepolia | 84532 | `BaseSepoliaChain.s.sol` | `https://sepolia.base.org` |
| Arbitrum Sepolia | 421614 | `ArbitrumSepoliaChain.s.sol` | `https://sepolia-rollup.arbitrum.io/rpc` |

**Adapter availability per testnet:**

| Adapter | Ethereum Sepolia | Base Sepolia | Arbitrum Sepolia |
|---|---|---|---|
| AaveV3Adapter | ✅ | ✅ (WETH only) | ❌ |
| StargateAdapter | ✅ | ❌ | ❌ |
| PendlePTAdapter | ❌ | ❌ | ❌ |
| ERC4626Adapter (Morpho/Euler) | ❌ | ❌ | ❌ |
| WstETHAdapter | ❌ | ❌ | ❌ |

Aqua registry + SwapVM router use the **same vanity addresses** as mainnet on all
three testnets. Morpho, Euler, Pendle, and wstETH have no public testnet
deployments (permissionless — deploy your own).

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
      MakerCapitalGuardOpcode.sol   # byte 36: simulated-withdrawal fill oracle
      SupercazzolaOpcodes.sol       # AquaOpcodes table + the two appended opcodes
  script/
    base/ arbitrum/ ethereum/       # per-chain live scenarios (one forge script per adapter)
    AnvilScenario.s.sol             # scenario base contract: approvals, deploy, setSides, ship, fills
    Deploy.s.sol                    # multi-chain: deploys config + router + EVERY adapter of the chain
    Demo.s.sol                      # one-shot fork walkthrough
    start-anvil.sh / fund.sh / lib.sh   # funded anvil in two commands, per chain
    base|arbitrum|ethereum/execute-with-*.sh  # scenario shortcuts (VERB=0/1/2)
  test/                             # unit + invariants + fork (see table above)
  lib/                              # submodules: swap-vm v1.0.2, aqua v1.0.0, aave-v3-core,
                                    # openzeppelin v5.4.0, solidity-utils 6.9.7, forge-std
docs/
  SPEC.md                           # full design + decision log (B1.1 … B10.3)
  ADDRESSES.md                      # all addresses: mainnet + testnets
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

## Base addresses (verified on-chain, see `script/BaseChain.s.sol` + `docs/ADDRESSES.md`)

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
