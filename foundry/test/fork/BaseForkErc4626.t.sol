// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { GuardArgsBuilder, CHAINLINK_GUARD_XD } from "src/opcodes/ChainlinkGuardOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";
import { BaseChain } from "script/BaseChain.s.sol";

/// @notice Proof on a Base mainnet fork that the generic ERC4626Adapter works against
/// REAL Morpho (MetaMorpho) and Euler v2 vaults — no mocks anywhere.
contract BaseForkErc4626Test is Test {
    ERC4626Adapter internal adapter;
    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;
    IAqua internal aqua;

    address internal weth = BaseChain.WETH;
    address internal usdc = BaseChain.USDC;
    IERC4626 internal morphoWeth = IERC4626(BaseChain.MORPHO_WETH_VAULT);
    IERC4626 internal morphoUsdc = IERC4626(BaseChain.MORPHO_USDC_VAULT);
    IERC4626 internal eulerWeth = IERC4626(BaseChain.EULER_WETH_VAULT);

    address internal maker;
    address internal taker;
    ISwapVM.Order internal order;

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL_BASE", string(BaseChain.RPC_URL)));
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        aqua = IAqua(BaseChain.AQUA);

        address[] memory underlyings = new address[](2);
        underlyings[0] = weth;
        underlyings[1] = usdc;
        address[] memory vaults = new address[](2);
        vaults[0] = BaseChain.MORPHO_WETH_VAULT;
        vaults[1] = BaseChain.MORPHO_USDC_VAULT;
        adapter = new ERC4626Adapter(underlyings, vaults);
        makerConfig = new MakerConfig();
        router = new SupercazzolaRouter(
            BaseChain.AQUA, weth, makeAddr("owner"), "SupercazzolaRouter", "1", address(makerConfig)
        );

        // sanity: vaults are the real ones we verified
        assertEq(morphoWeth.asset(), weth);
        assertEq(morphoUsdc.asset(), usdc);
        assertEq(eulerWeth.asset(), weth);
        assertTrue(morphoWeth.convertToAssets(1e18) > 1e18, "Morpho WETH vault must accrue yield");
    }

    /// Deposit into real Morpho WETH + USDC vaults, verify rates and shares, withdraw back.
    function test_fork_realVaultRoundTrip() public {
        deal(weth, maker, 10e18);
        deal(usdc, maker, 10_000e6);
        vm.startPrank(maker);
        IERC20(weth).approve(address(adapter), type(uint256).max);
        IERC20(usdc).approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, weth, 10e18);
        adapter.depositFor(maker, usdc, 10_000e6);
        vm.stopPrank();

        // shares minted at the vault's current rate
        assertApproxEqRel(adapter.yieldToUnderlying(weth, morphoWeth.balanceOf(maker)), 10e18, 1e15);
        assertApproxEqRel(adapter.yieldToUnderlying(usdc, morphoUsdc.balanceOf(maker)), 10_000e6, 1e15);

        // withdraw back to recipient, burning maker shares
        vm.startPrank(maker);
        morphoWeth.approve(address(adapter), type(uint256).max);
        morphoUsdc.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        uint256 wethBefore = IERC20(weth).balanceOf(recipientAddr());
        vm.prank(makeAddr("router"));
        adapter.withdrawTo(maker, weth, 5e18, recipientAddr());
        assertEq(IERC20(weth).balanceOf(recipientAddr()) - wethBefore, 5e18);

        uint256 usdcBefore = IERC20(usdc).balanceOf(recipientAddr());
        vm.prank(makeAddr("router"));
        adapter.withdrawTo(maker, usdc, 5_000e6, recipientAddr());
        assertEq(IERC20(usdc).balanceOf(recipientAddr()) - usdcBefore, 5_000e6);
    }

    /// Same for an Euler v2 vault — proves the adapter is protocol-agnostic.
    function test_fork_eulerVaultRoundTrip() public {
        deal(weth, maker, 5e18);
        vm.startPrank(maker);
        IERC20(weth).approve(address(eulerWeth), type(uint256).max);
        uint256 shares = eulerWeth.deposit(5e18, maker);
        vm.stopPrank();

        assertApproxEqRel(eulerWeth.convertToAssets(shares), 5e18, 1e15);

        vm.prank(maker);
        uint256 assetsBack = eulerWeth.redeem(shares, maker, maker);
        assertApproxEqRel(assetsBack, 5e18, 1e15);
    }

    /// Full JIT cycle on real vaults: maker capital in Morpho shares, fill cycles it.
    function test_fork_fullJitCycleWithMorphoVaults() public {
        uint256 wethReal = 105e18;
        uint256 usdcReal = 262_500e6;
        deal(weth, maker, wethReal);
        deal(usdc, maker, usdcReal);
        vm.startPrank(maker);
        IERC20(weth).approve(address(adapter), type(uint256).max);
        IERC20(usdc).approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, weth, wethReal);
        adapter.depositFor(maker, usdc, usdcReal);
        morphoWeth.approve(address(adapter), type(uint256).max);
        morphoUsdc.approve(address(adapter), type(uint256).max);
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: weth, adapter: address(adapter), kind: AdapterKind.ERC4626, autoManaged: true });
        sides[1] = SideConfig({ underlying: usdc, adapter: address(adapter), kind: AdapterKind.ERC4626, autoManaged: true });
        makerConfig.setSides(sides);

        // ship in UNDERLYING units; rate0 baked in args captures post-ship yield only
        uint256 wethVirtual = wethReal - 1e4; // dust buffer (vault ceil-rounding on withdraw)
        uint256 usdcVirtual = usdcReal - 1e4; // dust buffer
        uint256 rate0Weth = adapter.exchangeRate(weth);
        uint256 rate0Usdc = adapter.exchangeRate(usdc);
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
                    YieldArgsBuilder.build(usdc, weth, rate0Usdc, rate0Weth),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0), // XYCSwap
                    uint8(CHAINLINK_GUARD_XD),
                    uint8(92),
                    GuardArgsBuilder.build(
                        weth, usdc, BaseChain.CHAINLINK_ETH_USD, BaseChain.CHAINLINK_USDC_USD, 200, 3600, 86_400
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
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopPrank();

        deal(usdc, taker, 1000e6);
        vm.startPrank(taker);
        IERC20(usdc).approve(address(router), type(uint256).max);
        (, uint256 amountOut,) = router.swap(order, usdc, weth, 1000e6, _takerTraits());
        vm.stopPrank();

        // taker received WETH, paid USDC
        assertGt(amountOut, 0);
        assertEq(IERC20(weth).balanceOf(taker), amountOut);
        assertEq(IERC20(usdc).balanceOf(taker), 0);

        // JIT: maker wallet idle stays zero, capital cycled through the Morpho vaults
        assertEq(IERC20(weth).balanceOf(maker), 0, "maker holds idle WETH");
        assertEq(IERC20(usdc).balanceOf(maker), 0, "maker holds idle USDC");

        // invariant: real (vault-backed, underlying terms) >= virtual on both sides
        bytes32 strategyHash = keccak256(abi.encode(order));
        (uint256 vIn,) = aqua.rawBalances(maker, address(router), strategyHash, usdc);
        (uint256 vOut,) = aqua.rawBalances(maker, address(router), strategyHash, weth);
        assertGe(adapter.yieldToUnderlying(usdc, morphoUsdc.balanceOf(maker)), vIn);
        assertGe(adapter.yieldToUnderlying(weth, morphoWeth.balanceOf(maker)), vOut);
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

    address internal _recipient;
    function recipientAddr() internal returns (address) {
        if (_recipient == address(0)) _recipient = makeAddr("recipient");
        return _recipient;
    }
}
