// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Calldata } from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";
import { Context } from "@1inch/swap-vm/libs/VM.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

// Opcode byte index, appended at the end of the AquaOpcodes table (base AquaOpcodes table = 34 usable opcodes, 0..33).
uint256 constant YIELD_ADJUSTED_RATE_XD = 34;

library YieldArgsBuilder {
    error YieldArgsInvalidLength();

    /// @dev Builds opcode args: adapter + underlyingIn + underlyingOut (60 bytes)
    function build(address adapter, address underlyingIn, address underlyingOut) internal pure returns (bytes memory) {
        return abi.encodePacked(adapter, underlyingIn, underlyingOut);
    }
}

/// @title YieldAdjustedRateOpcode
/// @notice Adjusts SwapRegisters balances by the current lending exchange rate so quotes
///         are always accurate in underlying terms while maker capital sits in yield tokens.
/// @dev Virtual balances are shipped in underlying-equivalent units; scaling by the current
///      rate reflects accrued interest. Real (aToken-backed) capital is always >= effective
///      balance, so overcounting can only fail a fill, never oversell (SPEC B5.1).
contract YieldAdjustedRateOpcode {
    using Calldata for bytes;

    error YieldArgsTooShort();

    /// @param args.adapter        | 20 bytes
    /// @param args.underlyingIn   | 20 bytes
    /// @param args.underlyingOut  | 20 bytes
    function _yieldAdjustedRateXD(Context memory ctx, bytes calldata args) internal view {
        if (args.length < 60) revert YieldArgsTooShort();

        address adapter = address(bytes20(args.slice(0, 20)));
        address underlyingIn = address(bytes20(args.slice(20, 40)));
        address underlyingOut = address(bytes20(args.slice(40, 60)));

        uint256 rateIn = ILendingAdapter(adapter).exchangeRate(underlyingIn);
        uint256 rateOut = ILendingAdapter(adapter).exchangeRate(underlyingOut);

        ctx.swap.balanceIn = ctx.swap.balanceIn * rateIn / 1e18;
        ctx.swap.balanceOut = ctx.swap.balanceOut * rateOut / 1e18;
    }
}
