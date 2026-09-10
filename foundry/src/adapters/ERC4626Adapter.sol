// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

/// @title ERC4626Adapter
/// @notice Generic ILendingAdapter for any ERC-4626 vault: one implementation covers
///         Morpho (MetaMorpho), Euler v2, and any other 4626-compliant yield vault.
/// @dev The vault address per underlying is fixed at deployment. Rate source is the
///      vault itself (convertToAssets) — no external oracle needed.
contract ERC4626Adapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;

    /// @dev underlying => yield vault
    mapping(address underlying => IERC4626 vault) public vaultOf;

    constructor(address[] memory underlyings, address[] memory vaults) {
        uint256 n = underlyings.length;
        require(n == vaults.length && n > 0, "pairs length mismatch");
        for (uint256 i = 0; i < n; i++) {
            vaultOf[underlyings[i]] = IERC4626(vaults[i]);
        }
    }

    function name() external pure returns (string memory) {
        return "ERC4626";
    }

    function yieldToken(address underlying) external view returns (address) {
        return address(vaultOf[underlying]);
    }

    function underlyingToYield(address underlying, uint256 amount) external view returns (uint256) {
        IERC4626 vault = vaultOf[underlying];
        uint256 shares = vault.convertToShares(amount);
        if (vault.convertToAssets(shares) < amount) shares += 1; // round up: cover the withdrawal
        return shares;
    }

    function yieldToUnderlying(address underlying, uint256 amount) external view returns (uint256) {
        return vaultOf[underlying].convertToAssets(amount);
    }

    /// @notice Underlying per 1 displayed vault token, 1e18 precision — straight
    ///      from the vault, decimals-agnostic: works for any share/asset decimal
    ///      split (18/18 Morpho WETH, 6/6 Steakhouse USDC, ...).
    function exchangeRate(address underlying) public view returns (uint256) {
        IERC4626 vault = vaultOf[underlying];
        uint256 oneShare = 10 ** vault.decimals();
        uint256 assets = vault.convertToAssets(oneShare);
        return assets * WAD / oneShare;
    }

    /// @notice Withdraws underlying on behalf of maker: redeem from the vault straight
    ///         to recipient (the vault burns the maker's shares — maker approved this
    ///         adapter for the vault shares).
    function withdrawTo(address maker, address underlying, uint256 underlyingAmount, address recipient) external {
        vaultOf[underlying].withdraw(underlyingAmount, recipient, maker);
    }

    /// @notice Simulated withdrawal: the vault's own maxWithdraw (4626 standard),
    /// which accounts for vault liquidity, caps and pause states.
    function maxWithdrawable(address maker, address underlying) external view returns (uint256) {
        return vaultOf[underlying].maxWithdraw(maker);
    }

    /// @notice Deposits underlying on behalf of maker: pulls tokens from the maker
    ///         wallet (tokenIn arrives there after the swap), deposits into the vault
    ///         minting shares to the maker.
    function depositFor(address maker, address underlying, uint256 underlyingAmount) external {
        IERC20(underlying).safeTransferFrom(maker, address(this), underlyingAmount);
        IERC20(underlying).forceApprove(address(vaultOf[underlying]), underlyingAmount);
        vaultOf[underlying].deposit(underlyingAmount, maker);
    }
}
