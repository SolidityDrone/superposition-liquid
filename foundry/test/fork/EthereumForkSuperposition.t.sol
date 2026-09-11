// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SuperpositionFixture } from "../helpers/SuperpositionFixture.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { SuperpositionUniAdapter } from "src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol";
import { AdapterKind } from "src/config/MakerConfig.sol";

contract EthereumForkSuperpositionTest is SuperpositionFixture {
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
}
