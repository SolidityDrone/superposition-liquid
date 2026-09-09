// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice Minimal ERC-4626 vault mock (shared base for MetaMorpho-style and Euler-style
/// variants in the adapter tests). Assets/shares 1:1 at genesis; yield accrues by adding
/// assets without minting shares, so share price grows exactly like real vaults.
contract MockERC4626Vault is ERC20, IERC4626 {
    IERC20 public immutable ASSET;
    uint256 internal _totalAssets;

    constructor(IERC20 asset_, string memory name, string memory symbol) ERC20(name, symbol) {
        ASSET = asset_;
    }

    /// @notice Simulates yield accrual: assets grow, share count unchanged -> price up.
    function accrue(uint256 yieldAssets) external {
        IERC20(ASSET).transferFrom(msg.sender, address(this), yieldAssets);
        _totalAssets += yieldAssets;
    }

    function asset() external view returns (address) {
        return address(ASSET);
    }

    function totalAssets() public view returns (uint256) {
        return _totalAssets;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        return assets * supply / _totalAssets;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        return shares * _totalAssets / supply;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        uint256 shares = convertToShares(assets);
        _totalAssets += assets;
        _mint(receiver, shares);
        IERC20(ASSET).transferFrom(msg.sender, address(this), assets);
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256) {
        uint256 shares = _ceilShares(assets);
        require(balanceOf(owner) >= shares, "insufficient shares");
        require(allowance(owner, msg.sender) >= shares, "insufficient allowance");
        _spendAllowance(owner, msg.sender, shares);
        _totalAssets -= assets;
        _burn(owner, shares);
        IERC20(ASSET).transfer(receiver, assets);
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256) {
        uint256 assets = _ceilAssets(shares);
        _totalAssets += assets;
        _mint(receiver, shares);
        IERC20(ASSET).transferFrom(msg.sender, address(this), assets);
        return assets;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        require(allowance(owner, msg.sender) >= shares, "insufficient allowance");
        _spendAllowance(owner, msg.sender, shares);
        uint256 assets = convertToAssets(shares);
        _totalAssets -= assets;
        _burn(owner, shares);
        IERC20(ASSET).transfer(receiver, assets);
        return assets;
    }

    /// @dev shares needed to cover exactly `assets`: round up
    function _ceilShares(uint256 assets) internal view returns (uint256) {
        uint256 shares = convertToShares(assets);
        if (convertToAssets(shares) < assets) shares += 1;
        return shares;
    }

    /// @dev assets needed to mint exactly `shares`: round up
    function _ceilAssets(uint256 shares) internal view returns (uint256) {
        uint256 assets = convertToAssets(shares);
        if (convertToShares(assets) < shares) assets += 1;
        return assets;
    }

    // --- ERC20 metadata passthroughs required by the interface ---
    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return _ceilAssets(shares);
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return _ceilShares(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }
}

/// @notice MetaMorpho-style naming wrapper
contract MockMetaMorphoVault is MockERC4626Vault {
    constructor(IERC20 asset_) MockERC4626Vault(asset_, "MetaMorpho WETH Vault", "MMWETH") { }
}

/// @notice Euler-style naming wrapper
contract MockEulerVault is MockERC4626Vault {
    constructor(IERC20 asset_) MockERC4626Vault(asset_, "Euler WETH Vault", "eWETH") { }
}
