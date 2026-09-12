// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DataTypes } from "@aave/core/protocol/libraries/types/DataTypes.sol";

/// @notice Aave-like pool mock with borrow/repay + account data, for borrow-mode
///         adapter tests (legacy semantics: displayed == scaled, rate via index).
contract MockAaveBorrowPool {
    uint256 internal constant RAY = 1e27;

    mapping(address asset => BorrowAToken) public aTokens;
    mapping(address asset => BorrowDebtToken) public debtTokens;
    mapping(address asset => uint256) public ltvBps; // reserve LTV in basis points
    mapping(address asset => uint256) public normalizedIncome; // ray
    mapping(address asset => uint256) public poolBalance;
    mapping(address user => uint256) public availableBorrowsBase; // base currency (8 dec)

    address public provider;
    bool public failSupply;

    function registerAToken(address asset, BorrowAToken aToken) external {
        aTokens[asset] = aToken;
    }

    function setFailSupply(bool v) external {
        failSupply = v;
    }

    function registerDebtToken(address asset, BorrowDebtToken debtToken) external {
        debtTokens[asset] = debtToken;
    }

    function setLtv(address asset, uint256 bps) external {
        ltvBps[asset] = bps;
    }

    function setNormalizedIncome(address asset, uint256 income) external {
        normalizedIncome[asset] = income;
    }

    function setAvailableBorrowsBase(address user, uint256 amount) external {
        availableBorrowsBase[user] = amount;
    }

    function setProvider(address p) external {
        provider = p;
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /* referralCode */
    )
        external
    {
        require(!failSupply, "51"); // 51 = Aave SUPPLY_CAP_EXCEEDED
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        aTokens[asset].mint(onBehalfOf, (amount * RAY) / _income(asset));
        poolBalance[asset] += amount;
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        aTokens[asset].burn(msg.sender, (amount * RAY) / _income(asset));
        poolBalance[asset] -= amount;
        ERC20(asset).transfer(to, amount);
        return amount;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256,
        /* rateMode */
        uint16,
        /* referral */
        address onBehalfOf
    )
        external
    {
        poolBalance[asset] -= amount;
        debtTokens[asset].mint(onBehalfOf, amount);
        ERC20(asset).transfer(msg.sender, amount);
    }

    function repay(
        address asset,
        uint256 amount,
        uint256,
        /* rateMode */
        address onBehalfOf
    )
        external
        returns (uint256)
    {
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        debtTokens[asset].burn(onBehalfOf, amount);
        poolBalance[asset] += amount;
        return amount;
    }

    function getUserAccountData(address user)
        external
        view
        returns (uint256, uint256, uint256 availableBase, uint256, uint256, uint256)
    {
        return (0, 0, availableBorrowsBase[user], 0, 0, type(uint256).max);
    }

    function ADDRESSES_PROVIDER() external view returns (address) {
        return provider;
    }

    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return DataTypes.ReserveData({
            configuration: DataTypes.ReserveConfigurationMap(ltvBps[asset]),
            liquidityIndex: uint128(_income(asset)),
            currentLiquidityRate: 0,
            variableBorrowIndex: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: 0,
            aTokenAddress: address(aTokens[asset]),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(debtTokens[asset]),
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

contract BorrowAToken is ERC20 {
    constructor() ERC20("BorrowAToken", "baT") { }

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

contract BorrowDebtToken is ERC20 {
    constructor() ERC20("BorrowDebtToken", "bDebt") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockAaveOracle {
    mapping(address asset => uint256) public prices; // base currency, 8 decimals

    function setAssetPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }
}

contract MockAaveAddressesProvider {
    address public oracle;

    function setPriceOracle(address o) external {
        oracle = o;
    }

    function getPriceOracle() external view returns (address) {
        return oracle;
    }
}
