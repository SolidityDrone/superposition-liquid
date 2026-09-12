// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Aave4626Vault } from "src/vaults/Aave4626Vault.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { MockAaveBorrowPool, BorrowAToken } from "./mocks/MockAaveBorrowPool.sol";

contract Aave4626VaultTest is Test {
    address internal constant USER = address(0xBEEF);

    MockToken internal usdc;
    MockAaveBorrowPool internal pool;
    BorrowAToken internal aUsdc;
    Aave4626Vault internal vault;

    function setUp() public {
        usdc = new MockToken("USDC", 6);
        pool = new MockAaveBorrowPool();
        aUsdc = new BorrowAToken();
        pool.registerAToken(address(usdc), aUsdc);
        vault = new Aave4626Vault(IERC20(address(usdc)), address(pool), "waUSDC", "waUSDC");
    }

    function test_deposit_supplies_and_withdraw_returns() public {
        usdc.mint(USER, 100e6);
        vm.startPrank(USER);
        usdc.approve(address(vault), 100e6);
        uint256 shares = vault.deposit(100e6, USER);
        vm.stopPrank();

        assertEq(shares, 100e6);
        assertEq(vault.totalAssets(), 100e6);
        assertEq(aUsdc.balanceOf(address(vault)), 100e6);
        assertEq(usdc.balanceOf(address(vault)), 0);

        vm.prank(USER);
        vault.withdraw(40e6, USER, USER);
        assertEq(usdc.balanceOf(USER), 40e6);
        assertEq(vault.totalAssets(), 60e6);
    }

    function test_maxDeposit_is_open() public view {
        assertEq(vault.maxDeposit(USER), type(uint256).max);
    }

    function test_deposit_falls_back_to_idle_when_supply_capped() public {
        pool.setFailSupply(true); // Aave reserve at its cap -> supply reverts "51"
        usdc.mint(USER, 100e6);
        vm.startPrank(USER);
        usdc.approve(address(vault), 100e6);
        uint256 shares = vault.deposit(100e6, USER);
        vm.stopPrank();

        assertEq(shares, 100e6);
        assertEq(vault.totalAssets(), 100e6); // idle counted
        assertEq(usdc.balanceOf(address(vault)), 100e6);

        vm.prank(USER);
        vault.withdraw(40e6, USER, USER);
        assertEq(usdc.balanceOf(USER), 40e6);
        assertEq(vault.totalAssets(), 60e6);
    }
}
