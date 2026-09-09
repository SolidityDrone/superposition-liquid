// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { Context, VM, SwapQuery, SwapRegisters } from "@1inch/swap-vm/libs/VM.sol";
import { CalldataPtr } from "@1inch/solidity-utils/contracts/libraries/CalldataPtr.sol";

import { MockAavePool, MockAToken } from "test/unit/mocks/MockAavePool.sol";
import { MockToken } from "test/unit/mocks/MockToken.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { YieldAdjustedRateOpcode } from "src/opcodes/YieldAdjustedRateOpcode.sol";

contract YieldAdjustedRateOpcodeTest is YieldAdjustedRateOpcode, Test {
    uint256 internal constant RAY = 1e27;

    AaveV3Adapter internal adapter;
    MockAavePool internal pool;
    MockAToken internal aToken;
    MockToken internal usdc;
    MockToken internal weth;
    address internal maker;
    address internal taker;

    function setUp() public {
        aToken = new MockAToken();
        pool = new MockAavePool(address(aToken));
        adapter = new AaveV3Adapter(address(pool));
        usdc = new MockToken("USDC", 18);
        weth = new MockToken("WETH", 18);
        maker = makeAddr("maker");
        taker = makeAddr("taker");
    }

    function _opcodeArgs() internal view returns (bytes memory) {
        return abi.encodePacked(address(adapter), address(usdc), address(weth));
    }

    function _ctx(uint256 balanceIn, uint256 balanceOut) internal view returns (Context memory ctx) {
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
                tokenIn: address(usdc),
                tokenOut: address(weth),
                isExactIn: true
            }),
            swap: SwapRegisters({ balanceIn: balanceIn, balanceOut: balanceOut, amountIn: 0, amountOut: 0, amountNetPulled: 0 })
        });
    }

    function _execExternal(uint256 balanceIn, uint256 balanceOut, bytes calldata args)
        external view
        returns (uint256 balIn, uint256 balOut)
    {
        Context memory ctx = _ctx(balanceIn, balanceOut);
        _yieldAdjustedRateXD(ctx, args);
        return (ctx.swap.balanceIn, ctx.swap.balanceOut);
    }

    function test_scalesBothBalancesByExchangeRate() public {
        pool.setNormalizedIncome(address(usdc), 103 * RAY / 100);
        pool.setNormalizedIncome(address(weth), 105 * RAY / 100);

        (uint256 balIn, uint256 balOut) = this._execExternal(4000e6, 100 ether, _opcodeArgs());

        assertEq(balIn, 4000e6 * 103e18 / 100 / 1e18);
        assertEq(balOut, 100 ether * 105e18 / 100 / 1e18);
    }

    function test_noop_whenRateIsOne() public view {
        (uint256 balIn, uint256 balOut) = this._execExternal(4000e6, 100 ether, _opcodeArgs());

        assertEq(balIn, 4000e6);
        assertEq(balOut, 100 ether);
    }

    function test_roundsDown() public {
        pool.setNormalizedIncome(address(weth), 15 * RAY / 10); // rate = 1.5e18
        (, uint256 balOut) = this._execExternal(0, 1, _opcodeArgs());

        assertEq(balOut, 1); // 1.5 rounds down to 1
    }

    function test_argsTooShort_reverts() public {
        vm.expectRevert(YieldArgsTooShort.selector);
        this._execExternal(0, 0, hex"dead");
    }
}
