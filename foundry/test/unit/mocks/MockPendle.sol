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

    /// @notice test-only: direct SY minting (real SY mints via deposit)
    function mint(address to, uint256 amount) external {
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

/// @notice ACTIVE-market mock: PT/SY swap with the Pendle callback pattern.
/// The market sends SY out first, then calls back on the caller to collect the PT.
contract MockActiveMarket {
    MockPendlePT public immutable PT;
    address public immutable SY;
    address public immutable YT;
    // pt price in SY units (18 dec), e.g. 0.95e18 for a 5% implied yield
    uint256 public ptPrice = 95e16;

    constructor(MockPendlePT pt, address sy, address yt) {
        PT = pt;
        SY = sy;
        YT = yt;
    }

    function readTokens() external view returns (address, address, address) {
        return (SY, address(PT), YT);
    }

    function setPtPrice(uint256 price) external {
        ptPrice = price;
    }

    function isExpired() external view returns (bool) {
        return false;
    }

    /// @notice fund the market with SY inventory
    function seed(uint256 amount) external {
        IERC20(SY).transferFrom(msg.sender, address(this), amount);
    }

    function swapExactPtForSy(address receiver, uint256 exactPtIn, bytes calldata data)
        external
        returns (uint256 netSyOut, uint256 netSyFee)
    {
        netSyOut = exactPtIn * ptPrice / 1e18;
        IERC20(SY).transfer(receiver, netSyOut);
        IPMarketSwapCallbackLike(msg.sender).swapCallback(-int256(exactPtIn), int256(netSyOut), data);
        require(IERC20(address(PT)).balanceOf(address(this)) >= exactPtIn, "PT not received");
        data; netSyFee;
    }
}

interface IPMarketSwapCallbackLike {
    function swapCallback(int256 ptToAccount, int256 syToAccount, bytes calldata data) external;
}

/// @notice PendlePYLpOracle mock: settable PT->asset rate
contract MockPendleOracle {
    uint256 public rate = 95e16;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function getPtToAssetRate(address /* market */, uint32 /* duration */ ) external view returns (uint256) {
        return rate;
    }

    /// @notice the adapter denominates the rate in the DELIVERABLE (SY redeems 1:1)
    function getPtToSyRate(address /* market */, uint32 /* duration */ ) external view returns (uint256) {
        return rate;
    }
}

contract MockPendleMarket {
    address public immutable SY;
    address public immutable PT;
    address public immutable YT;
    bool public immutable expired;

    constructor(address sy, address pt, address yt, bool expired_) {
        SY = sy;
        PT = pt;
        YT = yt;
        expired = expired_;
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
