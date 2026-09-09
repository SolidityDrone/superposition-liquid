# superposition-liquid — Supercazzola Brematurata

A custom SwapVM router (1inch Aqua) where makers provide ETH/USDC liquidity while holding
100% of their capital in a yield-bearing lending protocol (Aave v3). From the outside it
looks like a normal ETH/USDC AMM position; internally every fill cycles capital through
Aave atomically via maker transfer hooks ("JIT-unwrap"). Maker earns swap fees + lending
APY on the same capital. Adapter-based: any lending protocol can plug in per-maker.

Built for ETHGlobal ETHOnline 2026. Bounties: 1inch Aqua (primary), Chainlink Data Feeds (secondary).

See [SPEC.md](SPEC.md) for the full design + decision log.

## How it works

```
swap() on SupercazzolaRouter (modified SwapVM redeploy — allowed by 1inch rules)
  program: [YieldAdjustedRateXD][flatFeeIn][xycSwapXD][ChainlinkGuardXD]
             ^ aToken count * exchange rate    ^ MEV guard vs Chainlink feeds

  preTransferOut hook  -> withdraw amountOut from Aave into the maker wallet (JIT)
  Aqua.pull (default)  -> deliver real WETH to the taker from the maker wallet
  Aqua.push (default)  -> taker's USDC lands in the maker wallet
  postTransferIn hook  -> deposit the received USDC back into Aave for the maker
```

The maker wallet only holds tokens for the duration of one transaction — idle balance is
always zero, 100% of capital sits in the lending protocol earning supply APY on top of swap fees.

The adapter layer is pluggable per maker: v0.1 ships `AaveV3Adapter` plus a generic
`ERC4626Adapter` (Morpho MetaMorpho, Euler v2, any 4626 vault). A delta-neutral borrow-based
profile is designed and deferred to v0.2 (requires health-factor management).

## Repo layout

```
foundry/
  src/
    SupercazzolaRouter.sol        # SwapVM fork + hooks + custom opcode table
    config/MakerConfig.sol        # per-maker vault config (msg.sender-owned)
    adapters/AaveV3Adapter.sol    # ILendingAdapter impl (Aave v3, v3.2+ aware)
    adapters/ERC4626Adapter.sol   # generic adapter: Morpho (MetaMorpho), Euler v2, any 4626 vault
    interfaces/                   # ILendingAdapter, AggregatorV3Interface
    opcodes/
      YieldAdjustedRateOpcode.sol # byte 34: balances * lending exchange rate
      ChainlinkGuardOpcode.sol    # byte 35: price deviation + staleness guard
      SupercazzolaOpcodes.sol     # AquaOpcodes table + 2 appended opcodes
  script/
    BaseChain.s.sol               # verified Base mainnet addresses
    Deploy.s.sol                  # deploy stack
    Demo.s.sol                    # one-shot E2E demo (see below)
  test/
    unit/                         # TDD unit tests on mocks
    unit/invariants/              # JIT invariants (fuzz, 256 runs)
    fork/BaseFork.t.sol           # Base mainnet fork E2E (real Aqua/Aave/Chainlink)
  lib/                            # submodules: swap-vm v1.0.1, aqua v1.0.0, aave-v3-core,
                                  # openzeppelin v5.4.0, solidity-utils 6.9.7, forge-std
```

## Setup

```bash
cd foundry
forge build && forge test          # 37 tests (unit + fuzz + Base fork E2E)
```

The fork test forks Base mainnet (public RPC by default; override with `RPC_URL_BASE`).

## Demo

Two ways to present the onchain execution (both use a Base fork):

```bash
# 1) full E2E as a forge test (real Aqua registry, real Aave v3, real Chainlink feeds)
forge test --match-contract BaseForkTest -vvvv

# 2) scripted walkthrough with per-step capital logs
anvil --fork-url https://mainnet.base.org --port 8545 &
forge script script/Demo.s.sol --rpc-url http://localhost:8545
```

Note: `Demo.s.sol` funds the demo wallets with the `deal` cheatcode, so it runs without
`--broadcast` (the script execution is real onchain interaction against the fork — every
swap, deposit, withdrawal and fee flows through the real contracts). `BaseForkTest` is the
broadcast-style proof and needs no cheats except funding.

## Base addresses (verified on-chain, see `script/BaseChain.s.sol`)

| Contract | Address |
|---|---|
| Aqua registry | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` |
| Aave v3 Pool | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| WETH / aWETH | `0x4200…0006` / `0xD4a0…8bb7` |
| USDC / aUSDC | `0x8335…2913` / `0x4e65…c0AB` |
| Chainlink ETH/USD | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` |
| Chainlink USDC/USD | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` |
