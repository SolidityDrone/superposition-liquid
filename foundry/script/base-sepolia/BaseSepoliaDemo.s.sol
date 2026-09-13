// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
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

interface IWETH9 { function deposit() external payable; }
interface IFaucet { function mint(address token, address to, uint256 amount) external; }

/// @dev Concrete subclasses (fixed ctor args) to dodge the forge-script decode bug.
contract BsWethVault is Aave4626Vault {
    constructor(address pool) Aave4626Vault(IERC20(0x4200000000000000000000000000000000000006), pool, "SuperPosition WETH", "spWETH") { }
}
contract BsUsdcVault is Aave4626Vault {
    constructor(address pool) Aave4626Vault(IERC20(0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f), pool, "SuperPosition USDC", "spUSDC") { }
}

/// @notice Base Sepolia end-to-end: deploy MakerConfig + router + two Aave4626Vaults
///         (our ERC-4626 wrapper over Aave, holding REAL aWETH/aUSDC since WETH is not
///         capped) + ERC4626Adapter, then a maker ships a USDC->WETH order on Aqua and
///         a taker takes it. The ERC-4626 "waToken" shares burn on delivery (aWETH
///         redeemed) and mint on the received side (USDC deposited).
/// @dev Single funded key = chack (0x223677A3…c7F3), password `pass`.
contract BaseSepoliaDemo is Script {
    using SafeERC20 for IERC20;

    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f;
    address constant AAVE_POOL = 0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27;
    address constant FAUCET = 0xD9145b5F45Ad4519c7ACcD6E0A4A82e83bB8A6Dc;
    address constant MAKER = 0x223677A35623AD17Bf1B110D185842917605c7F3; // chack keystore

    function run() external {
        vm.startBroadcast();
        address me = MAKER;

        // ---- deploy (Aqua is absent on Base Sepolia -> deploy our own) ----
        Aqua aqua = new Aqua();
        MakerConfig mc = new MakerConfig();
        SuperPositionVMRouter router =
            new SuperPositionVMRouter(address(aqua), WETH, me, "SuperPositionVMRouter", "1", address(mc));
        BsWethVault wv = new BsWethVault(AAVE_POOL);
        BsUsdcVault uv = new BsUsdcVault(AAVE_POOL);
        address[] memory vs = new address[](2);
        vs[0] = address(wv);
        vs[1] = address(uv);
        ERC4626Adapter adapter = new ERC4626Adapter(vs);
        console2.log("Aqua", address(aqua));
        console2.log("MakerConfig", address(mc));
        console2.log("Router", address(router));
        console2.log("Adapter", address(adapter));
        console2.log("spWETH", address(wv));
        console2.log("spUSDC", address(uv));

        // ---- maker capital: real aWETH + aUSDC inside our ERC-4626 vaults ----
        IWETH9(WETH).deposit{value: 0.01 ether}();
        IFaucet(FAUCET).mint(USDC, me, 1_100e6);
        IERC20(WETH).approve(address(wv), 0.01e18);
        wv.deposit(0.01e18, me);
        // deposit 1000, keep 100 in the wallet so the taker has tokenIn to pay
        IERC20(USDC).approve(address(uv), 1_000e6);
        uv.deposit(1_000e6, me);

        // ---- sides ----
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig(WETH, address(adapter), AdapterKind.ERC4626, true);
        sides[1] = SideConfig(USDC, address(adapter), AdapterKind.ERC4626, true);
        mc.setSides(sides);

        IERC20(WETH).approve(address(router), type(uint256).max);
        IERC20(USDC).approve(address(router), type(uint256).max);
        IERC20(WETH).approve(address(aqua), type(uint256).max);
        IERC20(USDC).approve(address(aqua), type(uint256).max);
        // the JIT pull moves the VAULT SHARES maker -> adapter -> router needs them approved
        IERC20(address(wv)).approve(address(router), type(uint256).max);
        IERC20(address(uv)).approve(address(router), type(uint256).max);

        // ---- ship + take ----
        ISwapVM.Order memory order = _order(me, address(router), USDC, WETH, WETH);
        address[] memory toks = new address[](2);
        toks[0] = USDC;
        toks[1] = WETH;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 10e6;
        amts[1] = 0.01e18;
        IAqua(address(aqua)).ship(address(router), abi.encode(order), toks, amts);
        console2.log("shipped USDC->WETH on Aqua");

        (uint256 amountIn, uint256 amountOut,) = router.swap(order, USDC, WETH, 1e6, _takerTraits());
        console2.log("taker paid USDC:", amountIn);
        console2.log("taker got  WETH:", amountOut);

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
