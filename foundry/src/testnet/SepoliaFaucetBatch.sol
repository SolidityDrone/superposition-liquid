// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IAaveFaucet {
    function isMintable(address token) external view returns (bool);
    function mint(address token, address to, uint256 amount) external returns (uint256);
}

/// @title SepoliaFaucetBatch
/// @notice One-transaction faucet for Ethereum Sepolia: mints `wholeAmount` of every
///         mintable test token from the Aave faucet directly to the recipient.
/// @dev Skips non-mintable tokens (e.g. WETH) and swallows per-token reverts
///      (e.g. GHO bucket-cap) so a single failed token never blocks the batch.
contract SepoliaFaucetBatch {
    IAaveFaucet public constant FAUCET = IAaveFaucet(0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D);

    address[] public tokens;

    constructor(address[] memory tokens_) {
        tokens = tokens_;
    }

    function tokenCount() external view returns (uint256) {
        return tokens.length;
    }

    /// @notice Mints `wholeAmount` whole tokens of each mintable token to `to`
    ///         (defaults to msg.sender). One transaction.
    /// @return minted Number of tokens successfully minted.
    function mintAll(address to, uint256 wholeAmount) external returns (uint256 minted) {
        if (to == address(0)) to = msg.sender;
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; i++) {
            address t = tokens[i];
            if (t == address(0) || !FAUCET.isMintable(t)) continue;
            uint256 amount = wholeAmount * 10 ** IERC20Metadata(t).decimals();
            try FAUCET.mint(t, to, amount) {
                minted++;
            } catch { }
        }
    }
}
