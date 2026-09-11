// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { HookMiner } from "superposition-hook/libraries/HookMiner.sol";

/// @dev Deploys the REAL SuperpositionHook on an Ethereum mainnet fork, backed by
///      Aave's ERC-4626 wrappers (waEthUSDC / waEthUSDT, resolved via the StataToken factory).
abstract contract SuperpositionFixture is Test {
    address internal constant PM = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    // Aave ERC-4626 wrappers on Ethereum (asset() verified == USDC / USDT).
    address internal constant WA_USDC = 0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E;
    address internal constant WA_USDT = 0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8;
    // Aave StataTokenFactory on Ethereum (permissionless wrapper factory/registry).
    address internal constant STATA_FACTORY = 0xCb0b5cA20b6C5C02A9A3B2cE433650768eD2974F;

    uint160 internal constant SQRT_PRICE_1_0 = 79228162514264337593543950336; // 2**96

    function _fork() internal {
        vm.createSelectFork(vm.envOr("RPC_URL_ETH", string("https://ethereum-rpc.publicnode.com")));
    }

    function _deployHook(uint24 fee, int24 spacing) internal returns (SuperpositionHook hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args = abi.encode(
            IPoolManager(PM), WA_USDC, WA_USDT, fee, spacing, address(this)
        );
        (address predicted, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SuperpositionHook).creationCode, args);
        hook = new SuperpositionHook{salt: salt}(
            IPoolManager(PM), IERC4626(WA_USDC), IERC4626(WA_USDT), fee, spacing, address(this)
        );
        require(address(hook) == predicted, "hook address mismatch");
        hook.initializePool(SQRT_PRICE_1_0);
    }
}
