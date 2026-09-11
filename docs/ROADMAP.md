# Roadmap — what is not built yet, and what it would take

Everything shipped is in [README.md](../README.md); the design decisions and the two
adapter deep-dives are in [SPEC.md](../SPEC.md), [pendle-adapter.md](pendle-adapter.md)
and [stargate-adapter.md](stargate-adapter.md). This file documents what is NOT built
yet, ordered by value-for-effort, with enough design detail that any of them could be
picked up without re-deriving the context.

## 1. Off-chain resolver / indexer (the discovery layer)

**Gap**: today a taker must know the router address and the strategy to fill it. The
1inch routing infrastructure (aqua-api, dApp, FUSE) indexes strategies shipped to the
OFFICIAL router only — our redeploy (explicitly allowed by the bounty rules) is not
indexed by them, and Aqua itself ships with no public indexer (confirmed by ETHGlobal
Lisbon 2026 projects, who all built their own).

**Design** (a day of TypeScript):
1. Listen for Aqua `Shipped` events filtered by `app = SupercazzolaRouter` → extract
   `(maker, strategyHash, token0/token1, virtual balances)`.
2. Read `MakerConfig` per maker → adapter → live exchange rate.
3. Expose quotes by calling the router's `quote()` (the complete fill-oracle: AMM pricing
   + yield rate + Chainlink guard + simulated capital check — a passing quote is a strong
   fillability signal; a failing one returns the exact on-chain revert reason).
4. Surface the best strategy per direction/size; optionally a Fusion-style resolver that
   plugs into 1inch routing for the target pair.

**Demo value**: proves the core claim — *"the outside world sees a plain ETH/USDC pool"*
— by letting an aggregator discover and quote the position without any special access.

## 2. UI

A read-only dashboard is enough for the demo: position state (Aqua virtual balances,
lending-backed capital, accumulated revenue, current exchange rate), a quote widget, and
the capital-flow diagram. The scripts already print everything a UI needs
(`script/Demo.s.sol` logs the capital state at every step).

## 3. Real deployment on Base

`script/Deploy.s.sol` already deploys MakerConfig → AaveV3Adapter → router. What remains:
- Fund the maker EOA and run the full maker setup on Base mainnet (not just the fork).
- Verify the contracts on Basescan (flatcosource or standard verification).
- Note: strategies shipped against a real deployment are permanent until `dock()` — the
  demo can dock after showing the cycle.

## 4. Stargate: reward claiming + rewarder monitoring

Documented in [stargate-adapter.md](stargate-adapter.md#deferred-v02). Today the Base
USDC pool's rewarder is `address(0)` (verified on-chain), so the staked LP earns nothing
yet. When Stargate configures it:
- The rewards accrue to the adapter (per-maker attribution is already clean).
- Add a `claimRewards()` function routing `StargateStaking.claim([lp])` proceeds to the
  adapter owner, and optionally auto-restake the reward tokens if they are yield-bearing
  (e.g. staked-USDC variants).
- Monitor `rewarder(lp)` changes and the pool's `redeemable()` credit — if a chain's
  credit dries up (planner-driven), fills fail at quote time gracefully; the maker
  re-targets a healthier pool via the native Aqua `dock()` → `ship()` lifecycle.

## 5. wstETH: the re-stake leg

Documented in [pendle-adapter.md](pendle-adapter.md). The delivery leg (stETH→WETH via
Curve) is shipped; the reverse leg (WETH→stETH→wstETH for `depositFor` on the real
wrapper) needs the pool's payable ETH entry or a 1inch-routed leg, with `min_dy` bounded
by the Chainlink-derived price instead of the current 0 (same pattern as the
MakerCapitalGuardOpcode-style bounds from the reference price).

## 6. Delta-neutral borrow profile (designed, SPEC B8.2)

The maker locks ETH as collateral, borrows the AMM's ETH inventory (net ETH exposure ≈
0), repays debt in-kind on reverse fills, and swaps+repays via 1inch otherwise. Deferred
because it requires health-factor management (the borrow-vs-collateral ratio drifts and
needs monitoring/rebalancing) — an explicitly in-scope risk system, not just an adapter.

## 7. Multi-asset adapter (one adapter, both sides yield)

Today a 2D strategy has one adapter: one side is yield-backed, the other is passthrough
(revenue sits idle in the maker wallet). A composite adapter could route EACH side to its
own protocol (e.g. ETH side in wstETH via the swap leg, USDC side in Aave) — the interface
already takes `underlying` per call, so the composition is a dispatcher over a per-token
config. Also enables the wstETH maker to auto-deploy the USDC revenue into Aave instead
of idling it.

## 8. Pendle polish

- **Re-lock cadence**: the maker can `dock()` and re-`ship()` periodically to relock the
  fixed yield at the current implied rate — native Aqua lifecycle, zero extra code, worth
  a demo segment.
- **Oracle-bounded slippage**: replace the flat 1% buffer with a `min_sy` derived from the
  PendlePYLpOracle rate × (1 − tolerance) — same shape as the Chainlink guard.
- **Market health monitoring**: the active-PT path depends on the market's PT/SY
  liquidity; monitor it off-chain and pause re-targeting thin markets (same pattern as
  the Stargate credit monitor).

## Non-goals (explicit)

- Liquidation/health-factor management (until the borrow profile ships).
- Cross-chain strategy replication (each chain ships independently — native Aqua
  behavior; automation is a planner's job, not the router's).
- Yield arbitrage with YT (long-variable-yield exposure is orthogonal to the LP profile).
