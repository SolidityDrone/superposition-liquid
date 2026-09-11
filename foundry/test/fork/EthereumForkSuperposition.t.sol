// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SuperpositionFixture } from "../helpers/SuperpositionFixture.sol";
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
}
