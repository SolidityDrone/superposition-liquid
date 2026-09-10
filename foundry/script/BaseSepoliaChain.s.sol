// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title BaseSepoliaChain
/// @notice Base Sepolia testnet addresses (verified on-chain Sep 2026):
///         Aqua registry + SwapVM router are the same vanity addresses as mainnet.
library BaseSepoliaChain {
    string internal constant RPC_URL = "https://sepolia.base.org";

    // Aqua — same vanity address as mainnet
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant SWAPVM_ROUTER = 0x111111338c5091E8440b67B168bAe16a668AC0De;

    // Tokens
    address internal constant WETH = 0x4200000000000000000000000000000000000006; // canonical L2 WETH
    address internal constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Circle USDC

    // Aave v3 (Base Sepolia market) — only WETH registered; USDC not listed
    address internal constant AAVE_POOL = 0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27;
    address internal constant A_WETH = 0x73a5bB60b0B0fc35710DDc0ea9c407031E31Bdbb; // underlying = WETH (verified)
    // address internal constant A_USDC = 0x...; // NOT registered as a reserve on Base Sepolia Aave

    // Chainlink price feeds
    address internal constant CHAINLINK_ETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    address internal constant CHAINLINK_USDC_USD = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
}
