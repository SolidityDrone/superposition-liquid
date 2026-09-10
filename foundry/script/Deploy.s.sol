// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { StargateAdapter } from "src/adapters/stargate/StargateAdapter.sol";
import { PendlePTAdapter } from "src/adapters/pendle/PendlePTAdapter.sol";
import { MakerConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { BaseChain } from "./BaseChain.s.sol";

address constant ARB_AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
address constant ARB_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
address constant ARB_MARKET = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5; // PT-aUSDC-27JUN2024 (EXPIRED)
address constant ETH_AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
address constant ETH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant ETH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant ETH_MARKET = 0x34280882267ffa6383B363E278B027Be083bBe3b; // PT-wstETH (ACTIVE)
address constant ETH_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;

address constant BASE_STARGATE_POOL = 0x27a16dc786820B16E5c9028b75B99F6f604b5d26; // StargatePoolUSDC
address constant BASE_STARGATE_STAKING = 0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80;

/// @notice Deploys the FULL Supercazzola stack — config, router and EVERY
///         adapter (one artifact per chain, consumed by fund/scenario scripts):
///   base     : MakerConfig, SupercazzolaRouter, AaveV3Adapter, ERC4626Adapter
///              (Morpho Gauntlet WETH + Steakhouse USDC), StargateAdapter
///   arbitrum : MakerConfig, SupercazzolaRouter, PendlePTAdapter (expired PT-aUSDC)
///   ethereum : MakerConfig, SupercazzolaRouter, PendlePTAdapter (active PT-wstETH)
contract Deploy is Script {
    function run() external {
        // defaults to the well-known anvil key (always funded on an anvil
        // fork); set PRIVATE_KEY explicitly for real deployments
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        string memory chain = vm.envOr("CHAIN", string("base"));
        address deployer = vm.addr(deployerKey);
        address aqua = _eq(chain, "base") ? BaseChain.AQUA : _eq(chain, "arbitrum") ? ARB_AQUA : ETH_AQUA;
        address weth = _eq(chain, "base") ? BaseChain.WETH : _eq(chain, "arbitrum") ? ARB_WETH : ETH_WETH;

        vm.startBroadcast(deployerKey);

        MakerConfig makerConfig = new MakerConfig();
        SupercazzolaRouter router = new SupercazzolaRouter(
            aqua,
            weth,
            deployer, // owner: rescue funds only
            "SupercazzolaRouter",
            "1",
            address(makerConfig)
        );

        if (_eq(chain, "base")) {
            AaveV3Adapter aave = new AaveV3Adapter(BaseChain.AAVE_POOL);
            console2.log("AaveV3Adapter:      ", address(aave));
            ERC4626Adapter erc = new ERC4626Adapter(
                _arr2(BaseChain.USDC, BaseChain.WETH),
                _arr2(BaseChain.MORPHO_USDC_VAULT, BaseChain.MORPHO_WETH_VAULT)
            );
            console2.log("ERC4626Adapter:     ", address(erc));
            StargateAdapter stg = new StargateAdapter(BASE_STARGATE_POOL, BASE_STARGATE_STAKING, BaseChain.WETH);
            console2.log("StargateAdapter:    ", address(stg));

            vm.stopBroadcast();
            _persist(chain, makerConfig, router, address(aave), address(erc), address(stg));
        } else if (_eq(chain, "arbitrum")) {
            vm.stopBroadcast();
            // the expired-PT scenario must be broadcast in its own window
            // (the PT pull address differs); the scenario deploys it
            _persistArb(chain, makerConfig, router);
        } else {
            vm.stopBroadcast();
            _persistArb(chain, makerConfig, router);
        }

        console2.log("=== Supercazzola deployment ===");
        console2.log("MakerConfig:        ", address(makerConfig));
        console2.log("SupercazzolaRouter: ", address(router));
        console2.log("Aqua registry:      ", aqua);
    }

    function _persist(string memory chain, MakerConfig mc, SupercazzolaRouter r, address aave, address erc, address stg)
        internal
    {
        string memory artifact = string.concat(
            '{"makerConfig":"', vm.toString(address(mc)),
            '","router":"', vm.toString(address(r)),
            '","AaveV3":"', vm.toString(aave),
            '","ERC4626":"', vm.toString(erc),
            '","Stargate":"', vm.toString(stg), '"}'
        );
        vm.writeFile(string.concat("deployments/supercazzola-", chain, ".json"), artifact);
    }

    function _persistArb(string memory chain, MakerConfig mc, SupercazzolaRouter r) internal {
        string memory artifact = string.concat(
            '{"makerConfig":"', vm.toString(address(mc)), '","router":"', vm.toString(address(r)), '"}'
        );
        vm.writeFile(string.concat("deployments/supercazzola-", chain, ".json"), artifact);
    }

    function _arr2(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
