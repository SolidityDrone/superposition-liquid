// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AggregatorV3Interface } from "src/interfaces/AggregatorV3Interface.sol";

contract MockAggregator is AggregatorV3Interface {
    int256 public answer = 2000e8;
    uint8 public decimalsOverride = 8;
    uint256 public updatedAt = block.timestamp;

    function setAnswer(int256 _answer) external {
        answer = _answer;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function setDecimals(uint8 _decimals) external {
        decimalsOverride = _decimals;
    }

    function decimals() external view returns (uint8) {
        return decimalsOverride;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 ans, uint256 startedAt, uint256 stamp, uint80 answeredInRound)
    {
        return (1, answer, 0, updatedAt, 1);
    }
}
