# Address Reference

## Base mainnet (verified on-chain Sep 2026)

| Contract | Address |
|---|---|
| Aqua registry | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` |
| SwapVM router | `0x111111338c5091E8440b67B168bAe16a668AC0De` |
| Aave v3 Pool | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| WETH | `0x4200000000000000000000000000000000000006` |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| aWETH | `0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7` |
| aUSDC | `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB` |
| Morpho Gauntlet WETH Core | `0x6b13c060F13Af1fdB319F52315BbbF3fb1D88844` |
| Morpho Steakhouse Prime USDC | `0xBEEFE94c8aD530842bfE7d8B397938fFc1cb83b2` |
| Euler EVK eWETH-1 | `0x859160DB5841E5cfB8D3f144C6b3381A85A4b410` |
| Stargate V2 PoolUSDC | `0x27a16dc786820B16E5c9028b75B99F6f604b5d26` |
| Stargate V2 Staking | `0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80` |
| Chainlink ETH/USD | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` |
| Chainlink USDC/USD | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` |

## Ethereum Sepolia (testnet)

| Contract | Address |
|---|---|
| Aqua registry | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` |
| SwapVM router | `0x111111338c5091E8440b67B168bAe16a668AC0De` |
| Aave v3 Pool | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` |
| WETH | `0xfff9976782d46cc05630d1f6ebab18b2324d6b14` |
| USDC | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` |
| aWETH | `0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830` |
| aUSDC | `0x16dA4541aD1807f4443d92D26044C1147406EB80` |
| Chainlink ETH/USD | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |
| Chainlink USDC/USD | `0xA2F22CF35C20Fa56c3Daa4C560e76531A4573ad2` |
| Stargate V2 PoolUSDC | `0x4985b8fcEA3659FD801a5b857dA1D00e985863F0` |
| Stargate V2 Staking | `0xE62F51D9DA2b082abed838E9Ac48D0EDFFbfedaE` |

## Base Sepolia (testnet)

> ⚠️ **Aqua and the 1inch SwapVM router are NOT deployed on Base Sepolia** (the vanity
> `0x111…` addresses have no code there). We therefore **deploy our own Aqua** and the
> SuperPosition stack, and use it end-to-end (see below).

**External**

| Contract | Address | Notes |
|---|---|---|
| Aave v3 Pool | `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27` | reserves: USDC · USDT · WBTC · WETH · cbETH · LINK |
| Aave DataProvider | `0xBc9f5b7E248451CdD7cA54e717a2BFe1F32b566b` | |
| Aave faucet | `0xD9145b5F45Ad4519c7ACcD6E0A4A82e83bB8A6Dc` | `mint(token,to,amount)` permissionless, **per-recipient timelock** |
| WETH | `0x4200000000000000000000000000000000000006` | canonical L2 |
| USDC (Aave reserve) | `0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f` | 6dp |
| USDT (Aave reserve) | `0x0a215D8ba66387DCA84B284D18c3B4ec3de6E54a` | 6dp |
| aWETH | `0x73a5bB60b0B0fc35710DDc0ea9c407031E31Bdbb` | |
| aUSDC | `0x10F1A9D11CDf50041f3f8cB7191CBE2f31750ACC` | |
| aUSDT | `0xcE3CAae5Ed17A7AafCEEbc897DE843fA6CC0c018` | |

**SuperPosition app stack (our deploy — Sourcify `exact_match`, 11/11)**

| Contract | Address |
|---|---|
| Aqua (ours) | `0x06DC4edCF4F3ABdFa65Cc4fD58AB459B5ff20F9e` |
| MakerConfig | `0x0196eeF216fAF47DE34bcbEd5fB1ab4f97A932ee` |
| SuperPositionVMRouter | `0x4fefc5D38eE27f09F68484574A3B4AAC914d4097` |
| AaveV3Adapter | `0x56BE9DC69c798BC8B7567958b1B45f4b6e4502eb` |
| ERC4626Adapter (USDC/USDT vaults) | `0x0f47Ca0065B7f0Ff00eEDf6D92D977389Aa8CcbF` |
| spUSDC (Aave-backed ERC-4626) | `0x126b97C6AF4748118504A993e97EbAA1cb863576` |
| spUSDT (Aave-backed ERC-4626) | `0x682E0DBEF9Ce3487b06F961A8667fBdcb2093396` |
| SuperpositionHook (v4, USDT/USDC) | `0x2F6bA013a29967F3A638887f8BefB18424658Ac0` |
| SuperpositionUniAdapter | `0x81e92e910B978e5F3865E4E815660725662EE236` |
| OrderBuilder | `0x7a8F11c29FD46e21aA70638f8f6BA62777cf920C` |
| HookLpHelper | `0x24F0A572A6A7Ae73322aB5B19Ee83d50343A5D23` |
| SepoliaFaucetBatch | `0xbe135721492C6525cAf47454aEEFc37B378bf895` |
| poolId | `0x61ba18cc22f164da8266f5335986bc2d38edd40a8e997c413376b70ea2dc98bf` |

Deploy script: `foundry/script/base-sepolia/DeployBaseSepolia.s.sol` (deploys our Aqua, the stack,
the v4 hook via CREATE2, and the testnet helpers). No official StataToken (waToken) factory on
Base Sepolia — the ERC-4626 wrapper is our `Aave4626Vault` (holds **real** aTokens; USDC/USDT/WETH
reserves are **not** supply-capped here).

**Live swaps (demo deployment, same bytecode)**

| Demo | Tx |
|---|---|
| USDC→WETH · `ship` | [`0x8d7ea4…`](https://sepolia.basescan.org/tx/0x8d7ea40c376dfa76e1748b4bfb9a6623dff6839714d8797aa9b68611309f595a) |
| USDC→WETH · `swap` | [`0xc5871d…`](https://sepolia.basescan.org/tx/0xc5871d8b99e98fc1fb7311f89050568678f6bbeef87ac00294e6bcc1fb583f16) |
| USDC→USDT · `ship` | [`0xa1991f…`](https://sepolia.basescan.org/tx/0xa1991fb8f22245622d2c5c07b2e58104f3e291c000b5ff14ee8d8fa199d293dd) |
| USDC→USDT · `swap` | [`0x91db65…`](https://sepolia.basescan.org/tx/0x91db65a7c83a2ef15a1a3071483e7a0ee542e6c4080b9f15ccbc97e62f553526) |



## Arbitrum Sepolia (testnet)

| Contract | Address |
|---|---|
| Aqua registry | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` |
| SwapVM router | `0x111111338c5091E8440b67B168bAe16a668AC0De` |
| WETH | `0x980B62Da83Ff3D742ac43b2A95c4cf3345De64a1` |
| USDC | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` |
| Chainlink ETH/USD | `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` |
| Chainlink USDC/USD | `0x0153002d20B96532C639313c2d54c3dA09109309` |
