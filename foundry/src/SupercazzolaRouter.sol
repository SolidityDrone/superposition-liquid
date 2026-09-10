// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Simulator } from "@1inch/solidity-utils/contracts/mixins/Simulator.sol";
import { IMakerHooks } from "@1inch/swap-vm/interfaces/IMakerHooks.sol";
import { SwapVM } from "@1inch/swap-vm/SwapVM.sol";
import { Context } from "@1inch/swap-vm/libs/VM.sol";

import { SupercazzolaOpcodes } from "src/opcodes/SupercazzolaOpcodes.sol";
import { MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { MakerCapitalGuardOpcode } from "src/opcodes/MakerCapitalGuardOpcode.sol";
import { YieldAdjustedRateOpcode } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

/// @title SupercazzolaRouter
/// @notice Modified SwapVM redeploy: makers provide ETH/USDC liquidity while keeping 100%
///         of capital in a lending protocol (Aave v3 via adapters). Every fill cycles
///         capital JIT: withdraw from lending -> deliver to taker -> deposit back,
///         atomically within the swap transaction (SPEC.md B1.2 JIT-unwrap pattern).
/// @dev The router is both the VM executor and the maker hooks target.
contract SupercazzolaRouter is Simulator, SwapVM, SupercazzolaOpcodes, IMakerHooks {
    MakerConfig public immutable MAKER_CONFIG;

    constructor(
        address aqua,
        address weth,
        address owner,
        string memory name,
        string memory version,
        address makerConfig
    ) SwapVM(aqua, weth, owner, name, version) SupercazzolaOpcodes(aqua) {
        MAKER_CONFIG = MakerConfig(makerConfig);
    }

    /// @dev Returns instruction set for VM execution (Aqua set + 2 custom opcodes)
    function _instructions() internal pure override returns (function(Context memory, bytes calldata) internal[] memory result) {
        return _opcodes();
    }

    /// @notice Opcode-context hook: the custom opcodes resolve the maker's
    ///         side adapters from the same registry the hooks use.
    function _makerConfig() internal view override(SupercazzolaOpcodes) returns (MakerConfig) {
        return MAKER_CONFIG;
    }

    // --- Maker hooks (JIT capital cycling) ---

    /// @notice Called by SwapVM before tokenOut leaves the maker. JIT-unwraps from the
    ///         lending protocol into the maker wallet; SwapVM's default Aqua.pull then
    ///         delivers to the taker from the maker wallet.
    /// @dev Direction-agnostic: tokenOut can be either of the strategy's two underlyings.
    function preTransferOut(
        address maker,
        address /* taker */,
        address /* tokenIn */,
        address tokenOut,
        uint256 /* amountIn */,
        uint256 amountOut,
        bytes32 /* orderHash */,
        bytes calldata /* makerData */,
        bytes calldata /* takerData */
    ) external {
        SideConfig memory s = MAKER_CONFIG.sides(maker, tokenOut);
        if (s.autoManaged && s.adapter != address(0)) {
            ILendingAdapter(s.adapter).withdrawTo(maker, tokenOut, amountOut, maker);
        }
    }

    /// @notice Called by SwapVM after tokenIn reached the maker wallet. Deploys the
    ///         received tokens into the lending protocol on behalf of the maker.
    /// @dev Direction-agnostic: tokenIn can be either of the strategy's two underlyings.
    function postTransferIn(
        address maker,
        address /* taker */,
        address tokenIn,
        address /* tokenOut */,
        uint256 amountIn,
        uint256 /* amountOut */,
        bytes32 /* orderHash */,
        bytes calldata /* makerData */,
        bytes calldata /* takerData */
    ) external {
        SideConfig memory s = MAKER_CONFIG.sides(maker, tokenIn);
        if (s.autoManaged && s.adapter != address(0)) {
            ILendingAdapter(s.adapter).depositFor(maker, tokenIn, amountIn);
        }
    }

    function preTransferIn(
        address, address, address, address, uint256, uint256, bytes32, bytes calldata, bytes calldata
    ) external pure { }

    function postTransferOut(
        address, address, address, address, uint256, uint256, bytes32, bytes calldata, bytes calldata
    ) external pure { }
}
