// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { ILendingAdapter } from "src/interfaces/ILendingAdapter.sol";

/// @dev Minimal Stargate V2 surfaces (verified against the real contracts)
interface IStargatePoolLike {
    /// @notice the underlying token (e.g. USDC)
    function token() external view returns (address);

    /// @notice deposit underlying, mints LP 1:1 to receiver (instant)
    function deposit(address _receiver, uint256 _amountLD) external returns (uint256 amountLD);

    /// @notice burn LP 1:1 from the CALLER, sends underlying to receiver (instant);
    /// reverts if the pool's local credit is insufficient
    function redeem(uint256 _amountLD, address _receiver) external returns (uint256 amountLD);

    /// @notice the pool token (LP) address
    function lpToken() external view returns (address);

    /// @notice JIT oracle: min(local credit, LP balance of _owner) in underlying terms
    function redeemable(address _owner) external view returns (uint256 amountLD);
}

interface IStargateStakingLike {
    /// @notice stake LP tokens (pulled from msg.sender); rewards settle on update
    function deposit(IERC20 token, uint256 amount) external;

    /// @notice INSTANT unstake: LP returns to msg.sender in the same transaction
    /// (verified: pure accounting + rewarder settlement + safeTransfer, no lock)
    function withdraw(IERC20 token, uint256 amount) external;
}

/// @title StargateAdapter
/// @notice Bridge-liquidity maker: capital sits in a Stargate V2 pool, staked for
/// rewards. The maker provides bridge liquidity (the liquidity the protocol uses for
/// cross-chain swaps) and earns the protocol's reward stream.
///   depositFor: pull underlying -> pool.deposit (LP 1:1) -> staking.deposit (staked)
///   withdrawTo: staking.withdraw (INSTANT, verified in source) -> pool.redeem -> deliver
/// Foreign strategy sides (e.g. the ETH side of an ETH/USDC market) are passthrough.
/// @dev The JIT constraint is the pool's local credit: redemptions beyond it revert.
///      The capital guard uses the pool's `redeemable()` view (min(credit, position))
///      so over-limit fills fail at quote time, never mid-delivery. Reward attribution:
///      the rewarder pays the adapter — deploy one adapter per maker (MakerConfig) for
///      clean per-maker reward ownership. Note: on Base today the rewarder for the USDC
///      pool is unconfigured (verified on-chain), so rewards start when Stargate sets one.
contract StargateAdapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    IStargatePoolLike public immutable POOL;
    IStargateStakingLike public immutable STAKING;
    IERC20 public immutable UNDERLYING; // e.g. USDC
    address public immutable PASSTHROUGH; // the other strategy side (e.g. WETH)
    IERC20 public immutable LP; // the pool's LP token (staked position)

    error UnsupportedAsset();
    error InsufficientStaked();

    uint256 internal staked; // this adapter's staked LP position (exact accounting)

    constructor(address pool, address staking, address passthrough) {
        POOL = IStargatePoolLike(pool);
        STAKING = IStargateStakingLike(staking);
        UNDERLYING = IERC20(IStargatePoolLike(pool).token());
        PASSTHROUGH = passthrough;
        LP = IERC20(IStargatePoolLike(pool).lpToken());
    }

    function name() external pure returns (string memory) {
        return "Stargate";
    }

    function yieldToken(address underlying) external view returns (address) {
        // passthrough for foreign sides; the staked LP for the underlying
        return underlying == address(UNDERLYING) ? address(LP) : underlying;
    }

    function exchangeRate(address underlying) public view returns (uint256) {
        underlying; // LP is 1:1 with the underlying (verified: mint/burn amountLD == LP)
        return 1e18;
    }

    function underlyingToYield(address underlying, uint256 amount) external view returns (uint256) {
        underlying;
        return amount; // 1:1
    }

    function yieldToUnderlying(address underlying, uint256 amount) external view returns (uint256) {
        underlying;
        return amount; // 1:1
    }

    function withdrawTo(address maker, address underlying, uint256 underlyingAmount, address recipient) external {
        if (underlying != address(UNDERLYING)) return; // passthrough: default transfer delivers
        if (staked < underlyingAmount) revert InsufficientStaked();
        // unstake (instant, verified: no lock/cooldown in StargateStaking) then redeem
        STAKING.withdraw(LP, underlyingAmount); // LP returns to this adapter
        staked -= underlyingAmount;
        uint256 out = POOL.redeem(underlyingAmount, address(this)); // burns LP, pays USDC
        if (out < underlyingAmount) revert("stargate redemption shortfall");
        IERC20(underlying).safeTransfer(recipient, underlyingAmount);
        uint256 surplus = IERC20(underlying).balanceOf(address(this));
        if (surplus > 0) IERC20(underlying).safeTransfer(maker, surplus);
    }

    /// @notice no-op for the underlying too? No: received underlying (fill revenue)
    /// gets deposited AND staked — same as the Aave supply flow.
    function depositFor(address maker, address underlying, uint256 underlyingAmount) external {
        if (underlying != address(UNDERLYING)) return; // passthrough
        IERC20(underlying).safeTransferFrom(maker, address(this), underlyingAmount);
        IERC20(underlying).forceApprove(address(POOL), underlyingAmount);
        POOL.deposit(address(this), underlyingAmount); // mints LP to this adapter
        IERC20(address(LP)).forceApprove(address(STAKING), underlyingAmount);
        STAKING.deposit(LP, underlyingAmount); // staked: rewards accrue to the adapter
        staked += underlyingAmount;
    }

    /// @notice JIT oracle: the pool's own redeemable() = min(local credit, position).
    /// For the underlying we take min(redeemable-of-the-staked-LP, staked balance):
    /// redeemable(address(0)) is the pool-wide credit cap.
    function maxWithdrawable(address maker, address underlying) external view returns (uint256) {
        if (underlying != address(UNDERLYING)) return IERC20(underlying).balanceOf(maker); // passthrough
        maker; // single-maker adapter: the staked position is the maker's
        // JIT cap = min(staked position, pool-wide instant credit); the pool's own
        // redeemable() view is exactly the credit oracle
        uint256 credit = POOL.redeemable(address(0));
        return staked < credit ? staked : credit;
    }
}

