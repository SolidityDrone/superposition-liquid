// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { IPool } from "@aave/core/interfaces/IPool.sol";

/// @title Aave4626Vault
/// @notice Minimal ERC-4626 vault that supplies its asset to an Aave v3 pool and
///         holds the resulting aTokens. Shares track the aToken balance, so yield
///         accrues to holders via `totalAssets` growth.
/// @dev Testnet scaffolding: on chains where no official depositable ERC-4626
///      wrapper exists (e.g. Aave's legacy StataTokens on Sepolia report
///      `maxDeposit == 0`), this gives the SuperpositionHook a working yield vault.
///      Uses the displayed aToken balance (Aave v3.2 index-accrued) as assets.
contract Aave4626Vault is ERC4626 {
    using SafeERC20 for IERC20;

    IPool public immutable POOL;

    constructor(
        IERC20 asset_,
        address pool,
        string memory name_,
        string memory symbol_
    )
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        POOL = IPool(pool);
    }

    /// @inheritdoc ERC4626
    /// @dev Counts idle underlying plus the Aave aToken position, so the vault stays
    ///      correct when a supply is rejected (testnet supply caps).
    function totalAssets() public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        address aToken = POOL.getReserveData(asset()).aTokenAddress;
        uint256 supplied = aToken == address(0) ? 0 : IERC20(aToken).balanceOf(address(this));
        return idle + supplied;
    }

    /// @dev Pull the assets in (mint shares), then try to supply them to Aave. If the
    ///      supply is rejected (e.g. the reserve is at its cap) assets stay idle in the
    ///      vault and still count in `totalAssets`.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        IERC20(asset()).forceApprove(address(POOL), assets);
        try POOL.supply(asset(), assets, address(this), 0) { }
        catch {
            IERC20(asset()).forceApprove(address(POOL), 0);
        }
    }

    /// @dev Burn shares, then pay from idle first and withdraw the rest from Aave.
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);

        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle >= assets) {
            IERC20(asset()).safeTransfer(receiver, assets);
            return;
        }
        if (idle > 0) {
            IERC20(asset()).safeTransfer(receiver, idle);
        }
        POOL.withdraw(asset(), assets - idle, receiver);
    }
}
