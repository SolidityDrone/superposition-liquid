// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { SuperpositionUniAdapter } from "src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol";
import { MakerConfig } from "src/config/MakerConfig.sol";
import { SuperPositionVMRouter } from "src/SuperPositionVMRouter.sol";
import { Aave4626Vault } from "src/vaults/Aave4626Vault.sol";
import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { HookMiner } from "superposition-hook/libraries/HookMiner.sol";

// Ethereum Sepolia (chainId 11155111)
address constant SE_AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
address constant SE_WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // canonical WETH9
address constant SE_AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
address constant SE_PM = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543; // v4 PoolManager
address constant SE_USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // Aave mock USDC
address constant SE_USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; // Aave mock USDT
address constant SE_CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

/// @dev Derived contracts with STATIC constructor args (strings hardcoded) so
///      `forge script` does not hit its dynamic-constructor-arg decode bug
///      ("type check failed for offset (usize)").
contract SepoliaRouter is SuperPositionVMRouter {
    constructor(address aqua, address weth, address owner, address mc)
        SuperPositionVMRouter(aqua, weth, owner, "SuperPositionVMRouter", "1", mc)
    { }
}

contract SepoliaUSDCVault is Aave4626Vault {
    constructor(address pool) Aave4626Vault(IERC20(SE_USDC), pool, "SuperPosition USDC", "spUSDC") { }
}

contract SepoliaUSDTVault is Aave4626Vault {
    constructor(address pool) Aave4626Vault(IERC20(SE_USDT), pool, "SuperPosition USDT", "spUSDT") { }
}

/// @title DeploySepolia
/// @notice Deploys the SuperPosition stack on Ethereum Sepolia: MakerConfig, router,
///         AaveV3Adapter, an Aave-backed ERC-4626 vault per stable, and the
///         Superposition v4 hook + adapter (USDC/USDT one-sided buckets).
contract DeploySepolia is Script {
    function run() external {
        address owner = vm.envOr("OWNER", msg.sender);
        string memory path = "deployments/superposition-sepolia.json";

        address existing = _existingRouter(path);
        if (existing != address(0)) {
            console2.log("== sepolia stack already live ==");
            console2.log("router:", existing);
            return;
        }

        console2.log("owner:", owner);
        vm.startBroadcast();

        MakerConfig mc = new MakerConfig();
        SepoliaRouter router = new SepoliaRouter(SE_AQUA, SE_WETH, owner, address(mc));
        AaveV3Adapter aave = new AaveV3Adapter(SE_AAVE_POOL, address(mc));
        SepoliaUSDCVault vault0 = new SepoliaUSDCVault(SE_AAVE_POOL);
        SepoliaUSDTVault vault1 = new SepoliaUSDTVault(SE_AAVE_POOL);
        address[] memory vaults = new address[](2);
        vaults[0] = address(vault0);
        vaults[1] = address(vault1);
        ERC4626Adapter erc = new ERC4626Adapter(vaults);

        vm.stopBroadcast();

        address hook = _deployHook(address(vault0), address(vault1), owner);

        vm.startBroadcast();
        SuperpositionUniAdapter sup = new SuperpositionUniAdapter(
            hook, address(router), SE_USDC, int24(1), int24(101), SE_USDT, int24(-101), int24(-1)
        );
        vm.stopBroadcast();

        _persist(
            path,
            address(mc),
            address(router),
            address(aave),
            address(erc),
            address(vault0),
            address(vault1),
            hook,
            address(sup)
        );

        console2.log("MakerConfig:", address(mc));
        console2.log("Router:", address(router));
        console2.log("AaveV3Adapter:", address(aave));
        console2.log("ERC4626Adapter:", address(erc));
        console2.log("Vault USDC:", address(vault0));
        console2.log("Vault USDT:", address(vault1));
        console2.log("SuperpositionHook:", hook);
        console2.log("SuperpositionUniAdapter:", address(sup));
    }

    function _deployHook(address vault0, address vault1, address owner) internal returns (address hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args = abi.encode(IPoolManager(SE_PM), vault0, vault1, uint24(100), int24(1), owner);
        (address predicted, bytes32 salt) =
            HookMiner.find(SE_CREATE2, flags, type(SuperpositionHook).creationCode, args);
        hook = predicted;
        bytes memory initCode = abi.encodePacked(type(SuperpositionHook).creationCode, args);
        vm.startBroadcast();
        if (hook.code.length == 0) {
            (bool ok,) = SE_CREATE2.call(abi.encodePacked(salt, initCode));
            require(ok, "create2 hook deploy failed");
            SuperpositionHook(hook).initializePool(79228162514264337593543950336); // price 1.0
        }
        vm.stopBroadcast();
    }

    function _existingRouter(string memory path) internal view returns (address) {
        try vm.readFile(path) returns (string memory art) {
            address r = vm.parseAddress(vm.parseJsonString(art, ".router"));
            if (r.code.length > 0) return r;
        } catch { }
        return address(0);
    }

    function _persist(
        string memory path,
        address mc,
        address router,
        address aave,
        address erc,
        address vault0,
        address vault1,
        address hook,
        address sup
    ) internal {
        string memory artifact = string.concat(
            '{"makerConfig":"', vm.toString(mc), '","router":"', vm.toString(router),
            '","AaveV3":"', vm.toString(aave), '","ERC4626":"', vm.toString(erc),
            '","vaultUSDC":"', vm.toString(vault0),
            '","vaultUSDT":"', vm.toString(vault1), '","SuperpositionHook":"', vm.toString(hook),
            '","SuperpositionUniHook":"', vm.toString(sup), '"}'
        );
        vm.writeFile(path, artifact);
    }
}
