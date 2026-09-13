// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { SuperPositionVMRouter } from "src/SuperPositionVMRouter.sol";

interface IOrderBuilder { function build(address, address, address, address, address, uint32, uint256, uint256) external pure returns (bytes memory); }
interface IFaucet { function mint(address token, address to, uint256 amount) external; }

/// @notice TAKE (Aave): the taker mints LINK and swaps LINK -> WETH against the
///         maker's aWETH-backed order. Trace shows aWETH -> WETH on delivery and
///         LINK -> aLINK on the received side: real Aave movement.
/// @dev Run with the taker keystore (kondor).
contract AaveTakeSepolia is Script {
    address constant ROUTER = 0x201D78030bed2d81F827B7650E2CB7C00Ea0c9EC;
    address constant ORDER_BUILDER = 0x593f18800df097f059270357948F24bC677f50c5;
    address constant FAUCET = 0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D;
    address constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address constant LINK = 0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5;
    address constant MAKER = 0xD6f889AeF522bC43DCEE4f08c93f419A9CEa1B97;
    address constant TAKER = 0xDD7D64BFd13EF3b733374Fc8DE9B9C651487a15D;

    function run() external {
        vm.startBroadcast();

        IFaucet(FAUCET).mint(LINK, TAKER, 5e18);
        IERC20(LINK).approve(ROUTER, type(uint256).max);

        bytes memory orderBytes =
            IOrderBuilder(ORDER_BUILDER).build(MAKER, ROUTER, LINK, WETH, WETH, 3_100_000, 1e18, 1e18);
        ISwapVM.Order memory order = abi.decode(orderBytes, (ISwapVM.Order));

        (uint256 amountIn, uint256 amountOut,) =
            SuperPositionVMRouter(payable(ROUTER)).swap(order, LINK, WETH, 1e18, _takerTraits());
        vm.stopBroadcast();

        console2.log("taker paid LINK :", amountIn);
        console2.log("taker got  WETH :", amountOut);
    }

    function _takerTraits() internal pure returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(0), isExactIn: true, shouldUnwrapWeth: false, isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false, useTransferFromAndAquaPush: true, threshold: "", to: address(0),
                deadline: 0, hasPreTransferInCallback: false, hasPreTransferOutCallback: false,
                preTransferInHookData: "", postTransferInHookData: "", preTransferOutHookData: "",
                postTransferOutHookData: "", preTransferInCallbackData: "", preTransferOutCallbackData: "",
                instructionsArgs: "", signature: ""
            })
        );
    }
}
