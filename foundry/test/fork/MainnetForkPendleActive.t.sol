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
import { SuperPositionVMRouter } from "src/SuperPositionVMRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";

/// @notice Proof on an ETHEREUM MAINNET fork with a REAL ACTIVE Pendle market:
/// PT-wstETH (expiry Dec 2027). The maker locks a fixed yield — PT trades at ~0.974 of
/// wstETH (the implied-yield discount) and appreciates toward par, captured by the
/// rate0 opcode. JIT delivery: PT -> market AMM swap (callback) -> SY -> wstETH.
contract MainnetForkPendleActiveTest is Test {
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant PENDLE_MARKET = 0x34280882267ffa6383B363E278B027Be083bBe3b; // PT-wstETH active (Dec 2027)
    address internal constant PENDLE_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;

    PendlePTAdapter internal adapter;
    MakerConfig internal makerConfig;
    SuperPositionVMRouter internal router;
    IAqua internal aqua;
    IERC20 internal pt;

    address internal maker;
    address internal taker;
    ISwapVM.Order internal order;

    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        aqua = IAqua(AQUA);

        adapter = new PendlePTAdapter(PENDLE_MARKET, WSTETH, USDC, PENDLE_ORACLE, 900);
        pt = IERC20(adapter.yieldToken(WSTETH));

        makerConfig = new MakerConfig();
        router = new SuperPositionVMRouter(AQUA, WSTETH, makeAddr("owner"), "SuperPositionVMRouter", "1", address(makerConfig));

        // sanity: the market is active and PT trades at a discount (fixed income)
        assertTrue(!adapter.isExpiredMarket(), "market must be active");
        // PT trades at a discount to wstETH (the implied fixed yield, ~9% APY for a
        // Dec-2027 maturity), converging to par as maturity approaches
        assertGt(adapter.exchangeRate(WSTETH), 5e17, "PT must trade above 0.5 wstETH");
        assertLt(adapter.exchangeRate(WSTETH), 1e18, "PT must trade below par (implied yield)");

        // maker capital: PT-wstETH (fixed income) + USDC passthrough
        deal(address(pt), maker, 100e18);
        deal(USDC, maker, 100_000e6);
        vm.startPrank(maker);
        pt.approve(address(router), type(uint256).max); // the router pulls PT for the JIT delivery
        IERC20(WSTETH).approve(address(AQUA), type(uint256).max);
        IERC20(USDC).approve(address(AQUA), type(uint256).max);
        IERC20(USDC).approve(address(router), type(uint256).max); // revenue echo-back
        IERC20(WSTETH).approve(address(router), type(uint256).max); // reverse-fill deposit pull
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: WSTETH, adapter: address(adapter), kind: AdapterKind.PendlePT, autoManaged: true });
        sides[1] = SideConfig({ underlying: USDC, adapter: address(adapter), kind: AdapterKind.PendlePT, autoManaged: true });
        makerConfig.setSides(sides);

        // ship in UNDERLYING units: wstETH virtual = PT position at the oracle rate
        uint256 rate0 = adapter.exchangeRate(WSTETH);
        // price ~3100 USDC/wstETH with the maker's real USDC balance as the passthrough side
        uint256 wstVirtual = 32e18 - 1e15;
        uint256 usdcVirtual = 100_000e6 - 1e4;
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
                    YieldArgsBuilder.build(USDC, WSTETH, 1e18, rate0),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0), // XYCSwap
                    uint8(35), uint8(20),
                    CapitalArgsBuilder.build(WSTETH)
                )
            })
        );

        address[] memory tokens = new address[](2);
        tokens[0] = WSTETH;
        tokens[1] = USDC;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wstVirtual;
        amounts[1] = usdcVirtual;
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopPrank();

        deal(USDC, taker, 1000e6);
        vm.startPrank(taker);
        IERC20(USDC).approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    /// taker buys wstETH paying USDC: the JIT delivers through the real Pendle market
    /// AMM swap (PT -> SY via callback) + SY redemption to wstETH
    function test_fork_pendleActiveFixedIncomeJitCycle() public {
        uint256 ptBefore = pt.balanceOf(maker);

        vm.prank(taker);
        (, uint256 amountOut,) = router.swap(order, USDC, WSTETH, 1000e6, _takerTraits());

        // taker received real wstETH delivered from the maker's PT position
        assertGt(amountOut, 0);
        assertEq(IERC20(WSTETH).balanceOf(taker), amountOut);
        assertEq(IERC20(USDC).balanceOf(taker), 0);

        // the maker's PT position shrank (sold on the market to fund the delivery)
        assertLt(pt.balanceOf(maker), ptBefore);

        // the fill's USDC revenue lands in the maker wallet (passthrough by design)
        assertGe(IERC20(USDC).balanceOf(maker), 997e6);

        // invariant: real >= virtual on both sides
        bytes32 strategyHash = keccak256(abi.encode(order));
        (uint256 vIn,) = aqua.rawBalances(maker, address(router), strategyHash, USDC);
        (uint256 vOut,) = aqua.rawBalances(maker, address(router), strategyHash, WSTETH);
        assertGe(adapter.yieldToUnderlying(USDC, IERC20(USDC).balanceOf(maker)), vIn);
        assertGe(adapter.yieldToUnderlying(WSTETH, pt.balanceOf(maker)), vOut);
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
