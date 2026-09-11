// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SuperpositionFixture } from "../helpers/SuperpositionFixture.sol";
import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";

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
}
