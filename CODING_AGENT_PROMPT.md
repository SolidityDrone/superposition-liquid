# CODING AGENT PROMPT — Supercazzola Brematurata

Sei un coding agent che implementa un protocollo DeFi per ETHOnline 2026. Non hai context
della conversazione di design: TUTTE le decisioni sono in `SPEC_FINAL.md` nella root del repo.
Leggilo PRIMA di scrivere codice. Questo file ti dice come lavorare.

## Cosa stai costruendo

Un custom SwapVM router (fork modified-redeploy di 1inch/swap-vm — permesso dalle bounty rules)
dove i maker forniscono liquidità ETH/USDC tenendo il capitale 100% in Aave v3. Ogni fill è
atomico: withdraw da Aave → consegna al taker → deposit back to Aave (pattern "JIT-unwrap",
v. decisioni B1.1-B1.3 in SPEC_FINAL.md).

## Setup iniziale (fase 0)

1. Init Foundry project (Solidity 0.8.30) nella root.
2. Dipendenze (come submodule `lib/` o remapping — valuta tu, pattern usato a ETHGlobal Lisbon:
   submodule di `1inch/swap-vm` e `1inch/aqua`):
   - `1inch/swap-vm` @ tag release v1.0.1/v1.0.2 — NON main (main non è deployato e ha enum renumbered)
   - `1inch/aqua` @ tag compatibile
   - `aave/aave-v3-core` (solo interfacce: IPool, IAToken, getReserveData)
   - `smartcontractkit/chainlink` (AggregatorV3Interface)
   - `openzeppelin/contracts`
   - `@1inch/solidity-utils`
3. Verifica che il build funzioni con `forge build` PRIMA di scrivere codice custom.

## Vincoli architetturali NON negoziabili (da SPEC_FINAL.md)

- Hooks NON possono skippare il default transfer: il preTransferOut hook fa JIT-withdraw verso
  il WALLET DEL MAKER, poi SwapVM/Aqua fa il transfer di default. Non tentare pattern alternativi.
- `postTransferIn` riceve tokenIn GIÀ nel wallet maker: deposita `amountIn - fee` in Aave.
- Custom opcodes APPESI a fine opcode table (mai inserti in mezzo): YieldAdjustedRateXD,
  ChainlinkGuardXD. La table deployata v1.0.2 ha gap 0-9/22-26 = no-op: non derivare indici da main.
- Rate aToken: SOLO `IPool.getReserveNormalizedIncome(asset)` (ray→1e18). Chainlink feed usati
  SOLO nel guard opcode (devia >2% o stale >1h → revert).
- Swap fee in tokenIn (flatFeeAmountIn). JIT-withdraw = esattamente `amountOut`.
- Solo path Aqua (`useAquaInsteadOfSignature`). Base mainnet come target; test su Anvil fork Base.

## File da creare

Struttura esatta in SPEC_FINAL.md (sezione Contratti). Seguila. In più:
- `script/Deploy.s.sol`: deploy router+adapter+config, setup maker E2E
- `script/Demo.s.sol`: E2E demo per il bounty (Base fork): ship → quote → swap sell → swap buy →
  assert capitale in Aave in ogni step
- Test: unit/ + fork/ + invariants/ (invariant principale: real aToken balance ≥ virtual balance;
  e quote() == swap() per stesso stato)

## Approvals maker (B4.1 — non sbagliare)

- `aWETH → adapter`, `USDC → adapter`, `WETH → Aqua registry` (pull da Aqua, non dal router).
- `ship()` non richiede approval (pura accounting).

## Workflow (OBBLIGATORIO)

1. Lavora incrementalmente con commit piccoli e progressivi (requisito bounty: no single-commit).
   Commit message corti e descrittivi (es. `feat: ILendingAdapter interface`).
2. TDD: per ogni contrato, scrivi prima il test fallente, poi implementa.
3. Dopo ogni modifica: `forge build` + `forge test`. Test suite verde prima di ogni commit.
4. I test fork usano `--fork-url` Base mainnet RPC (variabile env). Se un RPC non è disponibile,
   derivi chain id 8453 fork e documenta come avviarlo nel README.
5. NON modificare i contratti sorgente 1inch nei submodule; il tuo router eredita e override.

## Definition of done

- [ ] `forge build` pulito
- [ ] `forge test` verde (unit + fork + invariant)
- [ ] `script/Demo.s.sol` gira end-to-end su Base fork e stampa: capitale sempre in aWETH/aUSDC,
      fee corrette, quote == swap
- [ ] Struttura file conforme a SPEC_FINAL.md
- [ ] README breve con setup + comandi demo
- [ ] Git history progressiva con commit atomici

## Indirizzi Base (verifica on-chain, non hardcodare ciecamente)

- Aqua registry: `0x1111113ccf1426a8e30e2bff5e005d929bf6a90a`
- SwapVM router deployato: `0x111111338c5091E8440b67B168bAe16a668AC0De` (riferimento; noi
  ridoployamo il fork come SupercazzolaRouter)
- WETH Base: `0x4200000000000000000000000000000000000006`
- USDC Base: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- Aave v3 Pool Base: verificare via `AddressesProvider` (documenta l'indirizzo trovato)
- Chainlink ETH/USD e USDC/USD su Base: verificare su docs.chain.link e on-chain (decimals 8)

Se un indirizzo non combacia on-chain, fermati e segnala, non inventare.
