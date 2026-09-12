// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { IPool } from "@aave/core/interfaces/IPool.sol";
import { IAToken } from "@aave/core/interfaces/IAToken.sol";
import { IPriceOracleGetter } from "@aave/core/interfaces/IPriceOracleGetter.sol";
import { DataTypes } from "@aave/core/protocol/libraries/types/DataTypes.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";
import { MakerConfig, BorrowConfig } from "src/config/MakerConfig.sol";

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
    uint256 internal constant BPS = 10_000;
    uint256 internal constant VARIABLE_RATE_MODE = 2;

    IPool public immutable AAVE_POOL;
    /// @dev Optional: the maker registry that holds per-token BorrowConfig. When
    ///      address(0) (plain supply adapter, e.g. tests) borrow mode is off.
    MakerConfig public immutable MAKER_CONFIG;

    constructor(address pool, address makerConfig) {
        AAVE_POOL = IPool(pool);
        MAKER_CONFIG = MakerConfig(makerConfig);
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
        if (reserve.aTokenAddress == address(0)) {
            return WAD;
        }
        uint256 scaledTotal = IAToken(reserve.aTokenAddress).scaledTotalSupply();
        uint256 displayedTotal = IERC20(reserve.aTokenAddress).totalSupply();
        if (scaledTotal == 0 || displayedTotal == 0) {
            return uint256(reserve.liquidityIndex) / 1e9;
        }
        // underlying backing = scaledTotal * index / RAY; rate = backing * WAD / displayedTotal
        return scaledTotal * uint256(reserve.liquidityIndex) * WAD / (displayedTotal * RAY);
    }

    /// @dev The aTokens were pulled maker -> this adapter by the ROUTER (plan:
    ///      displayed count for the underlying, rounded up) — the pool burns them
    ///      from this adapter's balance and delivers real tokens to recipient. If
    ///      the side is borrow-enabled and the position is short, borrow the rest.
    function withdraw(
        address maker,
        address underlying,
        uint256 underlyingAmount,
        uint256 yieldAmount,
        address recipient
    )
        external
    {
        uint256 withdrawn = yieldAmount == 0 ? 0 : this.yieldToUnderlying(underlying, yieldAmount);
        if (withdrawn > underlyingAmount) {
            withdrawn = underlyingAmount;
        }
        if (withdrawn > 0) {
            AAVE_POOL.withdraw(underlying, withdrawn, recipient);
        }
        uint256 shortfall = underlyingAmount - withdrawn;
        if (shortfall > 0 && _borrowConfig(maker, underlying).enabled) {
            AAVE_POOL.borrow(underlying, shortfall, VARIABLE_RATE_MODE, 0, maker);
            IERC20(underlying).safeTransfer(recipient, shortfall);
        }
    }

    /// @dev Pull plan for the JIT delivery: the displayed aToken count covering
    ///      `underlyingAmount`, rounded up, delivered to this adapter. On a
    ///      borrow-enabled side with no position, pull nothing (the adapter
    ///      sources the tokens by borrowing); with a partial position, pull at
    ///      most what the maker actually holds.
    function pullPlan(
        address maker,
        address underlying,
        uint256 underlyingAmount
    )
        external
        view
        returns (address token, uint256 amount, address to)
    {
        DataTypes.ReserveData memory reserve = AAVE_POOL.getReserveData(underlying);
        token = reserve.aTokenAddress;
        if (token == address(0)) {
            return (address(0), 0, address(0));
        }
        uint256 need = this.underlyingToYield(underlying, underlyingAmount);
        if (_borrowConfig(maker, underlying).enabled) {
            uint256 bal = IERC20(token).balanceOf(maker);
            if (bal == 0) {
                return (address(0), 0, address(0));
            }
            amount = need < bal ? need : bal;
        } else {
            amount = need;
        }
        to = address(this);
    }

    /// @notice Simulated withdrawal: min(maker position, pool cash), plus the
    ///         remaining borrow headroom on a borrow-enabled side.
    /// Pool cash = supplied (underlying-equivalent) - debt - unbacked.
    function maxWithdrawable(address maker, address underlying) external view returns (uint256) {
        DataTypes.ReserveData memory reserve = AAVE_POOL.getReserveData(underlying);
        if (reserve.aTokenAddress == address(0)) {
            return 0;
        }
        uint256 position = this.yieldToUnderlying(underlying, IERC20(reserve.aTokenAddress).balanceOf(maker));
        uint256 supplied = this.yieldToUnderlying(underlying, IERC20(reserve.aTokenAddress).totalSupply());
        uint256 debt;
        if (reserve.stableDebtTokenAddress != address(0)) {
            debt += IERC20(reserve.stableDebtTokenAddress).totalSupply();
        }
        if (reserve.variableDebtTokenAddress != address(0)) {
            debt += IERC20(reserve.variableDebtTokenAddress).totalSupply();
        }
        uint256 cash = supplied > debt + uint256(reserve.unbacked) ? supplied - debt - uint256(reserve.unbacked) : 0;
        uint256 base = position < cash ? position : cash;
        if (_borrowConfig(maker, underlying).enabled) {
            base += _borrowHeadroom(maker, underlying);
        }
        return base;
    }

    /// @dev The underlying was pulled maker -> this adapter by the ROUTER. On a
    ///      borrow-enabled side, repay outstanding debt FIRST, then supply the
    ///      remainder (this is what closes the position on the matching in-fill).
    function deposit(address maker, address underlying, uint256 underlyingAmount) external {
        uint256 repayAmount = 0;
        if (_borrowConfig(maker, underlying).enabled) {
            uint256 debt = _debtOf(maker, underlying);
            repayAmount = underlyingAmount < debt ? underlyingAmount : debt;
            if (repayAmount > 0) {
                IERC20(underlying).forceApprove(address(AAVE_POOL), repayAmount);
                AAVE_POOL.repay(underlying, repayAmount, VARIABLE_RATE_MODE, maker);
            }
        }
        uint256 remaining = underlyingAmount - repayAmount;
        if (remaining > 0) {
            IERC20(underlying).forceApprove(address(AAVE_POOL), remaining);
            AAVE_POOL.supply(underlying, remaining, maker, 0);
        }
    }

    // --- Borrow mode internals ---

    /// @dev Empty config when the adapter was deployed without a registry.
    function _borrowConfig(address maker, address underlying) internal view returns (BorrowConfig memory) {
        if (address(MAKER_CONFIG) == address(0)) {
            return BorrowConfig({ enabled: false, collateral: address(0), maxDebt: 0 });
        }
        return MAKER_CONFIG.borrowConfigOf(maker, underlying);
    }

    /// @dev The maker's variable debt for `underlying` (displayed, interest-accrued).
    function _debtOf(address maker, address underlying) internal view returns (uint256) {
        DataTypes.ReserveData memory reserve = AAVE_POOL.getReserveData(underlying);
        if (reserve.variableDebtTokenAddress == address(0)) {
            return 0;
        }
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(maker);
    }

    /// @dev Borrow capacity: min(protocol available borrows, the configured
    ///      collateral's own capacity, the maker's risk capacitor).
    function _borrowHeadroom(address maker, address underlying) internal view returns (uint256) {
        BorrowConfig memory bc = _borrowConfig(maker, underlying);
        (,, uint256 availableBase,,,) = AAVE_POOL.getUserAccountData(maker);
        uint256 headroom = _baseToUnderlying(underlying, availableBase);
        if (bc.collateral != address(0)) {
            uint256 collCap = _baseToUnderlying(underlying, _collateralCapacityBase(maker, bc.collateral));
            if (collCap < headroom) {
                headroom = collCap;
            }
        }
        if (bc.maxDebt != 0 && bc.maxDebt < headroom) {
            headroom = bc.maxDebt;
        }
        return headroom;
    }

    /// @dev Borrow capacity contributed by a single collateral, in base currency:
    ///      collateral underlying value * its own LTV. Soft isolation: caps the
    ///      offered liquidity to what the configured token alone can back.
    function _collateralCapacityBase(address maker, address collateral) internal view returns (uint256) {
        DataTypes.ReserveData memory reserve = AAVE_POOL.getReserveData(collateral);
        if (reserve.aTokenAddress == address(0)) {
            return 0;
        }
        uint256 units = this.yieldToUnderlying(collateral, IERC20(reserve.aTokenAddress).balanceOf(maker));
        if (units == 0) {
            return 0;
        }
        uint256 price = _price(collateral);
        if (price == 0) {
            return 0;
        }
        uint256 valueBase = units * price / (10 ** IERC20Metadata(collateral).decimals());
        uint256 ltv = reserve.configuration.data & 0xFFFF;
        return valueBase * ltv / BPS;
    }

    /// @dev Base-currency amount -> underlying units via the pool's own oracle.
    function _baseToUnderlying(address underlying, uint256 baseAmount) internal view returns (uint256) {
        if (baseAmount == 0) {
            return 0;
        }
        uint256 price = _price(underlying);
        if (price == 0) {
            return 0;
        }
        return baseAmount * (10 ** IERC20Metadata(underlying).decimals()) / price;
    }

    function _price(address asset) internal view returns (uint256) {
        address oracle = AAVE_POOL.ADDRESSES_PROVIDER().getPriceOracle();
        return IPriceOracleGetter(oracle).getAssetPrice(asset);
    }
}
