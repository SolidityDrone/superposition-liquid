// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

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
/// @notice Makes quote() a complete fill-oracle: reverts unless an ACTUAL withdrawal
///         of amountOut would succeed for the maker right now (simulated via the
///         adapter: maker position AND protocol liquidity, not just balanceOf).
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

        // simulated withdrawal: min(maker position, protocol liquidity) — see ILendingAdapter
        uint256 available = ILendingAdapter(adapter).maxWithdrawable(ctx.query.maker, underlyingOut);
        if (available < ctx.swap.amountOut) {
            revert MakerCapitalInsufficient(available, ctx.swap.amountOut);
        }
    }
}
