// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockStargatePool, MockStargateStaking, MockToken } from "test/unit/mocks/MockStargate.sol";
import { StargateAdapter } from "src/adapters/stargate/StargateAdapter.sol";

/// @notice Bridge-liquidity maker: capital in Stargate V2 pool LP, staked for rewards.
/// depositFor: pull USDC -> pool.deposit -> staking (LP staked).
/// withdrawTo: staking.withdraw (INSTANT, verified in source) -> pool.redeem -> deliver.
contract StargateAdapterTest is Test {
    MockToken internal usdc;
    MockStargatePool internal pool;
    MockStargateStaking internal staking;
    StargateAdapter internal adapter;

    address internal maker = makeAddr("maker");
    address internal recipient = makeAddr("recipient");
    address internal router = makeAddr("router");
    address internal weth = makeAddr("weth"); // passthrough side

    function setUp() public {
        usdc = new MockToken("USDC");
        pool = new MockStargatePool(IERC20(address(usdc)));
        staking = new MockStargateStaking(IERC20(address(pool)));
        pool.setStaking(address(staking));
        adapter = new StargateAdapter(address(pool), address(staking), weth);
        pool.setCreditLD(50_000e6);

        usdc.mint(address(pool), 100_000e6); // pool cash for redemptions
    }

    function _seedMaker(uint256 usdcAmount) internal {
        usdc.mint(maker, usdcAmount);
        vm.startPrank(maker);
        usdc.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(usdc), usdcAmount);
        vm.stopPrank();
    }

    function test_name_isStargate() public view {
        assertEq(adapter.name(), "Stargate");
    }

    function test_yieldToken_isThePoolLP() public view {
        assertEq(adapter.yieldToken(address(usdc)), address(pool));
    }

    function test_exchangeRate_isOne() public view {
        assertEq(adapter.exchangeRate(address(usdc)), 1e18);
    }

    /// the token the maker receives gets deposited AND staked — like the Aave flow
    function test_depositFor_depositsAndStakes() public {
        _seedMaker(10_000e6);

        assertEq(pool.balanceOf(maker), 0); // LP went to the staking, not the maker
        assertEq(staking.stakedBalanceOf(address(adapter)), 10_000e6);
        assertEq(pool.balanceOf(address(staking)), 10_000e6);
        assertEq(usdc.balanceOf(maker), 0); // capital 100% deployed
    }

    function test_withdrawTo_unstakesRedeemsAndDelivers() public {
        _seedMaker(10_000e6);
        vm.prank(router);
        adapter.withdrawTo(maker, address(usdc), 4_000e6, recipient);

        assertEq(usdc.balanceOf(recipient), 4_000e6);
        assertEq(staking.stakedBalanceOf(address(adapter)), 6_000e6); // unstaked instantly
        assertEq(pool.balanceOf(maker), 0);
    }

    /// the JIT constraint: the pool's local credit caps instant redemptions
    function test_withdrawTo_revertsBeyondPoolCredit() public {
        _seedMaker(60_000e6); // staked 60k, but credit is 50k
        vm.prank(router);
        vm.expectRevert(); // the pool's own credit revert (insufficient credit)
        adapter.withdrawTo(maker, address(usdc), 55_000e6, recipient);
    }

    /// the guard oracle: redeemable() = min(pool credit, staked position)
    function test_maxWithdrawable_isMinCreditAndStaked() public {
        _seedMaker(30_000e6); // credit 50k > staked 30k -> capped by position
        assertEq(adapter.maxWithdrawable(maker, address(usdc)), 30_000e6);
    }

    function test_maxWithdrawable_cappedByPoolCredit() public {
        _seedMaker(60_000e6); // staked 60k > credit 50k -> capped by credit
        assertEq(adapter.maxWithdrawable(maker, address(usdc)), 50_000e6);
    }

    function test_passthrough_side_noOps() public {
        MockToken wethToken = new MockToken("WETH");
        wethToken.mint(maker, 5e18);
        vm.startPrank(maker);
        IERC20(address(wethToken)).approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(wethToken), 5e18);
        vm.stopPrank();

        assertEq(wethToken.balanceOf(maker), 5e18); // untouched
        vm.prank(router);
        adapter.withdrawTo(maker, address(wethToken), 1e18, recipient); // no-op
        assertEq(wethToken.balanceOf(maker), 5e18);
    }
}
