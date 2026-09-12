// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";

/// @title OrderBuilder
/// @notice Builds a SuperPosition SwapVM `Order` (maker traits + program) with the
///         exact same libraries the scripts use, and returns `abi.encode(order)`.
/// @dev Lets the frontend ship a strategy on Aqua without porting the order encoder
///      to TypeScript: `pubClient.readContract(build(...))` then `aqua.ship(...)`.
///      The program is the standard template: yield-adjusted rate (34) → fee (21)
///      → xyc swap (17) → maker capital guard (35).
contract OrderBuilder {
    uint256 internal constant FEE_OPCODE = 21;
    uint256 internal constant XYC_SWAP_OPCODE = 17;

    /// @param maker       LP who owns the strategy (balances live in the maker's Aqua account)
    /// @param router      SuperPositionVMRouter (the app + maker-hooks target)
    /// @param tokenIn     strategy tokenIn (program + guard)
    /// @param tokenOut    strategy tokenOut
    /// @param guardToken  token whose real capital is checked by the capital guard
    /// @param feeBps      flat fee in 1e9 units (e.g. 3_000_000 = 0.3%)
    /// @param rateIn      ship-time exchange rate for tokenIn (1e18 when idle)
    /// @param rateOut     ship-time exchange rate for tokenOut
    function build(
        address maker,
        address router,
        address tokenIn,
        address tokenOut,
        address guardToken,
        uint32 feeBps,
        uint256 rateIn,
        uint256 rateOut
    ) external pure returns (bytes memory) {
        bytes memory yieldArgs = YieldArgsBuilder.build(tokenIn, tokenOut, rateIn, rateOut);
        bytes memory feeArgs = FeeArgsBuilder.buildFlatFee(feeBps);
        bytes memory guardArgs = CapitalArgsBuilder.build(guardToken);

        bytes memory program = abi.encodePacked(
            uint8(YIELD_ADJUSTED_RATE_XD),
            uint8(yieldArgs.length),
            yieldArgs,
            uint8(FEE_OPCODE),
            uint8(feeArgs.length),
            feeArgs,
            uint8(XYC_SWAP_OPCODE),
            uint8(0),
            uint8(MAKER_CAPITAL_GUARD_XD),
            uint8(guardArgs.length),
            guardArgs
        );

        ISwapVM.Order memory order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: true,
                hasPreTransferOutHook: true,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: router,
                postTransferInData: "",
                preTransferOutTarget: router,
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );

        return abi.encode(order);
    }
}
