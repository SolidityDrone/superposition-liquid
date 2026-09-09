# Supercazzola Brematurata — SPEC FINAL v1.0

ETHOnline 2026 · single dev · 1 week · bounty: 1inch Aqua (primary), Chainlink Data Feeds (secondary)

## One-liner

Custom SwapVM router (modified redeploy — allowed by 1inch rules) where makers provide ETH/USDC
liquidity while holding 100% of capital in Aave v3 (aWETH/aUSDC). Per-fill, transfer hooks cycle
capital JIT: withdraw from Aave → deliver to taker → deposit back to Aave, atomically in one tx.
Maker earns swap fee + lending APY on the same capital. Adapter-based so any lending protocol can
plug in per-maker.

## DECISION LOG

| ID | Decision | Impatto |
|----|----------|---------|
| B1.1 | Hook NON riceve `recipient`. Riceve `(maker, taker, tokenIn, tokenOut, amountIn, amountOut, orderHash, makerData, takerData)` (IMakerHooks.sol:67). Recipient finale risolto DOPO il hook via `takerTraits.to()` (SwapVM.sol:336) | Hook non può consegnare direttamente al taker |
| B1.2 | NON si può skippare il default transfer. Nessun return value/flag; SwapVM fa sempre il transfer dopo il pre-hook (SwapVM.sol:336→358) | → pattern **JIT-unwrap**: hook withdrawal verso il wallet maker; il default transfer (Aqua.pull o safeTransferFrom) consegna |
| B1.3 | `postTransferIn` chiamato DOPO che tokenIn è nel wallet maker (SwapVM.sol:293). Hook riceve `fee` come parametro | Hook deposita in Aave quanto arrivato al maker |
| B2.1 | `ship()` NON verifica balance: pura accounting su mapping `(maker, app, strategyHash, token)` (Aqua.sol:40-52) | Ship con token WETH/USDC e capitale in aWETH/aUSDC è design valido |
| B2.2 | Balance virtuali aggiornati automaticamente: push incrementa (Aqua.sol:76), pull decrementa (Aqua.sol:66); VM le carica nei registers a inizio swap (SwapVM.sol:163) | Nessun bookkeeping extra |
| B3.1 | Custom opcode: deployed router v1.0.2 ha opcode table con gap riservati (0-9, 22-26 = no-op); opcodes custom vanno APPESI a fine table (pattern validato a ETHGlobal Lisbon 2026: qilinswap, Aqua Prime). Non derivare la table da main branch (non deployato) | Modifichiamo il repo v1.0.2-tag, appendiamo 2 opcodes |
| B3.2 | Opcode scrive su `ctx.swap` (memory) → permesso anche in static context (quote). View call a `adapter.exchangeRate()` permesso in staticcall | Opcode funziona identico in quote e swap |
| B3.3 | Rate aToken: SOLO `IPool.getReserveNormalizedIncome(asset)` (ray→1e18). Chainlink non ha feed aWETH/ETH né aWETH/USD; comporre feeds aggiunge staleness senza beneficio. L'index Aave non è manipolabile al ribasso intra-tx | Spec Chainlink ridefinuita: guard opcode, non rate feed |
| B3.4 | Chainlink Data Feeds usati come **price-sanity guard opcode**: revert se prezzo implicito swap devia >2% da ETH/USD o USDC/USD di Chainlink (staleness check incluso). Data Feeds, non Data Streams | Bounty Chainlink: MEV-protection reale |
| B3.5 | Opcode order nel program: `YieldAdjustedRate` prima di `xycSwap`; `ChainlinkGuard` dopo pricing, prima dei transfer | Deterministico |
| B4.1 | Approvals: `aWETH → adapter`, `USDC → adapter`, `WETH → Aqua registry` (Aqua.pull fa transferFrom da wallet maker, caller è Aqua). NO approval a router per depositFor: `depositFor` fa transferFrom **dal wallet del maker** (tokenIn arriva lì) | Tabella approvals sotto |
| B4.2 | MakerConfig: permissionless read, write solo dal maker (msg.sender == maker) | Registry semplice |
| B5.1 | Invariant `real ≥ virtual` sempre vero (ship=accounting; interesse aumenta solo real; fill atomico). Se maker ritira aTokens manualmente → fill revert naturale nel JIT withdraw. Nessun codice extra | Test invariant only |
| B5.2 | Nessun locking per fill concorrenti: reentrancy guard SwapVM per orderHash + tx atomico sequenziale nel blocco | Nessun codice extra |
| B5.3 | Swap fee in **tokenIn** (flatFeeAmountIn, dedotta dal taker). postTransferIn deposita `amountIn - fee` in Aave; fee resta in wallet maker come underlying | JIT-withdraw esattamente `amountOut` |
| B6.1 | **Solo path Aqua** (`useAquaInsteadOfSignature = true`). No path EIP-712 puro | Scope ridotto |
| B6.2 | **Base mainnet** come chain target: Aqua+SwapVM deployati (`0x111111338c…c0de`), Aave v3 (aWETH/aUSDC) live, Chainlink feeds live. Demo su **Anvil fork di Base** (bounty rules: "local forks are ok") | Nessuna dipendenza testnet |
| B6.3 | Testnet: 1inch Aqua NON è su Base Sepolia; su Sepolia il router vanity non è deployato (solo gen 2026-07-16). Self-deploy dello stack solo se strettamente necessario | Skip: fork-only demo |
| B7.1 | **Aave su Base è v3.2+**: `aToken.balanceOf` è già index-accrued (deposit 105 WETH → 105 aWETH displayed, yield cresce come balance). Il rate generico `scaledTotalSupply × liquidityIndex × 1e18 / (totalSupply × 1e27)` = 1e18 su v3.2+, = liquidityIndex su legacy. Converto SEMPRE in unità displayed | Adapter AaveV3Adapter.exchangeRate |
| B7.2 | Virtual balance shipped in **aToken count units** (non underlying): effective = count × rate = real underlying esatto. Ship-side dust buffer (~1e4 raw) sul lato in: il rounding displayed di Aave può lasciare il real 1-2 wei sotto l'importo pushed esatto | ship amounts; invariant real ≥ virtual |
| B7.3 | Opcode dispatch bytes (v1.0.1): byte = indice statico − 1 (xycSwap=17, flatFeeIn=21, salt=20, gap 0-9/22-26). Custom: YieldAdjustedRateXD=**34**, ChainlinkGuardXD=**35** (appesi dopo onlyTxOrigin=33) | program bytecode |
| B7.4 | Program order: `[yield][flatFeeIn][xyc][guard]` — flatFee esegue ricorsivamente il resto del programma e il guard deve vedere amountIn/amountOut già calcolati | program bytecode |
| B7.5 | Hook **direction-agnostic**: la strategia 2D scambia in entrambe le direzioni → preTransferOut/postTransferIn matchano tokenOut/tokenIn contro ENTRAMBI gli underlyings della config (bug trovato dal demo fill #2) | SupercazzolaRouter hooks |
| B7.6 | Guard staleness **per-feed**: USDC/USD su Base aggiorna su heartbeat ~12h (stablecoin); ETH/USD ~1m. Args: (token0, token1, feed0, feed1, maxDevBps, staleness0, staleness1) = 92 bytes | ChainlinkGuardOpcode |
| B7.7 | Approvals completi (update B4.1): `aWETH → adapter`, `aUSDC → adapter`, `WETH → Aqua`, `USDC → Aqua` (pull bidirezionale). Verificato dal demo: senza aUSDC→adapter il fill reverse reverta | maker setup |
| B8.1 | **Adapter generico ERC-4626**: `ERC4626Adapter` copre qualsiasi vault 4626-compliant (testato contro mock in stile MetaMorpho/Morpho e Euler v2). Registry `underlying → vault` fissato al deploy; rate = `vault.convertToAssets(1e18)` (fonte: il vault stesso, niente oracle); `withdrawTo` = redeem diretto al recipient; `depositFor` = pull da maker + deposit con `forceApprove` verso il vault (il vault pulla dal caller) | src/adapters/ERC4626Adapter.sol |
| B8.2 | Adapter borrow delta-neutral (collateral WETH + borrow WETH come inventario AMM, repay same-asset sui fill): **designato, deferred a v0.2** — il repay con USDC ricevuti richiede swap nel hook e la gestione HF è out of scope. Documentato nel README come future work | future work |

## Architettura (aggiornata JIT-unwrap)

```
swap() (AquaSwapVMRouter fork = SupercazzolaRouter)
  runLoop: [_dynamicBalancesXD da Aqua virtual balances]
           [YieldAdjustedRateXD]      ← aWETH/aUSDC rate × balances (memory, quote-safe)
           [xycSwapXD]                ← pricing AMM
           [flatFeeAmountInXD]        ← fee al maker, dedotta dal taker
           [ChainlinkGuardXD]         ← sanity vs Chainlink feed, revert se devia >2%
  _transferOut: preTransferOut hook (router)
      → adapter.withdrawTo(maker, WETH, amountOut, maker wallet)   ← JIT unwrap
    default: Aqua.pull(maker → taker)                               ← consegna reale
  _transferIn:  default: Aqua push → tokenIn arriva nel wallet maker
    postTransferIn hook (router)
      → adapter.depositFor(maker, USDC, amountIn - fee)             ← redeploy to Aave
```

## Contratti

```
src/
  interfaces/
    ILendingAdapter.sol      (name, yieldToken, underlyingToYield, yieldToUnderlying,
                              exchangeRate, withdrawTo, depositFor)
  adapters/
    AaveV3Adapter.sol        (IPool.withdraw/supply, getReserveNormalizedIncome,
                              aToken da getReserveData, per-asset feed map per futuro)
  config/
    MakerConfig.sol          (MakerVaultConfig: adapter, underlyingIn, underlyingOut,
                              autoDepositIn, autoWithdrawOut; write solo maker)
  opcodes/
    YieldAdjustedRateOpcode.sol  (balanceIn/balanceOut × exchangeRate, 1e18)
    ChainlinkGuardOpcode.sol     (AggregatorV3Interface ETH/USD + USDC/USD, devia>2% → revert,
                              staleness >1h → revert)
  SupercazzolaRouter.sol     (Simulator, SwapVM, AquaOpcodes fork — opcodes appesi a fine table;
                              hooks: hasPreTransferOutHook + hasPostTransferInHook, target = router)
script/
  Deploy.s.sol               (router + adapter + config; maker setup script)
test/
  unit/  (adapter, config, opcodes — mock Aave pool dove serve)
  fork/  (Base fork: ship → quote → swap → assert capital sempre in Aave)
  invariants/ (real ≥ virtual; quote == swap per stesso stato)
```

Dipendenze Foundry (submodule o remapping, pattern qilinswap):
- `1inch/swap-vm` @ release v1.0.1/v1.0.2 tag (NON main)
- `1inch/aqua` @ tag compatibile
- `aave/aave-v3-core` (interfacce IPool + periferiche Base)
- `smartcontractkit/chainlink` (AggregatorV3Interface)
- `openzeppelin/contracts`
- `@1inch/solidity-utils`

## Maker setup flow (finale)

1. `aWETH.approve(adapter, max)` — per withdrawTo
2. `USDC.approve(adapter, max)` — per depositFor
3. `WETH.approve(AQUA registry, max)` — per Aqua.pull dopo JIT unwrap
4. `MakerConfig.setConfig({adapter, underlyingIn: USDC, underlyingOut: WETH, autoDepositIn: true, autoWithdrawOut: true})`
5. `AQUA.ship(app=SupercazzolaRouter, strategy=encoded Order, tokens=[WETH, USDC], amounts=virtual balances)` — nessuna verifica balance, nessun token movimentato
6. Program: `[YieldAdjustedRateXD][xycSwapXD][flatFeeAmountInXD][ChainlinkGuardXD]` + traits `useAquaInsteadOfSignature, hasPreTransferOutHook, hasPostTransferInHook, preTransferOutTarget=router, postTransferInTarget=router`

## Demo (bounty compliance)

- Anvil fork Base mainnet, script E2E: deploy → maker setup → ship → quote → swap (sell ETH) → swap (buy ETH) → assert: capitale 100% in aWETH/aUSDC in ogni momento, fee+rate corretti
- Git commit history progressivo (no single-commit final day — requisito bounty)
- Eventuali schermate minimal: cast/anvil output o pagina statica read-only (non bloccante)

## Out of scope (v0.1)

Health factor/liquidation, Uniswap v4 hook, multi-adapter per maker (un adapter per maker per ora), frontend full, cross-chain, path EIP-712 puro, adapter borrow delta-neutral (B8.2), adapter wstETH (richiede swap leg nel hook).
