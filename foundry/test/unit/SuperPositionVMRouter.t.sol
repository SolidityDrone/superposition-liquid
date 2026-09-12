// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console2 } from "forge-std/console2.sol";

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraits, MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { MockAavePool, MockAToken } from "test/unit/mocks/MockAavePool.sol";
import { MockToken } from "test/unit/mocks/MockToken.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SuperPositionVMRouter } from "src/SuperPositionVMRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder } from "src/opcodes/MakerCapitalGuardOpcode.sol";
import { AggregatorV3Interface } from "src/interfaces/AggregatorV3Interface.sol";

/// @notice Full E2E on mocks: ship -> quote -> swap with JIT Aave cycling.
contract SuperPositionVMRouterTest is Test {
    uint256 internal constant RAY = 1e27;

    Aqua internal aqua;
    MockAavePool internal pool;
    MockAToken internal aToken;
    MockAToken internal aTokenUsdc;
    MockToken internal weth;
    MockToken internal usdc;
    AaveV3Adapter internal adapter;
    MakerConfig internal makerConfig;
    SuperPositionVMRouter internal router;

    address internal maker;
    address internal taker;

    ISwapVM.Order internal order;
    bytes32 internal strategyHash;

    function setUp() public {
        vm.warp(1_700_000_000);

        maker = makeAddr("maker");
        taker = makeAddr("taker");

        aqua = new Aqua();
        pool = new MockAavePool();
        weth = new MockToken("WETH", 18);
        usdc = new MockToken("USDC", 6);
        aToken = new MockAToken();
        pool.registerAToken(address(weth), aToken);
        aTokenUsdc = new MockAToken();
        pool.registerAToken(address(usdc), aTokenUsdc);
        adapter = new AaveV3Adapter(address(pool), address(0));
        makerConfig = new MakerConfig();
        router = new SuperPositionVMRouter(
            address(aqua), address(weth), makeAddr("owner"), "SuperPositionVMRouter", "1", address(makerConfig)
        );

        _setupMaker();
        _shipStrategy();
        _setupTaker();
    }

    function _setupMaker() internal {
        // maker capital 100% into Aave: 105 WETH + 4500 USDC (surplus covers aToken rounding)
        weth.mint(maker, 105e18);
        usdc.mint(maker, 4500e6);
        vm.startPrank(maker);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(address(weth)).transfer(address(adapter), 105e18);
        adapter.deposit(maker, address(weth), 105e18);
        IERC20(address(usdc)).transfer(address(adapter), 4500e6);
        adapter.deposit(maker, address(usdc), 4500e6);
        // approvals per SPEC B4.1: aWETH/USDC -> adapter, WETH -> Aqua registry
        aToken.approve(address(router), type(uint256).max);
        weth.approve(address(aqua), type(uint256).max);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: address(weth), adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        sides[1] = SideConfig({ underlying: address(usdc), adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        makerConfig.setSides(sides);
        vm.stopPrank();

        // sanity: maker holds zero idle capital, all in aTokens
        assertEq(weth.balanceOf(maker), 0);
        assertEq(usdc.balanceOf(maker), 0);
        assertEq(aToken.balanceOf(maker) + aTokenUsdc.balanceOf(maker), 105e18 + 4500e6);
    }

    function _shipStrategy() internal {
        bytes memory program = abi.encodePacked(
            uint8(YIELD_ADJUSTED_RATE_XD),
            uint8(104),
            YieldArgsBuilder.build(address(usdc), address(weth), 1e18, 1e18),
            uint8(21), // Fee._flatFeeAmountInXD (v1.0.1 dispatch bytes)
            uint8(4),
            FeeArgsBuilder.buildFlatFee(3e6), // 0.3%
            uint8(17), // XYCSwap._xycSwapXD (v1.0.1 dispatch bytes)
            uint8(0),
            uint8(35), uint8(20),
            CapitalArgsBuilder.build(address(weth))
        );

        order = MakerTraitsLib.build(
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
                postTransferInTarget: address(router),
                postTransferInData: "",
                preTransferOutTarget: address(router),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );

        bytes memory strategy = abi.encode(order);
        strategyHash = keccak256(strategy);
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18; // virtual balance in underlying terms
        amounts[1] = 4000e6;
        vm.prank(maker);
        aqua.ship(address(router), strategy, tokens, amounts);
    }

    function _setupTaker() internal {
        usdc.mint(taker, 1000e6);
        vm.startPrank(taker);
        usdc.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function _takerTraits() internal returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(0),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: true,
                threshold: "",
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: false,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
    }

    // 1000 USDC in, xyc with balances (4000e6, 100e18), fee 0.3%:
    // pricing amountIn = 997e6 -> amountOut = 997e6 * 100e18 / (4000e6 + 997e6) = 19.952e18
    function _expectedAmountOut() internal pure returns (uint256) {
        uint256 amountIn = 997e6;
        return amountIn * 100e18 / (4000e6 + amountIn);
    }

    function test_quote_matchesExpectedXycMath() public {
        (uint256 amountIn, uint256 amountOut,) = router.quote(order, address(usdc), address(weth), 1000e6, _takerTraits());
        assertEq(amountIn, 1000e6);
        assertEq(amountOut, _expectedAmountOut());
    }

    function test_swap_deliversAndReallocatesCapital() public {
        uint256 expectedOut = _expectedAmountOut();

        vm.prank(taker);
        (uint256 amountIn, uint256 amountOut,) =
            router.swap(order, address(usdc), address(weth), 1000e6, _takerTraits());

        assertEq(amountIn, 1000e6);
        assertEq(amountOut, expectedOut);

        // taker side
        assertEq(usdc.balanceOf(taker), 0);
        assertEq(weth.balanceOf(taker), expectedOut);

        // maker wallet idle capital stays zero (JIT cycling worked)
        assertEq(weth.balanceOf(maker), 0);
        assertEq(usdc.balanceOf(maker), 0);

        // capital moved into Aave: aWETH burned for delivery, aUSDC from the fill
        assertEq(aToken.balanceOf(maker) + aTokenUsdc.balanceOf(maker), 105e18 + 4500e6 - expectedOut + 1000e6);

        // pool holds everything
        assertEq(weth.balanceOf(address(pool)), 105e18 - expectedOut);
        assertEq(usdc.balanceOf(address(pool)), 5500e6);
    }

    function test_quoteAndSwapAgree() public {
        (, uint256 quotedOut,) = router.quote(order, address(usdc), address(weth), 1000e6, _takerTraits());
        vm.prank(taker);
        (, uint256 swappedOut,) = router.swap(order, address(usdc), address(weth), 1000e6, _takerTraits());
        assertEq(quotedOut, swappedOut);
    }

    function test_swapUpdatesAquaVirtualBalances() public {
        uint256 expectedOut = _expectedAmountOut();
        vm.prank(taker);
        router.swap(order, address(usdc), address(weth), 1000e6, _takerTraits());

        (uint256 balanceIn,) = aqua.rawBalances(maker, address(router), strategyHash, address(usdc));
        (uint256 balanceOut,) = aqua.rawBalances(maker, address(router), strategyHash, address(weth));
        assertEq(balanceIn, 4000e6 + 1000e6);
        assertEq(balanceOut, 100e18 - expectedOut);
    }

    function test_secondFillAfterFirstWorks() public {
        vm.prank(taker);
        router.swap(order, address(usdc), address(weth), 1000e6, _takerTraits());

        usdc.mint(taker, 500e6);
        vm.prank(taker);
        usdc.approve(address(router), type(uint256).max);

        vm.prank(taker);
        (, uint256 amountOut,) = router.swap(order, address(usdc), address(weth), 500e6, _takerTraits());
        assertTrue(amountOut > 0);
        assertEq(usdc.balanceOf(maker), 0); // still no idle capital
        assertEq(weth.balanceOf(maker), 0);
    }
}
