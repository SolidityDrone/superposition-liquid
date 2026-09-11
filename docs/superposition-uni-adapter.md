# SuperpositionUni Adapter

`SuperpositionUniAdapter` plugs a maker into **Superposition**, the Uniswap v4
concentrated-liquidity hook (`SolidityDrone/superposition-hook-uni-v4`) whose capital
sits in Aave v3 between swaps and is tracked per tick range ("bucket"). It is the
`ILendingAdapter` that lets a Supercazzola maker keep USDC/USDT as **one-sided,
yield-bearing buckets** while a SwapVM strategy quotes against them.

## Model

The hook tracks bucket ownership with a transferable **ERC-1155** (`BucketShares`), one
id per range:

```
id = uint256(keccak256(abi.encodePacked(tickLower, tickUpper)))
```

- The **maker holds the ERC-1155** and (once) calls
  `shareToken.setApprovalForAll(adapter, true)`.
- `withdraw` on the hook accepts an explicit `owner` and succeeds if the caller is the
  owner **or an approved operator**. The adapter is that operator, so it can JIT-withdraw
  on the maker's behalf.
- The adapter is configured with one fixed **one-sided range per token**. A range fully
  above spot needs only token0; a range fully below spot needs only token1 — so a
  single-token JIT deposit is valid. (A dual-sided in-range range cannot accept a
  single-token `deposit`: `getLiquidityForAmounts` returns 0 and the hook reverts.)

## Adapter API

| Function | Behaviour |
|---|---|
| `name()` | `"SuperpositionUniHook"` |
| `yieldToken(underlying)` | the hook's `BucketShares` token |
| `exchangeRate(underlying)` | bucket claim per 1e18 shares |
| `underlyingToYield` / `yieldToUnderlying` | underlying ↔ bucket shares |
| `pullPlan(...)` | `(0,0,0)` — shares are delegated, never pulled from the wallet |
| `deposit(maker, underlying, amount)` | approves the hook, `HOOK.deposit(... recipient: maker)` — mints ERC-1155 to the maker |
| `withdraw(maker, underlying, amountOut, _, recipient)` | burns the maker's shares as operator, `HOOK.withdraw(owner: maker, recipient)`; **router-only** |
| `maxWithdrawable(maker, underlying)` | maker claim, clamped to the hook's real liquidity |

`withdraw` is restricted to the router (`NotRouter`) because the hook authorizes the
adapter, not the caller: without the guard, anyone could burn a maker's shares and
redirect the payout.

## Ethereum mainnet

| Contract | Address |
|---|---|
| Uniswap v4 `PoolManager` | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Aave v3 `Pool` | `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` |
| USDC (6) / aUSDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` / `0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c` |
| USDT (6) / aUSDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` / `0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a` |

Pool: `currency0 = USDC`, `currency1 = USDT`, `fee = 100`, `tickSpacing = 1`, price 1.0.
USDC (token0) → range above spot; USDT (token1) → range below spot.

`DeployAndSetup.s.sol` (ethereum) **self-deploys the hook conditionally**: it mines the
CREATE2 salt, deploys through the deterministic proxy if the predicted address has no
code, calls `initializePool`, then deploys the adapter and records both in
`deployments/supercazzola-ethereum.json`. No separate hook deployment step.

## Run it

Fork test (real v4 + Aave on Ethereum mainnet):

```bash
cd foundry
forge test --match-path 'test/fork/EthereumForkSuperposition.t.sol' -vv
```

Anvil demo (worker deploys + arms; then run the scenario):

```bash
cd foundry
./script/start-anvil.sh ethereum
# wait for "ready: pick a scenario"
forge script script/ethereum/SuperpositionScenario.s.sol \
  --fork-url http://localhost:8547 --broadcast --skip-simulation
```

## Limitations

- If the price crosses a bucket, the hook fills it and the bucket's claim flips token.
  `maxWithdrawable` for the original token returns 0 (fail-safe, no oversell); the maker
  rebalances.
- If the maker transfers the ERC-1155 away, the backing shrinks accordingly.
- Views use the hook's cached claims until the next `syncYield`.
- `DEPOSIT_BUFFER` dust (≤ ~2000 wei) can remain in the adapter per deposit.
