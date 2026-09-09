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
/// @dev Restrict this adapter to EXPIRED markets (verified at deploy) so PT redemption is
///      exactly 1:1 and exchangeRate is constant. Active markets trade PT at a discount
///      (implied yield) and would need the Pendle AMM as a swap leg — v0.2.
contract PendlePTAdapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    IERC20 public immutable PT;
    IPYieldTokenLike public immutable YT;
    ISYLike public immutable SY;
    address public immutable ASSET; // final deliverable (e.g. USDC, from SY-aUSDC)
    address public immutable PASSTHROUGH; // the other strategy side (e.g. WETH)

    error MarketNotExpired();
    error UnsupportedAsset();
    error PendleRedemptionShortfall();

    uint256 internal constant PT_PULL_BUFFER = 100; // covers PT->SY->token rounding dust

    /// @param market expired Pendle market; PT/SY discovered from the market itself
    constructor(address market, address asset, address passthrough) {
        (address sy, address pt,) = IPMarketLike(market).readTokens();
        if (!IPMarketLike(market).isExpired()) revert MarketNotExpired();
        PT = IERC20(pt);
        YT = IPYieldTokenLike(IPPrincipalTokenLike(pt).YT());
        SY = ISYLike(sy);
        ASSET = asset;
        PASSTHROUGH = passthrough;
    }

    function name() external pure returns (string memory) {
        return "PendlePT";
    }

    function yieldToken(address underlying) external view returns (address) {
        return underlying == ASSET ? address(PT) : underlying; // passthrough for foreign sides
    }

    /// @notice post-maturity PT redeems 1:1 for the asset, and the SY redeems 1:1 for the
    /// underlying (v3.2 displayed balances) — rate constant at 1e18.
    function exchangeRate(address underlying) external view returns (uint256) {
        underlying; // same rate for asset and passthrough
        return 1e18;
    }

    function underlyingToYield(address underlying, uint256 amount) external view returns (uint256) {
        underlying; // 1:1 for both sides post-maturity
        return amount;
    }

    function yieldToUnderlying(address underlying, uint256 amount) external view returns (uint256) {
        underlying;
        return amount;
    }

    function withdrawTo(address maker, address underlying, uint256 underlyingAmount, address recipient) external {
        if (underlying != ASSET) return; // passthrough: Aqua's default transfer delivers
        // Pendle post-maturity redemption chain (official router pattern):
        // PT -> YT contract -> YT.redeemPY() -> SY -> SY.redeem(underlying) -> deliver
        // A tiny PT buffer covers the PT->SY->token rounding dust; the surplus
        // returns to the maker wallet after the exact delivery.
        uint256 ptAmount = underlyingAmount + PT_PULL_BUFFER;
        IERC20(PT).safeTransferFrom(maker, address(YT), ptAmount);
        uint256 syOut = YT.redeemPY(address(this));
        uint256 out = SY.redeem(address(this), syOut, underlying, 0, false);
        if (out + PT_PULL_BUFFER < underlyingAmount) revert PendleRedemptionShortfall();
        IERC20(underlying).safeTransfer(recipient, underlyingAmount);
        uint256 surplus = IERC20(underlying).balanceOf(address(this));
        if (surplus > 0) IERC20(underlying).safeTransfer(maker, surplus);
    }

    /// @notice no-op: an expired PT cannot be re-minted. Fill revenue (tokenIn) stays in
    /// the maker wallet — the fixed yield was already locked when the PT was bought.
    function depositFor(address maker, address underlying, uint256 underlyingAmount) external {
        if (underlying != ASSET) return; // passthrough: revenue stays in the maker wallet
        underlying; maker; underlyingAmount;
    }

    function maxWithdrawable(address maker, address underlying) external view returns (uint256) {
        if (underlying == ASSET) return PT.balanceOf(maker); // 1:1 at live rate
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
