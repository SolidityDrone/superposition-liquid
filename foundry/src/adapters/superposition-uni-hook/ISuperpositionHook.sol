// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ISuperpositionHook
/// @notice Minimal ABI of SuperpositionHook (SolidityDrone/superposition-hook-uni-v4),
///         field-for-field compatible. No Uniswap v4 imports.
interface ISuperpositionHook {
    struct DepositParams {
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
    }

    struct WithdrawParams {
        int24 tickLower;
        int24 tickUpper;
        address owner;
        uint256 shareAmount;
        address recipient;
    }

    struct Bucket {
        int24 lower;
        int24 upper;
        uint128 liquidity;
        uint256 shares;
        uint256 c0;
        uint256 c1;
        bool active;
    }

    function deposit(DepositParams calldata p) external returns (uint256 sharesMinted);
    function withdraw(WithdrawParams calldata p) external returns (uint256 wethOut, uint256 usdcOut);
    function sharesOf(address user, int24 lower, int24 upper) external view returns (uint256);
    function getBuckets() external view returns (Bucket[] memory);
    function shareToken() external view returns (address);
    function currentBalance() external view returns (uint256 wethAmt, uint256 usdcAmt);
    function syncYield() external;
}
