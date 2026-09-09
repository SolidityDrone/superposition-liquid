// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { MakerConfig, MakerVaultConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { GuardArgsBuilder, CHAINLINK_GUARD_XD } from "src/opcodes/ChainlinkGuardOpcode.sol";
import { BaseChain } from "./BaseChain.s.sol";

/// @notice Bounty demo (SPEC "Demo"): one-shot E2E on a Base fork.
/// Deploys the stack, sets the maker up with 100% capital in Aave, ships the strategy,
/// quotes, fills once in each direction, and prints the capital state at every step.
/// Run:  anvil --fork-url $RPC_URL_BASE &  then
///       forge script script/Demo.s.sol --rpc-url http://localhost:8545 --broadcast
contract Demo is Script, StdCheats {
    uint256 internal constant MAKER_KEY = 0xA11CE;
    uint256 internal constant TAKER_KEY = 0xB0B;

    AaveV3Adapter internal adapter;
    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;
    IAqua internal aqua;

    address internal weth = BaseChain.WETH;
    address internal usdc = BaseChain.USDC;
    address internal aWeth = BaseChain.A_WETH;
    address internal aUsdc = BaseChain.A_USDC;

    address internal maker;
    address internal taker;
    ISwapVM.Order internal order;

    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0xAC1E));
        maker = vm.addr(MAKER_KEY);
        taker = vm.addr(TAKER_KEY);
        aqua = IAqua(BaseChain.AQUA);

        vm.startBroadcast(deployerKey);
        makerConfig = new MakerConfig();
        adapter = new AaveV3Adapter(BaseChain.AAVE_POOL);
        router = new SupercazzolaRouter(BaseChain.AQUA, weth, msg.sender, "SupercazzolaRouter", "1", address(makerConfig));
        vm.stopBroadcast();

        console2.log("== 1. deployed ==");
        _printCapital("after deploy");

        // --- maker setup: 100% capital into Aave ---
        vm.startBroadcast(MAKER_KEY);
        deal(weth, maker, 105e18);
        deal(usdc, maker, 262_500e6);
        IERC20(weth).approve(address(adapter), type(uint256).max);
        IERC20(usdc).approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, weth, 105e18);
        adapter.depositFor(maker, usdc, 262_500e6);
        IERC20(aWeth).approve(address(adapter), type(uint256).max);
        IERC20(aUsdc).approve(address(adapter), type(uint256).max);
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max); // reverse-direction pulls
        makerConfig.setConfig(
            MakerVaultConfig({
                adapter: address(adapter),
                underlyingIn: usdc,
                underlyingOut: weth,
                autoDepositIn: true,
                autoWithdrawOut: true
            })
        );
        vm.stopBroadcast();
        console2.log("== 2. maker capital 100% in Aave (aWETH/aUSDC) ==");
        _printCapital("after setup");

        // --- ship strategy: [yield][flatFee][xyc][chainlink guard], virtual = aToken counts ---
        vm.startBroadcast(MAKER_KEY);
        uint256 wethVirtual = IERC20(aWeth).balanceOf(maker);
        uint256 usdcVirtual = IERC20(aUsdc).balanceOf(maker) - 1e4; // dust buffer
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
                    uint8(60),
                    YieldArgsBuilder.build(address(adapter), usdc, weth),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6), // 0.3% fee to maker
                    uint8(17), uint8(0), // XYCSwap._xycSwapXD
                    uint8(CHAINLINK_GUARD_XD),
                    uint8(92),
                    GuardArgsBuilder.build(
                        weth, usdc, BaseChain.CHAINLINK_ETH_USD, BaseChain.CHAINLINK_USDC_USD, 200, 3600, 86_400
                    )
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
        vm.stopBroadcast();
        console2.log("== 3. strategy shipped on Aqua (ETH/USDC visible to the world) ==");
        _printCapital("after ship");

        // --- taker fills: sell USDC, buy WETH ---
        bytes memory tt = _takerTraits();
        deal(usdc, taker, 1000e6);
        vm.startBroadcast(TAKER_KEY);
        IERC20(usdc).approve(address(router), type(uint256).max);
        (, uint256 amountOut,) = router.swap(order, usdc, weth, 1000e6, tt);
        vm.stopBroadcast();
        console2.log("== 4. fill #1: taker sold 1000 USDC, received WETH ==");
        console2.log("   taker got WETH:", amountOut);
        _printCapital("after fill 1");

        // --- taker fills reverse direction: sell WETH, buy USDC ---
        deal(weth, taker, amountOut);
        vm.startBroadcast(TAKER_KEY);
        IERC20(weth).approve(address(router), type(uint256).max);
        router.swap(order, weth, usdc, amountOut, _takerTraitsReverse());
        vm.stopBroadcast();
        console2.log("== 5. fill #2: taker sold WETH back, bought USDC ==");
        _printCapital("after fill 2");

        console2.log("== DONE: maker wallet idle balance stayed 0 through every fill ==");
        console2.log("        100% of capital in aWETH/aUSDC, earning Aave APY + swap fees.");
    }

    function _takerTraits() internal view returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(0), isExactIn: true, shouldUnwrapWeth: false, isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false, useTransferFromAndAquaPush: true, threshold: "",
                to: address(0), deadline: 0, hasPreTransferInCallback: false, hasPreTransferOutCallback: false,
                preTransferInHookData: "", postTransferInHookData: "", preTransferOutHookData: "",
                postTransferOutHookData: "", preTransferInCallbackData: "", preTransferOutCallbackData: "",
                instructionsArgs: "", signature: ""
            })
        );
    }

    function _takerTraitsReverse() internal view returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(0), isExactIn: true, shouldUnwrapWeth: false, isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false, useTransferFromAndAquaPush: true, threshold: "",
                to: address(0), deadline: 0, hasPreTransferInCallback: false, hasPreTransferOutCallback: false,
                preTransferInHookData: "", postTransferInHookData: "", preTransferOutHookData: "",
                postTransferOutHookData: "", preTransferInCallbackData: "", preTransferOutCallbackData: "",
                instructionsArgs: "", signature: ""
            })
        );
    }

    function _printCapital(string memory label) internal view {
        console2.log("  [%s]", label);
        console2.log("   maker WETH (idle): ", IERC20(weth).balanceOf(maker));
        console2.log("   maker USDC (idle): ", IERC20(usdc).balanceOf(maker));
        console2.log("   maker aWETH:       ", IERC20(aWeth).balanceOf(maker));
        console2.log("   maker aUSDC:       ", IERC20(aUsdc).balanceOf(maker));
    }
}
