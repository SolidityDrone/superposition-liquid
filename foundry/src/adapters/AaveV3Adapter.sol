// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { IPool } from "@aave/core/interfaces/IPool.sol";
import { IAToken } from "@aave/core/interfaces/IAToken.sol";
import { DataTypes } from "@aave/core/protocol/libraries/types/DataTypes.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

/// @title AaveV3Adapter
/// @notice ILendingAdapter implementation for Aave v3.
/// @dev All conversions use the *displayed* aToken unit (what `balanceOf` returns).
///      On Aave v3.2+ markets balances are already index-accrued, so the displayed
///      unit tracks underlying 1:1 and yield accrues as balance growth. On legacy
///      markets the displayed unit is the scaled balance and the rate is the
///      liquidity index. Both cases are covered by:
///        rate = scaledTotalSupply * liquidityIndex / totalSupply
///      (== 1e18 on v3.2+, == liquidityIndex on legacy).
contract AaveV3Adapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant WAD = 1e18;

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
        uint256 rate = exchangeRate(underlying);
        return (amount * WAD + rate - 1) / rate;
    }

    function yieldToUnderlying(address underlying, uint256 amount) external view returns (uint256) {
        return amount * exchangeRate(underlying) / WAD;
    }

    /// @notice Underlying per 1 displayed aToken, 1e18 precision (see contract docs).
    function exchangeRate(address underlying) public view returns (uint256) {
        DataTypes.ReserveData memory reserve = AAVE_POOL.getReserveData(underlying);
        if (reserve.aTokenAddress == address(0)) return WAD;
        uint256 scaledTotal = IAToken(reserve.aTokenAddress).scaledTotalSupply();
        uint256 displayedTotal = IERC20(reserve.aTokenAddress).totalSupply();
        if (scaledTotal == 0 || displayedTotal == 0) return uint256(reserve.liquidityIndex) / 1e9;
        // underlying backing = scaledTotal * index / RAY; rate = backing * WAD / displayedTotal
        return scaledTotal * uint256(reserve.liquidityIndex) * WAD / (displayedTotal * RAY);
    }

    /// @notice Withdraws underlying on behalf of maker.
    /// Pulls the equivalent displayed aTokens from the maker wallet (maker approved this
    /// adapter), then withdraws from Aave sending real tokens to recipient.
    function withdrawTo(address maker, address underlying, uint256 underlyingAmount, address recipient) external {
        address aToken = AAVE_POOL.getReserveData(underlying).aTokenAddress;
        uint256 aTokenAmount = this.underlyingToYield(underlying, underlyingAmount);
        IERC20(aToken).safeTransferFrom(maker, address(this), aTokenAmount);
        AAVE_POOL.withdraw(underlying, underlyingAmount, recipient);
    }

    /// @notice Deposits underlying on behalf of maker.
    /// Pulls tokens from the maker wallet (tokenIn arrives there after the swap),
    /// supplies to Aave minting displayed aTokens to the maker.
    function depositFor(address maker, address underlying, uint256 underlyingAmount) external {
        IERC20(underlying).safeTransferFrom(maker, address(this), underlyingAmount);
        IERC20(underlying).forceApprove(address(AAVE_POOL), underlyingAmount);
        AAVE_POOL.supply(underlying, underlyingAmount, maker, 0);
    }
}
