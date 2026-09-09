// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal Stargate V2 mocks (verified against the real Pool/Staking sources):
///   - Pool.deposit(receiver, amountLD): mints LP 1:1 to receiver (instant)
///   - Pool.redeem(amountLD, receiver): burns LP 1:1 from caller, sends underlying,
///     REVERTS via decreaseCredit if the local credit is insufficient
///   - Staking.deposit(token, amount): pulls LP via transferFrom, rewards settle on update
///   - Staking.withdraw(token, amount): INSTANT return of LP to msg.sender
contract MockStargatePool is ERC20 {
    IERC20 public immutable TOKEN; // underlying (USDC)
    address internal staking;

    function token() external view returns (address) {
        return address(TOKEN);
    }

    function lpToken() external view returns (address) {
        return address(this); // the mock pool is itself the LP token
    }

    /// @notice the real pool's JIT oracle: min(local credit, LP balance of _owner)
    function redeemable(address _owner) external view returns (uint256) {
        if (_owner == address(0)) return creditLD; // pool-wide credit cap
        return creditLD < balanceOf(_owner) ? creditLD : balanceOf(_owner);
    }

    uint256 public creditLD;

    constructor(IERC20 token) ERC20("Mock SG LP", "mSGLP") {
        TOKEN = token;
    }

    function setStaking(address s) external {
        staking = s;
    }

    function setCreditLD(uint256 amountLD) external {
        creditLD = amountLD;
    }

    function deposit(address _receiver, uint256 _amountLD) external returns (uint256 amountLD) {
        IERC20(TOKEN).transferFrom(msg.sender, address(this), _amountLD);
        _mint(_receiver, _amountLD); // 1:1
        amountLD = _amountLD;
    }

    function redeem(uint256 _amountLD, address _receiver) external returns (uint256 amountLD) {
        require(creditLD >= _amountLD, "Stargate: insufficient credit");
        creditLD -= _amountLD;
        _burn(msg.sender, _amountLD);
        IERC20(TOKEN).transfer(_receiver, _amountLD);
        amountLD = _amountLD;
    }

    /// @notice the pool's withdrawable cash (underlying sitting in the pool contract)
    function unpooledTokens() external view returns (uint256) {
        return IERC20(TOKEN).balanceOf(address(this));
    }

}

contract MockStargateStaking {
    IERC20 public immutable LP;
    address internal rewarder;

    mapping(address => uint256) public stakedBalanceOf;

    constructor(IERC20 lp) {
        LP = lp;
    }

    function setRewarder(address r) external {
        rewarder = r;
    }

    /// @notice staking deposit: pulls LP from msg.sender (via transferFrom)
    function deposit(IERC20 /* token */, uint256 amount) external {
        IERC20(LP).transferFrom(msg.sender, address(this), amount);
        stakedBalanceOf[msg.sender] += amount;
        if (rewarder != address(0)) MockRewarder(rewarder).onUpdate(msg.sender, stakedBalanceOf[msg.sender]);
    }

    /// @notice INSTANT unstake: pure accounting + LP back to msg.sender in the same tx
    function withdraw(IERC20 /* token */, uint256 amount) external {
        require(stakedBalanceOf[msg.sender] >= amount, "insufficient staked");
        stakedBalanceOf[msg.sender] -= amount;
        IERC20(LP).transfer(msg.sender, amount);
        if (rewarder != address(0)) MockRewarder(rewarder).onUpdate(msg.sender, stakedBalanceOf[msg.sender]);
    }

    /// @notice rewards settle to the staker (the adapter) — per-maker attribution
    function claimable(address /* user */) external view returns (uint256) {
        return 0; // no rewarder configured on Base today (verified on-chain)
    }
}

contract MockRewarder {
    mapping(address => uint256) public lastUpdateBalance;

    function onUpdate(address user, uint256 balance) external {
        lastUpdateBalance[user] = balance;
    }
}

contract MockToken is ERC20 {
    constructor(string memory name) ERC20(name, name) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
