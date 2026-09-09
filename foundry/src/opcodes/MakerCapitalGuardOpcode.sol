// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Calldata } from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";

import { Context } from "@1inch/swap-vm/libs/VM.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

// Opcode byte index, appended after ChainlinkGuardXD (see SPEC.md).
uint256 constant MAKER_CAPITAL_GUARD_XD = 36;

library CapitalArgsBuilder {
    /// @dev Builds opcode args: adapter + underlyingIn + underlyingOut (60 bytes)
    function build(address adapter, address underlyingIn, address underlyingOut) internal pure returns (bytes memory) {
        return abi.encodePacked(adapter, underlyingIn, underlyingOut);
    }
}

/// @title MakerCapitalGuardOpcode
/// @notice Makes quote() a complete fill-oracle: reverts unless the maker's REAL
///         lending-backed capital (aTokens / vault shares, valued in underlying terms
///         at the live rate) covers the amount the maker must deliver.
/// @dev Quote()/swap() share the same runLoop, so a quote that passes guarantees the
///      capital check passes at swap time too (modulo state changes between the two).
contract MakerCapitalGuardOpcode {
    using Calldata for bytes;

    error CapitalArgsTooShort();
    error MakerCapitalInsufficient(uint256 available, uint256 required);

    /// @param args.adapter       | 20 bytes
    /// @param args.underlyingIn  | 20 bytes
    /// @param args.underlyingOut | 20 bytes
    function _makerCapitalGuardXD(Context memory ctx, bytes calldata args) internal view {
        if (args.length < 60) revert CapitalArgsTooShort();

        address adapter = address(bytes20(args.slice(0, 20)));
        address underlyingIn = address(bytes20(args.slice(20, 40)));
        address underlyingOut = address(bytes20(args.slice(40, 60)));

        if (ctx.swap.amountOut == 0) return;

        address yieldTokenOut = ILendingAdapter(adapter).yieldToken(underlyingOut);
        uint256 available = ILendingAdapter(adapter).yieldToUnderlying(underlyingOut, IERC20(yieldTokenOut).balanceOf(ctx.query.maker));
        if (available < ctx.swap.amountOut) {
            revert MakerCapitalInsufficient(available, ctx.swap.amountOut);
        }
    }
}
