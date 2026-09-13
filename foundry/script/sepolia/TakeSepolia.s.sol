// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { SuperPositionVMRouter } from "src/SuperPositionVMRouter.sol";

interface IOrderBuilder {
    function build(address, address, address, address, address, uint32, uint256, uint256) external pure returns (bytes memory);
}
interface IFaucet { function mint(address token, address to, uint256 amount) external; }

/// @notice TAKE side: fund the taker, approve the router and execute `swap()`
///         against the maker's shipped SuperPosition order (Sepolia).
/// @dev Run with the taker keystore:  --keystore ~/.foundry/keystores/kondor --password pass
contract TakeSepolia is Script {
    address constant ROUTER = 0x201D78030bed2d81F827B7650E2CB7C00Ea0c9EC;
    address constant ADAPTER = 0x1be3291f7Ef08e56f0141007F49846fB07794C8B;
    address constant ORDER_BUILDER = 0x593f18800df097f059270357948F24bC677f50c5;
    address constant FAUCET = 0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
    address constant MAKER = 0xD6f889AeF522bC43DCEE4f08c93f419A9CEa1B97;
    address constant TAKER = 0xDD7D64BFd13EF3b733374Fc8DE9B9C651487a15D; // kondor keystore

    function run() external {
        vm.startBroadcast();

        IFaucet(FAUCET).mint(USDC, TAKER, 1_000e6);
        IERC20(USDC).approve(ROUTER, type(uint256).max);

        bytes memory orderBytes = IOrderBuilder(ORDER_BUILDER).build(MAKER, ROUTER, USDC, USDT, USDT, 3_100_000, 1e18, 1e18);
        ISwapVM.Order memory order = abi.decode(orderBytes, (ISwapVM.Order));

        (uint256 amountIn, uint256 amountOut,) =
            SuperPositionVMRouter(payable(ROUTER)).swap(order, USDC, USDT, 100e6, _takerTraits());
        vm.stopBroadcast();

        console2.log("taker paid USDC (in) :", amountIn);
        console2.log("taker got  USDT (out):", amountOut);
    }

    function _takerTraits() internal pure returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(0),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: true,
                threshold: "",
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: false,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
    }
}
