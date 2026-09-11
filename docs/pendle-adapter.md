# PendlePTAdapter — design notes

`src/adapters/pendle/PendlePTAdapter.sol` — the fixed-income maker profile.

This file preserves the full context of HOW and WHY the adapter works the way it does,
including the on-chain mechanics discovered during development (mock tests could not have
caught several of these).

## What it does

The maker's capital sits in a Pendle **PT (Principal Token)** — a zero-coupon claim on the
market's accounting asset. The SuperPositionVMRouter hooks redeem/sell the PT **just-in-time**
to deliver the underlying to the taker, atomically inside the swap. The maker earns swap
fees on top of the **fixed yield** locked into the PT (no variable-rate exposure like Aave).

The adapter supports both states of a PT market, branching on `isExpired()`:

## Path 1 — EXPIRED market (1:1 redemption, zero swap legs)

```
preTransferOut hook
  pull PT from maker wallet (maker approved adapter)
  PT -> YT contract (plain transfer)
  YT.redeemPY(adapter)        -> burns ALL PT the YT holds, credits SY 1:1
  SY.redeem(recipient, ..., tokenOut=underlying)  -> underlying out, delivered exactly
default transfer: Aqua.pull delivers from the maker wallet to the taker
```

- Rate: constant `1e18` (post-maturity PT = 1 accounting asset; SY redeems 1:1 to the
  underlying because of Aave v3.2 displayed balances for the aUSDC family).
- Buffer: 100 wei PT pull buffer (`PT_PULL_BUFFER`) covers the PT->SY->token rounding dust;
  the surplus returns to the maker wallet after the exact delivery.
- Verified: **Arbitrum mainnet fork**, real expired market `PT-aUSDC-27JUN2024`
  (`0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5`, expiry 27 Jun 2024).
  PT `0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c`, SY `0x50288c30c37FA1Ec6167a31E575EA8632645dE20`,
  YT `0xA1c32EF8d3c4c30cB596bAb8647e11daF0FA5C94`, deliverable = native USDC
  `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` (SY `getTokensOut()` includes USDC directly —
  no Aave withdraw leg needed).
- Limitation: capital is static. The fixed yield was earned in the past; nothing accrues.

## Path 2 — ACTIVE market (the real fixed-income story)

Pre-maturity, PT trades at a **discount** to its accounting asset (the implied-yield
discount) and appreciates toward par linearly as maturity approaches. The maker locks a
fixed APY that **accrues in real time** — and the `YieldAdjustedRateXD` opcode captures
exactly that accrual through the rate0 design (`rate(now)/rate(ship)`, ship rate baked in
the immutable strategy args).

```
preTransferOut hook
  pull PT from maker: ceil( (amountOut + 1% buffer) / ptToAssetRate )
  PT.forceApprove(market)
  market.swapExactPtForSy(adapter, ptAmount, CALLBACK_DATA)
      ^ Pendle sends SY to the adapter FIRST, then calls back to collect the PT
  SY.redeem(adapter, syOut, underlying)   -> underlying out (1:1 for displayed-balance SYs)
  deliver exact amountOut to recipient, surplus (buffer minus spread) -> maker wallet
```

- Rate source: **PendlePYLpOracle** `getPtToSyRate(market, twapDuration)` — the TWAP rate
  denominated in SY, which is the deliverable (SY redeems 1:1). Do NOT use
  `getPtToAssetRate` for the adapter rate: for the wstETH family the accounting asset is
  stETH, so `getPtToAssetRate` returns *stETH per PT* (0.9737) while the deliverable rate
  is *wstETH per PT* (0.783 = 0.9737 / 1.2436). Mixing them made deliveries shortfall.
- Verified: **Ethereum mainnet fork**, real ACTIVE market PT-wstETH
  (`0x34280882267ffa6383B363E278B027Be083bBe3b`, expiry Dec 2027), rate ≈ 0.783 wstETH per
  PT (~9% implied APY until Dec 2027). Oracle `0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2`
  (canonical, same address on every chain; `0x14418800e0b4c971905423aa873e83355922428c`
  also works), TWAP duration 900s used in tests.
- Strategy pair in the fork proof: **wstETH/USDC** — the wstETH side is PT-backed fixed
  income; the USDC side is passthrough (revenue stays in the maker wallet).

## Pendle mechanics you must not get wrong (all bit us once)

1. **Callback sign convention**: `swapCallback(ptToAccount, syToAccount, data)` receives
   `ptToAccount` **NEGATIVE** when the caller owes PT to the market (positive = receives).
   We transfer `uint256(-ptToAccount)` only when negative.
2. **The market only invokes the callback when `data.length > 0`**: passing empty bytes
   means the PT is never transferred in, and the swap reverts with
   `MarketInsufficientPtReceived`. We pass `hex"00"`.
3. **SY.redeem is 1:1 with the underlying** for displayed-balance (v3.2-era) SYs, but the
   PT -> SY conversion can round down by 1-2 wei: hence the `PT_PULL_BUFFER` (100 wei).
4. **`getPtToSyRate` vs `getPtToAssetRate`**: the asset (stETH for wstETH markets) is not
   the deliverable (wstETH). The deliverable rate is `getPtToSyRate` (SY redeems 1:1).
5. **maxWithdrawable** for active markets = `PT.balanceOf(maker) × ptToAssetRate` — an
   approximation that ignores the market swap's slippage; the 1% buffer in
   `withdrawTo` covers the realistic spread (tested: a spot crash below the TWAP oracle
   beyond the buffer reverts with `PendleSwapShortfall` instead of delivering short).
6. **Security of the callback**: `swapCallback` must revert unless `msg.sender == MARKET`,
   otherwise anyone could drain the adapter's PT balance by calling it directly.
7. **Constructor discovers PT/SY/YT on-chain** from the market address (`readTokens()`),
   and rejects active markets when no oracle is provided (`MarketNotExpired`).

## Pricing interplay with the strategy

The strategy's AMM prices against the **deliverable** (e.g. wstETH). The virtual balances
are shipped in underlying units; `exchangeRate(underlying)` (deliverable per PT) feeds both
the opcode (`rate(now)/rate0` = fixed-yield accrual) and the capital guard
(`maxWithdrawable`). The passthrough side (e.g. USDC) has rate 1 and no-op hooks — fill
revenue stays in the maker wallet by design (it is the maker's realized profit).

## Test evidence

| Test | Proves |
|---|---|
| `test/unit/PendlePTAdapter.t.sol` (9) | expired path: redemption chain, dust buffer, passthrough no-ops, maxWithdrawable |
| `test/unit/PendleActivePTAdapter.t.sol` (7) | active path: oracle rate, callback-gated delivery, surplus to maker, spot-crash revert, callback security, passthrough |
| `test/fork/ArbitrumForkPendle.t.sol` | real expired PT-aUSDC market, full ship -> quote -> swap, invariants |
| `test/fork/MainnetForkPendleActive.t.sol` | real active PT-wstETH market, full ship -> quote -> swap, invariants |

## Deferred (v0.2+)

- Re-stake leg for `depositFor` on active markets (received underlying -> mint PT back —
  needs an ACTIVE market and the PT/YT mint path).
- Slippage bound via the oracle instead of the flat buffer (min_sy from the TWAP rate).
- The maker can re-ship periodically to relock the fixed yield at the current implied rate
  (dock -> ship pattern — native Aqua lifecycle, no extra code needed).
