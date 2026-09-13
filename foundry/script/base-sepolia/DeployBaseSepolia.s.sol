// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { SuperpositionUniAdapter } from "src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol";
import { MakerConfig } from "src/config/MakerConfig.sol";
import { SuperPositionVMRouter } from "src/SuperPositionVMRouter.sol";
import { Aave4626Vault } from "src/vaults/Aave4626Vault.sol";
import { OrderBuilder } from "src/testnet/OrderBuilder.sol";
import { HookLpHelper } from "src/testnet/HookLpHelper.sol";
import { SepoliaFaucetBatch } from "src/testnet/SepoliaFaucetBatch.sol";
import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { HookMiner } from "superposition-hook/libraries/HookMiner.sol";

// Base Sepolia (chainId 84532)
address constant BS_AQUA = 0x06DC4edCF4F3ABdFa65Cc4fD58AB459B5ff20F9e; // ours (Aqua not deployed here)
address constant BS_WETH = 0x4200000000000000000000000000000000000006;
address constant BS_AAVE_POOL = 0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27;
address constant BS_PM = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408; // v4 PoolManager
address constant BS_USDC = 0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f; // Aave reserve USDC
address constant BS_USDT = 0x0a215D8ba66387DCA84B284D18c3B4ec3de6E54a; // Aave reserve USDT
address constant BS_CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

/// @dev Static-arg subclasses (dodge the forge-script dynamic-ctor decode bug).
contract BsRouter is SuperPositionVMRouter {
    constructor(address aqua, address weth, address owner, address mc)
        SuperPositionVMRouter(aqua, weth, owner, "SuperPositionVMRouter", "1", mc)
    { }
}
contract BsUSDCVault is Aave4626Vault {
    constructor(address pool) Aave4626Vault(IERC20(BS_USDC), pool, "SuperPosition USDC", "spUSDC") { }
}
contract BsUSDTVault is Aave4626Vault {
    constructor(address pool) Aave4626Vault(IERC20(BS_USDT), pool, "SuperPosition USDT", "spUSDT") { }
}

/// @title DeployBaseSepolia
/// @notice Full SuperPosition stack on Base Sepolia (fresh), incl. the v4 hook and the
///         testnet helpers the console uses (OrderBuilder, HookLpHelper, FaucetBatch).
contract DeployBaseSepolia is Script {
    function run() external {
        address owner = vm.envOr("OWNER", msg.sender);
        string memory path = "deployments/superposition-base-sepolia.json";

        if (_existing(path) != address(0)) {
            console2.log("== base-sepolia stack already live ==");
            return;
        }

        vm.startBroadcast();
        MakerConfig mc = new MakerConfig();
        BsRouter router = new BsRouter(BS_AQUA, BS_WETH, owner, address(mc));
        AaveV3Adapter aave = new AaveV3Adapter(BS_AAVE_POOL, address(mc));
        BsUSDTVault vault0 = new BsUSDTVault(BS_AAVE_POOL); // token0 (lower asset)
        BsUSDCVault vault1 = new BsUSDCVault(BS_AAVE_POOL); // token1
        address[] memory vaults = new address[](2);
        vaults[0] = address(vault0);
        vaults[1] = address(vault1);
        ERC4626Adapter erc = new ERC4626Adapter(vaults);
        OrderBuilder ob = new OrderBuilder();
        vm.stopBroadcast();

        address hook = _deployHook(address(vault0), address(vault1), owner);

        vm.startBroadcast();
        SuperpositionUniAdapter sup = new SuperpositionUniAdapter(
            hook, address(router), BS_USDT, int24(1), int24(101), BS_USDC, int24(-101), int24(-1)
        );
        HookLpHelper lp = new HookLpHelper(hook);
        address[] memory fbTokens = new address[](2);
        fbTokens[0] = BS_USDC;
        fbTokens[1] = BS_USDT;
        SepoliaFaucetBatch fb = new SepoliaFaucetBatch(fbTokens);
        vm.stopBroadcast();

        _persist(path, address(mc), address(router), address(aave), address(erc), address(vault0), address(vault1), hook, address(sup), address(ob), address(lp), address(fb), PoolId.unwrap(SuperpositionHook(hook).poolId()));

        console2.log("MakerConfig:", address(mc));
        console2.log("Router:", address(router));
        console2.log("AaveV3Adapter:", address(aave));
        console2.log("ERC4626Adapter:", address(erc));
        console2.log("Vault USDC:", address(vault0));
        console2.log("Vault USDT:", address(vault1));
        console2.log("SuperpositionHook:", hook);
        console2.log("SuperpositionUniAdapter:", address(sup));
        console2.log("OrderBuilder:", address(ob));
        console2.log("HookLpHelper:", address(lp));
        console2.log("FaucetBatch:", address(fb));
    }

    function _deployHook(address vault0, address vault1, address owner) internal returns (address hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args = abi.encode(IPoolManager(BS_PM), vault0, vault1, uint24(100), int24(1), owner);
        (address predicted, bytes32 salt) = HookMiner.find(BS_CREATE2, flags, type(SuperpositionHook).creationCode, args);
        hook = predicted;
        bytes memory initCode = abi.encodePacked(type(SuperpositionHook).creationCode, args);
        vm.startBroadcast();
        if (hook.code.length == 0) {
            (bool ok,) = BS_CREATE2.call(abi.encodePacked(salt, initCode));
            require(ok, "create2 hook deploy failed");
            SuperpositionHook(hook).initializePool(79228162514264337593543950336);
        }
        vm.stopBroadcast();
    }

    function _existing(string memory path) internal view returns (address) {
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
        address sup,
        address ob,
        address lp,
        address fb,
        bytes32 poolId
    ) internal {
        string memory artifact = string.concat(
            '{"makerConfig":"', vm.toString(mc), '","router":"', vm.toString(router),
            '","AaveV3":"', vm.toString(aave), '","ERC4626":"', vm.toString(erc),
            '","vaultUSDC":"', vm.toString(vault1), '","vaultUSDT":"', vm.toString(vault0),
            '","SuperpositionHook":"', vm.toString(hook), '","SuperpositionUniHook":"', vm.toString(sup),
            '","OrderBuilder":"', vm.toString(ob), '","HookLpHelper":"', vm.toString(lp),
            '","FaucetBatch":"', vm.toString(fb), '","poolId":"', vm.toString(poolId), '"}'
        );
        vm.writeFile(path, artifact);
    }
}
