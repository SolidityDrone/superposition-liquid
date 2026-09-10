// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockToken } from "test/unit/mocks/MockToken.sol";
import { MockMetaMorphoVault, MockEulerVault, MockERC4626Vault } from "test/unit/mocks/MockERC4626Vault.sol";
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";

/// @notice Same adapter suite executed against a MetaMorpho-style and an Euler-style
/// ERC-4626 vault: the generic adapter must be vault-agnostic.
abstract contract ERC4626AdapterTest is Test {
    uint256 internal constant WAD = 1e18;

    ERC4626Adapter internal adapter;
    MockERC4626Vault internal vault;
    MockToken internal weth;
    MockToken internal usdc;
    MockToken internal usdcVaultToken;

    address internal maker = makeAddr("maker");
    address internal recipient = makeAddr("recipient");
    address internal router = makeAddr("router");

    /// @dev hook to build the parameterized vault
    function _createVault(MockToken assetToken) internal virtual returns (MockERC4626Vault);

    function setUp() public {
        weth = new MockToken("WETH", 18);
        usdc = new MockToken("USDC", 6);
        vault = _createVault(weth);
        (address[] memory underlyings, address[] memory vaults) = _pairs();
        adapter = new ERC4626Adapter(underlyings, vaults);
    }

    function _pairs() internal returns (address[] memory underlyings, address[] memory vaults) {
        usdcVaultToken = new MockToken("USDC", 6);
        underlyings = new address[](2);
        vaults = new address[](2);
        underlyings[0] = address(weth);
        vaults[0] = address(vault);
        underlyings[1] = address(usdc);
        vaults[1] = address(_createVault(usdcVaultToken));
    }

    function _seed(address underlying, uint256 amount) internal returns (MockERC4626Vault v) {
        v = MockERC4626Vault(adapter.yieldToken(underlying));
        MockToken(underlying).mint(maker, amount);
        vm.startPrank(maker);
        IERC20(underlying).approve(address(adapter), type(uint256).max);
        IERC20(underlying).transfer(address(adapter), amount);
        adapter.deposit(maker, underlying, amount);
        vm.stopPrank();
    }

    function test_name_isErc4626() public {
        assertEq(adapter.name(), "ERC4626");
    }

    function test_yieldToken_returnsTheVault() public {
        assertEq(adapter.yieldToken(address(weth)), address(vault));
    }

    function test_exchangeRate_isOneAtGenesis() public {
        assertEq(adapter.exchangeRate(address(weth)), WAD);
    }

    function test_exchangeRate_reflectsAccruedYield() public {
        _seed(address(weth), 100e18);
        _accrue(10e18); // +10% yield
        assertEq(adapter.exchangeRate(address(weth)), 11 * WAD / 10);
    }

    function _accrue(uint256 yieldAssets) internal {
        weth.mint(address(this), yieldAssets);
        weth.approve(address(vault), type(uint256).max);
        vault.accrue(yieldAssets);
    }

    function test_depositFor_pullsUnderlyingAndMintsSharesToMaker() public {
        weth.mint(maker, 100e18);
        vm.startPrank(maker);
        weth.approve(address(adapter), type(uint256).max);
        IERC20(address(weth)).transfer(address(adapter), 100e18);
        adapter.deposit(maker, address(weth), 100e18);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(vault)), 100e18);
        assertEq(vault.balanceOf(maker), 100e18); // 1:1 at genesis
        assertEq(weth.balanceOf(maker), 0);
    }

    function test_withdrawTo_burnsMakerSharesAndDeliversUnderlying() public {
        _seed(address(weth), 100e18);
        vm.startPrank(maker);
        vault.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        vm.prank(router);
        (address pT, uint256 pA, address pT0) = adapter.pullPlan(maker, address(weth), 40e18);
        vm.prank(maker); IERC20(pT).transfer(pT0, pA);
        adapter.withdraw(maker, address(weth), 40e18, adapter.underlyingToYield(address(weth), 40e18), recipient);

        assertEq(weth.balanceOf(recipient), 40e18);
        assertEq(vault.balanceOf(maker), 60e18);
    }

    function test_withdrawAtAccruedYield_burnsFewerSharesThanUnderlying() public {
        _seed(address(weth), 100e18);
        _accrue(25e18); // +25% -> 1 WETH worth 0.8 shares
        vm.startPrank(maker);
        vault.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        vm.prank(router);
        (address pT, uint256 pA, address pT0) = adapter.pullPlan(maker, address(weth), 100e18);
        vm.prank(maker); IERC20(pT).transfer(pT0, pA);
        adapter.withdraw(maker, address(weth), 100e18, adapter.underlyingToYield(address(weth), 100e18), recipient);

        assertEq(weth.balanceOf(recipient), 100e18);
        assertEq(vault.balanceOf(maker), 20e18); // 100 assets = 80 shares burned... +1 rounding guard
    }

    function test_roundTrip_preservesUnderlyingValue() public {
        _seed(address(weth), 100e18);
        _accrue(7e18);
        vm.startPrank(maker);
        vault.approve(address(adapter), type(uint256).max);
        vm.stopPrank();

        vm.prank(router);
        (address pT, uint256 pA, address pT0) = adapter.pullPlan(maker, address(weth), 50e18);
        vm.prank(maker); IERC20(pT).transfer(pT0, pA);
        adapter.withdraw(maker, address(weth), 50e18, adapter.underlyingToYield(address(weth), 50e18), recipient);
        assertEq(weth.balanceOf(recipient), 50e18);
        assertGe(adapter.yieldToUnderlying(address(weth), vault.balanceOf(maker)), 50e18);
    }
}

contract ERC4626AdapterMetaMorphoTest is ERC4626AdapterTest {
    function _createVault(MockToken assetToken) internal override returns (MockERC4626Vault) {
        return new MockMetaMorphoVault(IERC20(address(assetToken)));
    }
}

contract ERC4626AdapterEulerTest is ERC4626AdapterTest {
    function _createVault(MockToken assetToken) internal override returns (MockERC4626Vault) {
        return new MockEulerVault(IERC20(address(assetToken)));
    }
}
