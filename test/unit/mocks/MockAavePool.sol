// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DataTypes } from "@aave/core/protocol/libraries/types/DataTypes.sol";

/// @notice Minimal Aave-like pool mock for adapter unit tests.
/// 1:1 aToken accounting with a configurable normalized income (ray) for rate tests.
contract MockAavePool {
    address public immutable A_TOKEN;

    uint256 internal constant RAY = 1e27;

    // asset => normalized income (ray); 1e27 == index of 1.0
    mapping(address asset => uint256) public normalizedIncome;
    mapping(address asset => uint256) public poolBalance;

    constructor(address aToken) {
        A_TOKEN = aToken;
    }

    function setNormalizedIncome(address asset, uint256 income) external {
        normalizedIncome[asset] = income;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 /* referralCode */ ) external {
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        MockAToken(A_TOKEN).mint(onBehalfOf, (amount * RAY) / _income(asset));
        poolBalance[asset] += amount;
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        MockAToken(A_TOKEN).burn(msg.sender, (amount * RAY) / _income(asset));
        poolBalance[asset] -= amount;
        ERC20(asset).transfer(to, amount);
        return amount;
    }

    function getReserveNormalizedIncome(address asset) external view returns (uint256) {
        return _income(asset);
    }

    function getReserveData(address /* asset */ ) external view returns (DataTypes.ReserveData memory) {
        return DataTypes.ReserveData({
            configuration: DataTypes.ReserveConfigurationMap(0),
            liquidityIndex: 0,
            currentLiquidityRate: 0,
            variableBorrowIndex: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: 0,
            aTokenAddress: A_TOKEN,
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
}

contract MockAToken is ERC20 {
    constructor() ERC20("MockAToken", "maT") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
