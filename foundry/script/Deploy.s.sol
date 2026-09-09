// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { MakerConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { BaseChain } from "./BaseChain.s.sol";

/// @notice Deploys the full Supercazzola stack on Base:
///         MakerConfig -> AaveV3Adapter -> SupercazzolaRouter (modified SwapVM redeploy).
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        MakerConfig makerConfig = new MakerConfig();
        AaveV3Adapter adapter = new AaveV3Adapter(BaseChain.AAVE_POOL);
        SupercazzolaRouter router = new SupercazzolaRouter(
            BaseChain.AQUA,
            BaseChain.WETH,
            deployer, // owner: rescue funds only
            "SupercazzolaRouter",
            "1",
            address(makerConfig)
        );

        vm.stopBroadcast();

        console2.log("=== Supercazzola deployment (Base) ===");
        console2.log("MakerConfig:           ", address(makerConfig));
        console2.log("AaveV3Adapter:         ", address(adapter));
        console2.log("SupercazzolaRouter:    ", address(router));
        console2.log("Aqua registry:         ", BaseChain.AQUA);
        console2.log("Aave Pool:             ", BaseChain.AAVE_POOL);

        // persist addresses for downstream scripts/tests
        string memory json = "deploy";
        json = vm.serializeAddress(json, "makerConfig", address(makerConfig));
        json = vm.serializeAddress(json, "adapter", address(adapter));
        json = vm.serializeAddress(json, "router", address(router));
        vm.writeJson(json, "deployments/supercazzola.json");
    }
}
