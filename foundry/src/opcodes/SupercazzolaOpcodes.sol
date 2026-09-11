// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AquaOpcodes } from "@1inch/swap-vm/opcodes/AquaOpcodes.sol";
import { Context } from "@1inch/swap-vm/libs/VM.sol";

import { YieldAdjustedRateOpcode } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { MakerCapitalGuardOpcode, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";
import { MakerConfig } from "src/config/MakerConfig.sol";

/// @title SupercazzolaOpcodes
/// @notice AquaOpcodes table with two custom instructions appended at the end
///         (backward-compatible append-only pattern, see SPEC.md B3.1):
///         35 = YieldAdjustedRateXD, 36 = MakerCapitalGuardXD
abstract contract SupercazzolaOpcodes is AquaOpcodes, YieldAdjustedRateOpcode, MakerCapitalGuardOpcode {
    constructor(address aqua) AquaOpcodes(aqua) { }

    /// @dev Abstract: the concrete router provides its MakerConfig so the
    ///      custom opcodes resolve the maker's side adapters from the registry.
    function _makerConfig() internal view virtual override(MakerCapitalGuardOpcode, YieldAdjustedRateOpcode) returns (MakerConfig);

    function _opcodes()
        internal
        pure
        override
        returns (function(Context memory, bytes calldata) internal[] memory result)
    {
        function(Context memory, bytes calldata) internal[] memory base = super._opcodes();
        uint256 baseLen = base.length;

        result = new function(Context memory, bytes calldata) internal[](baseLen + 2);
        for (uint256 i = 0; i < baseLen; i++) {
            result[i] = base[i];
        }
        result[baseLen] = _yieldAdjustedRateXD;
        result[baseLen + 1] = _makerCapitalGuardXD;
    }
}
