// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { Context, VM, SwapQuery, SwapRegisters } from "@1inch/swap-vm/libs/VM.sol";
import { CalldataPtr } from "@1inch/solidity-utils/contracts/libraries/CalldataPtr.sol";

import { MockAavePool, MockAToken, MockDebtToken } from "test/unit/mocks/MockAavePool.sol";
import { MockToken } from "test/unit/mocks/MockToken.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { MakerCapitalGuardOpcode, CapitalArgsBuilder } from "src/opcodes/MakerCapitalGuardOpcode.sol";

contract MakerCapitalGuardOpcodeTest is MakerCapitalGuardOpcode, Test {
    MockAavePool internal pool;
    MockAToken internal aWethToken;
    MockToken internal usdc;
    MockToken internal weth;
    AaveV3Adapter internal adapter;
    MakerConfig internal makerConfig;
    address internal maker;
    address internal taker;

    function setUp() public {
        pool = new MockAavePool();
        usdc = new MockToken("USDC", 6);
        weth = new MockToken("WETH", 18);
        aWethToken = new MockAToken();
        pool.registerAToken(address(weth), aWethToken);
        pool.registerAToken(address(usdc), new MockAToken());
        pool.registerDebtToken(address(weth), new MockDebtToken());
        pool.registerDebtToken(address(usdc), new MockDebtToken());
        adapter = new AaveV3Adapter(address(pool));
        maker = makeAddr("maker");
        taker = makeAddr("taker");

        // the guard resolves the side adapter from the maker's registry
        makerConfig = new MakerConfig();
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: address(weth), adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        sides[1] = SideConfig({ underlying: address(usdc), adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        vm.prank(maker);
        makerConfig.setSides(sides);
    }

    function _makerConfig() internal view override returns (MakerConfig) {
        return makerConfig;
    }

    function _args() internal view returns (bytes memory) {
        return CapitalArgsBuilder.build(address(weth));
    }

    function _ctx(address tokenIn, address tokenOut, uint256 amountOut)
        internal view returns (Context memory ctx)
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
            swap: SwapRegisters({ balanceIn: 0, balanceOut: 0, amountIn: 1000e6, amountOut: amountOut, amountNetPulled: 0 })
        });
    }

    function _execExternal(address tokenIn, address tokenOut, uint256 amountOut, bytes calldata args) external {
        Context memory ctx = _ctx(tokenIn, tokenOut, amountOut);
        _makerCapitalGuardXD(ctx, args);
    }

    /// maker holds 50 WETH of real aTokens: a 40 WETH delivery is coverable
    function test_passesWhenRealCapitalCoversAmountOut() public {
        weth.mint(maker, 50e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(weth), 50e18);
        vm.stopPrank();

        this._execExternal(address(usdc), address(weth), 40e18, _args());
    }

    function test_revertsWhenRealCapitalBelowAmountOut() public {
        weth.mint(maker, 10e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(weth), 10e18);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(MakerCapitalInsufficient.selector, 10e18, 40e18));
        this._execExternal(address(usdc), address(weth), 40e18, _args());
    }

    /// the classic broken-invariant case: maker shipped virtual but withdrew the aTokens
    function test_revertsWhenMakerWithdrewCapitalBehindTheStrategy() public {
        weth.mint(maker, 40e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(weth), 40e18);
        // maker drains their position: real capital behind the shipped inventory is gone
        aWethToken.transfer(address(1), 40e18);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(MakerCapitalInsufficient.selector, 0, 40e18));
        this._execExternal(address(usdc), address(weth), 40e18, _args());
    }

    /// maker balance is fine but the pool is lent out: simulated withdrawal caps it
    function test_revertsWhenPoolLiquidityCapsWithdrawal() public {
        weth.mint(maker, 100e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(weth), 100e18);
        vm.stopPrank();
        pool.simulateDebt(address(weth), 95e18); // only 5 WETH cash left

        vm.expectRevert(abi.encodeWithSelector(MakerCapitalInsufficient.selector, 5e18, 40e18));
        this._execExternal(address(usdc), address(weth), 40e18, _args());
    }

    function test_skipsWhenAmountOutIsZero() public {
        this._execExternal(address(usdc), address(weth), 0, _args());
    }

    function test_revertsOnShortArgs() public {
        vm.expectRevert(CapitalArgsTooShort.selector);
        this._execExternal(address(usdc), address(weth), 1e18, hex"beef");
    }
}
