// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockPendlePT, MockPendleYieldToken, MockPendleSY, MockPendleMarket, MockToken } from "test/unit/mocks/MockPendle.sol";
import { PendlePTAdapter } from "src/adapters/pendle/PendlePTAdapter.sol";

/// @notice Fixed-income adapter: maker's capital in an EXPIRED Pendle PT (redeemable 1:1
/// for the underlying, zero swap legs). Post-maturity redemption:
/// PT -> YT -> YT.redeemPY() -> SY -> SY.redeem(USDC) -> deliver.
contract PendlePTAdapterTest is Test {
    MockToken internal usdc;
    MockPendlePT internal pt;
    MockPendleYieldToken internal yt;
    MockPendleSY internal sy;
    address internal market = makeAddr("market");
    PendlePTAdapter internal adapter;

    address internal maker = makeAddr("maker");
    address internal recipient = makeAddr("recipient");
    address internal router = makeAddr("router");
    address internal weth = makeAddr("weth"); // passthrough side

    function setUp() public {
        usdc = new MockToken("USDC");
        pt = new MockPendlePT(1_719_446_400);
        yt = new MockPendleYieldToken(pt);
        sy = new MockPendleSY(address(usdc));
        sy.setYt(address(yt));
        yt.setSy(address(sy));
        pt.setYt(address(yt));
        market = address(new MockPendleMarket(address(sy), address(pt), address(yt), true));
        adapter = new PendlePTAdapter(address(market), address(usdc), weth, address(0), 900);

        // SY holds the underlying backing (Pendle holds it post-maturity too)
        usdc.mint(address(sy), 1_000_000e6);
    }

    function _seedMaker(uint256 usdcAmount) internal {
        pt.mint(maker, usdcAmount);
        vm.startPrank(maker);
        pt.approve(address(adapter), type(uint256).max);
        vm.stopPrank();
    }

    function test_name_isPendlePT() public view {
        assertEq(adapter.name(), "PendlePT");
    }

    function test_yieldToken_returnsPT() public view {
        assertEq(adapter.yieldToken(address(usdc)), address(pt));
    }

    function test_yieldToken_passthroughForForeignAssets() public view {
        assertEq(adapter.yieldToken(weth), weth);
    }

    function test_exchangeRate_isOnePostMaturity() public view {
        assertEq(adapter.exchangeRate(address(usdc)), 1e18);
    }

    function test_withdrawTo_redeemsPTAndDeliversUnderlying() public {
        _seedMaker(10_000e6);
        vm.prank(router);
        adapter.withdrawTo(maker, address(usdc), 4_000e6, recipient);

        assertEq(usdc.balanceOf(recipient), 4_000e6); // exact delivery
        assertEq(pt.balanceOf(maker), 6_000e6 - 100); // + the 100-wei pull buffer
        assertEq(usdc.balanceOf(maker), 100); // surplus back to the maker
    }

    function test_maxWithdrawable_cappedByMakerPT() public {
        _seedMaker(10_000e6);
        assertEq(adapter.maxWithdrawable(maker, address(usdc)), 10_000e6);
        assertEq(adapter.maxWithdrawable(makeAddr("unknown"), address(usdc)), 0);
    }

    function test_passthrough_side_depositsAreNoOp() public {
        // the ETH/WETH side has no PT backing: hooks must not revert on it
        MockToken wethToken = new MockToken("WETH");
        wethToken.mint(maker, 5e18);
        vm.startPrank(maker);
        IERC20(address(wethToken)).approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(wethToken), 5e18);
        vm.stopPrank();
        assertEq(wethToken.balanceOf(maker), 5e18); // untouched
    }

    function test_passthrough_side_withdrawIsNoOp() public {
        MockToken wethToken = new MockToken("WETH");
        wethToken.mint(maker, 5e18);
        vm.prank(router);
        adapter.withdrawTo(maker, address(wethToken), 1e18, recipient);
        // no-op: Aqua's default transfer handles delivery from the maker wallet
        assertEq(wethToken.balanceOf(maker), 5e18);
        assertEq(wethToken.balanceOf(recipient), 0);
    }

    function test_maxWithdrawable_passthroughUsesWalletBalance() public {
        MockToken wethToken = new MockToken("WETH");
        wethToken.mint(maker, 5e18);
        assertEq(adapter.maxWithdrawable(maker, address(wethToken)), 5e18);
    }
}
