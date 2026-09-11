# SuperpositionUniAdapter — design notes

`src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol` — the
yield-bearing limit-order maker profile, built on the **Superposition** Uniswap v4 hook.

> **Original hook repository:** <https://github.com/SolidityDrone/superposition-hook-uni-v4>
> The hook source is vendored here as the git submodule `foundry/lib/superposition-hook`
> (pinned commit `70651c6`) and compiled unmodified.

This file preserves the full context of the integration: how the hook works, why the
adapter is shaped the way it is, the exact JIT data flow, and the on-chain facts we
discovered while building it.

---

## 1. What Superposition is (the venue)

`SuperpositionHook` is a Uniswap v4 concentrated-liquidity hook that keeps **100% of
pooled capital in Aave v3 between swaps**. Its pool liquidity is *virtual*: between swaps
the pool holds zero real tokens, and `beforeSwap`/`afterSwap` materialize the recorded
tick ranges as real v4 liquidity for the duration of a swap, then unwind it and re-supply
everything to Aave.

Ownership is tracked **per tick range** (a *bucket*), and each bucket's claim
(`c0` = token0 amount, `c1` = token1 amount) is updated by per-bucket swap PnL and by a
per-token, pro-rata distribution of Aave yield. A bucket that sits entirely on one side of
the current price is **one-sided**:

- a range fully **below** spot needs only token1 (a bid);
- a range fully **above** spot needs only token0 (an ask).

A one-sided, out-of-range deposit is therefore a real **limit order**, and it can be
withdrawn one-sided.

Positions are **transferable ERC-1155 tokens** (`BucketShares`), one id per range:

```
id = uint256(keccak256(abi.encodePacked(tickLower, tickUpper)))
```

- `deposit(DepositParams)` mints the ERC-1155 to `recipient`.
- `withdraw(WithdrawParams)` takes an explicit `owner` and succeeds if the caller is the
  owner **or an approved ERC-1155 operator** (`setApprovalForAll`). It burns the owner's
  shares and pays principal + yield (+ any v4 fees) to `recipient`.

Key hook views used by the adapter: `sharesOf(user, lower, upper)`, `totalSharesOf`,
`getBuckets()`, `currentBalance()`, `shareToken()`, `syncYield()`.

The full hook documentation (lifecycle, share model, invariants, security) lives in the
original repository README.

---

## 2. Why an adapter, and why "one-sided"

Supercazzola is a meta-layer: `MakerConfig` maps `(maker, token) -> ILendingAdapter`, and
the router JIT-deploys capital on receive (`postTransferIn`) and JIT-withdraws on send
(`preTransferOut`) using a single token at a time.

The Superposition bucket is a **range + two tokens**, while the adapter interface is
**per-token**. Two design consequences follow:

1. **The range lives in the adapter.** `MakerConfig` only routes the token; the adapter is
   the single source of truth for the bucket range and the token↔range mapping — exactly
   like `ERC4626Adapter.vaultOf[underlying]`. No tick ever travels through the router.

2. **Single-token JIT requires one-sided ranges.** The hook's `deposit` computes liquidity
   from the amounts provided; with one amount at zero it calls
   `LiquidityAmounts.getLiquidityForAmounts`, which returns 0 for an **in-range** range when
   the other amount is missing (`NoLiquidity`/`Slippage` revert). Only an **out-of-range**
   range needs a single token. Since the router re-deposits exactly the single token the
   taker paid, the adapter must use one-sided, out-of-range buckets. This is the mechanism,
   not a limitation of the demo.

Therefore the adapter holds **one fixed one-sided range per token**:

| token | side | range | needs |
|---|---|---|---|
| `underlying0` (pool currency0, e.g. USDC) | above spot | `[lower0, upper0]` | token0 only |
| `underlying1` (pool currency1, e.g. USDT) | below spot | `[lower1, upper1]` | token1 only |

A maker can fund just one side ("provide one token side") or both; each side grows or
shrinks in its own bucket and stays one-sided.

---

## 3. The adapter

`SuperpositionUniAdapter is ILendingAdapter`

```solidity
constructor(
    address hook,
    address router,
    address underlying0, int24 lower0, int24 upper0,
    address underlying1, int24 lower1, int24 upper1
)
```

State and config:

- `HOOK` — the `SuperpositionHook` (minimal `ISuperpositionHook` ABI, no v4 imports).
- `ROUTER` — the only address allowed to call `withdraw`.
- `sideOf[underlying] = Side{ lower, upper, isToken0, set }`.
- The maker holds the ERC-1155; the adapter is an **operator**, so no per-maker share
  bookkeeping is needed — the adapter reads `HOOK.sharesOf(maker, lower, upper)`.

`_bucket(side)` looks the range up in `getBuckets()` and returns `{shares, c0, c1}`; the
per-token claim is `c0` for token0, `c1` for token1.

### API

| Function | Behaviour |
|---|---|
| `name()` | `"SuperpositionUniHook"` |
| `yieldToken(underlying)` | `HOOK.shareToken()` — the ERC-1155 LP token |
| `exchangeRate(underlying)` | `claim * 1e18 / bucketShares` (`1e18` when empty) |
| `underlyingToYield(underlying, amount)` | shares covering `amount`, rounded **up** |
| `yieldToUnderlying(underlying, amount)` | underlying claim of `amount` shares |
| `pullPlan(...)` | `(address(0), 0, address(0))` — shares are delegated, not pulled |
| `deposit(maker, underlying, amount)` | approve HOOK, `HOOK.deposit(range, amount0/1 = amount, recipient: maker)` |
| `withdraw(maker, underlying, amountOut, _, recipient)` | `HOOK.withdraw({range, owner: maker, shares: ceil cover amountOut, recipient})`; **router-only** |
| `maxWithdrawable(maker, underlying)` | `makerShares * claim / bucketShares`, clamped to `currentBalance()` for that token |

Notes:

- `deposit` passes `recipient = maker`, so the **maker** accrues the ERC-1155. The hook
  pulls `required + DEPOSIT_BUFFER` (≤ `amount`), so at most ~2000 wei can stay idle in the
  adapter as dust.
- `withdraw` rounds shares **up** so the hook's pro-rata payout covers `amountOut`.
- Views read the hook's **cached** claims; `deposit`/`withdraw` trigger the hook's internal
  `_syncYield`, so fills are exact (a quote before a `syncYield` may understate yield).

### Security: router-only `withdraw`

The hook authorizes the **adapter** (it is the operator), not the caller. Without a guard,
anyone could call `adapter.withdraw(maker, ..., attacker)` and burn the maker's shares with
the payout redirected. Hence `withdraw` reverts `NotRouter()` unless
`msg.sender == ROUTER`. `deposit` is safe: it only moves tokens the router already sent to
the adapter.

---

## 4. JIT data flow

One fill: the taker pays USDT and receives USDC (the maker's USDC bucket backs the
delivery). The maker LP'd both tokens into their one-sided buckets beforehand and set the
adapter as an ERC-1155 operator.

```
maker (once):  BucketShares.setApprovalForAll(adapter, true)

taker -> router: swap(USDT -> USDC)
  MakerCapitalGuardXD            // quote() and swap() share the runLoop
    adapter.maxWithdrawable(maker, USDC) >= amountOut

  preTransferOut(USDC):
    adapter.pullPlan             -> (0,0,0)                      // nothing moves from the wallet
    adapter.withdraw(maker, USDC, amountOut, _, maker)           // adapter = operator, ROUTER-only
      -> HOOK.withdraw({usdcRange, owner: maker, shares, recipient: maker})
         burns maker ERC-1155 shares, pays USDC from idle + aUSDC (Aave)

  SwapVM: USDC maker -> taker

  postTransferIn(USDT):
    router: USDT maker -> adapter
    adapter.deposit(maker, USDT, amountIn)
      -> HOOK.deposit({usdtRange, amount1: amountIn, recipient: maker})
         supplies USDT to Aave, mints ERC-1155 USDT-bucket shares to the maker
```

So on every fill the maker's capital cycles **out of Aave → to the taker** and the
received token cycles **into the hook → to Aave**, while the maker keeps owning the
position as an ERC-1155. Between fills the idle capital earns Aave yield, and if the pool's
own v4 price crosses a bucket the hook fills the limit order and the bucket's claim flips
token.

---

## 5. Important behaviour: what the adapter does *not* do

- It does **not** move the ERC-1155. The router never pulls the share token; the adapter
  exercises the operator delegation and the hook burns the maker's shares directly. The
  economic effect is identical to a pull-and-withdraw, without transferring the NFT.
- It does **not** swap on the hook's v4 pool. The fill is priced by the outer
  Supercazzola AMM; the hook is used as the deposit/withdraw vault (aUSDC/aUSDT). The
  hook's own `beforeSwap`/`afterSwap` JIT runs only when a third party swaps the v4 pool,
  and that path is covered by the hook's own test suite.
- It does **not** re-derive the quote from live balances. SwapVM quotes on the shipped
  **virtual balances**, scaled for yield by `YieldAdjustedRateXD`; the
  `MakerCapitalGuardXD` only guarantees the out side is actually withdrawable. As long as
  the shipped virtuals mirror the bucket claim this is exact; if the composition changes
  (a crossed range) the virtuals drift and the quote stays "stale" while still passing the
  guard — the maker rebalances/re-ships.

---

## 6. Ethereum mainnet integration

| Contract | Address |
|---|---|
| Uniswap v4 `PoolManager` | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Aave v3 `Pool` | `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` |
| USDC (6) / aUSDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` / `0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c` |
| USDT (6) / aUSDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` / `0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a` |
| Aqua / CREATE2 deployer | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` / `0x4e59b44847b379578588920cA78FbF26c0B4956C` |

Pool: `currency0 = USDC`, `currency1 = USDT` (address order), `fee = 100`,
`tickSpacing = 1`, initialized at `sqrtPriceX96 = 2**96` (price 1.0). Buckets:
USDC `[1, 101]` (above spot), USDT `[-101, -1]` (below spot).

`DeployAndSetup.s.sol` (ethereum branch) handles the whole stack:

1. Mine the CREATE2 salt with `HookMiner` for the hook flags
   (`BEFORE_ADD_LIQUIDITY | BEFORE_REMOVE_LIQUIDITY | BEFORE_SWAP | AFTER_SWAP`).
2. If the predicted hook address has no code, deploy it through the deterministic
   CREATE2 proxy and call `initializePool(2**96)`; otherwise **reuse** it.
3. Deploy `SuperpositionUniAdapter` targeting the hook and record `SuperpositionHook` +
   `SuperpositionUniHook` in `deployments/supercazzola-ethereum.json`.
4. Arm the maker: ERC-20 approvals to the router/Aqua, ERC-1155
   `setApprovalForAll(adapter)`, and a one-sided LP into each bucket (idempotent).

---

## 7. Running it

Fork test — real Uniswap v4 + Aave v3 on Ethereum mainnet:

```bash
cd foundry
forge test --match-path 'test/fork/EthereumForkSuperposition.t.sol' -vv
```

Covers: hook deploy+init, adapter views, one-sided deposit (maker gets ERC-1155, hook
holds aUSDC), delegated withdraw + `NotAuthorized` for non-operators + `NotRouter`, a full
Supercazzola JIT fill with `quote() == swap()`, capital-in-hook assertions, and yield
accrual growing the claim.

Anvil demo (fork Ethereum; the worker funds + deploys + arms, then run the scenario):

```bash
cd foundry
./script/start-anvil.sh ethereum
# wait for "ready: pick a scenario"
forge script script/ethereum/SuperpositionScenario.s.sol \
  --fork-url http://localhost:8547 --broadcast --skip-simulation
```

Demo numbers (100k/100k buckets): a taker's 1000 USDT fills at ~987 USDC (`quote == swap`).

> Build note: after adding/removing `.sol` files, a stale `out/`/`cache/` can make
> `forge script` panic with `type check failed for "offset (usize)"`. Rebuild clean:
> `rm -rf foundry/out foundry/cache && forge build`.

---

## 8. Limitations

- **Crossed ranges.** If the v4 price crosses a bucket, the hook fills the limit order and
  the claim flips token. `maxWithdrawable` for the original token then returns 0
  (fail-safe: no oversell); the maker must rebalance.
- **Transferred shares.** If the maker transfers the ERC-1155 away, the backing shrinks
  accordingly (`maxWithdrawable` reads the live balance).
- **Cached claims.** Views use the hook's cached `c0`/`c1` until the next `syncYield`.
- **Dust.** The hook's `DEPOSIT_BUFFER` (1000 wei) can leave ≤ ~2000 wei per deposit idle in
  the adapter.
- **Quote drift.** Virtual balances are shipped once and scaled only for yield; a
  composition change (crossed range, partial fills) is not automatically re-priced — the
  guard prevents overselling but the quoted price can lag until the maker re-ships.
- **Aave cash.** `maxWithdrawable` clamps to the hook's real aToken balance; it does not
  additionally check Aave's available cash (a withdrawal could still revert if the reserve
  is fully borrowed).
