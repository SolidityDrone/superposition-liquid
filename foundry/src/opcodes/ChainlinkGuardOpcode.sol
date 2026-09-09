// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Calldata } from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";

import { Context } from "@1inch/swap-vm/libs/VM.sol";

import { AggregatorV3Interface } from "src/interfaces/AggregatorV3Interface.sol";

// Opcode byte index, appended after YieldAdjustedRateOpcode (see SPEC.md B3.4).
uint256 constant CHAINLINK_GUARD_XD = 35;

library GuardArgsBuilder {
    /// @dev Builds opcode args: token0 + token1 + feed0 + feed1 + maxDeviationBps + staleness0 + staleness1 (92 bytes).
    ///      Feeds are USD-quoted; they are mapped to tokenIn/tokenOut by address, so the guard
    ///      works for both swap directions of the same strategy. Per-feed staleness because
    ///      stablecoin feeds legitimately update on long heartbeats (e.g. ~12h for USDC on Base).
    function build(
        address token0,
        address token1,
        address feed0,
        address feed1,
        uint32 maxDeviationBps,
        uint32 staleness0Seconds,
        uint32 staleness1Seconds
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(token0, token1, feed0, feed1, maxDeviationBps, staleness0Seconds, staleness1Seconds);
    }
}

/// @title ChainlinkGuardOpcode
/// @notice Manipulation-resistant pricing guard (Chainlink Data Feeds): reverts if the
///         implied swap price deviates more than maxDeviationBps from the Chainlink
///         reference price, or if a feed is stale beyond maxStalenessSeconds.
contract ChainlinkGuardOpcode {
    using Calldata for bytes;

    error GuardArgsTooShort();
    error StalePrice(address feed);
    error PriceDeviationExceeded(uint256 implied, uint256 amountIn, uint256 ref);

    /// @param args.token0             | 20 bytes
    /// @param args.token1             | 20 bytes
    /// @param args.feed0              | 20 bytes | Chainlink feed of token0 (USD-quoted)
    /// @param args.feed1              | 20 bytes | Chainlink feed of token1 (USD-quoted)
    /// @param args.maxDeviationBps    |  4 bytes | uint32, e.g. 200 = 2%
    /// @param args.staleness0Seconds  |  4 bytes | uint32 max age of feed0, e.g. 3600
    /// @param args.staleness1Seconds  |  4 bytes | uint32 max age of feed1
    function _chainlinkGuardXD(Context memory ctx, bytes calldata args) internal view {
        if (args.length < 92) revert GuardArgsTooShort();

        address token0 = address(bytes20(args.slice(0, 20)));
        address token1 = address(bytes20(args.slice(20, 40)));
        address feed0 = address(bytes20(args.slice(40, 60)));
        address feed1 = address(bytes20(args.slice(60, 80)));
        uint32 maxDeviationBps = uint32(bytes4(args.slice(80, 84)));
        uint32 staleness0Seconds = uint32(bytes4(args.slice(84, 88)));
        uint32 staleness1Seconds = uint32(bytes4(args.slice(88, 92)));

        if (ctx.swap.amountIn == 0 || ctx.swap.amountOut == 0) return;

        address feedIn = ctx.query.tokenIn == token0 ? feed0 : feed1;
        address feedOut = ctx.query.tokenIn == token0 ? feed1 : feed0;

        _checkFresh(feedIn, ctx.query.tokenIn == token0 ? staleness0Seconds : staleness1Seconds);
        _checkFresh(feedOut, ctx.query.tokenIn == token0 ? staleness1Seconds : staleness0Seconds);

        (, int256 answerIn,, ,) = AggregatorV3Interface(feedIn).latestRoundData();
        (, int256 answerOut,, ,) = AggregatorV3Interface(feedOut).latestRoundData();

        // Reference: tokenOut per tokenIn, 1e18 fixed point (feeds are USD-quoted)
        uint8 decFeedIn = AggregatorV3Interface(feedIn).decimals();
        uint8 decFeedOut = AggregatorV3Interface(feedOut).decimals();
        uint256 ref = uint256(answerIn) * (10 ** decFeedOut) * 1e18
            / (uint256(answerOut) * (10 ** decFeedIn));

        // Implied price: tokenOut per tokenIn, 1e18 fixed point, decimal-normalized
        uint8 decIn = IERC20Metadata(ctx.query.tokenIn).decimals();
        uint8 decOut = IERC20Metadata(ctx.query.tokenOut).decimals();
        uint256 implied = ctx.swap.amountOut * (10 ** decIn) * 1e18 / (ctx.swap.amountIn * (10 ** decOut));

        uint256 deviation = implied > ref ? implied - ref : ref - implied;
        if (deviation * 10_000 > ref * maxDeviationBps) {
            revert PriceDeviationExceeded(implied, ctx.swap.amountIn, ref);
        }
    }

    function _checkFresh(address feed, uint32 maxStalenessSeconds) internal view {
        (, , , uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();
        if (block.timestamp - updatedAt > maxStalenessSeconds) revert StalePrice(feed);
    }
}
