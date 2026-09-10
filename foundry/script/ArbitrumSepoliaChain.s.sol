// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ArbitrumSepoliaChain
/// @notice Arbitrum Sepolia testnet addresses (verified on-chain Sep 2026):
///         Aqua registry + SwapVM router are the same vanity addresses as mainnet.
library ArbitrumSepoliaChain {
    string internal constant RPC_URL = "https://sepolia-rollup.arbitrum.io/rpc";

    // Aqua — same vanity address as mainnet
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant SWAPVM_ROUTER = 0x111111338c5091E8440b67B168bAe16a668AC0De;

    // Tokens
    address internal constant WETH = 0x980B62Da83fF3D742AC43b2a95c4cF3345dE64a1; // canonical testnet WETH
    address internal constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; // Circle USDC

    // Chainlink price feeds
    address internal constant CHAINLINK_ETH_USD = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
    address internal constant CHAINLINK_USDC_USD = 0x0153002d20B96532C639313c2d54c3dA09109309;
}
