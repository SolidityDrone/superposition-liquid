// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";

interface IOrderBuilder { function build(address, address, address, address, address, uint32, uint256, uint256) external pure returns (bytes memory); }
interface IFaucet { function mint(address token, address to, uint256 amount) external; }
interface IAaveAdapter { function deposit(address maker, address underlying, uint256 amount) external; }
interface IWETH9 { function deposit() external payable; }

/// @notice MAKE (Aave, uncapped): wrap ETH -> WETH, supply it to Aave via the
///         AaveV3Adapter (maker holds aWETH), register sides, ship LINK->WETH.
/// @dev WETH is chosen because its Aave Sepolia reserve has cash (the stable
///      reserves are supply-capped -> idle vault -> no aToken movement).
contract AaveShipSepolia is Script {
    address constant ROUTER = 0x201D78030bed2d81F827B7650E2CB7C00Ea0c9EC;
    address constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address constant MAKER_CONFIG = 0xF56EBe6386F40969A9721C6aB3fa07BEaD1Bd926;
    address constant AAVE_ADAPTER = 0xd915d3Db7f18f75D67c63B3Aa00872fbCE793c57;
    address constant ORDER_BUILDER = 0x593f18800df097f059270357948F24bC677f50c5;
    address constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address constant LINK = 0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5;
    address constant MAKER = 0xD6f889AeF522bC43DCEE4f08c93f419A9CEa1B97;

    function run() external {
        vm.startBroadcast();

        IWETH9(WETH).deposit{value: 0.005 ether}();
        IERC20(WETH).transfer(AAVE_ADAPTER, 0.005e18);
        IAaveAdapter(AAVE_ADAPTER).deposit(MAKER, WETH, 0.005e18);
        console2.log("WETH supplied to Aave -> maker holds aWETH");

        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig(WETH, AAVE_ADAPTER, AdapterKind.AaveV3, true);
        sides[1] = SideConfig(LINK, AAVE_ADAPTER, AdapterKind.AaveV3, true);
        MakerConfig(MAKER_CONFIG).setSides(sides);

        IERC20(WETH).approve(ROUTER, type(uint256).max);
        IERC20(LINK).approve(ROUTER, type(uint256).max);
        IERC20(WETH).approve(AQUA, type(uint256).max);
        IERC20(LINK).approve(AQUA, type(uint256).max);

        bytes memory order =
            IOrderBuilder(ORDER_BUILDER).build(MAKER, ROUTER, LINK, WETH, WETH, 3_100_000, 1e18, 1e18);
        address[] memory toks = new address[](2);
        toks[0] = LINK; toks[1] = WETH;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 10e18; amts[1] = 0.005e18;
        IAqua(AQUA).ship(ROUTER, order, toks, amts);
        console2.log("shipped LINK->WETH order (aWETH-backed)");

        vm.stopBroadcast();
    }
}
