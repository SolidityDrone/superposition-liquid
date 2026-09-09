# StargateAdapter — design notes

`src/adapters/stargate/StargateAdapter.sol` — the bridge-liquidity maker profile.

This file preserves the full context of the Stargate V2 integration, including the
on-chain facts discovered during development.

## What it does

The maker's capital sits in a **Stargate V2 pool, staked** — the maker provides the
liquidity the protocol uses for cross-chain swaps and earns the protocol's reward stream.
The JIT hooks unstake + redeem just-in-time to deliver the underlying, atomically inside
the swap.

## On-chain mechanics (verified against the real contracts, Sep 2026)

Contracts on Base (Stargate V2, from docs.stargate.finance + verified):
- **StargatePoolUSDC**: `0x27a16dc786820B16E5c9028b75B99F6f604b5d26`
  - LP token: `0x53983F31E8E0D0c3Fd0b8d85654989A1336317d7` ("S*USDC", via `lpToken()` —
    note: the getter is `lpToken()`, NOT `lp()`; `lp` is internal)
  - `deposit(receiver, amountLD)`: instant, mints LP 1:1 with the underlying
  - `redeem(amountLD, receiver)`: instant, burns LP 1:1 from the CALLER (no approval
    needed for own tokens), sends underlying — **BUT reverts via `decreaseCredit` if the
    pool's local credit is insufficient**
  - `redeemable(owner)`: view returning `min(local credit, LP balance of owner)`;
    `redeemable(address(0))` = the pool-wide instant-credit cap — this is the JIT oracle
  - `token()`: the underlying (USDC)
  - Numbers at dev time: TVL ~37.9k USDC, instant credit ~30.8k USDC (small pool on Base;
    the Arbitrum pool is bigger — fork target is flexible)
- **StargateStaking**: `0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80`
  - `deposit(IERC20 lp, uint256 amount)`: pulls LP from msg.sender (transferFrom)
  - `withdraw(IERC20 lp, uint256 amount)`: **INSTANT** — verified in source: pure
    accounting + rewarder settlement + `safeTransfer` in the same tx. No lock, no
    cooldown, no unbonding anywhere.
  - `claim(IERC20[] lpTokens)`: reward claim, goes to msg.sender
  - `rewarder(lp)` on Base = **address(0)** today: rewards are not live on the Base USDC
    pool yet. The staking leg is mechanically proven and future-proof; rewards start when
    Stargate configures the rewarder, and they accrue to the ADAPTER — one adapter per
    maker (MakerConfig) keeps per-maker reward attribution clean.

## Flows

```
depositFor (postTransferIn hook):
  pull underlying from maker -> pool.deposit (LP 1:1 to adapter)
  -> staking.deposit (LP staked; rewards accrue to the adapter)

withdrawTo (preTransferOut hook):
  staking.withdraw (INSTANT: LP back to the adapter + auto-claim settlement)
  -> pool.redeem (burns LP 1:1, sends underlying — credit-capped)
  -> deliver EXACT amountOut to recipient, surplus (none in practice) to maker
```

## Key design points

1. **The JIT constraint is the pool's local credit** — the planner moves liquidity between
   the pool's cash and the bridging OFT; only the cash side ("credit") supports instant
   redemptions. `maxWithdrawable` = `min(staked position, pool-wide credit)` via the
   pool's own `redeemable()` view → over-limit fills fail at QUOTE time with
   `MakerCapitalInsufficient`, never mid-delivery.
2. **The adapter tracks its own staked counter** (`staked`) — it is the only depositor of
   itself, so internal accounting is exact without relying on staking views.
3. **LP is 1:1 static** (mint/burn both amountLD): no share appreciation. The yield comes
   from the reward stream (staking), not from the LP token price.
4. **Passthrough** for foreign strategy sides (e.g. the ETH side): rate 1, no-op hooks.

## Implementation gotchas (bit us once)

- The LP getter is `lpToken()` on StargateBase — `lp` is internal.
- `Pool.redeem` burns from `msg.sender` (the adapter) — the adapter must hold the LP
  before redeeming, hence the unstake MUST complete first (same-tx, instant ✓).
- `StargateStaking.withdraw` auto-settles rewards via the rewarder callback
  (`onUpdate`) on every deposit/withdraw — claims need no separate flow.

## Test evidence

| Test | Proves |
|---|---|
| `test/unit/StargateAdapter.t.sol` (9) | deposit+stake, unstake+redeem+deliver, credit cap, maxWithdrawable = min(credit, position), passthrough |
| `test/fork/BaseForkStargate.t.sol` | REAL StargatePoolUSDC + REAL StargateStaking on a Base fork: full ship -> quote -> swap; deposit delta verified on the real staking; JIT unstake -> redeem delivers USDC; invariants hold |

## Deferred (v0.2+)

- Reward claiming UX (the rewards accrue to the adapter; a `claimRewards()` admin
  function or per-maker reward routing can be added — the MultiRewarder claim flows
  through `StargateStaking.claim`).
- If Stargate's planner tightens the credit on a chain, fills on that chain fail at
  quote time (graceful) — the maker would re-target a healthier pool (dock -> ship).
