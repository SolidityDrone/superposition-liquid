// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

/// @dev Minimal Pendle V2 surfaces used here
interface IPYieldTokenLike {
    /// @notice post-maturity: burns ALL PT held by this contract and credits SY to user
    function redeemPY(address userToCredit) external returns (uint256 netSyOut);
}

interface ISYLike {
    /// @notice redeems SY for a supported token (the SY's underlying, e.g. aUSDC -> USDC)
    function redeem(
        address receiver,
        uint256 amountShareToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnAsReward
    ) external returns (uint256 tokenOutAmount);
}

/// @title PendlePTAdapter
/// @notice Fixed-income adapter: maker capital sits in an EXPIRED Pendle PT — a zero-coupon
/// claim redeemable 1:1 for the underlying. Post-maturity redemption is pure Pendle
/// mechanics, no swap legs:
///   withdrawTo: pull PT -> send to the YT contract -> YT.redeemPY() -> SY -> SY.redeem(USDC)
///   depositFor: no-op (an expired PT cannot be re-minted; fill revenue stays in the maker wallet)
/// Foreign strategy sides (e.g. the ETH side of an ETH/USDC market) are passthrough.
///      For ACTIVE (unmatured) markets the adapter supports the real fixed-income flow:
///      PT trades below par (the implied-yield discount) and appreciates toward 1 asset
///      as maturity approaches. Delivery pre-maturity goes through the market's native
///      PT->SY swap (IPMarketSwapCallback pattern) with slippage bounded by a buffer;
///      the YieldAdjustedRateXD opcode captures the fixed-yield accrual via
///      rate(now)/rate(ship) from the PendlePYLpOracle TWAP.
interface IPMarketLike2 {
    function swapExactPtForSy(address receiver, uint256 exactPtIn, bytes calldata data) external returns (uint256 netSyOut, uint256 netSyFee);
}

interface IPMarketSwapCallbackLike {
    /// @notice called by the market during swapExactPtForSy; the adapter owes exactPtIn PT
    function swapCallback(int256 ptToAccount, int256 syToAccount, bytes calldata data) external;
}

interface IPPYLpOracleLike {
    function getPtToSyRate(address market, uint32 duration) external view returns (uint256);
}
contract PendlePTAdapter is ILendingAdapter, IPMarketSwapCallbackLike {
    using SafeERC20 for IERC20;

    IERC20 public immutable PT;
    IPYieldTokenLike public immutable YT;
    ISYLike public immutable SY;
    address public immutable ASSET; // accounting asset (e.g. wstETH, aUSDC)
    address public immutable PASSTHROUGH; // the other strategy side (e.g. WETH/USDC)
    address public immutable MARKET;
    address public immutable ORACLE; // PendlePYLpOracle (active markets); address(0) = expired-only
    uint32 public immutable TWAP_DURATION;

    bool public immutable isExpiredMarket;

    error MarketNotExpired();
    error UnsupportedAsset();
    error PendleRedemptionShortfall();
    error PendleSwapShortfall();
    error CallbackNotMarket();

    uint256 internal constant PT_PULL_BUFFER = 100; // covers PT->SY->token rounding dust
    uint256 internal constant BPS = 10_000;
    uint256 internal constant BUFFER_BPS = 100; // 1% swap-leg buffer, surplus returns to maker

    /// @param market Pendle market (active or expired; PT/SY discovered on-chain)
    /// @param oracle PendlePYLpOracle — required for ACTIVE markets, address(0) for expired
    /// @param twapDuration TWAP duration for the oracle rate (e.g. 900 = 15 min)
    constructor(address market, address asset, address passthrough, address oracle, uint32 twapDuration) {
        (address sy, address pt,) = IPMarketLike(market).readTokens();
        bool expired = IPMarketLike(market).isExpired();
        if (!expired && oracle == address(0)) revert MarketNotExpired();
        PT = IERC20(pt);
        YT = IPYieldTokenLike(IPPrincipalTokenLike(pt).YT());
        SY = ISYLike(sy);
        ASSET = asset;
        PASSTHROUGH = passthrough;
        MARKET = market;
        ORACLE = oracle;
        TWAP_DURATION = twapDuration;
        isExpiredMarket = expired;
    }

    function name() external pure returns (string memory) {
        return "PendlePT";
    }

    function yieldToken(address underlying) external view returns (address) {
        return underlying == ASSET ? address(PT) : underlying; // passthrough for foreign sides
    }

    /// @notice deliverable per 1 PT: expired markets redeem 1:1 (1e18); active markets
    /// price PT at the oracle TWAP rate denominated in the deliverable (getPtToSyRate,
    /// since the SY redeems 1:1 to the strategy token). The implied-yield appreciation
    /// toward par is what the rate0 relative growth captures — see YieldAdjustedRateXD.
    function exchangeRate(address underlying) public view returns (uint256) {
        if (underlying != ASSET) return 1e18; // passthrough
        if (isExpiredMarket) return 1e18;
        return IPPYLpOracleLike(ORACLE).getPtToSyRate(MARKET, TWAP_DURATION);
    }

    function underlyingToYield(address underlying, uint256 amount) external view returns (uint256) {
        if (underlying != ASSET || isExpiredMarket) return amount; // 1:1 post-maturity
        // active: PT = asset / ptToAssetRate, rounded up to cover the delivery
        uint256 rate = exchangeRate(underlying);
        return (amount * 1e18 + rate - 1) / rate;
    }

    function yieldToUnderlying(address underlying, uint256 amount) external view returns (uint256) {
        if (underlying != ASSET || isExpiredMarket) return amount;
        return amount * exchangeRate(underlying) / 1e18;
    }

    function withdrawTo(address maker, address underlying, uint256 underlyingAmount, address recipient) external {
        if (underlying != ASSET) return; // passthrough: Aqua's default transfer delivers
        // buffer: the swap leg loses a small spread vs the oracle rate; surplus returns
        // to the maker wallet after the exact delivery
        // expired: 1:1 redemption, only the rounding dust buffer; active: the market
        // swap leg loses a small spread vs the oracle rate, so pull with a buffer
        uint256 ptAmount = isExpiredMarket
            ? underlyingAmount + PT_PULL_BUFFER
            : this.underlyingToYield(underlying, underlyingAmount * (BPS + BUFFER_BPS) / BPS);

        if (isExpiredMarket) {
            // redemption chain (official router pattern):
            // PT -> YT contract -> YT.redeemPY() -> SY -> SY.redeem(underlying) -> deliver
            IERC20(PT).safeTransferFrom(maker, address(YT), ptAmount);
            uint256 syOut = YT.redeemPY(address(this));
            uint256 out = SY.redeem(address(this), syOut, underlying, 0, false);
            if (out + PT_PULL_BUFFER < underlyingAmount) revert PendleRedemptionShortfall();
        } else {
            // active market: sell PT for SY on the market's AMM (callback pattern),
            // then redeem SY to the underlying
            IERC20(PT).safeTransferFrom(maker, address(this), ptAmount);
            IERC20(PT).forceApprove(address(MARKET), ptAmount);
            IPMarketLike2(MARKET).swapExactPtForSy(address(this), ptAmount, CALLBACK_DATA);
            uint256 syOut = IERC20(SYy()).balanceOf(address(this));
            uint256 out = SY.redeem(address(this), syOut, underlying, 0, false);
            if (out + PT_PULL_BUFFER < underlyingAmount) revert PendleSwapShortfall();
        }
        IERC20(underlying).safeTransfer(recipient, underlyingAmount);
        uint256 surplus = IERC20(underlying).balanceOf(address(this));
        if (surplus > 0) IERC20(underlying).safeTransfer(maker, surplus);
    }

    bytes internal constant CALLBACK_DATA = hex"00"; // market invokes the callback only for non-empty data

    function SYy() internal view returns (address) {
        return address(SY);
    }

    /// @notice Pendle market callback: the market sends SY out first, then pulls the PT
    /// it is owed. Pendle's convention: ptToAccount is NEGATIVE when the caller owes PT.
    /// Only the market may invoke it.
    function swapCallback(int256 ptToAccount, int256 syToAccount, bytes calldata data) external {
        syToAccount; data;
        if (msg.sender != MARKET) revert CallbackNotMarket();
        if (ptToAccount < 0) IERC20(PT).safeTransfer(MARKET, uint256(-ptToAccount));
    }

    /// @notice no-op: an expired PT cannot be re-minted. Fill revenue (tokenIn) stays in
    /// the maker wallet — the fixed yield was already locked when the PT was bought.
    function depositFor(address maker, address underlying, uint256 underlyingAmount) external {
        if (underlying != ASSET) return; // passthrough: revenue stays in the maker wallet
        underlying; maker; underlyingAmount;
    }

    function maxWithdrawable(address maker, address underlying) external view returns (uint256) {
        if (underlying == ASSET) {
            // PT position valued at the live rate (1:1 expired, oracle discount active)
            return PT.balanceOf(maker) * exchangeRate(underlying) / 1e18;
        }
        return IERC20(underlying).balanceOf(maker); // passthrough
    }
}

interface IPMarketLike {
    function readTokens() external view returns (address sy, address pt, address yt);
    function isExpired() external view returns (bool);
}

interface IPPrincipalTokenLike {
    function YT() external view returns (address);
}

