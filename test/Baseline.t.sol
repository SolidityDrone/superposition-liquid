// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { AquaSwapVMRouter } from "@1inch/swap-vm/routers/AquaSwapVMRouter.sol";

contract BaselineTest is Test {
    function testSwapVMDeploys() public {
        AquaSwapVMRouter router = new AquaSwapVMRouter(address(1), address(2), address(3), "1inch SwapVM v1.0", "1.0.2");
        assertTrue(address(router) != address(0));
    }
}
