// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { IPool } from "@aave/core/interfaces/IPool.sol";
import { DataTypes } from "@aave/core/protocol/libraries/types/DataTypes.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

/// @title AaveV3Adapter
/// @notice ILendingAdapter implementation for Aave v3.
/// @dev Rate source is exclusively IPool.getReserveNormalizedIncome (decision B3.3 in SPEC.md).
contract AaveV3Adapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    uint256 internal constant RAY = 1e27;

    IPool public immutable AAVE_POOL;

    constructor(address pool) {
        AAVE_POOL = IPool(pool);
    }

    function name() external pure returns (string memory) {
        return "AaveV3";
    }

    function yieldToken(address underlying) external view returns (address) {
        return AAVE_POOL.getReserveData(underlying).aTokenAddress;
    }

    function underlyingToYield(address underlying, uint256 amount) external view returns (uint256) {
        return (amount * RAY + AAVE_POOL.getReserveNormalizedIncome(underlying) - 1)
            / AAVE_POOL.getReserveNormalizedIncome(underlying);
    }

    function yieldToUnderlying(address underlying, uint256 amount) external view returns (uint256) {
        return amount * AAVE_POOL.getReserveNormalizedIncome(underlying) / RAY;
    }

    /// @notice Underlying per 1 aToken, 1e18 precision (ray scaled down by 1e9).
    function exchangeRate(address underlying) external view returns (uint256) {
        return AAVE_POOL.getReserveNormalizedIncome(underlying) / 1e9;
    }

    /// @notice Withdraws underlying on behalf of maker.
    /// Pulls the equivalent aTokens from the maker wallet (maker approved this adapter),
    /// then withdraws from Aave sending real tokens to recipient.
    function withdrawTo(address maker, address underlying, uint256 underlyingAmount, address recipient) external {
        address aToken = AAVE_POOL.getReserveData(underlying).aTokenAddress;
        uint256 aTokenAmount = this.underlyingToYield(underlying, underlyingAmount);
        IERC20(aToken).safeTransferFrom(maker, address(this), aTokenAmount);
        AAVE_POOL.withdraw(underlying, underlyingAmount, recipient);
    }

    /// @notice Deposits underlying on behalf of maker.
    /// Pulls tokens from the maker wallet (tokenIn arrives there after the swap),
    /// supplies to Aave minting aTokens to the maker.
    function depositFor(address maker, address underlying, uint256 underlyingAmount) external {
        IERC20(underlying).safeTransferFrom(maker, address(this), underlyingAmount);
        IERC20(underlying).forceApprove(address(AAVE_POOL), underlyingAmount);
        AAVE_POOL.supply(underlying, underlyingAmount, maker, 0);
    }
}
