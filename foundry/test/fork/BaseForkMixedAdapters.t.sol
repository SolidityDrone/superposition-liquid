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
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";
import { BaseChain } from "script/BaseChain.s.sol";

/// @notice The per-side registry end to end on a Base mainnet fork: the maker
///         parks WETH capital in AAVE and USDC capital in a MORPHO ERC-4626
///         vault (Steakhouse Prime). One maker, two adapters, one config —
///         each side resolved by token with one registry lookup, nothing hard
///         coded in the program.
contract BaseForkMixedAdaptersTest is Test {
    IAqua internal aqua;
    AaveV3Adapter internal aaveAdapter; // WETH side
    ERC4626Adapter internal morphoAdapter; // USDC side
    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;

    address internal weth = BaseChain.WETH;
    address internal usdc = BaseChain.USDC;
    address internal aWeth = BaseChain.A_WETH;
    address internal morphoUsdcVault = BaseChain.MORPHO_USDC_VAULT; // ERC-4626 shares

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
        aaveAdapter = new AaveV3Adapter(BaseChain.AAVE_POOL);
        morphoAdapter = new ERC4626Adapter(
            _single(usdc), _single(morphoUsdcVault)
        );
        makerConfig = new MakerConfig();
        router = new SupercazzolaRouter(
            BaseChain.AQUA, weth, makeAddr("owner"), "SupercazzolaRouter", "1", address(makerConfig)
        );

        // maker capital split by protocol: WETH in Aave, USDC in Morpho
        uint256 wethReal = 105e18;
        uint256 usdcReal = 262_500e6;
        deal(weth, maker, wethReal);
        deal(usdc, maker, usdcReal);
        vm.startPrank(maker);
        IERC20(weth).approve(address(router), type(uint256).max);
        IERC20(weth).transfer(address(aaveAdapter), wethReal);
        aaveAdapter.deposit(maker, weth, wethReal);
        IERC20(usdc).approve(address(router), type(uint256).max);
        IERC20(usdc).transfer(address(morphoAdapter), usdcReal);
        morphoAdapter.deposit(maker, usdc, usdcReal);
        // per-side JIT pull approvals: yield tokens -> their own adapter,
        // underlyings -> Aqua registry (for the reverse-direction pulls)
        IERC20(aWeth).approve(address(router), type(uint256).max);
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(morphoUsdcVault).approve(address(router), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: weth, adapter: address(aaveAdapter), kind: AdapterKind.AaveV3, autoManaged: true });
        sides[1] = SideConfig({ underlying: usdc, adapter: address(morphoAdapter), kind: AdapterKind.ERC4626, autoManaged: true });
        makerConfig.setSides(sides);
        vm.stopPrank();

        // dust buffers: real balances round a few wei below the exact amounts
        // ship virtual balances in UNDERLYING units with rate0 = the rate at
        // ship time: the yield opcode then scales by rate(now)/rate0, capturing
        // only post-ship accrual (BaseFork semantics — Aave v3.2 displayed
        // balances are underlying-denominated, so is the deposited USDC).
        wethVirtual = IERC20(aWeth).balanceOf(maker) - 1e4;
        usdcVirtual = usdcReal - 1e4;

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
                    YieldArgsBuilder.build(
                        usdc, weth, morphoAdapter.exchangeRate(usdc), aaveAdapter.exchangeRate(weth)
                    ),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0), // XYCSwap._xycSwapXD
                    uint8(35), uint8(20),
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

    function _single(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function test_fork_mixedAdapterCycle() public {
        // virtuals ship in UNDERLYING units with rate0 = the ship-time rate,
        // so the yield opcode's factor rate(now)/rate0 is exactly 1 on the same
        // block: the AMM prices on the underlying amounts themselves.
        uint256 balanceOutEff = wethVirtual;
        uint256 balanceInEff = usdcVirtual;

        uint256 amountIn = 1000e6;
        uint256 feeBps = 3e6;
        uint256 bps = 1e9;
        uint256 pricingIn = amountIn - (amountIn * feeBps + bps - 1) / bps;
        uint256 expectedOut = pricingIn * balanceOutEff / (balanceInEff + pricingIn);

        vm.prank(taker);
        (, uint256 quotedOut,) = router.quote(order, usdc, weth, amountIn, takerTraitsData);
        assertApproxEqRel(quotedOut, expectedOut, 1e14);

        uint256 aWethBefore = IERC20(aWeth).balanceOf(maker);
        uint256 sharesBefore = IERC20(morphoUsdcVault).balanceOf(maker);

        vm.prank(taker);
        (, uint256 amountOut,) = router.swap(order, usdc, weth, amountIn, takerTraitsData);
        assertEq(amountOut, quotedOut, "quote != swap");

        // taker received WETH, paid USDC
        assertEq(IERC20(weth).balanceOf(taker), amountOut);
        assertEq(IERC20(usdc).balanceOf(taker), 0);

        // JIT: maker wallet idle capital stays zero on BOTH sides
        assertEq(IERC20(weth).balanceOf(maker), 0, "maker holds idle WETH");
        assertEq(IERC20(usdc).balanceOf(maker), 0, "maker holds idle USDC");

        // the two sides cycled through DIFFERENT protocols:
        // aWETH decreased (Aave JIT delivery), Morpho shares increased (redeployed fill)
        assertLt(IERC20(aWeth).balanceOf(maker), aWethBefore);
        assertGt(IERC20(morphoUsdcVault).balanceOf(maker), sharesBefore);

        // invariant: real >= virtual on both sides, each priced by ITS adapter
        bytes32 strategyHash = keccak256(abi.encode(order));
        (uint256 vIn,) = aqua.rawBalances(maker, address(router), strategyHash, usdc);
        (uint256 vOut,) = aqua.rawBalances(maker, address(router), strategyHash, weth);
        assertGe(morphoAdapter.yieldToUnderlying(usdc, IERC20(morphoUsdcVault).balanceOf(maker)), vIn);
        assertGe(aaveAdapter.yieldToUnderlying(weth, IERC20(aWeth).balanceOf(maker)), vOut);
    }
}
