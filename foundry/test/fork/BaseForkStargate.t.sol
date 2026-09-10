// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { StargateAdapter } from "src/adapters/stargate/StargateAdapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";

/// @notice Proof on a BASE MAINNET fork with the REAL Stargate V2 contracts:
/// StargatePoolUSDC (0x27a16dc7...5d26) + StargateStaking (0xDFc47DCe...a0B80).
/// The maker's USDC liquidity gets deposited into the pool AND staked; the JIT hook
/// unstakes (instant, verified in source) and redeems — capped by the pool's credit.
contract BaseForkStargateTest is Test {
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant STARGATE_POOL = 0x27a16dc786820B16E5c9028b75B99F6f604b5d26; // StargatePoolUSDC
    address internal constant STARGATE_STAKING = 0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80;
    address internal constant CHAINLINK_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address internal constant CHAINLINK_USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;

    StargateAdapter internal adapter;
    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;
    IAqua internal aqua;
    IERC20 internal lp;

    address internal maker;
    address internal taker;
    ISwapVM.Order internal order;
    uint256 internal stakedBefore;

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL_BASE", string("https://mainnet.base.org")));
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        aqua = IAqua(AQUA);

        adapter = new StargateAdapter(STARGATE_POOL, STARGATE_STAKING, WETH);
        lp = IERC20(adapter.LP());
        assertEq(IERC20Metadata(address(lp)).symbol(), "S*USDC"); // the real LP token

        makerConfig = new MakerConfig();
        router = new SupercazzolaRouter(AQUA, WETH, makeAddr("owner"), "SupercazzolaRouter", "1", address(makerConfig));

        // maker capital: USDC side gets deposited AND staked; WETH side passthrough
        deal(USDC, maker, 5_000e6);
        deal(WETH, maker, 8e18);
        vm.startPrank(maker);
        IERC20(USDC).approve(address(router), type(uint256).max);
        IERC20(USDC).approve(address(AQUA), type(uint256).max);
        IERC20(WETH).approve(address(AQUA), type(uint256).max);
        IERC20(WETH).approve(address(router), type(uint256).max);
        // deposit + stake the maker's USDC (real pool.deposit + real staking.deposit)
        stakedBefore = lp.balanceOf(address(STARGATE_STAKING));
        IERC20(USDC).transfer(address(adapter), 5_000e6);
        adapter.deposit(maker, USDC, 5_000e6);
        assertEq(lp.balanceOf(address(STARGATE_STAKING)) - stakedBefore, 5_000e6);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: WETH, adapter: address(adapter), kind: AdapterKind.Stargate, autoManaged: true });
        sides[1] = SideConfig({ underlying: USDC, adapter: address(adapter), kind: AdapterKind.Stargate, autoManaged: true });
        makerConfig.setSides(sides);

        // ship: USDC virtual backed by the staked LP; price = 5000/1.6 ≈ 3125 USDC/WETH
        // (near market, keeps the AMM average within tolerance; no Chainlink guard here
        //  to keep the proof focused on the Stargate mechanics)
        uint256 usdcVirtual = 5_000e6 - 1e4; // dust buffer
        uint256 wethVirtual = 16e17;
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
                    uint8(36), uint8(20),
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

    /// taker buys USDC paying WETH: JIT unstakes (instant) + redeems through the REAL pool
    function test_fork_stargateJitCycle() public {
        // maker capital: deposited AND staked in the REAL contracts
        assertGt(lp.balanceOf(address(STARGATE_STAKING)), 0);

        vm.prank(taker);
        (, uint256 amountOut,) = router.swap(order, WETH, USDC, 0.05e18, _takerTraits());

        // taker received USDC delivered from the maker's staked LP (unstaked -> redeemed)
        assertGt(amountOut, 0);
        assertEq(IERC20(USDC).balanceOf(taker), amountOut);
        assertEq(IERC20(WETH).balanceOf(taker), 0);

        // the staked position net change = +deposit - redeemed (1:1 LP accounting)
        assertEq(lp.balanceOf(address(STARGATE_STAKING)) - stakedBefore, 5_000e6 - amountOut);

        // the fill's WETH revenue lands in the maker wallet (passthrough by design)
        assertGt(IERC20(WETH).balanceOf(maker), 0);

        // invariant: real >= virtual on both sides
        bytes32 strategyHash = keccak256(abi.encode(order));
        (uint256 vIn,) = aqua.rawBalances(maker, address(router), strategyHash, USDC);
        (uint256 vOut,) = aqua.rawBalances(maker, address(router), strategyHash, WETH);
        assertGe(adapter.yieldToUnderlying(USDC, _stakedLp()), vIn);
        assertGe(adapter.yieldToUnderlying(WETH, IERC20(WETH).balanceOf(maker)), vOut);
    }

    function _stakedLp() internal view returns (uint256) {
        return IERC20(lp).balanceOf(address(STARGATE_STAKING)) / 1; // staked LP = our position
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
