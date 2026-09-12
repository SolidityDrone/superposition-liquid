// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { MakerConfig, BorrowConfig } from "src/config/MakerConfig.sol";
import { MockToken } from "./mocks/MockToken.sol";
import {
    MockAaveBorrowPool,
    BorrowAToken,
    BorrowDebtToken,
    MockAaveOracle,
    MockAaveAddressesProvider
} from "./mocks/MockAaveBorrowPool.sol";

contract AaveV3BorrowTest is Test {
    address internal constant MAKER = address(0xA11CE);
    address internal constant RECIPIENT = address(0xCAFE);

    MockToken internal usdc;
    MockToken internal link;
    BorrowAToken internal aUsdc;
    BorrowAToken internal aLink;
    BorrowDebtToken internal debtLink;
    MockAaveBorrowPool internal pool;
    MockAaveOracle internal oracle;
    MockAaveAddressesProvider internal provider;
    MakerConfig internal makerConfig;
    AaveV3Adapter internal adapter;

    function setUp() public {
        usdc = new MockToken("USDC", 6);
        link = new MockToken("LINK", 18);
        aUsdc = new BorrowAToken();
        aLink = new BorrowAToken();
        debtLink = new BorrowDebtToken();
        pool = new MockAaveBorrowPool();
        oracle = new MockAaveOracle();
        provider = new MockAaveAddressesProvider();

        pool.registerAToken(address(usdc), aUsdc);
        pool.registerAToken(address(link), aLink);
        pool.registerDebtToken(address(link), debtLink);
        pool.setLtv(address(usdc), 8000); // 80%
        // prices in base currency (8 decimals): 1 USDC = $1, 1 LINK = $10
        oracle.setAssetPrice(address(usdc), 1e8);
        oracle.setAssetPrice(address(link), 10e8);
        provider.setPriceOracle(address(oracle));
        pool.setProvider(address(provider));

        makerConfig = new MakerConfig();
        adapter = new AaveV3Adapter(address(pool), address(makerConfig));

        // maker supplies 10_000 USDC as collateral (test contract holds + approves)
        usdc.mint(address(this), 10_000e6);
        usdc.approve(address(pool), type(uint256).max);
        pool.supply(address(usdc), 10_000e6, MAKER, 0);
        // 8000 USD of borrow power (account-level, as Aave would report)
        pool.setAvailableBorrowsBase(MAKER, 8000e8);
        // pool needs LINK liquidity to lend (supply it so poolBalance is consistent)
        link.mint(address(this), 1000e18);
        link.approve(address(pool), type(uint256).max);
        pool.supply(address(link), 1000e18, address(this), 0);
    }

    function _enableBorrow(address collateral, uint256 maxDebt) internal {
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(link);
        BorrowConfig[] memory cfgs = new BorrowConfig[](1);
        cfgs[0] = BorrowConfig({ enabled: true, collateral: collateral, maxDebt: maxDebt });
        vm.prank(MAKER);
        makerConfig.setBorrowConfigs(underlyings, cfgs);
    }

    function test_config_stored_per_token() public {
        _enableBorrow(address(usdc), 500e18);
        BorrowConfig memory bc = makerConfig.borrowConfigOf(MAKER, address(link));
        assertTrue(bc.enabled);
        assertEq(bc.collateral, address(usdc));
        assertEq(bc.maxDebt, 500e18);
        // another token is unaffected
        assertFalse(makerConfig.borrowConfigOf(MAKER, address(usdc)).enabled);
    }

    function test_headroom_is_min_of_available_collateral_capacitor() public {
        // available = 8000 base -> 800e18 LINK; collateral cap = 8000 base -> 800e18
        _enableBorrow(address(usdc), 0);
        assertEq(adapter.maxWithdrawable(MAKER, address(link)), 800e18);

        // risk capacitor binds
        _enableBorrow(address(usdc), 500e18);
        assertEq(adapter.maxWithdrawable(MAKER, address(link)), 500e18);
    }

    function test_headroom_zero_with_wrong_collateral() public {
        // LINK as its own collateral has no balance -> no capacity
        _enableBorrow(address(link), 0);
        assertEq(adapter.maxWithdrawable(MAKER, address(link)), 0);
    }

    function test_withdraw_borrows_shortfall() public {
        _enableBorrow(address(usdc), 500e18);

        // nothing to pull: adapter sources the tokens itself
        (address token, uint256 amount, address to) = adapter.pullPlan(MAKER, address(link), 100e18);
        assertEq(token, address(0));
        assertEq(amount, 0);
        assertEq(to, address(0));

        uint256 before = link.balanceOf(RECIPIENT);
        adapter.withdraw(MAKER, address(link), 100e18, 0, RECIPIENT);
        assertEq(link.balanceOf(RECIPIENT) - before, 100e18);
        assertEq(debtLink.balanceOf(MAKER), 100e18);
    }

    function test_withdraw_uses_position_then_borrows() public {
        _enableBorrow(address(usdc), 500e18);
        // maker holds 30 aLINK; the router's pullPlan must cap at the real balance
        aLink.mint(MAKER, 30e18);

        (address token, uint256 amount,) = adapter.pullPlan(MAKER, address(link), 100e18);
        assertEq(token, address(aLink));
        assertEq(amount, 30e18); // capped at the maker's real balance

        // the router executes the plan: maker -> adapter, then withdraw is called
        vm.prank(MAKER);
        aLink.transfer(address(adapter), 30e18);
        uint256 before = link.balanceOf(RECIPIENT);
        adapter.withdraw(MAKER, address(link), 100e18, 30e18, RECIPIENT);
        assertEq(link.balanceOf(RECIPIENT) - before, 100e18);
        assertEq(debtLink.balanceOf(MAKER), 70e18); // 100 - 30 from position
    }

    function test_deposit_repays_first_then_supplies() public {
        _enableBorrow(address(usdc), 500e18);
        adapter.withdraw(MAKER, address(link), 100e18, 0, RECIPIENT); // debt 100

        // partial repay
        link.mint(address(adapter), 40e18);
        adapter.deposit(MAKER, address(link), 40e18);
        assertEq(debtLink.balanceOf(MAKER), 60e18);
        assertEq(aLink.balanceOf(MAKER), 0); // nothing supplied yet

        // overpay: debt cleared, remainder supplied
        link.mint(address(adapter), 100e18);
        adapter.deposit(MAKER, address(link), 100e18);
        assertEq(debtLink.balanceOf(MAKER), 0);
        assertEq(aLink.balanceOf(MAKER), 40e18);
    }

    function test_borrow_disabled_behaves_as_plain_supply() public {
        AaveV3Adapter plain = new AaveV3Adapter(address(pool), address(0));
        assertEq(plain.maxWithdrawable(MAKER, address(link)), 0);

        link.mint(address(plain), 50e18);
        plain.deposit(MAKER, address(link), 50e18);
        assertEq(aLink.balanceOf(MAKER), 50e18);
        assertEq(debtLink.balanceOf(MAKER), 0);
    }
}
