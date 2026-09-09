// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DataTypes } from "@aave/core/protocol/libraries/types/DataTypes.sol";

/// @notice Minimal Aave-like pool mock for adapter unit tests (legacy semantics:
/// displayed == scaled, yield shows up as rate growth via a configurable index).
contract MockAavePool {
    uint256 internal constant RAY = 1e27;

    mapping(address asset => MockAToken) public aTokens;
    // asset => liquidity index (ray); 1e27 == 1.0
    mapping(address asset => uint256) public normalizedIncome;
    mapping(address asset => uint256) public poolBalance;

    function registerAToken(address asset, MockAToken aToken) external {
        aTokens[asset] = aToken;
    }

    function setNormalizedIncome(address asset, uint256 income) external {
        normalizedIncome[asset] = income;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 /* referralCode */ ) external {
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        _aToken(asset).mint(onBehalfOf, (amount * RAY) / _income(asset));
        poolBalance[asset] += amount;
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        _aToken(asset).burn(msg.sender, (amount * RAY) / _income(asset));
        poolBalance[asset] -= amount;
        ERC20(asset).transfer(to, amount);
        return amount;
    }

    function getReserveNormalizedIncome(address asset) external view returns (uint256) {
        return _income(asset);
    }

    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return DataTypes.ReserveData({
            configuration: DataTypes.ReserveConfigurationMap(0),
            liquidityIndex: uint128(_income(asset)),
            currentLiquidityRate: 0,
            variableBorrowIndex: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: 0,
            aTokenAddress: address(aTokens[asset]),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    function _income(address asset) internal view returns (uint256) {
        uint256 income = normalizedIncome[asset];
        return income == 0 ? RAY : income;
    }

    function _aToken(address asset) internal view returns (MockAToken) {
        MockAToken aToken = aTokens[asset];
        return aToken;
    }
}

contract MockAToken is ERC20 {
    constructor() ERC20("MockAToken", "maT") { }

    /// @dev Legacy Aave semantics: displayed == scaled, so both are the raw supply.
    function scaledTotalSupply() external view returns (uint256) {
        return totalSupply();
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
