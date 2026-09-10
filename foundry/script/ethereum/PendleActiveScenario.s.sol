// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AnvilScenario } from "../AnvilScenario.s.sol";

/// @notice Live scenario for the pendle-active adapter.
/// Run against a FUNDED anvil fork: ./anvil-scripts/start-anvil.sh ethereum
/// (then Deploy.s.sol once for this chain), then:
///   forge script script/ethereum/PendleActiveScenario.s.sol --fork-url http://localhost:8547 --broadcast
contract PendleActiveScenario is AnvilScenario {
    constructor() {
        _scenario = "pendle-active";
    }
}
