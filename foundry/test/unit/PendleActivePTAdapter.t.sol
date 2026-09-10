// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockPendlePT, MockPendleYieldToken, MockPendleSY, MockActiveMarket, MockPendleOracle, MockToken } from "test/unit/mocks/MockPendle.sol";
import { PendlePTAdapter } from "src/adapters/pendle/PendlePTAdapter.sol";

/// @notice ACTIVE (unmatured) PT market: the maker locks a fixed yield, PT trades at a
/// discount to the asset and appreciates toward par. Delivery pre-maturity goes through
/// the market's native PT->SY swap (IPMarketSwapCallback pattern) + SY redeem, with the
/// oracle-bounded buffer absorbing the spread.
contract PendleActivePTAdapterTest is Test {
    MockToken internal usdc;
    MockPendlePT internal pt;
    MockPendleYieldToken internal yt;
    MockPendleSY internal sy;
    MockActiveMarket internal market;
    MockPendleOracle internal oracle;
    PendlePTAdapter internal adapter;

    address internal maker = makeAddr("maker");
    address internal recipient = makeAddr("recipient");
    address internal router = makeAddr("router");
    address internal weth = makeAddr("weth");

    function setUp() public {
        usdc = new MockToken("USDC");
        pt = new MockPendlePT(0); // far future = active
        yt = new MockPendleYieldToken(pt);
        sy = new MockPendleSY(address(usdc));
        sy.setYt(address(yt));
        yt.setSy(address(sy));
        pt.setYt(address(yt));
        market = new MockActiveMarket(pt, address(sy), address(yt));
        oracle = new MockPendleOracle();
        oracle.setRate(95e16); // PT = 0.95 asset (5% implied yield)
        adapter = new PendlePTAdapter(address(market), address(usdc), weth, address(oracle), 900);

        // market holds SY inventory; SY holds USDC backing
        usdc.mint(address(sy), 1_000_000e6);
        sy.mint(address(market), 1_000_000e6);

        // maker's PT position
        pt.mint(maker, 10_000e6);
        vm.startPrank(maker);
        pt.approve(address(adapter), type(uint256).max);
        vm.stopPrank();
    }

    function test_rate_fromOracle() public view {
        assertEq(adapter.exchangeRate(address(usdc)), 95e16);
    }

    function test_rate_movesWithOracle() public {
        oracle.setRate(96e16);
        assertEq(adapter.exchangeRate(address(usdc)), 96e16);
    }

    function test_active_withdrawTo_swapsAndDelivers() public {
        vm.prank(router);
        (address pT, uint256 pA, address pT0) = adapter.pullPlan(maker, address(usdc), 4_000e6);
        vm.prank(maker); IERC20(pT).transfer(pT0, pA);
        adapter.withdraw(maker, address(usdc), 4_000e6, adapter.underlyingToYield(address(usdc), 4_000e6), recipient);

        // exact delivery, buffer surplus returns to the maker
        assertEq(usdc.balanceOf(recipient), 4_000e6);
        assertLe(pt.balanceOf(maker), 10_000e6 - uint256(4_000e6) * 1e18 / 95e16);
        assertGt(usdc.balanceOf(maker), 0);
    }

    function test_active_slippageBeyondBuffer_reverts() public {
        // attacker crashes the market SPOT below the lagging TWAP oracle: the swap
        // delivers far less than the oracle-priced pull expected, beyond the buffer
        oracle.setRate(95e16); // TWAP stays high
        market.setPtPrice(50e16); // spot crashes
        // atomic in the fill: the (buffered) pull and the losing swap revert together
        vm.startPrank(maker);
        (address pT, uint256 pA, address pT0) = adapter.pullPlan(maker, address(usdc), 4_000e6);
        IERC20(pT).transfer(pT0, pA);
        vm.expectRevert(PendlePTAdapter.PendleSwapShortfall.selector);
        adapter.withdraw(maker, address(usdc), 4_000e6, pA, recipient);
        vm.stopPrank();
    }

    function test_swapCallback_onlyMarketCanCall() public {
        vm.expectRevert(PendlePTAdapter.CallbackNotMarket.selector);
        adapter.swapCallback(int256(-1e6), int256(0), "");
    }

    function test_maxWithdrawable_usesOracleRate() public {
        assertEq(adapter.maxWithdrawable(maker, address(usdc)), 10_000e6 * 95e16 / 1e18);
    }

    function test_passthrough_side_unchanged() public {
        assertEq(adapter.exchangeRate(weth), 1e18);
        assertEq(adapter.yieldToken(weth), weth);
    }
}
