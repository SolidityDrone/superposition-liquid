# Borrow mode — design notes

**Status: implemented as a mode of `AaveV3Adapter` (Aave first). Morpho Blue = roadmap.**

An adapter is not only a place where capital *yields*; it can also be a **source/sink of
capital**. With borrow mode a maker can quote a market for an asset **they do not own**,
funded by yield-bearing collateral they already hold.

This is deliberately **not** a new adapter. The borrow mechanics (borrow on out-fill,
repay on the matching in-fill) are just the inverse of the supply mechanics already in
`AaveV3Adapter`. A separate `BorrowAdapter` would duplicate the account/health/LTV logic
and the guard integration; a **mode flag + a `BorrowConfig`** on the same adapter keeps a
single code path and a single source of truth.

## Model

Two sides of one pair:

- the **collateral side** earns yield as usual (`USDC → aUSDC`);
- the **borrowed side** is sourced on demand (`LINK`): the maker quotes LINK they do not
  hold; the adapter borrows it to deliver a fill, and repays the debt when the pair
  receives LINK back.

Net exposure: **short the borrowed asset, funded by the yield-bearing collateral**. The
curve and the risk appetite stay the maker's choice; the meta-layer only moves capital.

```
Fill A — taker buys LINK, pays USDC  (maker delivers LINK)
  preTransferOut(LINK):  AaveV3Adapter.withdraw → Aave.borrow(LINK, onBehalfOf=maker) → maker/taker
  postTransferIn(USDC):  AaveV3Adapter.deposit  → aUSDC up (collateral grows)

Fill B — taker sells LINK, receives USDC  (maker receives LINK)
  postTransferIn(LINK):  AaveV3Adapter.deposit  → Aave.repay(LINK, onBehalfOf=maker) first
  preTransferOut(USDC):  AaveV3Adapter.withdraw → aUSDC → maker/taker
```

The borrowed inventory is opened by an out-fill and **closed by the matching in-fill**: the
LINK that comes back repays the debt.

## Config

`BorrowConfig` lives next to the side registry (`MakerConfig`), one per `(maker, token)` —
the same key as `SideConfig`, and the same "one token, one config" constraint:

```solidity
struct BorrowConfig {
    bool enabled;       // the maker allows this side to be sourced by borrowing
    address collateral; // the token backing the borrow (e.g. USDC); 0 = account-level
    uint256 maxDebt;    // risk capacitor: hard cap on the side's debt (underlying units); 0 = no extra cap
}
```

`BorrowConfig` is a **separate mapping** from `SideConfig`, so existing side configs and
their ABI are untouched:

```solidity
MakerConfig.setBorrowConfigs(address[] underlyings, BorrowConfig[] configs) // maker-only
MakerConfig.borrowConfigOf(maker, underlying) -> BorrowConfig
```

Per-pair example:

| pair | side | `enabled` | `collateral` | `maxDebt` |
|---|---|---|---|---|
| USDC/LINK | LINK | true | USDC | 10_000e6-equivalent (in LINK units) |
| USDC/ETH  | ETH  | false | — | — |
| USDC/*    | USDC | (not borrow) | — | — |

`USDC` appears in both pairs but its own side is unchanged (collateral, not borrowed);
the flag sits on LINK vs ETH, so the two entries never collide.

## Adapter rules

`pullPlan`, `withdraw`, `deposit`, `maxWithdrawable` in `AaveV3Adapter` branch on
`borrowConfigOf(maker, underlying).enabled`:

- **`pullPlan`** — borrow side: if the maker has no `aToken`, return `(0,0,0)` (nothing to
  pull; the adapter sources the tokens itself, same pattern as `SuperpositionUniAdapter`).
  If a partial position exists, pull `min(needed, balance)`; the shortfall is borrowed.
  Non-borrow behavior is unchanged.
- **`withdraw`** — withdraw the pulled `aToken` to `recipient`; if that is not enough,
  **borrow the shortfall** up to capacity (`Aave.borrow(underlying, shortfall, 2, 0, maker)`)
  and send it to `recipient`.
- **`deposit`** — repays debt **first** (`Aave.repay(underlying, min(amount, debt), 2, maker)`),
  supplies only the remainder. This is what closes the position on the in-fill.
- **`maxWithdrawable`** = `min(position, poolCash)` **+ borrow headroom**:

  ```
  headroom = min(
      availableBorrowsBase → underlying,        // Aave account data (its own oracle)
      collateralCapacityBase → underlying,      // only the configured collateral
      maxDebt (if set)                          // risk capacitor
  )
  ```

  `collateralCapacityBase = aToken(collateral).balanceOf(maker) → underlying`
  `× price(collateral) / 1e(dec(collateral)) × LTV(collateral) / 1e4`.
  `availableBorrowsBase` is converted with `price(underlying)` via the pool's oracle
  (`ADDRESSES_PROVIDER().getPriceOracle()`); **no Chainlink feed of our own**.

`exchangeRate(borrowed)` returns `1e18`: a debt is not a positive balance and the virtual
inventory stays flat, while the real debt grows. This slightly over-quotes, which the
capital guard then rejects — safe. A decreasing rate (mirror of the yield scaling) is a
later refinement.

## Isolation and the risk capacitor

`collateral` + `maxDebt` are **our soft isolation**: the router only offers liquidity that
is covered by the configured collateral and capped by `maxDebt`. It does **not** hard-isolate
the debt at the protocol level: Aave debt is account-level, so a maker (or anyone, Aave is
permissionless) can borrow against other collateral outside the router, and the account's
health depends on all of it.

For **hard isolation**, one of:

- a **dedicated account per strategy** in which *only* the intended collateral is enabled
  (best: the pair cannot touch other balances) — the recommended production shape;
- Aave **isolation mode** / **e-mode** (asset-level: isolated collateral + debt ceiling /
  correlated group) — coarse but zero extra infra.

`maxDebt` is the maker's **risk capacitor**: it bounds how much of the pair can be quoted
from debt even if the protocol would allow more.

## Why Aave first (and Morpho later)

- **Aave v3**: account-level debt, `getUserAccountData().availableBorrowsBase`,
  `borrow/repay(..., onBehalfOf)`, isolation/e-mode. All primitives are already imported.
- **Morpho Blue** (roadmap): debt is **per-market** (`loanToken/collateralToken/oracle/lltv`),
  naturally isolated; capacity = collateral × LLTV − debt with the market's own oracle.
  It is supply-only in MetaMorpho, so a Morpho borrow path is a **separate adapter**, not
  the ERC-4626 one — but it implements the same `ILendingAdapter` + `BorrowConfig` contract,
  so the router, the guard and the config are unchanged.

## Security notes

- The router resolves adapters per `(maker, underlying)`; the guard (`MakerCapitalGuardXD`,
  via `maxWithdrawable`) and the yield opcode (`exchangeRate`) work unchanged.
- Interest cost must be offset by collateral yield + swap fees, or the maker tops up.
- Borrow caps / isolation mode / asset not borrowable can gate a fill — the borrow reverts
  atomically, so nothing can be lost.
- **Liquidation risk is real and is the maker's config.** The guard caps a *single* fill;
  it does not manage the health factor across fills.
- Debt drift: the flat `exchangeRate` over-quotes slightly; the guard rejects the excess.

## Test plan

- **Unit (mock pool)**: borrow headroom = `min(available, collateral×LTV, maxDebt)`;
  `withdraw` withdraws then borrows the shortfall; `deposit` repays before supplying;
  borrow-disabled sides behave exactly as today.
- **Fork (Base/ETH, real Aave)**: supply USDC collateral → fill A borrows LINK and delivers
  → incoming LINK repays debt → `maxWithdrawable` tracks `availableBorrowsBase`.
