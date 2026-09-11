// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { HookMiner } from "superposition-hook/libraries/HookMiner.sol";

/// @dev Deploys the REAL SuperpositionHook on an Ethereum mainnet fork.
abstract contract SuperpositionFixture is Test {
    address internal constant PM = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant AAVE = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant AUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address internal constant AUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
    uint160 internal constant SQRT_PRICE_1_0 = 79228162514264337593543950336; // 2**96

    function _fork() internal {
        vm.createSelectFork(vm.envOr("RPC_URL_ETH", string("https://ethereum-rpc.publicnode.com")));
    }

    function _deployHook(uint24 fee, int24 spacing) internal returns (SuperpositionHook hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args =
            abi.encode(IPoolManager(PM), AAVE, USDC, USDT, AUSDC, AUSDT, fee, spacing, address(this));
        (address predicted, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SuperpositionHook).creationCode, args);
        hook = new SuperpositionHook{salt: salt}(
            IPoolManager(PM), AAVE, USDC, USDT, AUSDC, AUSDT, fee, spacing, address(this)
        );
        require(address(hook) == predicted, "hook address mismatch");
        hook.initializePool(SQRT_PRICE_1_0);
    }
}
