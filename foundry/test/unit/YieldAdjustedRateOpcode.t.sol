// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Context, VM, SwapQuery, SwapRegisters } from "@1inch/swap-vm/libs/VM.sol";
import { CalldataPtr } from "@1inch/solidity-utils/contracts/libraries/CalldataPtr.sol";

import { MockAavePool, MockAToken } from "test/unit/mocks/MockAavePool.sol";
import { MockToken } from "test/unit/mocks/MockToken.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { YieldAdjustedRateOpcode, YieldArgsBuilder } from "src/opcodes/YieldAdjustedRateOpcode.sol";

contract YieldAdjustedRateOpcodeTest is YieldAdjustedRateOpcode, Test {
    uint256 internal constant RAY = 1e27;

    MakerConfig internal makerConfig;
    AaveV3Adapter internal adapter;
    MockAavePool internal pool;
    MockToken internal usdc;
    MockToken internal weth;
    address internal maker;
    address internal taker;

    function setUp() public {
        pool = new MockAavePool();
        usdc = new MockToken("USDC", 18);
        weth = new MockToken("WETH", 18);
        pool.registerAToken(address(usdc), new MockAToken());
        pool.registerAToken(address(weth), new MockAToken());
        adapter = new AaveV3Adapter(address(pool), address(0));
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        _seedSupply(address(usdc), 1e6);
        _seedSupply(address(weth), 1e15);

        // the opcode resolves the maker's side adapters from the registry
        makerConfig = new MakerConfig();
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: address(usdc), adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        sides[1] = SideConfig({ underlying: address(weth), adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        vm.prank(maker);
        makerConfig.setSides(sides);
    }

    function _makerConfig() internal view override returns (MakerConfig) {
        return makerConfig;
    }

    function _opcodeArgs(uint256 rate0In, uint256 rate0Out) internal view returns (bytes memory) {
        return YieldArgsBuilder.build(address(usdc), address(weth), rate0In, rate0Out);
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

    function _seedSupply(address asset, uint256 amount) internal {
        MockToken(asset).mint(address(this), amount);
        MockToken(asset).approve(address(adapter), type(uint256).max);
        IERC20(asset).transfer(address(adapter), amount);
        adapter.deposit(address(this), asset, amount);
    }

    function test_noop_whenRateUnchangedSinceShip() public {
        (uint256 balIn, uint256 balOut) = this._execExternal(4000e6, 100 ether, _opcodeArgs(1e18, 1e18));
        assertEq(balIn, 4000e6);
        assertEq(balOut, 100 ether);
    }

    function test_scalesByRateGrowthSinceShip() public {
        pool.setNormalizedIncome(address(usdc), 103 * RAY / 100);
        pool.setNormalizedIncome(address(weth), 105 * RAY / 100);

        (uint256 balIn, uint256 balOut) = this._execExternal(4000e6, 100 ether, _opcodeArgs(1e18, 1e18));

        assertEq(balIn, 4000e6 * 103e18 / 100 / 1e18);
        assertEq(balOut, 100 ether * 105e18 / 100 / 1e18);
    }

    function test_relativeGrowth_onlyPostShipYieldCounts() public {
        // rate0 = 1.05e18 at ship; now accrued to 1.1e18 -> only the 1.05->1.10 growth counts
        pool.setNormalizedIncome(address(usdc), 11 * RAY / 10);
        (uint256 balIn,) = this._execExternal(4000e6, 0, _opcodeArgs(105e16, 1e18));
        // 4000 * 1.10/1.05 = 4190.47...
        assertEq(balIn, uint256(4000e6) * 11e17 / 105e16); // 4190476190
    }

    function test_roundsDown() public {
        pool.setNormalizedIncome(address(weth), 15 * RAY / 10); // rate = 1.5e18
        (, uint256 balOut) = this._execExternal(0, 1, _opcodeArgs(1e18, 1e18));
        assertEq(balOut, 1); // 1.5 rounds down to 1
    }

    function test_argsTooShort_reverts() public {
        vm.expectRevert(YieldArgsTooShort.selector);
        this._execExternal(0, 0, hex"dead");
    }
}
