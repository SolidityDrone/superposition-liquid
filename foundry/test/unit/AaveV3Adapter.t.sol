// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { MockAavePool, MockAToken } from "test/unit/mocks/MockAavePool.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";

contract MockToken is ERC20 {
    constructor(string memory name) ERC20(name, name) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AaveV3AdapterTest is Test {
    uint256 internal constant RAY = 1e27;

    AaveV3Adapter internal adapter;
    MockAavePool internal pool;
    MockAToken internal aToken;
    MockToken internal usdc;
    MockToken internal weth;

    address internal maker = makeAddr("maker");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        aToken = new MockAToken();
        pool = new MockAavePool(address(aToken));
        adapter = new AaveV3Adapter(address(pool));
        usdc = new MockToken("USDC");
        weth = new MockToken("WETH");
    }

    function test_name_isAaveV3() public view {
        assertEq(adapter.name(), "AaveV3");
    }

    function test_exchangeRate_returnsRayIncomeScaledTo1e18() public {
        pool.setNormalizedIncome(address(weth), 105 * RAY / 100); // 1.05
        assertEq(adapter.exchangeRate(address(weth)), 105 * 1e18 / 100);
    }

    function test_exchangeRate_defaultsToOneWhenNoReserveInteraction() public view {
        assertEq(adapter.exchangeRate(address(weth)), 1e18);
    }

    function test_yieldToken_returnsATokenFromReserveData() public view {
        assertEq(adapter.yieldToken(address(weth)), address(aToken));
    }

    function test_underlyingToYield_convertsAtCurrentRate() public {
        pool.setNormalizedIncome(address(weth), 105 * RAY / 100);
        uint256 aAmount = adapter.underlyingToYield(address(weth), 105 ether);
        assertEq(aAmount, 100 ether);
    }

    function test_yieldToUnderlying_convertsAtCurrentRate() public {
        pool.setNormalizedIncome(address(weth), 105 * RAY / 100);
        assertEq(adapter.yieldToUnderlying(address(weth), 100 ether), 105 ether);
    }

    function test_depositFor_pullsFromMakerWalletAndSuppliesOnBehalfOfMaker() public {
        usdc.mint(maker, 10_000e6);
        vm.startPrank(maker);
        usdc.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        address router = makeAddr("router");
        vm.prank(router); // caller is the router, funds come from maker wallet
        adapter.depositFor(maker, address(usdc), 10_000e6);

        assertEq(usdc.balanceOf(address(pool)), 10_000e6);
        assertEq(aToken.balanceOf(maker), 10_000e6); // 1:1 at index 1.0
    }

    function test_withdrawTo_burnsMakerATokensAndSendsUnderlyingToRecipient() public {
        // maker supplies 100 USDC
        usdc.mint(maker, 100e6);
        vm.startPrank(maker);
        usdc.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(usdc), 100e6);
        // maker approves adapter for aToken spending (per approvals table)
        aToken.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        address router = makeAddr("router");
        vm.prank(router);
        adapter.withdrawTo(maker, address(usdc), 40e6, recipient);

        assertEq(usdc.balanceOf(recipient), 40e6);
        assertEq(aToken.balanceOf(maker), 60e6);
        assertEq(usdc.balanceOf(address(pool)), 60e6);
    }

    function test_withdrawAtAccruedRate_pullsFewerATokensThanUnderlying() public {
        usdc.mint(maker, 100e6);
        vm.startPrank(maker);
        usdc.approve(address(adapter), type(uint256).max);
        adapter.depositFor(maker, address(usdc), 100e6);
        aToken.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        // interest accrued: 100 underlying locked, index moves to 1.25 => 80 aTokens held
        pool.setNormalizedIncome(address(usdc), 125 * RAY / 100);

        address router = makeAddr("router");
        vm.prank(router);
        adapter.withdrawTo(maker, address(usdc), 100e6, recipient);

        // 100 underlying withdrawn costs 80 aTokens at index 1.25; 20 aTokens (≈25 underlying) remain
        assertEq(usdc.balanceOf(recipient), 100e6);
        assertEq(aToken.balanceOf(maker), 20e6);
    }
}
