// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { PendlePTAdapter } from "src/adapters/pendle/PendlePTAdapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";

/// @notice Proof on an ARBITRUM MAINNET fork: the maker's USDC liquidity is backed by a
/// REAL expired Pendle PT (PT-aUSDC-27JUN2024) — a fixed-income claim. The JIT hook
/// redeems PT -> aUSDC -> USDC through pure Pendle mechanics, zero swap legs.
contract ArbitrumForkPendleTest is Test {
    // verified on-chain (Arbitrum mainnet)
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // native USDC
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a; // same on Arbitrum
    address internal constant PENDLE_MARKET = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5; // PT-aUSDC-27JUN2024 (EXPIRED)
    address internal constant CHAINLINK_ETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address internal constant CHAINLINK_USDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    PendlePTAdapter internal adapter;
    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;
    IAqua internal aqua;
    IERC20 internal pt;

    address internal maker;
    address internal taker;
    ISwapVM.Order internal order;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        aqua = IAqua(AQUA);

        adapter = new PendlePTAdapter(PENDLE_MARKET, USDC, WETH, address(0), 900);
        pt = IERC20(adapter.yieldToken(USDC));

        makerConfig = new MakerConfig();
        router = new SupercazzolaRouter(AQUA, WETH, makeAddr("owner"), "SupercazzolaRouter", "1", address(makerConfig));

        // maker capital: fixed-income USDC side (expired PT) + plain WETH side (passthrough)
        deal(address(pt), maker, 20_000e6);
        deal(WETH, maker, 100e18);
        vm.startPrank(maker);
        pt.approve(address(router), type(uint256).max); // the router pulls PT for the JIT delivery
        IERC20(USDC).approve(address(AQUA), type(uint256).max);
        IERC20(WETH).approve(address(AQUA), type(uint256).max);
        IERC20(USDC).approve(address(router), type(uint256).max); // revenue echo-back
        IERC20(WETH).approve(address(router), type(uint256).max); // reverse-fill deposit pull
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: WETH, adapter: address(adapter), kind: AdapterKind.PendlePT, autoManaged: true });
        sides[1] = SideConfig({ underlying: USDC, adapter: address(adapter), kind: AdapterKind.PendlePT, autoManaged: true });
        makerConfig.setSides(sides);

        // ship: USDC virtual backed by PT, WETH virtual backed by wallet (passthrough)
        uint256 usdcVirtual = 20_000e6 - 1e4; // dust buffer
        // 8 WETH virtual -> AMM price = 20000/8 = 2500 USDC/WETH, matching the feed
        uint256 wethVirtual = 8e18 - 1e15;
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
                    YieldArgsBuilder.build(USDC, WETH, 1e18, 1e18),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0), // XYCSwap
                    uint8(35), uint8(20),
                    CapitalArgsBuilder.build(WETH)
                )
            })
        );

        address[] memory tokens = new address[](2);
        tokens[0] = WETH;
        tokens[1] = USDC;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethVirtual;
        amounts[1] = usdcVirtual;
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopPrank();

        deal(WETH, taker, 0.05e18);
        vm.startPrank(taker);
        IERC20(WETH).approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    /// taker buys USDC paying WETH: JIT redeems the maker's PT through Pendle mechanics
    /// (small fill: the xyc AMM price must stay within the Chainlink guard band)
    function test_fork_pendleFixedIncomeJitCycle() public {
        uint256 ptBefore = pt.balanceOf(maker);

        vm.prank(taker);
        (, uint256 amountOut,) = router.swap(order, WETH, USDC, 0.05e18, _takerTraits());

        // taker received USDC delivered from the maker's real PT redemption
        assertGt(amountOut, 0);
        assertEq(IERC20(USDC).balanceOf(taker), amountOut);
        assertEq(IERC20(WETH).balanceOf(taker), 0);

        // the maker's PT position shrank by exactly what was redeemed (1:1 post-maturity)
        assertLt(pt.balanceOf(maker), ptBefore);
        assertApproxEqRel(ptBefore - pt.balanceOf(maker), amountOut, 1e12);

        // the fill's WETH revenue lands in the maker wallet (passthrough by design)
        assertGt(IERC20(WETH).balanceOf(maker), 0);

        // invariant: real >= virtual on both sides
        bytes32 strategyHash = keccak256(abi.encode(order));
        (uint256 vIn,) = aqua.rawBalances(maker, address(router), strategyHash, USDC);
        (uint256 vOut,) = aqua.rawBalances(maker, address(router), strategyHash, WETH);
        assertGe(adapter.yieldToUnderlying(USDC, pt.balanceOf(maker)), vIn);
        assertGe(adapter.yieldToUnderlying(WETH, IERC20(WETH).balanceOf(maker)), vOut);
    }

    function _takerTraits() internal view returns (bytes memory) {
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
}
