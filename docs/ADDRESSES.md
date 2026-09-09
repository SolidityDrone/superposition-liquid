# ADDRESSES.md — protocols, chains, tokens

Every address Superposition-Liquid may need, per chain, per protocol. This is the
composition reference: when configuring a maker strategy on a given chain, this file
tells you which adapters are deployable and which tokens they support.

Legend:
- ✅ = verified on-chain by this repo (cast call / fork test at dev time)
- 📄 = from official docs (verify on-chain before relying on it in production config)

Chains we target (1inch Aqua production set, 13 chains):
Ethereum (1) · Arbitrum (42161) · Base (8453) · Optimism (10) · Polygon (137) ·
Avalanche (43114) · BNB (56) · Gnosis (100) · Sonic (146) · Linea (59144) ·
zkSync (324) · Unichain (130) · Robinhood (4663)

---

## 1. 1inch Aqua + SwapVM (our settlement layer)

The strategy layer itself — required on every chain we deploy on.

| Chain | Registry (Aqua) | SwapVM router |
|---|---|---|
| All 13 production chains ✅ | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` | `0x111111338c5091E8440b67B168bAe16a668AC0De` |

- Same universal address on: Ethereum, Arbitrum, Base, Optimism, Polygon, BNB,
  Avalanche, Gnosis, Sonic, Linea, zkSync, Unichain, Robinhood.
- Router build: **v1.0.2** (EIP-712 domain `1inch SwapVM v1.0` / `1.0.2`), 5-arg
  `quote`/`swap` with explicit `tokenIn/tokenOut`.
- `KycNFT` (taker access credential): `0x26FFc7D378E8e49Be2c483295A3e3E511F96a468`.
- 🔥 Our SupercazzolaRouter is a **modified redeploy** (allowed by bounty rules): we
  deploy our own router per chain; the official address above is the reference build.

### Testnet
- **Sepolia (11155111)**: vanity registry `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` ✅-docs;
  the vanity router is NOT deployed there — old-gen contracts remain:
  registry `0xe8026bf31e58b738647319362581AB11Be92139B` 📄,
  router `0x016b417bc933370f5EAcC40B1d58B015ac72B070` 📄. Sepolia is not part of the
  production chain set. **No Base Sepolia deployment.** For demos: mainnet fork (proven).

## 2. Aave v3 (AaveV3Adapter)

Deploys (v3/v3.7) — 18 chains: Ethereum, Arbitrum, Base, Optimism, Polygon, Avalanche,
BNB, Gnosis, Linea, Sonic, Metis, Scroll, zkSync, Celo, Soneium, Plasma, Mantle,
(+ Ethereum Lido market) 📄. Top markets by TVL 📄: Ethereum ~$44B, Base ~$1.8B,
Arbitrum ~$1.87B, Avalanche ~$1.05B.

| Chain | Pool | Status |
|---|---|---|
| Base | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` ✅ | verified (v3.2 displayed balances) |
| Arbitrum / Ethereum / Optimism / Polygon / Avalanche | via each chain's PoolAddressesProvider 📄 | same v3.2 balance model 📄 |

Base details ✅: AddressesProvider `0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D`,
aWETH `0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7`,
aUSDC `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB`.
Supported yield tokens (our adapter): aWETH, aUSDC per chain (both **v3.2 displayed**
on Base and newer markets — the adapter handles legacy index-based markets too).
Chain flags: native USDC on Base/Arbitrum/Ethereum/Optimism/Avalanche; USDC.e on
Polygon 📄.

### Testnet
- Aave v3 Sepolia market exists 📄 (Ethereum Sepolia AddressesProvider
  `0x012bAC54348C0E635dca4cD86AB93c5bA2305CF1` 📄). No Base Sepolia market 📄.
- The adapter unit tests run on protocol-faithful mocks; fork tests use mainnet forks
  (no testnet dependency).

## 3. Morpho (ERC4626Adapter)

- **Morpho Blue**: deployed via CREATE2 at the SAME address on every chain:
  `0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb` ✅-docs (chains: Ethereum, Optimism,
  Base, Unichain, Worldchain, Ink, Soneium, Mode, Base Sepolia 📄 + Arbitrum, Polygon 📄).
- MetaMorpho (ERC-4626 curated vaults) — the adapter takes ANY 4626 vault; pick per
  chain/asset. Verified Base vaults ✅:
  - Gauntlet WETH Core: `0x6b13c060F13Af1fdB319F52315BbbF3fb1D88844` (WETH)
  - Steakhouse Prime USDC: `0xBEEFE94c8aD530842bfE7d8B397938fFc1cb83b2` (USDC)
  - Also on Base 📄: Gauntlet USDC Prime `0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61`,
    Steakhouse USDC `0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183`,
    Moonwell Flagship USDC `0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca`
- Ethereum vaults 📄: Gauntlet WETH Prime `0x2371e134e3455e0593363cbf89d3b6cf53740618`,
  Steakhouse USDC `0xbeef01735c132ada46aa9aa4c54623caa92a64cb`, + dozens more.
- Testnet: Morpho Blue on **Base Sepolia** at the same CREATE2 address 📄
  (`0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb`, IRM `0x46415998764C29aB2a25CbeA6254146D50D22687`).

## 4. Euler v2 (ERC4626Adapter)

Euler Vault Kit (EVK) vaults are ERC-4626 → same generic adapter.
- Base ✅: EVK Vault eWETH-1 `0x859160DB5841E5cfB8D3f144C6b3381A85A4b410` (WETH)
- Ethereum 📄: EVK Vault eUSDC-2 `0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9` (USDC)
- Euler v2 chains 📄: Ethereum, Base + others; EVC is the coordination layer (not
  needed for plain deposit/redeem — direct vault calls work for our JIT pattern).

## 5. Lido wstETH (WstETHAdapter) + Curve swapper

- **Ethereum** ✅: wstETH `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` (rate
  `stEthPerToken` ≈ 1.2436 verified), stETH `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`,
  Curve stETH/ETH pool `0xDC24316b9AE028F1497c275EB9192a3Ea0f67022` (coin0=ETH, coin1=stETH ✅).
- **L2s** 📄: wstETH bridged on Arbitrum, Optimism, Base, Polygon (contract differs per
  chain — verify before config). NOTE: the Curve stETH/ETH pool used by our swapper is
  Ethereum-only → on L2s the swap leg needs an alternative venue (Aerodrome/Uni V3
  wstETH pools) — adapter takes the swapper as config, so per-chain swappers plug in.
- Testnet: no official wstETH testnet deployments 📄.

## 6. Pendle (PendlePTAdapter)

Deploys: Ethereum, Arbitrum, BNB, Optimism, Mantle, **Base**, Sonic, Berachain,
HyperEVM, Monad, Ink, Katana (12 networks) + cross-chain PT via LayerZero 📄.
- **PendlePYLpOracle**: same address on every chain `0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2` ✅
  (Ethereum; `0x14418800e0b4c971905423aa873e83355922428c` also live) — verified on-chain.
- **Ethereum markets**:
  - ACTIVE PT-wstETH (expiry Dec 2027) ✅: market `0x34280882267ffa6383B363E278B027Be083bBe3b`,
    PT `0xb253Eff1104802b97aC7E3aC9FdD73AecE295a2c`, SY `0xcbC72d92b2dc8187414F6734718563898740C0BC`,
    YT `0x04B7Fa1e727d7290D6E24fA9b426d0c940283a95` — rate ≈ 0.783 wstETH/PT (implied
    fixed APY until Dec 2027).
  - EXPIRED PT-sUSDe-12AUG2026 ✅: market `0x177768caf9d0e036725a51d3f60d7e20f2d4d194`
    (underlying sUSDe — NOT JIT-friendly, needs Ethena unstake; avoid).
- **Arbitrum markets**:
  - EXPIRED PT-aUSDC-27JUN2024 ✅: market `0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5`,
    PT `0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c`, SY `0x50288c30c37FA1Ec6167a31E575EA8632645dE20`,
    YT `0xA1c32EF8d3c4c30cB596bAb8647e11daF0FA5C94` — redeem directly to native USDC ✅
    (zero swap legs). IDEAL fixed-income maker on Arbitrum.
- **Base markets**: live but not cataloged in this file yet — enumerate via the Pendle
  API `GET /core/v2/markets/all?chain_id=8453` before configuring Base PT strategies.
- Testnet: no documented Pendle testnet deployments 📄.
- The adapter discovers PT/SY/YT from the MARKET address — adding a new market = one
  address in config (must be EXPIRED for the v0.1 redemption path; ACTIVE needs the
  oracle path, also shipped).

## 7. Stargate V2 (StargateAdapter)

Deploys: 30+ chains (Ethereum, Arbitrum, Base, Optimism, Polygon, BNB, Avalanche,
Mantle, Linea, zkSync, Scroll, …) 📄.
- **Base** ✅: StargatePoolUSDC `0x27a16dc786820B16E5c9028b75B99F6f604b5d26`,
  LP `0x53983F31E8E0D0c3Fd0b8d85654989A1336317d7` ("S*USDC", 1:1 static),
  StargateStaking `0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80`,
  rewarder(lp) = `address(0)` (rewards NOT live on Base yet ✅-verified).
  Pool size at dev time: TVL ~37.9k USDC, instant credit ~30.8k USDC.
- **Ethereum** 📄: PoolUSDC `0xc026395860Db2d07ee33e05fE50ed7bD583189C7`,
  PoolNative(ETH) `0x77b2043768d28E9C9aB44E1aBfC95944bcE57931`,
  PoolUSDT `0x933597a323Eb81cAe705C5bC29985172fd5A3973`,
  Staking `0xFF551fEDdbeDC0aEe764139cCD9Cb644Bb04A6BD`,
  MultiRewarder `0x5871A7f88b0f3F5143Bf599Fd45F8C0Dc237E881`.
- Supported pool assets on Base: USDC ✅ (ETH pool flag unclear in docs 📄).
- Testnet: Stargate testnet deployments exist 📄 (see v2 docs
  "supported networks and assets") — not cataloged here.

## 8. Chainlink Data Feeds (ChainlinkGuardOpcode)

Verified on-chain ✅ (freshness + price checked at dev time):

| Chain | ETH/USD | USDC/USD |
|---|---|---|
| Base ✅ | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` |
| Arbitrum ✅ | `0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612` | `0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3` |
| Ethereum ✅ | `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419` | `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6` |

- Note: Base feeds update at long heartbeats for stablecoins (USDC/USD ~12h) — the
  guard uses per-feed staleness bounds (3600s volatile, 86400s stable) for this reason.
- Other chains: use docs.chain.link addresses page; always verify on-chain (freshness +
  price sanity) before hardcoding — several "documented" Base/Arbitrum addresses
  returned no code during our checks.
- Testnet feeds 📄: Sepolia BTC/USD `0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43`,
  Sepolia ETH/USD `0x694AA1769357215DE4FAC081bf1f309aDC325306`; L2 sequencer uptime
  feeds also exist (grace-period check recommended for L2s in production).

## 9. Core tokens (deliverables)

| Chain | WETH | USDC | wstETH |
|---|---|---|---|
| Ethereum ✅ | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` |
| Base ✅ | `0x4200000000000000000000000000000000000006` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 📄 verify before use |
| Arbitrum ✅ | `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1` | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | 📄 |

---

## Composition matrix — what can we deploy where

A strategy needs: (1) Aqua registry + OUR router, (2) an adapter target, (3) a
Chainlink feed for the guard. Every chain in the Aqua set has (1) and (3)-eligible
feeds; the adapter target decides:

| Chain | Aave v3 | Morpho 4626 | Euler 4626 | wstETH | Pendle PT | Stargate LP |
|---|---|---|---|---|---|---|
| Base | ✅ proven | ✅ proven | ✅ proven | swap-leg venue ⚠ | markets exist 📄 | ✅ proven |
| Arbitrum | 📄 (v3 live) | 📄 | — | ⚠ | ✅ proven (expired aUSDC PT) | 📄 bigger pool |
| Ethereum | 📄 (v3 live) | 📄 | 📄 | ✅ proven | ✅ proven (active PT-wstETH) | 📄 |
| Optimism / Polygon / Avalanche / BNB / Gnosis / Sonic / Linea | 📄 (v3 live) | 📄 (subset) | — | 📄 (subset) | 📄 (subset) | 📄 |
| zkSync / Unichain / Robinhood | ⚠ partial / none | 📄 (Unichain) | — | — | — | 📄 |

✅ proven = fork-tested in this repo · ⚠ = works but needs a per-chain swapper ·
— = not deployed / not confirmed

**Recommended launch chains**: Base (everything verified, our home) → Arbitrum
(Pendle fixed-income USDC maker with the real expired PT) → Ethereum (active-PT
fixed income on wstETH).

## Housekeeping rules

- NEVER trust a documented address blindly: several Chainlink feed addresses found in
  third-party lists had NO code on-chain. Always `cast call` sanity-check (symbol /
  asset / a fresh answer) before baking into config.
- Pendle markets expire: always read `isExpired()` + `expiry()` and record the state in
  the strategy config; expired PTs keep redeeming 1:1 forever, active ones move.
- Stargate credit is planner-driven and per-chain — re-check `redeemable()` before
  sizing fills.
