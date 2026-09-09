// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AquaOpcodes } from "@1inch/swap-vm/opcodes/AquaOpcodes.sol";
import { Context } from "@1inch/swap-vm/libs/VM.sol";

import { YieldAdjustedRateOpcode } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { ChainlinkGuardOpcode } from "src/opcodes/ChainlinkGuardOpcode.sol";

/// @title SupercazzolaOpcodes
/// @notice AquaOpcodes table with two custom instructions appended at the end
///         (backward-compatible append-only pattern, see SPEC.md B3.1):
///         35 = YieldAdjustedRateXD, 36 = ChainlinkGuardXD
contract SupercazzolaOpcodes is AquaOpcodes, YieldAdjustedRateOpcode, ChainlinkGuardOpcode {
    constructor(address aqua) AquaOpcodes(aqua) { }

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
        result[baseLen + 1] = _chainlinkGuardXD;
    }
}
