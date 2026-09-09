# Superposition-Liquid

**A 1inch Aqua liquidity position that earns lending yield on 100% of its capital — while looking like a plain ETH/USDC AMM to the outside world.**

Makers ship an ETH/USDC strategy on 1inch Aqua, but their capital never sits idle: it lives
inside a lending protocol (Aave v3, or any ERC-4626 vault — Morpho, Euler). Every fill cycles
capital atomically through the lending protocol inside the swap transaction itself:

```
                    ┌─────────────────────────────────────────────────┐
 taker buys ETH ───▶│  preTransferOut hook:                           │
 (pays USDC)        │    withdraw WETH from Aave → maker wallet (JIT) │
                    │  default transfer: maker wallet → taker         │
                    │  postTransferIn hook:                           │
 taker buys USDC ◀──│    deposit received USDC back into Aave         │
 (pays WETH)        └─────────────────────────────────────────────────┘
```

The maker wallet only holds tokens for the duration of one transaction. Idle balance is
always **zero**: 100% of capital sits in yield-bearing tokens (aWETH/aUSDC, Morpho or Euler
vault shares), earning **lending APY on top of swap fees** on the same capital.

Built for ETHGlobal **ETHOnline 2026**. Bounties: **1inch Aqua** (primary, "Build an Aqua App"),
**Chainlink Data Feeds** (secondary).

---

## What exists today (shipped + tested)

### SupercazzolaRouter — a modified SwapVM redeploy
The 1inch bounty explicitly allows *"redeployments of a modified SwapVM contract"*, which is
the only way to run custom instructions. Our router:
- inherits the deployed v1.0.1 **SwapVM + AquaOpcodes** stack (same source the official router is built from)
- **appends two opcodes** at the end of the dispatch table (bytes 34/35, append-only so all
  existing opcodes keep their indices):
  - **`YieldAdjustedRateXD` (34)** — scales the swap registers by `rate(now)/rate(ship)` from
    the lending protocol, so quotes are always accurate in underlying terms while capital
    sits in yield tokens. The ship-time rate is baked into the immutable strategy args.
  - **`ChainlinkGuardXD` (35)** — MEV-protection guard: reverts if the implied swap price
    deviates more than a configurable bound (default 2%) from the Chainlink reference price,
    or if a feed is stale. Direction-agnostic: feeds are mapped to tokenIn/tokenOut by
    address, with per-feed staleness (stablecoin feeds legitimately update on ~12h heartbeats).
- doubles as the **maker hooks target**: `preTransferOut` JIT-unwraps from the lending
  protocol into the maker wallet (SwapVM's default transfer then delivers to the taker);
  `postTransferIn` redeploys received tokens into the lending protocol. Both hooks are
  **direction-agnostic** (the 2D strategy trades both ways).

### Lending adapters (pluggable per maker)
`MakerConfig` maps every maker to its own adapter — the maker picks the risk profile:
- **`AaveV3Adapter`** — Aave v3, aware of both balance models: legacy (yield accrues in the
  exchange rate) and **v3.2+ displayed balances** (yield accrues in `balanceOf`, rate ≡ 1).
  Generic rate formula: `scaledTotalSupply × liquidityIndex × WAD / (totalSupply × RAY)`.
- **`ERC4626Adapter`** — one implementation for *any* ERC-4626 vault: **Morpho (MetaMorpho),
  Euler v2**, and everything else 4626-compliant. Rate source is the vault itself
  (`convertToAssets`) — no oracle needed.

### The invariants (enforced by the JIT design, tested)
- **Real capital ≥ virtual balance** at all times: the strategy quotes against more than the
  lending-backed capital can only fail a fill, never oversell.
- **Maker idle balance = 0** before, during and after every fill.
- **`quote() == swap()`** for the same state (the VM's core guarantee, extended by our opcode).

---

## Verification: 57 tests, including real-protocol fork proofs

```
foundry/  →  forge test        # 57/57 green
```

| Layer | What it proves |
|---|---|
| `test/unit/` | TDD unit tests: adapters (mock Aave pool, mock MetaMorpho-style + Euler-style vaults), opcodes, config |
| `test/unit/invariants/` | Fuzz (256 runs): across randomized fill sequences — idle capital stays 0, `real ≥ virtual`, `quote == swap` |
| `test/fork/BaseFork.t.sol` | **Base mainnet fork, zero mocks**: real Aqua registry, real Aave v3 Pool (aWETH/aUSDC), real Chainlink ETH/USD + USDC/USD feeds — full ship → quote → swap JIT cycle |
| `test/fork/BaseForkErc4626.t.sol` | **Real Morpho + Euler vaults**: Gauntlet WETH Core, Steakhouse Prime USDC (MetaMorpho), EVK eWETH-1 (Euler v2) — round-trips plus a full JIT cycle with capital 100% in Morpho vault shares |

Real-vault fork testing caught a unit-mismatch bug invisible in mocks (shipping virtual
balances in share counts while Aqua fill flows move underlying units breaks `real ≥ virtual`
whenever the rate ≠ 1) — fixed with the `rate(now)/rate(ship)` design.

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
fill #1 → fill #2): idle balances stay 0 throughout, capital ends up where it started
(minus the sold ETH, plus the earned USDC), all of it earning lending APY.

Funding in the demo script uses the `deal` cheatcode, so it runs without `--broadcast`
(the script execution is real interaction with the fork — every swap, deposit, withdrawal
and fee flows through the real deployed contracts).

---

## Repo layout

```
foundry/
  src/
    SupercazzolaRouter.sol         # SwapVM fork + JIT hooks + custom opcode table
    config/MakerConfig.sol         # per-maker adapter configuration (msg.sender-owned)
    adapters/
      AaveV3Adapter.sol            # Aave v3 (v3.2 displayed-balance aware)
      ERC4626Adapter.sol           # generic: Morpho MetaMorpho, Euler v2, any 4626 vault
    interfaces/                    # ILendingAdapter, AggregatorV3Interface
    opcodes/
      YieldAdjustedRateOpcode.sol  # byte 34: registers × rate(now)/rate(ship)
      ChainlinkGuardOpcode.sol     # byte 35: price deviation + staleness guard
      SupercazzolaOpcodes.sol      # AquaOpcodes table + the two appended opcodes
  script/
    BaseChain.s.sol                # verified Base mainnet addresses
    Deploy.s.sol                   # deploys MakerConfig → adapter → router
    Demo.s.sol                     # one-shot fork walkthrough
  test/                            # unit + invariants + fork (see table above)
  lib/                             # submodules: swap-vm v1.0.1, aqua v1.0.0, aave-v3-core,
                                   # openzeppelin v5.4.0, solidity-utils 6.9.7, forge-std
SPEC.md                            # full design + decision log (B1.1 … B8.2)
```

## Dependency versions

| Package | Pinned | Why |
|---|---|---|
| `1inch/swap-vm` | **v1.0.2** | matches the source the deployed router is built from (per 1inch guidance). The v1.0.2 diff only touches the Aqua protocol-fee opcodes (best-effort collection) which Superposition does not use |
| `1inch/aqua` | **v1.0.0** | latest tag; interface proven compatible with the live Base registry by the fork E2E |
| `aave/aave-v3-core` | latest (interfaces only) | IPool/DataTypes |
| `openzeppelin/contracts` | **v5.4.0** | |
| `@1inch/solidity-utils` | **6.9.7** | matches swap-vm's dependency |
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
| Chainlink ETH/USD | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` |
| Chainlink USDC/USD | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` |

---

## Design decisions worth reading (full log in [SPEC.md](SPEC.md))

- **B1.2 — hooks cannot skip the default transfer**: SwapVM always transfers after the
  pre-hook, so the design is "JIT-unwrap into the maker wallet, then let the default
  transfer deliver". Discovered by reading the source before designing around it.
- **B3.3/B3.4 — Chainlink for the guard, not for the rate**: no Chainlink feed exists for
  aToken rates, and Aave's own index is the only correct source. Data Feeds instead power a
  real MEV-protection opcode (deviation + staleness guard).
- **B7.1 — Aave v3.2 changed the balance model**: on modern markets `aToken.balanceOf` is
  already index-accrued; the adapter handles both models generically.
- **B8.1 — one ERC-4626 adapter = many protocols**: Morpho and Euler both ship as 4626
  vaults; the generic adapter is proven against both on a mainnet fork.

## Out of scope (designed, deferred to v0.2)

- **Delta-neutral borrow profile** — maker locks ETH as collateral, borrows the AMM's ETH
  inventory (net ETH exposure ≈ 0), repays debt in-kind on reverse fills. Deferred because
  repaying WETH debt with received USDC needs an in-hook swap and health-factor management.
- **wstETH adapter** — rate comes from the token itself, but delivery needs a swap leg.
- **Health-factor management, off-chain resolver/indexing, UI** — resolver work (indexing
  `Shipped` events → ETH/USDC quotes for aggregators) is the natural next step to make the
  position visible to 1inch routing infrastructure.
