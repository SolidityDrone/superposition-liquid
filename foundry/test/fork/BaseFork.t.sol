// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { GuardArgsBuilder, CHAINLINK_GUARD_XD } from "src/opcodes/ChainlinkGuardOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";
import { BaseChain } from "script/BaseChain.s.sol";

/// @notice Full E2E on a Base mainnet fork: real Aqua registry, real Aave v3, real tokens,
/// real Chainlink feeds. Maker ships aWETH/aUSDC balances; fill cycles capital JIT.
contract BaseForkTest is Test {
    IAqua internal aqua;
    AaveV3Adapter internal adapter;
    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;

    address internal weth = BaseChain.WETH;
    address internal usdc = BaseChain.USDC;
    address internal aWeth = BaseChain.A_WETH;
    address internal aUsdc = BaseChain.A_USDC;

    address internal maker;
    address internal taker;
    ISwapVM.Order internal order;
    bytes internal takerTraitsData;
    uint256 internal wethVirtual;
    uint256 internal usdcVirtual;

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL_BASE", string(BaseChain.RPC_URL)));

        maker = makeAddr("maker");
        taker = makeAddr("taker");

        aqua = IAqua(BaseChain.AQUA);
        adapter = new AaveV3Adapter(BaseChain.AAVE_POOL);
        makerConfig = new MakerConfig();
        router = new SupercazzolaRouter(
            BaseChain.AQUA, weth, makeAddr("owner"), "SupercazzolaRouter", "1", address(makerConfig)
        );

        // maker capital: 105 WETH + 262,500 USDC supplied to real Aave
        uint256 wethReal = 105e18;
        uint256 usdcReal = 262_500e6;
        deal(weth, maker, wethReal);
        deal(usdc, maker, usdcReal);
        vm.startPrank(maker);
        IERC20(weth).approve(address(router), type(uint256).max);
        IERC20(usdc).approve(address(router), type(uint256).max);
        IERC20(weth).transfer(address(adapter), wethReal);
        adapter.deposit(maker, weth, wethReal);
        IERC20(usdc).transfer(address(adapter), usdcReal);
        adapter.deposit(maker, usdc, usdcReal);
        IERC20(aWeth).approve(address(router), type(uint256).max);
        IERC20(aUsdc).approve(address(router), type(uint256).max);
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max); // reverse-direction pulls
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: weth, adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        sides[1] = SideConfig({ underlying: usdc, adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        makerConfig.setSides(sides);
        vm.stopPrank();

        // ship in UNDERLYING units (rate0 baked in args captures post-ship yield only).
        // Tiny dust buffers both sides: Aave v3.2 displayed-balance rounding can leave the
        // real aToken balance a few wei below the exact underlying amounts moved per fill.
        wethVirtual = IERC20(aWeth).balanceOf(maker) - 1e4;
        usdcVirtual = IERC20(aUsdc).balanceOf(maker) - 1e4;

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
                program: abi.encodePacked(
                    uint8(YIELD_ADJUSTED_RATE_XD),
                    uint8(104),
                    YieldArgsBuilder.build(usdc, weth, adapter.exchangeRate(usdc), adapter.exchangeRate(weth)),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0), // XYCSwap._xycSwapXD
                    uint8(CHAINLINK_GUARD_XD),
                    uint8(92),
                    GuardArgsBuilder.build(
                        weth, usdc, BaseChain.CHAINLINK_ETH_USD, BaseChain.CHAINLINK_USDC_USD, 300, 3600, 86_400
                    ),
                    uint8(36), uint8(20),
                    CapitalArgsBuilder.build(weth)
                )
            })
        );

        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethVirtual;
        amounts[1] = usdcVirtual;
        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);

        takerTraitsData = TakerTraitsLib.build(
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

        deal(usdc, taker, 1000e6);
        vm.prank(taker);
        IERC20(usdc).approve(address(router), type(uint256).max);
    }

    function test_fork_fullCycle() public {
        // effective balances at quote time (aToken count * rate = real underlying)
        uint256 rateWeth = adapter.exchangeRate(weth);
        uint256 rateUsdc = adapter.exchangeRate(usdc);
        uint256 balanceOutEff = wethVirtual * rateWeth / 1e18;
        uint256 balanceInEff = usdcVirtual * rateUsdc / 1e18;

        uint256 amountIn = 1000e6;
        uint256 feeBps = 3e6;
        uint256 bps = 1e9;
        uint256 pricingIn = amountIn - (amountIn * feeBps + bps - 1) / bps; // flatFee ceil
        uint256 expectedOut = pricingIn * balanceOutEff / (balanceInEff + pricingIn);

        vm.prank(taker);
        (, uint256 quotedOut,) = router.quote(order, usdc, weth, amountIn, takerTraitsData);
        // AMM + fee math must land within 0.01% of expected
        assertApproxEqRel(quotedOut, expectedOut, 1e14);

        uint256 aWethBefore = IERC20(aWeth).balanceOf(maker);
        uint256 aUsdcBefore = IERC20(aUsdc).balanceOf(maker);

        vm.prank(taker);
        (, uint256 amountOut,) = router.swap(order, usdc, weth, amountIn, takerTraitsData);
        assertEq(amountOut, quotedOut, "quote != swap");

        // taker received WETH, paid USDC
        assertEq(IERC20(weth).balanceOf(taker), amountOut);
        assertEq(IERC20(usdc).balanceOf(taker), 0);

        // JIT: maker wallet idle capital stays zero, capital cycled through Aave
        assertEq(IERC20(weth).balanceOf(maker), 0, "maker holds idle WETH");
        assertEq(IERC20(usdc).balanceOf(maker), 0, "maker holds idle USDC");

        // aWETH decreased (JIT delivery), aUSDC increased (redeployed fill)
        assertLt(IERC20(aWeth).balanceOf(maker), aWethBefore);
        assertGt(IERC20(aUsdc).balanceOf(maker), aUsdcBefore);

        // invariant: real >= virtual on both sides
        bytes32 strategyHash = keccak256(abi.encode(order));
        (uint256 vIn,) = aqua.rawBalances(maker, address(router), strategyHash, usdc);
        (uint256 vOut,) = aqua.rawBalances(maker, address(router), strategyHash, weth);
        assertGe(adapter.yieldToUnderlying(usdc, IERC20(aUsdc).balanceOf(maker)), vIn);
        assertGe(adapter.yieldToUnderlying(weth, IERC20(aWeth).balanceOf(maker)), vOut);
    }
}
