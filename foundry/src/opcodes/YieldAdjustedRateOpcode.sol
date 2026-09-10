// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Calldata } from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";
import { Context } from "@1inch/swap-vm/libs/VM.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";
import { MakerConfig } from "src/config/MakerConfig.sol";

// Opcode byte index, appended at the end of the AquaOpcodes table (base AquaOpcodes table = 34 usable opcodes, 0..33).
uint256 constant YIELD_ADJUSTED_RATE_XD = 34;

library YieldArgsBuilder {
    error YieldArgsTooShort();

    /// @dev Builds opcode args: underlyingIn + underlyingOut + rate0In + rate0Out
    ///      (20+20+32+32 = 104 bytes). The adapters are resolved from the maker's
    ///      side registry (MakerConfig) at quote/fill time — the program carries
    ///      only the tokens and the ship-time rates: single source of truth, a
    ///      program/config adapter mismatch is impossible.
    function build(address underlyingIn, address underlyingOut, uint256 rate0In, uint256 rate0Out)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(underlyingIn, underlyingOut, rate0In, rate0Out);
    }
}

/// @title YieldAdjustedRateOpcode
/// @notice Adjusts SwapRegisters balances by the lending exchange rate growth since ship
///         time, so quotes reflect accrued yield while maker capital sits in yield tokens.
/// @dev Virtual balances are shipped in underlying units; scaling by rate(t)/rate0 adds the
///      post-ship yield only. Real (yield-token-backed) capital is always >= effective
///      balance, so overcounting can only fail a fill, never oversell (SPEC B5.1).
abstract contract YieldAdjustedRateOpcode {
    using Calldata for bytes;

    error YieldArgsTooShort();
    error SideNotRegistered();

    /// @dev The router provides its MakerConfig deployment (opcode execution context).
    function _makerConfig() internal view virtual returns (MakerConfig);

    /// @param args.underlyingIn   | 20 bytes
    /// @param args.underlyingOut  | 20 bytes
    /// @param args.rate0In        | 32 bytes | exchangeRate(underlyingIn) at ship time
    /// @param args.rate0Out       | 32 bytes | exchangeRate(underlyingOut) at ship time
    function _yieldAdjustedRateXD(Context memory ctx, bytes calldata args) internal view {
        if (args.length < 104) revert YieldArgsTooShort();

        address underlyingIn = address(bytes20(args.slice(0, 20)));
        address underlyingOut = address(bytes20(args.slice(20, 40)));
        uint256 rate0In = abi.decode(args.slice(40, 72), (uint256));
        uint256 rate0Out = abi.decode(args.slice(72, 104), (uint256));

        address adapterIn = _makerConfig().sides(ctx.query.maker, underlyingIn).adapter;
        address adapterOut = _makerConfig().sides(ctx.query.maker, underlyingOut).adapter;
        if (adapterIn == address(0) || adapterOut == address(0)) revert SideNotRegistered();

        uint256 rateIn = ILendingAdapter(adapterIn).exchangeRate(underlyingIn);
        uint256 rateOut = ILendingAdapter(adapterOut).exchangeRate(underlyingOut);

        ctx.swap.balanceIn = ctx.swap.balanceIn * rateIn / rate0In;
        ctx.swap.balanceOut = ctx.swap.balanceOut * rateOut / rate0Out;
    }
}
