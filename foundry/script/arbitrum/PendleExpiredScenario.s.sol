// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AnvilScenario } from "../AnvilScenario.s.sol";

/// @notice Live scenario for the pendle-expired adapter.
/// Run against a FUNDED anvil fork: ./anvil-scripts/start-anvil.sh arbitrum
/// (then Deploy.s.sol once for this chain), then:
///   forge script script/arbitrum/PendleExpiredScenario.s.sol --fork-url http://localhost:8546 --broadcast
contract PendleExpiredScenario is AnvilScenario {
    constructor() {
        _scenario = "pendle-expired";
    }
}
