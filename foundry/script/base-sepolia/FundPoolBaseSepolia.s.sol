// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHookLpHelper {
    function provide(
        address maker,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 lower0,
        int24 upper0,
        int24 lower1,
        int24 upper1
    ) external;
}

/// @notice Funds the SuperpositionHook v4 pool on Base Sepolia so the console shows
///         real buckets + liquidity. Pool currency0 = USDT, currency1 = USDC.
/// @dev Run with a funded keystore (kondor holds USDT+USDC from the faucet).
contract FundPoolBaseSepolia is Script {
    address constant MAKER = 0xDD7D64BFd13EF3b733374Fc8DE9B9C651487a15D; // kondor
    address constant HELPER = 0x24F0A572A6A7Ae73322aB5B19Ee83d50343A5D23; // HookLpHelper
    address constant USDT = 0x0a215D8ba66387DCA84B284D18c3B4ec3de6E54a; // currency0
    address constant USDC = 0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f; // currency1

    function run() external {
        vm.startBroadcast();
        IERC20(USDT).approve(HELPER, type(uint256).max);
        IERC20(USDC).approve(HELPER, type(uint256).max);
        IHookLpHelper(HELPER).provide(MAKER, USDT, USDC, 90e6, 90e6, int24(1), int24(101), int24(-101), int24(-1));
        console2.log("provided 90 USDT [1,101] + 90 USDC [-101,-1]");
        vm.stopBroadcast();
    }
}
