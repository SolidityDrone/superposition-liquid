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

    /// @dev The aTokens were pulled maker -> this adapter by the ROUTER (plan:
    ///      displayed count for the underlying, rounded up) — the pool burns them
    ///      from this adapter's balance and delivers real tokens to recipient.
    function withdraw(
        address maker,
        address underlying,
        uint256 underlyingAmount,
        uint256 yieldAmount,
        address recipient
    ) external {
        maker;
        yieldAmount;
        AAVE_POOL.withdraw(underlying, underlyingAmount, recipient);
    }

    /// @dev Pull plan for the JIT delivery: the displayed aToken count covering
    ///      `underlyingAmount`, rounded up, delivered to this adapter.
    function pullPlan(address maker, address underlying, uint256 underlyingAmount)
        external view
        returns (address token, uint256 amount, address to)
    {
        maker;
        token = AAVE_POOL.getReserveData(underlying).aTokenAddress;
        amount = this.underlyingToYield(underlying, underlyingAmount);
        to = address(this);
    }

    /// @notice Simulated withdrawal: min(maker position, pool cash).
    /// Pool cash = supplied (underlying-equivalent) - debt - unbacked.
    function maxWithdrawable(address maker, address underlying) external view returns (uint256) {
        DataTypes.ReserveData memory reserve = AAVE_POOL.getReserveData(underlying);
        if (reserve.aTokenAddress == address(0)) return 0;
        uint256 position = this.yieldToUnderlying(underlying, IERC20(reserve.aTokenAddress).balanceOf(maker));
        uint256 supplied = this.yieldToUnderlying(underlying, IERC20(reserve.aTokenAddress).totalSupply());
        uint256 debt;
        if (reserve.stableDebtTokenAddress != address(0)) debt += IERC20(reserve.stableDebtTokenAddress).totalSupply();
        if (reserve.variableDebtTokenAddress != address(0)) debt += IERC20(reserve.variableDebtTokenAddress).totalSupply();
        uint256 cash = supplied > debt + uint256(reserve.unbacked) ? supplied - debt - uint256(reserve.unbacked) : 0;
        return position < cash ? position : cash;
    }

    /// @dev The underlying was pulled maker -> this adapter by the ROUTER:
    ///      supplies to Aave minting displayed aTokens to the maker.
    function deposit(address maker, address underlying, uint256 underlyingAmount) external {
        IERC20(underlying).forceApprove(address(AAVE_POOL), underlyingAmount);
        AAVE_POOL.supply(underlying, underlyingAmount, maker, 0);
    }
}
