// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { MockAavePool, MockAToken } from "test/unit/mocks/MockAavePool.sol";
import { MockToken } from "test/unit/mocks/MockToken.sol";
import { MockAggregator } from "test/unit/mocks/MockAggregator.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { MakerConfig, MakerVaultConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { GuardArgsBuilder, CHAINLINK_GUARD_XD, ChainlinkGuardOpcode } from "src/opcodes/ChainlinkGuardOpcode.sol";

/// @notice E2E with the Chainlink guard opcode wired into the program (SPEC B3.4).
contract ChainlinkGuardE2ETest is Test {
    Aqua internal aqua;
    MockAavePool internal pool;
    MockAToken internal aToken;
    MockAToken internal aTokenUsdc;
    MockToken internal weth;
    MockToken internal usdc;
    MockAggregator internal ethFeed;
    MockAggregator internal usdcFeed;
    AaveV3Adapter internal adapter;
    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;

    address internal maker;
    address internal taker;
    ISwapVM.Order internal lastOrder;

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
        ethFeed = new MockAggregator();
        usdcFeed = new MockAggregator();
        ethFeed.setAnswer(2000e8);
        usdcFeed.setAnswer(1e8);
        adapter = new AaveV3Adapter(address(pool));
        makerConfig = new MakerConfig();
        router = new SupercazzolaRouter(
            address(aqua), address(weth), makeAddr("owner"), "SupercazzolaRouter", "1", address(makerConfig)
        );

        usdc.mint(taker, 1000e6);
        vm.startPrank(taker);
        usdc.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function _ship(bytes memory program, uint256 wethVirtual, uint256 usdcVirtual, uint256 wethReal, uint256 usdcReal)
        internal
    {
        weth.mint(maker, wethReal);
        usdc.mint(maker, usdcReal);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        usdc.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(weth), wethReal);
        adapter.depositFor(maker, address(usdc), usdcReal);
        aToken.approve(address(adapter), type(uint256).max);
        weth.approve(address(aqua), type(uint256).max);
        makerConfig.setConfig(
            MakerVaultConfig({
                adapter: address(adapter),
                underlyingIn: address(usdc),
                underlyingOut: address(weth),
                autoDepositIn: true,
                autoWithdrawOut: true
            })
        );

        bytes memory guardArgs = GuardArgsBuilder.build(
            address(weth), address(usdc), address(ethFeed), address(usdcFeed), 200, 3600, 3600
        );
        bytes memory fullProgram = abi.encodePacked(
            uint8(YIELD_ADJUSTED_RATE_XD),
            uint8(60),
            YieldArgsBuilder.build(address(adapter), address(usdc), address(weth)),
            program,
            uint8(CHAINLINK_GUARD_XD),
            uint8(92),
            guardArgs
        );

        lastOrder = MakerTraitsLib.build(
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
                program: fullProgram
            })
        );

        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethVirtual;
        amounts[1] = usdcVirtual;
        aqua.ship(address(router), abi.encode(lastOrder), tokens, amounts);
        vm.stopPrank();
    }

    function _marketProgram() internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
            uint8(17), uint8(0) // XYCSwap._xycSwapXD
        );
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

    /// AMM price = 200,000/100 = 2000 USDC/WETH, matches feed -> fill allowed
    function test_guardAllowsMarketPricedFill() public {
        _ship(_marketProgram(), 100e18, 200_000e6, 105e18, 210_000e6);

        vm.prank(taker);
        (, uint256 amountOut,) = router.swap(lastOrder, address(usdc), address(weth), 1000e6, _takerTraits());

        assertEq(amountOut, (uint256(997e6) * 100e18) / 200_997e6);
        assertEq(weth.balanceOf(maker), 0);
        assertEq(usdc.balanceOf(maker), 0);
    }

    /// AMM price = 2500 USDC/WETH, feed says 2000 -> 25% off -> guard reverts
    function test_guardRevertsOffMarketFill() public {
        _ship(_marketProgram(), 100e18, 250_000e6, 105e18, 265_000e6);

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkGuardOpcode.PriceDeviationExceeded.selector, 398411136388084, 997e6, 5e14
            )
        );
        router.swap(lastOrder, address(usdc), address(weth), 1000e6, _takerTraits());
    }
}
