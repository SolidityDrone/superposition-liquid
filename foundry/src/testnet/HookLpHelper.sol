// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISuperpositionHook } from "src/adapters/superposition-uni-hook/ISuperpositionHook.sol";

/// @title HookLpHelper
/// @notice One-transaction LP into the Superposition hook with a caller-chosen
///         tick range per side (one-sided buckets), all-or-nothing.
/// @dev Pulls both currencies from the maker, approves the hook and deposits each
///      side as a one-sided range. Atomic: a failure reverts the whole tx, so no
///      tokens are ever stranded half-way (unlike a manual transfer+deposit loop).
contract HookLpHelper {
    using SafeERC20 for IERC20;

    ISuperpositionHook public immutable HOOK;

    constructor(address hook) {
        HOOK = ISuperpositionHook(hook);
    }

    /// @notice Provide both sides in one tx, each in its own one-sided range.
    /// @param maker   LP receiving the bucket shares.
    /// @param token0  currency0 (e.g. USDC), deposited in [lower0, upper0] (above spot).
    /// @param token1  currency1 (e.g. USDT), deposited in [lower1, upper1] (below spot).
    /// @param amount0 token0 to deploy.
    /// @param amount1 token1 to deploy.
    function provide(
        address maker,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 lower0,
        int24 upper0,
        int24 lower1,
        int24 upper1
    ) external {
        IERC20(token0).safeTransferFrom(maker, address(this), amount0);
        IERC20(token1).safeTransferFrom(maker, address(this), amount1);
        IERC20(token0).forceApprove(address(HOOK), amount0);
        IERC20(token1).forceApprove(address(HOOK), amount1);

        HOOK.deposit(
            ISuperpositionHook.DepositParams({
                tickLower: lower0,
                tickUpper: upper0,
                amount0Desired: amount0,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                recipient: maker
            })
        );
        HOOK.deposit(
            ISuperpositionHook.DepositParams({
                tickLower: lower1,
                tickUpper: upper1,
                amount0Desired: 0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: maker
            })
        );
    }

    /// @notice Withdraw both buckets in one tx, all-or-nothing.
    /// @dev Requires the maker to have approved this helper as an ERC-1155 operator
    ///      on the hook share token (the hook checks owner or operator).
    function redeem(
        address maker,
        int24 lower0,
        int24 upper0,
        uint256 shares0,
        int24 lower1,
        int24 upper1,
        uint256 shares1
    ) external {
        if (shares0 > 0) {
            HOOK.withdraw(
                ISuperpositionHook.WithdrawParams({
                    tickLower: lower0, tickUpper: upper0, owner: maker, shareAmount: shares0, recipient: maker
                })
            );
        }
        if (shares1 > 0) {
            HOOK.withdraw(
                ISuperpositionHook.WithdrawParams({
                    tickLower: lower1, tickUpper: upper1, owner: maker, shareAmount: shares1, recipient: maker
                })
            );
        }
    }
}
