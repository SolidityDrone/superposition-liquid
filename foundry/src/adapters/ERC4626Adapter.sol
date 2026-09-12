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

    /// @param vaults The ERC-4626 vaults. The underlying of each vault is read from
    ///        `vault.asset()`, so no underlyings need to be passed.
    constructor(address[] memory vaults) {
        uint256 n = vaults.length;
        require(n > 0, "no vaults");
        for (uint256 i = 0; i < n; i++) {
            IERC4626 vault = IERC4626(vaults[i]);
            vaultOf[vault.asset()] = vault;
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

    /// @dev The vault shares were pulled maker -> this adapter by the ROUTER
    ///      (plan: `underlyingToYield`, rounded up): redeeming them from this
    ///      adapter's balance delivers underlying to the recipient.
    function withdraw(
        address maker,
        address underlying,
        uint256 underlyingAmount,
        uint256 yieldAmount,
        address recipient
    ) external {
        maker;
        underlying;
        vaultOf[underlying].redeem(yieldAmount, recipient, address(this));
    }

    /// @dev Pull plan: the share count covering `underlyingAmount`, rounded up,
    ///      delivered to this adapter.
    function pullPlan(address maker, address underlying, uint256 underlyingAmount)
        external view
        returns (address token, uint256 amount, address to)
    {
        maker;
        token = address(vaultOf[underlying]);
        amount = this.underlyingToYield(underlying, underlyingAmount);
        to = address(this);
    }

    /// @notice Simulated withdrawal: the vault's own maxWithdraw (4626 standard),
    /// which accounts for vault liquidity, caps and pause states.
    function maxWithdrawable(address maker, address underlying) external view returns (uint256) {
        return vaultOf[underlying].maxWithdraw(maker);
    }

    /// @dev The underlying was pulled maker -> this adapter by the ROUTER:
    ///      deposits into the vault minting shares to the maker.
    function deposit(address maker, address underlying, uint256 underlyingAmount) external {
        IERC20(underlying).forceApprove(address(vaultOf[underlying]), underlyingAmount);
        vaultOf[underlying].deposit(underlyingAmount, maker);
    }
}
