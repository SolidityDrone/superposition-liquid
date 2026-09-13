// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SuperPositionVMRouter } from "src/SuperPositionVMRouter.sol";
import { Aave4626Vault } from "src/vaults/Aave4626Vault.sol";
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";

interface IFaucet { function mint(address token, address to, uint256 amount) external; }

/// @dev USDT vault subclass (fixed ctor args, base-sepolia Aave pool).
contract BsUsdtVault is Aave4626Vault {
    constructor(address pool) Aave4626Vault(IERC20(0x0a215D8ba66387DCA84B284D18c3B4ec3de6E54a), pool, "SuperPosition USDT", "spUSDT") { }
}

/// @notice Stable swap, 1inch-only (no Uniswap hook, no WETH): reuses the deployed
///         MakerConfig/Router/Aqua + spUSDC, deploys spUSDT + a stable ERC4626Adapter,
///         then a maker ships USDC->USDT and a taker takes it. Both sides are Aave
///         ERC-4626 vaults, so the fill moves aUSDC / aUSDT.
contract BaseSepoliaStableSwap is Script {
    using SafeERC20 for IERC20;

    address constant MAKER = 0xDD7D64BFd13EF3b733374Fc8DE9B9C651487a15D; // kondor
    address constant AQUA = 0x06DC4edCF4F3ABdFa65Cc4fD58AB459B5ff20F9e;
    address constant MAKER_CONFIG = 0x1A3850d9189767254C14f82F21C08e74292525E6;
    address constant ROUTER = 0x2E227919A3F235f53215d4a61E845a75F1f05E1E;
    address constant SP_USDC = 0x1f369fb20848e1466827898F1dc1db4497e6B532;
    address constant USDC = 0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f;
    address constant USDT = 0x0a215D8ba66387DCA84B284D18c3B4ec3de6E54a;
    address constant AAVE_POOL = 0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27;
    address constant FAUCET = 0xD9145b5F45Ad4519c7ACcD6E0A4A82e83bB8A6Dc;

    function run() external {
        vm.startBroadcast();

        SuperPositionVMRouter router = SuperPositionVMRouter(payable(ROUTER));
        MakerConfig mc = MakerConfig(MAKER_CONFIG);

        BsUsdtVault spUsdt = new BsUsdtVault(AAVE_POOL);
        address[] memory vs = new address[](2);
        vs[0] = SP_USDC;
        vs[1] = address(spUsdt);
        ERC4626Adapter adapter = new ERC4626Adapter(vs);
        console2.log("spUSDT", address(spUsdt));
        console2.log("stable Adapter", address(adapter));

        IFaucet(FAUCET).mint(USDC, MAKER, 1_100e6);
        IFaucet(FAUCET).mint(USDT, MAKER, 1_100e6);
        IERC20(USDC).approve(SP_USDC, 1_000e6);
        IERC4626(SP_USDC).deposit(1_000e6, MAKER);
        IERC20(USDT).approve(address(spUsdt), 1_000e6);
        spUsdt.deposit(1_000e6, MAKER);

        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig(USDC, address(adapter), AdapterKind.ERC4626, true);
        sides[1] = SideConfig(USDT, address(adapter), AdapterKind.ERC4626, true);
        mc.setSides(sides);

        IERC20(USDC).approve(address(router), type(uint256).max);
        IERC20(USDT).approve(address(router), type(uint256).max);
        IERC20(USDC).approve(AQUA, type(uint256).max);
        IERC20(USDT).approve(AQUA, type(uint256).max);
        IERC20(SP_USDC).approve(address(router), type(uint256).max);
        IERC20(address(spUsdt)).approve(address(router), type(uint256).max);

        ISwapVM.Order memory order = _order(MAKER, address(router), USDC, USDT, USDT);
        address[] memory toks = new address[](2);
        toks[0] = USDC;
        toks[1] = USDT;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 10e6;
        amts[1] = 10e6;
        Aqua(AQUA).ship(address(router), abi.encode(order), toks, amts);
        console2.log("shipped USDC->USDT on Aqua");

        (uint256 amountIn, uint256 amountOut,) = router.swap(order, USDC, USDT, 1e6, _takerTraits());
        console2.log("taker paid USDC:", amountIn);
        console2.log("taker got  USDT:", amountOut);

        vm.stopBroadcast();
    }

    function _order(address maker, address router_, address tIn, address tOut, address guard)
        internal
        pure
        returns (ISwapVM.Order memory)
    {
        bytes memory yieldArgs = YieldArgsBuilder.build(tIn, tOut, 1e18, 1e18);
        bytes memory feeArgs = FeeArgsBuilder.buildFlatFee(3e6);
        bytes memory guardArgs = CapitalArgsBuilder.build(guard);
        bytes memory program = abi.encodePacked(
            uint8(YIELD_ADJUSTED_RATE_XD), uint8(yieldArgs.length), yieldArgs,
            uint8(21), uint8(feeArgs.length), feeArgs,
            uint8(17), uint8(0),
            uint8(MAKER_CAPITAL_GUARD_XD), uint8(guardArgs.length), guardArgs
        );
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker, receiver: address(0), shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true, allowZeroAmountIn: false,
                hasPreTransferInHook: false, hasPostTransferInHook: true,
                hasPreTransferOutHook: true, hasPostTransferOutHook: false,
                preTransferInTarget: address(0), preTransferInData: "",
                postTransferInTarget: router_, postTransferInData: "",
                preTransferOutTarget: router_, preTransferOutData: "",
                postTransferOutTarget: address(0), postTransferOutData: "",
                program: program
            })
        );
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
