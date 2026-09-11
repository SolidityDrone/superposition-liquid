// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { StargateAdapter } from "src/adapters/stargate/StargateAdapter.sol";
import { SuperpositionUniAdapter } from "src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol";
import { ISuperpositionHook } from "src/adapters/superposition-uni-hook/ISuperpositionHook.sol";
import { MakerConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { HookMiner } from "superposition-hook/libraries/HookMiner.sol";
import { BaseChain } from "./BaseChain.s.sol";

address constant ARB_AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
address constant ARB_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
address constant ARB_MARKET = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5; // PT-aUSDC-27JUN2024 (EXPIRED)
address constant ETH_AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
address constant ETH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant ETH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant ETH_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
address constant ETH_MARKET = 0x34280882267ffa6383B363E278B027Be083bBe3b; // PT-wstETH (ACTIVE)
address constant ETH_AAVE = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
address constant ETH_AUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
address constant ETH_AUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
address constant ETH_PM = 0x000000000004444c5dc75cB358380D2e3dE08A90;
address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
address constant BASE_STARGATE_POOL = 0x27a16dc786820B16E5c9028b75B99F6f604b5d26;
address constant BASE_STARGATE_STAKING = 0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80;

interface IPMarketLike {
    function readTokens() external view returns (address sy, address pt, address yt);
}

/// @title DeployAndSetup
/// @notice One script, two phases:
///   1. DEPLOY — MakerConfig + SupercazzolaRouter + EVERY adapter of the chain
///      (artifact in deployments/supercazzola-<chain>.json)
///   2. SETUP — the maker's one-time arming: MAX approvals for every token the
///      router can pull + capital deposited into every adapter; the taker's
///      tokenIn approvals too. Scenario scripts then only setSides + ship + fill.
///
/// Usage (against a funded anvil fork):
///   export CHAIN=base
///   forge script script/DeployAndSetup.s.sol --fork-url http://localhost:8545 --broadcast
/// Re-runs skip the deployment (router already live) and just re-arm.
contract DeployAndSetup is Script {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX = type(uint256).max;

    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        string memory chain = vm.envOr("CHAIN", string("base"));
        bool deployOnly = vm.envOr("DEPLOY_ONLY", false);
        address aqua = _eq(chain, "base") ? BaseChain.AQUA : _eq(chain, "arbitrum") ? ARB_AQUA : ETH_AQUA;
        address weth = _eq(chain, "base") ? BaseChain.WETH : _eq(chain, "arbitrum") ? ARB_WETH : ETH_WETH;
        string memory path = string.concat("deployments/supercazzola-", chain, ".json");

        address router = _existingRouter(path);
        if (router == address(0)) {
            router = _deploy(chain, deployerKey, aqua, weth, path);
        } else {
            console2.log("== stack already live - skipping deployment ==");
            console2.log("router:", router);
        }
        if (deployOnly) return;

        _setup(chain, router, aqua, weth);
    }

    // ---- phase 1: deploy -------------------------------------------------------
    function _deploy(string memory chain, uint256 deployerKey, address aqua, address weth, string memory path)
        internal
        returns (address router)
    {
        vm.startBroadcast(deployerKey);
        MakerConfig mc = new MakerConfig();
        SupercazzolaRouter r = new SupercazzolaRouter(
            aqua, weth, vm.addr(deployerKey), "SupercazzolaRouter", "1", address(mc)
        );
        router = address(r);
        console2.log("MakerConfig:", address(mc));
        console2.log("Router:", router);

        if (_eq(chain, "base")) {
            address aave = address(new AaveV3Adapter(BaseChain.AAVE_POOL));
            address erc = address(new ERC4626Adapter(
                _arr2(BaseChain.USDC, BaseChain.WETH),
                _arr2(BaseChain.MORPHO_USDC_VAULT, BaseChain.MORPHO_WETH_VAULT)
            ));
            address stg = address(new StargateAdapter(BASE_STARGATE_POOL, BASE_STARGATE_STAKING, BaseChain.WETH));
            vm.stopBroadcast();
            _persist(path, address(mc), router, aave, erc, stg, address(0), address(0));
        } else if (_eq(chain, "ethereum")) {
            // self-deploy the Superposition hook conditionally (CREATE2, mined salt)
            vm.stopBroadcast();
            address hook = _deploySuperpositionHookIfNeeded(deployerKey);
            vm.startBroadcast(deployerKey);
            address sup = address(
                new SuperpositionUniAdapter(hook, router, ETH_USDC, 1, 101, ETH_USDT, -101, -1)
            );
            vm.stopBroadcast();
            _persist(path, address(mc), router, address(0), address(0), address(0), hook, sup);
        } else {
            vm.stopBroadcast();
            _persist(path, address(mc), router, address(0), address(0), address(0), address(0), address(0));
        }
        console2.log("== deployed ==");
    }

    /// @dev Deploys the Superposition hook on Ethereum if it has no code yet; otherwise reuses it.
    function _deploySuperpositionHookIfNeeded(uint256 deployerKey) internal returns (address hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args = abi.encode(
            IPoolManager(ETH_PM),
            ETH_AAVE,
            ETH_USDC,
            ETH_USDT,
            ETH_AUSDC,
            ETH_AUSDT,
            uint24(100),
            int24(1),
            vm.addr(deployerKey)
        );
        (address predicted, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(SuperpositionHook).creationCode, args);
        hook = predicted;
        if (hook.code.length > 0) {
            console2.log("SuperpositionHook already live:", hook);
            return hook;
        }
        bytes memory initCode = abi.encodePacked(type(SuperpositionHook).creationCode, args);
        vm.startBroadcast(deployerKey);
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, initCode));
        require(ok, "create2 hook deploy failed");
        SuperpositionHook(hook).initializePool(79228162514264337593543950336); // price 1.0
        vm.stopBroadcast();
        console2.log("SuperpositionHook:", hook);
    }

    function _existingRouter(string memory path) internal view returns (address) {
        try vm.readFile(path) returns (string memory art) {
            address r = vm.parseAddress(vm.parseJsonString(art, ".router"));
            if (r.code.length > 0) return r;
        } catch { }
        return address(0);
    }

    // ---- phase 2: maker/taker arming ------------------------------------------
    function _setup(string memory chain, address router, address aqua, address weth) internal {
        uint256 makerKey = vm.envOr("MAKER_KEY", uint256(0xA11CE));
        uint256 takerKey = vm.envOr("TAKER_KEY", uint256(0xB0B));
        address maker = vm.addr(makerKey);
        address taker = vm.addr(takerKey);

        if (_eq(chain, "base")) {
            string memory art = vm.readFile("deployments/supercazzola-base.json");
            address aaveAd = vm.parseAddress(vm.parseJsonString(art, ".AaveV3"));
            address ercAd = vm.parseAddress(vm.parseJsonString(art, ".ERC4626"));
            address stgAd = vm.parseAddress(vm.parseJsonString(art, ".Stargate"));
            address usdc = BaseChain.USDC;

            vm.startBroadcast(makerKey);
            IERC20(weth).approve(router, MAX);
            IERC20(usdc).approve(router, MAX);
            IERC20(BaseChain.A_WETH).approve(router, MAX);
            IERC20(BaseChain.A_USDC).approve(router, MAX);
            IERC20(BaseChain.MORPHO_WETH_VAULT).approve(router, MAX);
            IERC20(BaseChain.MORPHO_USDC_VAULT).approve(router, MAX);
            IERC20(weth).approve(aqua, MAX);
            IERC20(usdc).approve(aqua, MAX);
            if (IERC20(weth).balanceOf(maker) >= 210e18) {
                IERC20(weth).transfer(aaveAd, 105e18);
                AaveV3Adapter(aaveAd).deposit(maker, weth, 105e18);
                IERC20(weth).transfer(ercAd, 105e18);
                ERC4626Adapter(ercAd).deposit(maker, weth, 105e18);
            }
            if (IERC20(usdc).balanceOf(maker) >= 530_000e6) {
                IERC20(usdc).transfer(aaveAd, 262_500e6);
                AaveV3Adapter(aaveAd).deposit(maker, usdc, 262_500e6);
                IERC20(usdc).transfer(ercAd, 262_500e6);
                ERC4626Adapter(ercAd).deposit(maker, usdc, 262_500e6);
                IERC20(usdc).transfer(stgAd, 5_000e6);
                StargateAdapter(stgAd).deposit(maker, usdc, 5_000e6);
            }
            vm.stopBroadcast();

            vm.startBroadcast(takerKey);
            IERC20(weth).approve(router, MAX);
            IERC20(usdc).approve(router, MAX);
            vm.stopBroadcast();
            console2.log("== setup base: approvals + Aave/Morpho/Stargate positions ==");
        } else if (_eq(chain, "arbitrum")) {
            address pt = _pt(ARB_MARKET);
            vm.startBroadcast(makerKey);
            IERC20(ARB_USDC).approve(router, MAX);
            IERC20(ARB_WETH).approve(router, MAX);
            IERC20(pt).approve(router, MAX);
            IERC20(ARB_USDC).approve(aqua, MAX);
            IERC20(ARB_WETH).approve(aqua, MAX);
            vm.stopBroadcast();
            vm.startBroadcast(takerKey);
            IERC20(ARB_WETH).approve(router, MAX);
            vm.stopBroadcast();
            console2.log("== setup arbitrum: pendle-expired approvals ==");
        } else {
            address pt = _pt(ETH_MARKET);
            string memory art = vm.readFile("deployments/supercazzola-ethereum.json");
            address supAd = vm.parseAddress(vm.parseJsonString(art, ".SuperpositionUniHook"));
            address supHook = vm.parseAddress(vm.parseJsonString(art, ".SuperpositionHook"));
            address shareToken = ISuperpositionHook(supHook).shareToken();
            vm.startBroadcast(makerKey);
            if (IERC20(ETH_USDC).allowance(maker, router) != MAX) IERC20(ETH_USDC).forceApprove(router, MAX);
            if (IERC20(ETH_USDT).allowance(maker, router) != MAX) IERC20(ETH_USDT).forceApprove(router, MAX);
            if (IERC20(pt).allowance(maker, router) != MAX) IERC20(pt).forceApprove(router, MAX);
            if (IERC20(ETH_USDC).allowance(maker, aqua) != MAX) IERC20(ETH_USDC).forceApprove(aqua, MAX);
            if (IERC20(ETH_USDT).allowance(maker, aqua) != MAX) IERC20(ETH_USDT).forceApprove(aqua, MAX);
            if (!IERC1155(shareToken).isApprovedForAll(maker, supAd)) {
                IERC1155(shareToken).setApprovalForAll(supAd, true);
            }
            // maker LP into the Superposition buckets (one-sided per token); idempotent
            if (ISuperpositionHook(supHook).sharesOf(maker, 1, 101) == 0 && IERC20(ETH_USDC).balanceOf(maker) >= 100_000e6) {
                IERC20(ETH_USDC).safeTransfer(supAd, 100_000e6);
                SuperpositionUniAdapter(supAd).deposit(maker, ETH_USDC, 100_000e6);
            }
            if (ISuperpositionHook(supHook).sharesOf(maker, -101, -1) == 0 && IERC20(ETH_USDT).balanceOf(maker) >= 100_000e6) {
                IERC20(ETH_USDT).safeTransfer(supAd, 100_000e6);
                SuperpositionUniAdapter(supAd).deposit(maker, ETH_USDT, 100_000e6);
            }
            vm.stopBroadcast();
            vm.startBroadcast(takerKey);
            if (IERC20(ETH_USDC).allowance(taker, router) != MAX) IERC20(ETH_USDC).forceApprove(router, MAX);
            if (IERC20(ETH_USDT).allowance(taker, router) != MAX) IERC20(ETH_USDT).forceApprove(router, MAX);
            vm.stopBroadcast();
            console2.log("== setup ethereum: pendle-active + superposition approvals + LP ==");
        }
    }

    function _pt(address market) internal view returns (address pt) {
        (,, pt) = IPMarketLike(market).readTokens();
    }

    function _persist(
        string memory path,
        address mc,
        address router,
        address aave,
        address erc,
        address stg,
        address supHook,
        address supAdapter
    ) internal {
        string memory artifact = string.concat(
            '{"makerConfig":"', vm.toString(mc), '","router":"', vm.toString(router),
            '","AaveV3":"', vm.toString(aave), '","ERC4626":"', vm.toString(erc),
            '","Stargate":"', vm.toString(stg), '","SuperpositionHook":"', vm.toString(supHook),
            '","SuperpositionUniHook":"', vm.toString(supAdapter), '"}'
        );
        vm.writeFile(path, artifact);
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
