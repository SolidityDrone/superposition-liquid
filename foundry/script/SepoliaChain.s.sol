// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title SepoliaChain
/// @notice Ethereum Sepolia testnet addresses (verified on-chain Sep 2026):
///         Aqua registry + SwapVM router are the same vanity addresses as mainnet.
library SepoliaChain {
    string internal constant RPC_URL = "https://ethereum-sepolia.publicnode.com";

    // Aqua — same vanity address as mainnet
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant SWAPVM_ROUTER = 0x111111338c5091E8440b67B168bAe16a668AC0De;

    // Tokens
    address internal constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // Sepolia WETH
    address internal constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // Aave testnet USDC

    // Aave v3 (Sepolia market)
    address internal constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address internal constant A_WETH = 0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830;
    address internal constant A_USDC = 0x16dA4541aD1807f4443d92D26044C1147406EB80;

    // Chainlink price feeds
    address internal constant CHAINLINK_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address internal constant CHAINLINK_USDC_USD = 0xA2f22CF35C20FA56c3DAA4C560e76531A4573ad2; // Sepolia USDC/USD

    // Stargate V2 (Sepolia)
    address internal constant STARGATE_POOL = 0x4985b8fcEA3659FD801a5b857dA1D00e985863F0; // StargatePoolUSDC
    address internal constant STARGATE_STAKING = 0xE62F51D9DA2b082abed838E9Ac48D0EDFFbfedaE;
}
