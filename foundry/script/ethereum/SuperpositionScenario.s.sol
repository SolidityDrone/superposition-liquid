// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AnvilScenario } from "../AnvilScenario.s.sol";

/// @notice Live scenario for the SuperpositionUni adapter (USDC/USDT on Ethereum).
/// Run against a FUNDED anvil fork: ./script/start-anvil.sh ethereum
/// (the worker deploys + arms the stack), then:
///   forge script script/ethereum/SuperpositionScenario.s.sol --fork-url http://localhost:8547 --broadcast
contract SuperpositionScenario is AnvilScenario {
    constructor() {
        _scenario = "superposition-uni";
    }
}
