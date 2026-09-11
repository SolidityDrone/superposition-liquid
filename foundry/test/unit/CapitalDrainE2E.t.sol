// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MockAavePool, MockAToken } from "test/unit/mocks/MockAavePool.sol";
import { MockToken } from "test/unit/mocks/MockToken.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";

/// @notice quote() as complete fill-oracle: the maker's real lending-backed capital is
/// checked inside the VM runLoop, so drained capital is caught at quote time — the case
/// the transfer phase used to catch only later.
contract CapitalDrainE2ETest is Test {
    MockAToken internal aToken;
    MockToken internal weth;
    MockToken internal usdc;
    AaveV3Adapter internal adapter;
    SupercazzolaRouter internal router;

    address internal maker;
    address internal taker;
    bytes internal program;
    ISwapVM.Order internal order;

    error MakerCapitalInsufficient(uint256 available, uint256 required);

    event ReasonHex(bytes reason);

    function setUp() public {
        maker = makeAddr("maker");
        taker = makeAddr("taker");

        Aqua aqua = new Aqua();
        aToken = new MockAToken();
        MockAavePool pool = new MockAavePool();
        weth = new MockToken("WETH", 18);
        usdc = new MockToken("USDC", 6);
        pool.registerAToken(address(weth), aToken);
        pool.registerAToken(address(usdc), new MockAToken());
        adapter = new AaveV3Adapter(address(pool));
        MakerConfig makerConfig = new MakerConfig();
        router = new SupercazzolaRouter(
            address(aqua), address(weth), makeAddr("owner"), "SupercazzolaRouter", "1", address(makerConfig)
        );

        // maker capital 100% in the lending protocol
        weth.mint(maker, 105e18);
        usdc.mint(maker, 4500e6);
        vm.startPrank(maker);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(address(weth)).transfer(address(adapter), 105e18);
        adapter.deposit(maker, address(weth), 105e18);
        IERC20(address(usdc)).transfer(address(adapter), 4500e6);
        adapter.deposit(maker, address(usdc), 4500e6);
        aToken.approve(address(router), type(uint256).max);
        weth.approve(address(aqua), type(uint256).max);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: address(weth), adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        sides[1] = SideConfig({ underlying: address(usdc), adapter: address(adapter), kind: AdapterKind.AaveV3, autoManaged: true });
        makerConfig.setSides(sides);

        program = abi.encodePacked(
            uint8(YIELD_ADJUSTED_RATE_XD),
            uint8(104),
            YieldArgsBuilder.build(address(usdc), address(weth), 1e18, 1e18),
            uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
            uint8(17), uint8(0), // XYCSwap
            uint8(35), uint8(20),
            CapitalArgsBuilder.build(address(weth))
        );

        // ship: virtual balances in underlying units
        order = _orderStruct();
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 4000e6;
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopPrank();
    }

    function _orderStruct() internal view returns (ISwapVM.Order memory) {
        return MakerTraitsLib.build(
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
                    program: program
                })
            );
    }

    function _strategy() internal view returns (bytes memory) {
        return abi.encode(_orderStruct());
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

    /// The classic broken-invariant case: the maker shipped virtual inventory but then
    /// drained the aTokens backing it. quote() must reject with the exact shortfall.
    /// (try/catch instead of vm.expectRevert: same assertions, friendlier stack layout)
    function test_quoteRevertsWhenMakerDrainsCapitalBehindStrategy() public {
        vm.startPrank(maker);
        aToken.transfer(address(1), aToken.balanceOf(maker));
        vm.stopPrank();

        uint256 requiredOut = (uint256(997e6) * 100e18) / 4997e6;
        bytes memory tt = _takerTraits();

        try router.quote(order, address(usdc), address(weth), 1000e6, tt) {
            revert("expected quote to revert with MakerCapitalInsufficient");
        } catch (bytes memory reason) {
            assertEq(uint32(bytes4(reason)), uint32(MakerCapitalInsufficient.selector), "unexpected revert reason");
            bytes memory data = new bytes(reason.length - 4);
            for (uint256 i = 4; i < reason.length; i++) data[i - 4] = reason[i];
            (uint256 available, uint256 required) = abi.decode(data, (uint256, uint256));
            assertEq(available, 0);
            assertEq(required, requiredOut);
        }
    }

    function test_quotePassesWhenCapitalIsIntact() public {
        bytes memory tt = _takerTraits();
        vm.prank(taker);
        (, uint256 amountOut,) = router.quote(order, address(usdc), address(weth), 1000e6, tt);
        assertEq(amountOut, (uint256(997e6) * 100e18) / 4997e6);
    }

}
