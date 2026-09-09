// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ILendingAdapter
/// @notice Core abstraction: every lending protocol plugs into the SupercazzolaRouter
///         through this interface (SPEC.md — adapters section).
interface ILendingAdapter {
    /// @notice Human-readable name, e.g. "AaveV3"
    function name() external view returns (string memory);

    /// @notice Returns the yield-bearing token for a given underlying.
    /// e.g. underlying=WETH → yieldToken=aWETH
    function yieldToken(address underlying) external view returns (address);

    /// @notice Converts underlying amount to yield token amount at current rate (rounded up).
    function underlyingToYield(address underlying, uint256 amount) external view returns (uint256);

    /// @notice Converts yield token amount to underlying at current rate.
    function yieldToUnderlying(address underlying, uint256 amount) external view returns (uint256);

    /// @notice Current exchange rate: how many underlying per 1 yield token (1e18 precision).
    /// Used by the SwapVM opcode for accurate quoting.
    function exchangeRate(address underlying) external view returns (uint256);

    /// @notice Withdraw `underlyingAmount` of `underlying` from the protocol on behalf of
    /// `maker`, sending real tokens to `recipient`. Pulls the equivalent yield tokens from
    /// the maker wallet — maker must have approved this adapter for yield token spending.
    function withdrawTo(address maker, address underlying, uint256 underlyingAmount, address recipient) external;

    /// @notice Deposit `underlyingAmount` of `underlying` into the protocol on behalf of
    /// `maker`. Pulls the tokens from the maker wallet — maker must have approved this
    /// adapter for underlying spending.
    function depositFor(address maker, address underlying, uint256 underlyingAmount) external;
}
