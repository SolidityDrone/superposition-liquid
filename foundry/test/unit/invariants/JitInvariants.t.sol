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
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { MakerConfig, MakerVaultConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";

/// @notice Core invariants over randomized fill sequences (SPEC B5.1 / Core Invariants):
///  I1: maker idle capital stays zero before and after every fill (capital 100% in Aave)
///  I2: real lending-backed balance >= Aqua virtual balance (never oversell)
///  I3: quote() == swap() for the same state
contract JitInvariantsTest is Test {
    Aqua internal aqua;
    MockAavePool internal pool;
    MockAToken internal aToken;
    MockAToken internal aTokenUsdc;
    MockToken internal weth;
    MockToken internal usdc;
    AaveV3Adapter internal adapter;
    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;

    address internal maker;
    address internal taker;
    ISwapVM.Order internal order;
    bytes32 internal strategyHash;
    bytes internal takerTraitsData;

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
        adapter = new AaveV3Adapter(address(pool));
        makerConfig = new MakerConfig();
        router = new SupercazzolaRouter(
            address(aqua), address(weth), makeAddr("owner"), "SupercazzolaRouter", "1", address(makerConfig)
        );

        // rate 1.0 for both (mock income default) -> pricing = shipped balances
        weth.mint(maker, 105e18);
        usdc.mint(maker, 4200e6);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        usdc.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(weth), 105e18);
        adapter.depositFor(maker, address(usdc), 4200e6);
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
                    uint8(YIELD_ADJUSTED_RATE_XD), uint8(124),
                    YieldArgsBuilder.build(address(adapter), address(usdc), address(weth), 1e18, 1e18),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0)
                )
            })
        );

        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 4000e6;
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopPrank();
        strategyHash = keccak256(abi.encode(order));

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
    }

    function _assertInvariants() internal view {
        // I1: no idle capital in maker wallet
        assertEq(weth.balanceOf(maker), 0, "I1: maker holds idle WETH");
        assertEq(usdc.balanceOf(maker), 0, "I1: maker holds idle USDC");

        // I2: lending-backed balance >= virtual balance (per token)
        (uint256 virtualIn,) = aqua.rawBalances(maker, address(router), strategyHash, address(usdc));
        (uint256 virtualOut,) = aqua.rawBalances(maker, address(router), strategyHash, address(weth));
        uint256 realUsdc = adapter.yieldToUnderlying(address(usdc), aTokenUsdc.balanceOf(maker));
        uint256 realWeth = adapter.yieldToUnderlying(address(weth), aToken.balanceOf(maker));
        assertGe(realUsdc, virtualIn, "I2: real USDC < virtual");
        assertGe(realWeth, virtualOut, "I2: real WETH < virtual");
    }

    /// @dev 8 sequential randomized fills; invariants must hold after each one
    function test_fuzz_invariantsHoldAcrossFillSequence(uint256 seed) public {
        vm.assume(seed > 0);

        for (uint256 i = 0; i < 8; i++) {
            uint256 amountIn = 10e6 + uint256(keccak256(abi.encode(seed, i))) % 500e6;

            usdc.mint(taker, amountIn);
            vm.prank(taker);
            usdc.approve(address(router), type(uint256).max);

            // I3: quote == swap at the same state
            vm.prank(taker);
            (, uint256 quotedOut,) = router.quote(order, address(usdc), address(weth), amountIn, takerTraitsData);
            vm.prank(taker);
            (, uint256 swappedOut,) = router.swap(order, address(usdc), address(weth), amountIn, takerTraitsData);
            assertEq(quotedOut, swappedOut, "I3: quote != swap");

            _assertInvariants();
        }
    }

    function test_fuzz_invariantAtFullDepletion(uint256 seed) public {
        vm.assume(seed > 0);
        // drain the WETH side almost fully with big fills; last remaining dust is fine
        for (uint256 i = 0; i < 4; i++) {
            uint256 amountIn = 700e6 + uint256(keccak256(abi.encode(seed, i))) % 300e6;
            usdc.mint(taker, amountIn);
            vm.prank(taker);
            usdc.approve(address(router), type(uint256).max);

            vm.prank(taker);
            router.swap(order, address(usdc), address(weth), amountIn, takerTraitsData);
            _assertInvariants();
        }
    }
}
