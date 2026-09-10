// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AnvilScenario } from "../AnvilScenario.s.sol";

/// @notice Live scenario for the aave adapter.
/// Run against a FUNDED anvil fork: ./anvil-scripts/start-anvil.sh base
/// (then Deploy.s.sol once for this chain), then:
///   forge script script/base/AaveScenario.s.sol --fork-url http://localhost:8545 --broadcast
contract AaveScenario is AnvilScenario {
    constructor() {
        _scenario = "aave";
    }
}
