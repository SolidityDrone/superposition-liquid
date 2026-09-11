// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";
import { ISuperpositionHook } from "./ISuperpositionHook.sol";

/// @title SuperpositionUniAdapter
/// @notice ILendingAdapter over a SuperpositionHook pool. The maker holds the hook's
///         ERC-1155 bucket shares and approves this adapter as an operator; the adapter
///         routes JIT deposits into a fixed one-sided bucket per token and JIT-withdraws
///         on the maker's behalf.
/// @dev Two one-sided buckets: `underlying0` (the pool's currency0) sits in a range above
///      spot (token0 only), `underlying1` (currency1) below spot (token1 only).
contract SuperpositionUniAdapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;

    struct Side {
        int24 lower;
        int24 upper;
        bool isToken0;
        bool set;
    }

    error UnknownUnderlying();
    error NotRouter();

    /// @notice The only caller allowed to trigger withdrawals (the SwapVM router).
    address public immutable ROUTER;
    /// @notice The Superposition hook.
    ISuperpositionHook public immutable HOOK;
    /// @notice Per-underlying bucket config.
    mapping(address underlying => Side) public sideOf;

    constructor(
        address hook,
        address router,
        address underlying0,
        int24 lower0,
        int24 upper0,
        address underlying1,
        int24 lower1,
        int24 upper1
    ) {
        HOOK = ISuperpositionHook(hook);
        ROUTER = router;
        sideOf[underlying0] = Side({ lower: lower0, upper: upper0, isToken0: true, set: true });
        sideOf[underlying1] = Side({ lower: lower1, upper: upper1, isToken0: false, set: true });
    }

    function name() external pure returns (string memory) {
        return "SuperpositionUniHook";
    }

    function yieldToken(address) external view returns (address) {
        return HOOK.shareToken();
    }

    /// @notice Underlying per 1e18 bucket shares (claim / total shares, 1e18).
    function exchangeRate(address underlying) public view returns (uint256) {
        Side memory s = _side(underlying);
        (uint256 shares, uint256 c0, uint256 c1) = _bucket(s);
        if (shares == 0) return WAD;
        uint256 claim = s.isToken0 ? c0 : c1;
        return claim * WAD / shares;
    }

    /// @notice Shares covering `amount` underlying, rounded up.
    function underlyingToYield(address underlying, uint256 amount) public view returns (uint256) {
        Side memory s = _side(underlying);
        (uint256 shares, uint256 c0, uint256 c1) = _bucket(s);
        if (shares == 0) return amount;
        uint256 claim = s.isToken0 ? c0 : c1;
        return (amount * shares + claim - 1) / claim;
    }

    /// @notice Underlying claim of `yieldAmount` shares.
    function yieldToUnderlying(address underlying, uint256 yieldAmount) external view returns (uint256) {
        Side memory s = _side(underlying);
        (uint256 shares, uint256 c0, uint256 c1) = _bucket(s);
        if (shares == 0) return yieldAmount;
        uint256 claim = s.isToken0 ? c0 : c1;
        return yieldAmount * claim / shares;
    }

    /// @notice Empty: bucket shares are delegated, never pulled from the maker wallet.
    function pullPlan(address, address, uint256) external pure returns (address, uint256, address) {
        return (address(0), 0, address(0));
    }

    /// @notice The maker's claim in the bucket, clamped to the hook's real liquidity.
    function maxWithdrawable(address maker, address underlying) public view returns (uint256) {
        Side memory s = _side(underlying);
        (uint256 shares, uint256 c0, uint256 c1) = _bucket(s);
        if (shares == 0) return 0;
        uint256 claim = s.isToken0 ? c0 : c1;
        uint256 makerShares = HOOK.sharesOf(maker, s.lower, s.upper);
        uint256 amount = makerShares * claim / shares;
        (uint256 r0, uint256 r1) = HOOK.currentBalance();
        uint256 real = s.isToken0 ? r0 : r1;
        return amount < real ? amount : real;
    }

    /// @notice Routes `amount` of `underlying` (already transferred to this adapter by the
    ///         router) into the token's one-sided bucket, minting ERC-1155 shares to `maker`.
    function deposit(address maker, address underlying, uint256 amount) external {
        Side memory s = _side(underlying);
        IERC20(underlying).forceApprove(address(HOOK), amount);
        if (s.isToken0) {
            HOOK.deposit(
                ISuperpositionHook.DepositParams({
                    tickLower: s.lower,
                    tickUpper: s.upper,
                    amount0Desired: amount,
                    amount1Desired: 0,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: maker
                })
            );
        } else {
            HOOK.deposit(
                ISuperpositionHook.DepositParams({
                    tickLower: s.lower,
                    tickUpper: s.upper,
                    amount0Desired: 0,
                    amount1Desired: amount,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: maker
                })
            );
        }
    }

    /// @notice Burns `maker`'s bucket shares (this adapter is an ERC-1155 operator) and
    ///         delivers the underlying to `recipient`. Router-only.
    function withdraw(
        address maker,
        address underlying,
        uint256 amountOut,
        uint256,
        address recipient
    ) external {
        if (msg.sender != ROUTER) revert NotRouter();
        Side memory s = _side(underlying);
        (uint256 shares, uint256 c0, uint256 c1) = _bucket(s);
        require(shares > 0, "no bucket");
        uint256 claim = s.isToken0 ? c0 : c1;
        uint256 shareAmount = (amountOut * shares + claim - 1) / claim; // round up
        HOOK.withdraw(
            ISuperpositionHook.WithdrawParams({
                tickLower: s.lower,
                tickUpper: s.upper,
                owner: maker,
                shareAmount: shareAmount,
                recipient: recipient
            })
        );
    }

    function _side(address underlying) internal view returns (Side memory s) {
        s = sideOf[underlying];
        if (!s.set) revert UnknownUnderlying();
    }

    function _bucket(Side memory s) internal view returns (uint256 shares, uint256 c0, uint256 c1) {
        ISuperpositionHook.Bucket[] memory bs = HOOK.getBuckets();
        for (uint256 i = 0; i < bs.length; i++) {
            if (bs[i].lower == s.lower && bs[i].upper == s.upper) {
                return (bs[i].shares, bs[i].c0, bs[i].c1);
            }
        }
        return (0, 0, 0);
    }
}
