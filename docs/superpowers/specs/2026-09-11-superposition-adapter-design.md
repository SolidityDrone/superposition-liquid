# Superposition Adapter — Design

Date: 2026-09-11
Status: awaiting user review (rev 2 — ERC-1155 bucket shares)
Branch: `superposition-hook-uni-v4`

## 1. Context

Supercazzola is a meta-layer over AMMs. `MakerConfig` maps `(maker, underlying) ->
ILendingAdapter`: the maker declares, per token, which adapter holds that token's
capital, and the router JIT-deploys on receive (`postTransferIn`) and JIT-withdraws
on send (`preTransferOut`).

`SuperpositionHook` (external repo `SolidityDrone/superposition-hook-uni-v4`, commit
`c1597bd`) is a Uniswap v4 concentrated-liquidity hook that keeps 100% of capital in
Aave v3 between swaps and tracks ownership **per tick range** (a bucket). A bucket that
sits entirely on one side of the pool's current price is **one-sided**: an out-of-range
deposit needs only one token, and withdrawing that bucket pays that token back
one-sided. Yield is distributed per token, pro-rata to each bucket's claim.

Positions are now **transferable ERC-1155** tokens (`BucketShares`), one id per range:

```
id = uint256(keccak256(abi.encodePacked(tickLower, tickUpper)))
```

`deposit` mints the ERC-1155 to `recipient`; `withdraw` takes an explicit `owner` and is
callable by that owner **or an approved ERC-1155 operator** (`setApprovalForAll`). This
is exactly the delegation hook the adapter needs.

## 2. Goal

An `ILendingAdapter` that lets a Supercazzola maker LP each stablecoin of a pair as a
**one-sided, yield-bearing bucket** on the Superposition hook, with single-token JIT
deposit/withdraw at fill time, while the maker **holds the ERC-1155 LP position** and the
adapter acts as its approved operator.

Non-goal: a limit-order product. The pair is stable, buckets sit just outside spot, and
the point is yield + capital efficiency. If the price does cross a bucket, the hook fills
it (limit-order semantics come for free); the adapter documents that case.

## 3. Decisions (log)

| Decision | Choice | Why |
|---|---|---|
| Chain | Ethereum mainnet | Aave v3 mainnet lists both stables |
| Pair | USDC / USDT | both Aave reserves, spot ~1.0 → fixed ranges stay valid |
| Token order | `currency0 = USDC`, `currency1 = USDT` | address order: `0xA0b8… < 0xdAC1…` |
| Position shape | two fixed **one-sided** buckets, one per token | single-token JIT is only valid out-of-range |
| Dual-sided in-range | **rejected** | `getLiquidityForAmounts` returns 0 when the other amount is 0 → `deposit` reverts |
| Share ownership | **maker holds the ERC-1155**; adapter is an operator | hook `withdraw(owner, …)` accepts `setApprovalForAll` delegates |
| Share accounting | read `HOOK.sharesOf(maker, lower, upper)` / ERC-1155 balance | no adapter-side mapping needed |
| Naming | folder `superposition-uni-hook/`, contract `SuperpositionUniAdapter`, kind `SuperpositionUniHook` | names the venue, no longer a "limit order" |
| Dependencies | git submodules | compile the hook unmodified |

## 4. Addresses (Ethereum mainnet, verified)

| Contract | Address |
|---|---|
| Uniswap v4 `PoolManager` | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Aave v3 `Pool` | `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` |
| USDC (6) / aUSDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` / `0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c` |
| USDT (6) / aUSDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` / `0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a` |
| CREATE2 deployer | `0x4e59b44847b379578588920cA78FbF26c0B4956C` |

Pool: `currency0 = USDC`, `currency1 = USDT`, `fee = 100`, `tickSpacing = 1`,
initialized at price ≈ 1.0.

## 5. Architecture

`SuperpositionUniAdapter is ILendingAdapter`

Config (constructor, immutable):
- `HOOK` — the `SuperpositionHook` instance.
- `rangeOf[underlying] = (int24 lower, int24 upper)` — one one-sided range per token:
  - USDC (token0) → range **above** spot → only token0 required.
  - USDT (token1) → range **below** spot → only token1 required.

The maker holds the ERC-1155 (`HOOK.shareToken()`) and approves the adapter once:

```solidity
IERC1155(HOOK.shareToken()).setApprovalForAll(address(adapter), true);
```

The adapter reads the maker's position directly:
`HOOK.sharesOf(maker, lower, upper)` (== ERC-1155 `balanceOf(maker, id)`).

Helper:
- `_bucket(underlying)` scans `HOOK.getBuckets()` for the matching `(lower, upper)` and
  returns its `{shares, c0, c1}`. No change to the hook repo needed.

Key insight: the tick lives in the adapter, not in `MakerConfig`. `MakerConfig` keeps the
`(maker, token) -> adapter` routing; the adapter is the single source of truth for the
range and the token↔bucket mapping — exactly like `ERC4626Adapter.vaultOf[underlying]`.

Interfaces used: a minimal `ISuperpositionHook` (deposit / withdraw / sharesOf /
getBuckets / shareToken, ABI-compatible with the hook structs) and OZ `IERC1155`. The
adapter therefore compiles without v4 imports; v4 deps are only needed to deploy the hook
in tests.

## 6. Adapter API

| Function | Behaviour |
|---|---|
| `name()` | `"SuperpositionUniHook"` |
| `yieldToken(underlying)` | `HOOK.shareToken()` — the ERC-1155 LP token |
| `exchangeRate(underlying)` | `claim(bucket) * 1e18 / totalSharesOf(range)`, `claim = c0` for token0, `c1` for token1 |
| `underlyingToYield(underlying, amount)` | shares covering `amount`, rounded **up** |
| `yieldToUnderlying(underlying, amount)` | underlying claim of `amount` shares |
| `pullPlan(maker, underlying, amountOut)` | `(address(0), 0, address(0))` — delegation, not transfer |
| `deposit(maker, underlying, amount)` | approve HOOK, `HOOK.deposit(range, amount0/1 = amount, recipient = maker)`; shares mint to the maker |
| `withdraw(maker, underlying, amountOut, yieldAmount, recipient)` | `HOOK.withdraw({range, owner = maker, shares = ceil cover amountOut, recipient = maker})` as operator; **router-only** (`NotRouter`) because the hook authorizes the adapter, not the caller |
| `maxWithdrawable(maker, underlying)` | `claim * makerShares / totalShares`, clamped to the hook's real liquidity |

- `deposit` approves the hook for `amount` (the hook pulls `required + DEPOSIT_BUFFER ≤
  amount0Desired`) and passes `recipient = maker`, so the maker accrues ERC-1155 shares.
- `withdraw` rounds shares **up** so the hook's pro-rata payout covers `amountOut`; the
  hook burns the maker's shares and pays `recipient` (the router passes the maker).
- Views read the hook's **cached** claims; `deposit`/`withdraw` call the hook's
  `_syncYield` internally so fills are exact.

## 7. Data flow — one fill (taker pays USDT, receives USDC)

```
maker (once): shareToken.setApprovalForAll(adapter, true)

taker → router: swap(USDT -> USDC)
  preTransferOut(USDC):
    adapter.pullPlan            → (0,0,0)
    adapter.withdraw(maker, USDC, amountOut, _, maker)      // adapter = operator
      → HOOK.withdraw({usdcRange, owner=maker, shares≈amountOut, recipient=maker})
        burns maker's ERC-1155, pays USDC to maker
  postTransferIn(USDT):
    router: USDT maker → adapter
    adapter.deposit(maker, USDT, amountIn)
      → HOOK.deposit({usdtRange, amount1=amountIn, recipient=maker})
        mints ERC-1155 USDT-bucket shares to maker
```

The maker is simultaneously an LP on the hook (holds ERC-1155) and on the 1inch/Aqua side
(the shipped strategy), with the adapter bridging the two.

## 8. Integration

- `AdapterKind.SuperpositionUniHook` added to `MakerConfig.sol`.
- Demo: register `(maker, USDC) -> adapter` and `(maker, USDT) -> adapter`; the maker may
  fund **one** token side (the other is passthrough), matching "provide just one side".
- Approvals the setup must establish for the maker:
  - ERC-20: `router` (pull) and `Aqua` (ship) for USDC/USDT.
  - ERC-1155: `shareToken.setApprovalForAll(adapter, true)`.
- `DeployAndSetup.s.sol` (ethereum branch) gains the Superposition stack. **The hook
  self-deploys conditionally inside `DeployAndSetup`** — no separate/manual deploy:
  1. Mine the CREATE2 salt with `HookMiner` (`BEFORE_ADD_LIQUIDITY |
     BEFORE_REMOVE_LIQUIDITY | BEFORE_SWAP | AFTER_SWAP`) against the CREATE2 deployer,
     exactly like the hook repo's `DeployHook.s.sol`.
  2. If the predicted hook address has no code, deploy through the deterministic proxy
     and call `initializePool(sqrtPriceX96 ≈ 1.0 for USDC/USDT)`.
  3. If it already has code (re-run / artifact present), **skip** and reuse it.
  4. Deploy `SuperpositionUniAdapter` targeting that hook; record hook + adapter + share
     token in the artifact.
  Deploy code is ported from the hook repo (present via the submodule).
- A `SuperpositionScenario.s.sol` (ethereum) runs the full demo: maker LPs a token side on
  the hook, approves the adapter as ERC-1155 operator, `setSides`, ships the strategy, and
  fills against it.

## 9. Dependencies

Git submodules:
- `lib/v4-core` (Uniswap v4-core, pinned)
- `lib/v4-periphery` (Uniswap v4-periphery, pinned — for `LiquidityAmounts`)
- `lib/superposition-hook` (hook repo, pinned at `c1597bd`)

Remappings for `@uniswap/v4-core/`, `@uniswap/v4-periphery/`, and the hook import path.
Alternative (lighter, rejected): vendor the hook + `LiquidityAmounts`.

## 10. Testing

Fork test on **Ethereum mainnet** with real contracts (v4, Aave v3): deploy the hook with
a mined CREATE2 salt (same pattern as the hook repo's tests), then adapter, `MakerConfig`,
`SupercazzolaRouter`.

| Test | Proves |
|---|---|
| `test_fork_deposit_usdc_one_sided` | USDC bucket holds USDC only; aUSDC in the hook; maker holds ERC-1155; claim tracked |
| `test_fork_operator_delegation` | adapter (operator) withdraws on the maker's behalf; non-operator reverts `NotAuthorized` |
| `test_fork_jit_fill` | full Supercazzola fill: taker pays USDT, gets USDC, JIT withdraw from the bucket |
| `test_fork_yield_attribution` | `syncYield` after time; claim grows; atomic deposit+withdraw earns nothing |
| `test_fork_max_withdrawable` | claim clamp / quote guard |
| `test_fork_both_sides` | USDC and USDT buckets independent |

## 11. Limitations (documented)

- If the price crosses a bucket, the hook fills it and the bucket's claim flips token.
  `maxWithdrawable` for the original token returns 0 → safe (no oversell); the maker
  rebalances.
- The maker can transfer the ERC-1155 away; `maxWithdrawable` reads the live balance, so
  a transfer simply reduces the backing (fail-safe).
- `DEPOSIT_BUFFER` dust (≤ ~2000 wei) can remain in the adapter per deposit.
- `maxWithdrawable` clamps to the hook's real balance; Aave cash is assumed available
  (can be tightened by reading the reserve's available liquidity).
- Views use cached claims until the next `syncYield`.

## 12. Resolved items

1. Names: folder `superposition-uni-hook/`, contract `SuperpositionUniAdapter`, kind
   `SuperpositionUniHook`.
2. Scope: items 1–5 (adapter, enum, fork test, docs, `DeployAndSetup` + scenario), with
   the hook self-deploying conditionally inside `DeployAndSetup`.
3. Pool params: `fee = 100`, `tickSpacing = 1`, ranges ~100 ticks outside spot
   (configurable).
