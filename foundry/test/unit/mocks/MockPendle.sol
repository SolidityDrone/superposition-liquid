// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal Pendle V2 PY-system mock (post-maturity redemption flow):
///   1. adapter sends PT to the YT contract
///   2. YT.redeemPY(user) burns ALL PT the YT holds and credits SY to user
///   3. SY.redeem burns SY from the caller and pays the underlying 1:1
contract MockPendlePT is ERC20 {
    address public YT;
    uint256 public immutable expiry;

    constructor(uint256 expiry_) ERC20("Mock PT", "mPT") {
        expiry = expiry_;
    }

    function setYt(address yt) external {
        YT = yt;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockPendleYieldToken {
    MockPendlePT public immutable PT;
    address internal sy;

    constructor(MockPendlePT pt) {
        PT = pt;
    }

    function setSy(address syAddress) external {
        sy = syAddress;
    }

    /// @notice burns ALL PT held by this contract and credits SY to the user — matches
    /// the real Pendle YT.redeemPY behavior
    function redeemPY(address userToCredit) external returns (uint256 syOut) {
        uint256 ptBalance = IERC20(address(PT)).balanceOf(address(this));
        require(ptBalance > 0, "no PT to redeem");
        PT.burn(address(this), ptBalance);
        MockPendleSY(sy).credit(userToCredit, ptBalance);
        return ptBalance;
    }
}

contract MockPendleSY is ERC20 {
    address public immutable UNDERLYING;
    address internal yt;

    constructor(address underlying) ERC20("Mock SY", "mSY") {
        UNDERLYING = underlying;
    }

    function setYt(address ytAddress) external {
        yt = ytAddress;
    }

    function credit(address to, uint256 amount) external {
        require(msg.sender == yt, "only YT");
        _mint(to, amount);
    }

    function redeem(
        address receiver,
        uint256 amountShareToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool /* burnAsReward */
    ) external returns (uint256 tokenOutAmount) {
        require(tokenOut == UNDERLYING, "unsupported tokenOut");
        _burn(msg.sender, amountShareToRedeem);
        tokenOutAmount = amountShareToRedeem; // 1:1 (aUSDC-style asset at v3.2 displayed rate)
        require(tokenOutAmount >= minTokenOut, "min out");
        IERC20(UNDERLYING).transfer(receiver, tokenOutAmount);
    }
}

contract MockPendleMarket {
    address public immutable SY;
    address public immutable PT;
    address public immutable YT;
    bool public immutable expired;

    constructor(address sy, address pt, address yt, bool isExpired) {
        SY = sy;
        PT = pt;
        YT = yt;
        expired = isExpired;
    }

    function readTokens() external view returns (address, address, address) {
        return (SY, PT, YT);
    }

    function isExpired() external view returns (bool) {
        return expired;
    }
}

contract MockToken is ERC20 {
    constructor(string memory name) ERC20(name, name) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
