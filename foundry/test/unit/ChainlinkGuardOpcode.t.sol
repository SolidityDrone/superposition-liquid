// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { Context, VM, SwapQuery, SwapRegisters } from "@1inch/swap-vm/libs/VM.sol";
import { CalldataPtr } from "@1inch/solidity-utils/contracts/libraries/CalldataPtr.sol";

import { MockToken } from "test/unit/mocks/MockToken.sol";
import { MockAggregator } from "test/unit/mocks/MockAggregator.sol";
import { ChainlinkGuardOpcode } from "src/opcodes/ChainlinkGuardOpcode.sol";

contract ChainlinkGuardOpcodeTest is ChainlinkGuardOpcode, Test {
    MockToken internal weth;
    MockToken internal usdc;
    MockAggregator internal ethFeed;
    MockAggregator internal usdcFeed;
    address internal maker;
    address internal taker;

    function setUp() public {
        vm.warp(1_700_000_000); // realistic timestamp, avoids underflow on staleness checks
        weth = new MockToken("WETH", 18);
        usdc = new MockToken("USDC", 6);
        ethFeed = new MockAggregator();
        usdcFeed = new MockAggregator();
        ethFeed.setAnswer(2000e8); // ETH = $2000
        usdcFeed.setAnswer(1e8); // USDC = $1
        maker = makeAddr("maker");
        taker = makeAddr("taker");
    }

    function _args() internal view returns (bytes memory) {
        return _argsFor(200, 3600); // 2% deviation, 1h staleness
    }

    function _argsFor(uint32 maxDeviationBps, uint32 maxStaleness) internal view returns (bytes memory) {
        return abi.encodePacked(address(weth), address(usdc), address(ethFeed), address(usdcFeed), maxDeviationBps, maxStaleness);
    }

    function _ctx(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
        internal
        view
        returns (Context memory ctx)
    {
        ctx = Context({
            vm: VM({
                isStaticContext: false,
                nextPC: 0,
                programPtr: CalldataPtr.wrap(0),
                takerArgsPtr: CalldataPtr.wrap(0),
                opcodes: new function(Context memory, bytes calldata) internal[](0)
            }),
            query: SwapQuery({
                orderHash: bytes32(0),
                maker: maker,
                taker: taker,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                isExactIn: true
            }),
            swap: SwapRegisters({
                balanceIn: 0,
                balanceOut: 0,
                amountIn: amountIn,
                amountOut: amountOut,
                amountNetPulled: 0
            })
        });
    }

    function _execExternal(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, bytes calldata args)
        external
    {
        Context memory ctx = _ctx(tokenIn, tokenOut, amountIn, amountOut);
        _chainlinkGuardXD(ctx, args);
    }

    /// 1 WETH -> 2000 USDC, feed ref 2000 -> within 2%
    function test_passesWhenPriceMatchesFeed() public {
        this._execExternal(address(weth), address(usdc), 1e18, 2000e6, _args());
    }

    /// 1 WETH -> 2500 USDC = 25% deviation, feed ref 2000 -> revert
    function test_revertsWhenDeviationExceedsBound() public {
        vm.expectRevert(abi.encodeWithSelector(PriceDeviationExceeded.selector, 2500e18, 1e18, 2000e18));
        this._execExternal(address(weth), address(usdc), 1e18, 2500e6, _args());
    }

    /// exactly at 2% deviation -> pass (boundary inclusive)
    function test_passesAtExactDeviationBound() public {
        // 1 WETH -> 2040 USDC = exactly 2% over 2000
        this._execExternal(address(weth), address(usdc), 1e18, 2040e6, _args());
    }

    function test_revertsOnStaleFeed() public {
        ethFeed.setUpdatedAt(block.timestamp - 3601); // just past 1h
        vm.expectRevert(abi.encodeWithSelector(StalePrice.selector, address(ethFeed)));
        this._execExternal(address(weth), address(usdc), 1e18, 2000e6, _args());
    }

    function test_skipsWhenZeroAmounts() public {
        this._execExternal(address(weth), address(usdc), 0, 0, _args());
    }

    function test_revertsOnShortArgs() public {
        vm.expectRevert(GuardArgsTooShort.selector);
        this._execExternal(address(weth), address(usdc), 1e18, 2000e6, hex"beef");
    }

    /// reversed direction: taker sells USDC, buys WETH — 2000 USDC -> 1 WETH (feed ref 1/2000)
    function test_passesReversedDirection() public {
        this._execExternal(address(usdc), address(weth), 2000e6, 1e18, _args());
    }

    function test_revertsReversedDirectionDeviation() public {
        // 1 USDC -> 0.001 WETH: implied 1e15 vs ref 5e14 = 100% deviation
        vm.expectRevert(abi.encodeWithSelector(PriceDeviationExceeded.selector, 1e15, 1e6, 5e14));
        this._execExternal(address(usdc), address(weth), 1e6, 0.001e18, _args());
    }
}
