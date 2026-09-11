// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SuperpositionFixture } from "../helpers/SuperpositionFixture.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";
import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { SuperpositionUniAdapter } from "src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol";
import { MakerConfig, AdapterKind, SideConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";

contract EthereumForkSuperpositionTest is SuperpositionFixture {
    using SafeERC20 for IERC20;

    SuperpositionHook internal hook;

    function setUp() public {
        _fork();
        hook = _deployHook(100, 1);
    }

    function test_fork_hookDeploysAndInitializes() public {
        assertGt(address(hook).code.length, 0);
        assertTrue(hook.initialized());
        assertTrue(address(hook.shareToken()) != address(0));
    }

    function test_fork_adapterViewsOnEmptyBucket() public {
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), address(0xBEEF), USDC, 1, 101, USDT, -101, -1);
        assertEq(adapter.name(), "SuperpositionUniHook");
        assertEq(adapter.yieldToken(USDC), address(hook.shareToken()));
        assertEq(adapter.exchangeRate(USDC), 1e18);
        assertEq(adapter.maxWithdrawable(address(0xA11CE), USDC), 0);
        assertEq(uint256(AdapterKind.SuperpositionUniHook), uint256(AdapterKind.SuperpositionUniHook));
    }

    function test_fork_deposit_usdc_oneSided() public {
        address maker = address(0xA11CE);
        deal(USDC, maker, 1_000e6);
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), address(0xBEEF), USDC, 1, 101, USDT, -101, -1);

        vm.startPrank(maker);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).transfer(address(adapter), 1_000e6);
        adapter.deposit(maker, USDC, 1_000e6);
        vm.stopPrank();

        assertGt(hook.sharesOf(maker, 1, 101), 0);
        assertGt(IERC20(AUSDC).balanceOf(address(hook)), 990e6);
        assertEq(hook.sharesOf(maker, -101, -1), 0);
        assertGt(adapter.maxWithdrawable(maker, USDC), 0);
    }

    function _makerWithUsdcDeposit(address maker, address adapter) internal {
        deal(USDC, maker, 1_000e6);
        vm.startPrank(maker);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).transfer(address(adapter), 1_000e6);
        SuperpositionUniAdapter(adapter).deposit(maker, USDC, 1_000e6);
        IERC1155(hook.shareToken()).setApprovalForAll(adapter, true);
        vm.stopPrank();
    }

    function test_fork_withdrawAsOperator() public {
        address maker = address(0xA11CE);
        address router = address(0xBEEF);
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), router, USDC, 1, 101, USDT, -101, -1);
        _makerWithUsdcDeposit(maker, address(adapter));

        uint256 sharesBefore = hook.sharesOf(maker, 1, 101);
        vm.prank(router);
        adapter.withdraw(maker, USDC, 100e6, 0, maker);

        assertApproxEqAbs(IERC20(USDC).balanceOf(maker), 100e6, 2);
        assertLt(hook.sharesOf(maker, 1, 101), sharesBefore);
    }

    function test_fork_withdrawNotOperatorReverts() public {
        address maker = address(0xA11CE);
        address router = address(0xBEEF);
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), router, USDC, 1, 101, USDT, -101, -1);
        deal(USDC, maker, 1_000e6);
        vm.startPrank(maker);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).transfer(address(adapter), 1_000e6);
        adapter.deposit(maker, USDC, 1_000e6);
        vm.stopPrank(); // NB: no setApprovalForAll

        vm.prank(router);
        vm.expectRevert();
        adapter.withdraw(maker, USDC, 100e6, 0, maker);
    }

    function test_fork_withdrawOnlyRouter() public {
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), address(0xBEEF), USDC, 1, 101, USDT, -101, -1);
        vm.expectRevert(SuperpositionUniAdapter.NotRouter.selector);
        adapter.withdraw(address(0xA11CE), USDC, 100e6, 0, address(0xA11CE));
    }

    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function test_fork_yieldGrowsClaim() public {
        address maker = address(0xA11CE);
        address router = address(0xBEEF);
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), router, USDC, 1, 101, USDT, -101, -1);
        _makerWithUsdcDeposit(maker, address(adapter));

        uint256 before = adapter.maxWithdrawable(maker, USDC);
        vm.warp(block.timestamp + 365 days);
        hook.syncYield();
        uint256 afterWarp = adapter.maxWithdrawable(maker, USDC);
        assertGt(afterWarp, before, "Aave yield grows the claim");
    }

    function test_fork_supercazzolaJitFill() public {
        address maker = address(0xA11CE);
        address taker = address(0xB0B);

        MakerConfig mc = new MakerConfig();
        SupercazzolaRouter router =
            new SupercazzolaRouter(AQUA, WETH, address(this), "SupercazzolaRouter", "1", address(mc));
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), address(router), USDC, 1, 101, USDT, -101, -1);

        // maker LPs USDC into the hook bucket, keeps USDT passthrough
        deal(USDC, maker, 5_000e6);
        deal(USDT, maker, 6_000e6);
        vm.startPrank(maker);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).transfer(address(adapter), 5_000e6);
        adapter.deposit(maker, USDC, 5_000e6);
        IERC1155(hook.shareToken()).setApprovalForAll(address(adapter), true);
        IERC20(USDC).forceApprove(address(router), type(uint256).max);
        IERC20(USDT).forceApprove(address(router), type(uint256).max);
        IERC20(USDC).forceApprove(AQUA, type(uint256).max);
        IERC20(USDT).forceApprove(AQUA, type(uint256).max);

        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig(USDC, address(adapter), AdapterKind.SuperpositionUniHook, true);
        sides[1] = SideConfig(USDT, address(adapter), AdapterKind.SuperpositionUniHook, true);
        mc.setSides(sides);

        ISwapVM.Order memory order = MakerTraitsLib.build(
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
                    YieldArgsBuilder.build(USDT, USDC, 1e18, 1e18),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0),
                    uint8(35), uint8(20),
                    CapitalArgsBuilder.build(USDC)
                )
            })
        );
        address[] memory tokens = new address[](2);
        tokens[0] = USDT;
        tokens[1] = USDC;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5_000e6; // USDT virtual (passthrough)
        amounts[1] = 5_000e6; // USDC virtual (bucket-backed)
        IAqua(AQUA).ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopPrank();

        deal(USDT, taker, 1_000e6);
        vm.startPrank(taker);
        IERC20(USDT).forceApprove(address(router), type(uint256).max);
        (, uint256 amountOut,) = router.swap(order, USDT, USDC, 1_000e6, _takerTraits());
        vm.stopPrank();

        assertGt(amountOut, 800e6, "USDC out");
        assertEq(IERC20(USDC).balanceOf(taker), amountOut);
        // the USDT revenue was deposited into the USDT bucket
        assertGt(hook.sharesOf(maker, -101, -1), 0);
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
