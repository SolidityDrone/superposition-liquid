// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";

interface IOrderBuilder {
    function build(address, address, address, address, address, uint32, uint256, uint256) external pure returns (bytes memory);
}
interface IHook { function shareToken() external view returns (address); }

/// @notice MAKE side: configure the maker's sides to the Superposition adapter,
///         set approvals, and ship the SuperPosition order on Aqua (Sepolia).
/// @dev Run with the maker keystore:  --keystore ~/.foundry/keystores/pippo --password pass
contract ShipSepolia is Script {
    address constant ROUTER = 0x201D78030bed2d81F827B7650E2CB7C00Ea0c9EC;
    address constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address constant MAKER_CONFIG = 0xF56EBe6386F40969A9721C6aB3fa07BEaD1Bd926;
    address constant ADAPTER = 0x1be3291f7Ef08e56f0141007F49846fB07794C8B; // SuperpositionUniAdapter
    address constant ORDER_BUILDER = 0x593f18800df097f059270357948F24bC677f50c5;
    address constant HOOK = 0x6A7A2C6495A16f0a4c77E771f8A3945ee3494aC0;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
    address constant MAKER = 0xD6f889AeF522bC43DCEE4f08c93f419A9CEa1B97;

    function run() external {
        vm.startBroadcast();

        MakerConfig mc = MakerConfig(MAKER_CONFIG);
        if (mc.sides(MAKER, USDC).adapter != ADAPTER) {
            SideConfig[] memory sides = new SideConfig[](2);
            sides[0] = SideConfig(USDC, ADAPTER, AdapterKind.SuperpositionUniHook, true);
            sides[1] = SideConfig(USDT, ADAPTER, AdapterKind.SuperpositionUniHook, true);
            mc.setSides(sides);
            console2.log("setSides -> SuperpositionUniAdapter");
        }

        IERC20(USDC).approve(ROUTER, type(uint256).max);
        IERC20(USDT).approve(ROUTER, type(uint256).max);
        IERC20(USDC).approve(AQUA, type(uint256).max);
        IERC20(USDT).approve(AQUA, type(uint256).max);
        IERC20(USDC).approve(ADAPTER, type(uint256).max);
        IERC20(USDT).approve(ADAPTER, type(uint256).max);
        IERC1155(IHook(HOOK).shareToken()).setApprovalForAll(ADAPTER, true);

        bytes memory orderBytes = IOrderBuilder(ORDER_BUILDER).build(MAKER, ROUTER, USDC, USDT, USDT, 3_100_000, 1e18, 1e18);

        address[] memory toks = new address[](2);
        toks[0] = USDC;
        toks[1] = USDT;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 10_000e6;
        amts[1] = 10_000e6;

        IAqua(AQUA).ship(ROUTER, orderBytes, toks, amts);
        console2.log("shipped order on Aqua");

        vm.stopBroadcast();
    }
}
