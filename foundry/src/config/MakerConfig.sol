// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

struct MakerVaultConfig {
    address adapter; // ILendingAdapter to use
    address underlyingIn; // e.g. USDC (what maker receives -> deposits)
    address underlyingOut; // e.g. WETH (what maker sends -> withdraws)
    bool autoDepositIn; // if true, postTransferInHook deposits tokenIn
    bool autoWithdrawOut; // if true, preTransferOutHook withdraws tokenOut
}

/// @title MakerConfig
/// @notice Per-maker vault configuration for the SupercazzolaRouter.
/// @dev Write is restricted to the maker itself (msg.sender); reads are permissionless.
contract MakerConfig {
    error AdapterZero();

    mapping(address maker => MakerVaultConfig) public configs;

    function setConfig(MakerVaultConfig calldata config) external {
        if (config.adapter == address(0)) revert AdapterZero();
        configs[msg.sender] = config;
    }

    function getConfig(address maker) external view returns (MakerVaultConfig memory) {
        return configs[maker];
    }
}
