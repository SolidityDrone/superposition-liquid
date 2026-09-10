// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockAavePool, MockAToken, MockDebtToken } from "test/unit/mocks/MockAavePool.sol";
import { MockToken } from "test/unit/mocks/MockToken.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { MockMetaMorphoVault } from "test/unit/mocks/MockERC4626Vault.sol";

/// @notice maxWithdrawable must SIMULATE the actual withdrawal: capped by both the
/// maker's balance AND the protocol's available liquidity (not just balanceOf).
contract MaxWithdrawableTest is Test {
    MockAavePool internal pool;
    MockAToken internal aToken;
    MockDebtToken internal debtToken;
    MockToken internal weth;
    AaveV3Adapter internal adapter;
    address internal maker = makeAddr("maker");

    function setUp() public {
        pool = new MockAavePool();
        weth = new MockToken("WETH", 18);
        aToken = new MockAToken();
        debtToken = new MockDebtToken();
        pool.registerAToken(address(weth), aToken);
        pool.registerDebtToken(address(weth), debtToken);
        adapter = new AaveV3Adapter(address(pool));
    }

    function test_zeroWhenNoPosition() public view {
        assertEq(adapter.maxWithdrawable(maker, address(weth)), 0);
    }

    function test_cappedByMakerBalance() public {
        weth.mint(maker, 100e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        IERC20(address(weth)).transfer(address(adapter), 100e18);
        adapter.deposit(maker, address(weth), 100e18);
        vm.stopPrank();
        assertEq(adapter.maxWithdrawable(maker, address(weth)), 100e18);
    }

    /// pool lent out 90 of 100 supplied -> only 10 cash is withdrawable, even though
    /// the maker holds 100 aTokens
    function test_cappedByPoolLiquidity() public {
        weth.mint(maker, 100e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        IERC20(address(weth)).transfer(address(adapter), 100e18);
        adapter.deposit(maker, address(weth), 100e18);
        vm.stopPrank();

        pool.simulateDebt(address(weth), 90e18); // utilization 90%

        assertEq(adapter.maxWithdrawable(maker, address(weth)), 10e18);
    }

    function test_poolCashFullyUtilized_returnsZero() public {
        weth.mint(maker, 100e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        IERC20(address(weth)).transfer(address(adapter), 100e18);
        adapter.deposit(maker, address(weth), 100e18);
        vm.stopPrank();
        pool.simulateDebt(address(weth), 100e18);
        assertEq(adapter.maxWithdrawable(maker, address(weth)), 0);
    }
}

contract MaxWithdrawableErc4626Test is Test {
    MockToken internal weth;
    MockMetaMorphoVault internal vault;
    ERC4626Adapter internal adapter;
    address internal maker = makeAddr("maker");

    function setUp() public {
        weth = new MockToken("WETH", 18);
        vault = new MockMetaMorphoVault(IERC20(address(weth)));
        address[] memory u = new address[](1);
        address[] memory v = new address[](1);
        u[0] = address(weth);
        v[0] = address(vault);
        adapter = new ERC4626Adapter(u, v);
    }

    /// the vault's own maxWithdraw is the simulated withdrawal limit
    function test_usesVaultMaxWithdraw() public {
        weth.mint(maker, 100e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        IERC20(address(weth)).transfer(address(adapter), 100e18);
        adapter.deposit(maker, address(weth), 100e18);
        vm.stopPrank();

        assertEq(adapter.maxWithdrawable(maker, address(weth)), vault.maxWithdraw(maker));
        assertEq(adapter.maxWithdrawable(maker, address(weth)), 100e18);
        assertEq(adapter.maxWithdrawable(makeAddr("someone"), address(weth)), 0);
    }
}
