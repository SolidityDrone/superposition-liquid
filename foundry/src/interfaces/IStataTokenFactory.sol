// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IStataTokenFactory
/// @notice Aave's permissionless StataToken (wrapped aToken) factory / registry.
///         `getStataToken` returns the ERC-4626 wrapper for an underlying, or address(0)
///         if none exists; `createStataTokens` deploys one.
interface IStataTokenFactory {
    function getStataToken(address underlying) external view returns (address);
    function createStataTokens(address[] memory underlyings) external returns (address[] memory);
}
