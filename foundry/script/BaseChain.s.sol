// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title BaseChain
/// @notice Verified Base mainnet addresses (checked on-chain Sep 2026):
///         Aave Pool income rates live, aTokens resolve, Chainlink feeds fresh.
library BaseChain {
    string internal constant RPC_URL = "https://mainnet.base.org";

    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a; // Aqua registry (from deployed router AQUA())
    address internal constant SWAPVM_ROUTER = 0x111111338c5091E8440b67B168bAe16a668AC0De; // deployed AquaSwapVMRouter v1.0.2 (reference)
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5; // Aave v3 Pool (AaveAddressBook)
    address internal constant A_WETH = 0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7; // verified: underlying = WETH
    address internal constant A_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB; // verified: underlying = USDC
    address internal constant CHAINLINK_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70; // verified live
    address internal constant CHAINLINK_USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B; // verified live

    // Real ERC-4626 vaults on Base (verified on-chain: asset(), convertToAssets, totalSupply)
    address internal constant MORPHO_WETH_VAULT = 0x6b13c060F13Af1fdB319F52315BbbF3fb1D88844; // Gauntlet WETH Core (MetaMorpho)
    address internal constant MORPHO_USDC_VAULT = 0xBEEFE94c8aD530842bfE7d8B397938fFc1cb83b2; // Steakhouse Prime USDC (MetaMorpho)
    address internal constant EULER_WETH_VAULT = 0x859160DB5841E5cfB8D3f144C6b3381A85A4b410; // EVK Vault eWETH-1 (Euler v2)
}
