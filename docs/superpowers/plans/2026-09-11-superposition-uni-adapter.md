# Superposition Uni Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `SuperpositionUniAdapter` that lets a Supercazzola maker hold one-sided, yield-bearing USDC/USDT buckets on a Uniswap v4 Superposition hook, with the adapter acting as an approved ERC-1155 operator for JIT deposit/withdraw.

**Architecture:** The maker holds the hook's ERC-1155 bucket shares and `setApprovalForAll`s the adapter. `deposit` routes a received token into its fixed one-sided bucket (minting ERC-1155 to the maker); `withdraw` (router-only) burns the maker's shares via the operator delegation and delivers the underlying. `pullPlan` is empty because no token moves out of the wallet. The hook self-deploys inside `DeployAndSetup` on Ethereum.

**Tech Stack:** Solidity 0.8.30, Foundry, Uniswap v4-core/v4-periphery, Aave v3, 1inch SwapVM/Aqua, OpenZeppelin 5.x.

## Global Constraints

- Solidity `0.8.30`, pinned in `foundry.toml` (`solc_version = "0.8.30"`, `via_ir = true`, `optimizer_runs = 700`). Do not add files with a pragma that cannot compile under 0.8.30.
- Naming: folder `foundry/src/adapters/superposition-uni-hook/`, adapter `SuperpositionUniAdapter`, `name()` = `"SuperpositionUniHook"`, enum value `AdapterKind.SuperpositionUniHook`.
- Chain under test: **Ethereum mainnet** fork. RPC env `RPC_URL_ETH`, default `https://ethereum-rpc.publicnode.com`.
- Fixed addresses:
  - v4 `PoolManager` `0x000000000004444c5dc75cB358380D2e3dE08A90`
  - Aave v3 `Pool` `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2`
  - USDC `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` / aUSDC `0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c`
  - USDT `0xdAC17F958D2ee523a2206206994597C13D831ec7` / aUSDT `0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a`
  - Aqua `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a`
  - WETH (router arg) `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
- Pool: `currency0 = USDC`, `currency1 = USDT`, `fee = 100`, `tickSpacing = 1`, initialized at `sqrtPriceX96 = 2**96` (= price 1.0).
- Buckets: USDC (token0) range `[1, 101]` (above spot, token0-only); USDT (token1) range `[-101, -1]` (below spot, token1-only).
- Hook repo pinned at commit `959d26a`; v4-core at `e50237c43811bd9b526eff40f26772152a42daba`; v4-periphery at `dce236d4e2057422d0791d9a973a58765eb46f65`.
- Security amendment (in addition to the design spec): the adapter as ERC-1155 operator can only be exercised by the router. `withdraw` reverts `NotRouter()` unless `msg.sender == ROUTER`, because the hook authorizes the adapter, not the caller.
- Commits go on branch `superposition-hook-uni-v4`. Do not push without the user's explicit approval.

---

## File Structure

- Create `foundry/remappings.txt` entries for the new libs.
- Create `foundry/src/adapters/superposition-uni-hook/ISuperpositionHook.sol` — minimal hook ABI (no v4 imports).
- Create `foundry/src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol` — the adapter.
- Modify `foundry/src/config/MakerConfig.sol` — add enum value.
- Create `foundry/test/helpers/SuperpositionFixture.sol` — deploy the real hook on an Ethereum fork.
- Create `foundry/test/fork/EthereumForkSuperposition.t.sol` — the fork suite.
- Modify `foundry/script/DeployAndSetup.s.sol` — self-deploy hook + adapter on ethereum.
- Create `foundry/script/ethereum/SuperpositionScenario.s.sol` — anvil demo.
- Modify `foundry/script/start-anvil.sh` — fund USDT on ethereum.
- Create `docs/superposition-uni-adapter.md`; modify `README.md`.

---

### Task 1: Dependencies + hook deploys on an Ethereum fork

**Files:**
- Create: `foundry/test/helpers/SuperpositionFixture.sol`
- Create: `foundry/test/fork/EthereumForkSuperposition.t.sol`
- Modify: `foundry/remappings.txt`
- Modify: `.gitmodules` (via `git submodule add`)

**Interfaces:**
- Produces: `SuperpositionFixture._deployHook(uint24 fee, int24 spacing, uint160 sqrtPriceX96) returns (SuperpositionHook hook)`; constants `USDC`, `USDT`, `AUSDC`, `AUSDT`, `AAVE`, `PM`.

- [ ] **Step 1: Add the submodules**

```bash
cd /home/drone/projects/superposition
git submodule add https://github.com/Uniswap/v4-core foundry/lib/v4-core
git -C foundry/lib/v4-core fetch --depth 1 origin e50237c43811bd9b526eff40f26772152a42daba
git -C foundry/lib/v4-core checkout e50237c43811bd9b526eff40f26772152a42daba
git submodule add https://github.com/Uniswap/v4-periphery foundry/lib/v4-periphery
git -C foundry/lib/v4-periphery fetch --depth 1 origin dce236d4e2057422d0791d9a973a58765eb46f65
git -C foundry/lib/v4-periphery checkout dce236d4e2057422d0791d9a973a58765eb46f65
git submodule add https://github.com/SolidityDrone/superposition-hook-uni-v4 foundry/lib/superposition-hook
git -C foundry/lib/superposition-hook fetch --depth 1 origin 959d26a
git -C foundry/lib/superposition-hook checkout 959d26a
```

- [ ] **Step 2: Add remappings**

Append to `foundry/remappings.txt`:

```
@uniswap/v4-core/=lib/v4-core/
@uniswap/v4-periphery/=lib/v4-periphery/
superposition-hook/=lib/superposition-hook/superposition-uni-v4-hook/src/
```

- [ ] **Step 3: Write the fixture**

Create `foundry/test/helpers/SuperpositionFixture.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { HookMiner } from "superposition-hook/libraries/HookMiner.sol";

/// @dev Deploys the REAL SuperpositionHook on an Ethereum mainnet fork.
abstract contract SuperpositionFixture is Test {
    address internal constant PM = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant AAVE = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant AUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address internal constant AUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
    uint160 internal constant SQRT_PRICE_1_0 = 79228162514264337593543950336; // 2**96

    function _fork() internal {
        vm.createSelectFork(vm.envOr("RPC_URL_ETH", string("https://ethereum-rpc.publicnode.com")));
    }

    function _deployHook(uint24 fee, int24 spacing) internal returns (SuperpositionHook hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args =
            abi.encode(IPoolManager(PM), AAVE, USDC, USDT, AUSDC, AUSDT, fee, spacing, address(this));
        (address predicted, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SuperpositionHook).creationCode, args);
        hook = new SuperpositionHook{salt: salt}(
            IPoolManager(PM), AAVE, USDC, USDT, AUSDC, AUSDT, fee, spacing, address(this)
        );
        require(address(hook) == predicted, "hook address mismatch");
        hook.initializePool(SQRT_PRICE_1_0);
    }
}
```

- [ ] **Step 4: Write the failing test**

Create `foundry/test/fork/EthereumForkSuperposition.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SuperpositionFixture } from "../helpers/SuperpositionFixture.sol";
import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";

contract EthereumForkSuperpositionTest is SuperpositionFixture {
    SuperpositionHook internal hook;

    function setUp() public {
        _fork();
        hook = _deployHook(100, 1);
    }

    function test_fork_hookDeploysAndInitializes() public {
        assertGt(address(hook).code.length, 0);
        assertTrue(hook.initialized());
        assertTrue(hook.shareToken() != address(0));
    }
}
```

- [ ] **Step 5: Run the test**

Run: `cd foundry && forge test --match-path 'test/fork/EthereumForkSuperposition.t.sol' -vv`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
cd /home/drone/projects/superposition
git add .gitmodules foundry/lib/v4-core foundry/lib/v4-periphery foundry/lib/superposition-hook foundry/remappings.txt foundry/test/helpers/SuperpositionFixture.sol foundry/test/fork/EthereumForkSuperposition.t.sol
git commit -m "test: Ethereum fork fixture deploys the Superposition hook"
```

---

### Task 2: `ISuperpositionHook` + adapter views + enum

**Files:**
- Create: `foundry/src/adapters/superposition-uni-hook/ISuperpositionHook.sol`
- Create: `foundry/src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol`
- Modify: `foundry/src/config/MakerConfig.sol:9-15`
- Test: `foundry/test/fork/EthereumForkSuperposition.t.sol`

**Interfaces:**
- Consumes: `SuperpositionFixture._deployHook`.
- Produces: `ISuperpositionHook`, `SuperpositionUniAdapter(address hook, address router, address underlying0, int24 lower0, int24 upper0, address underlying1, int24 lower1, int24 upper1)`; `AdapterKind.SuperpositionUniHook`.

- [ ] **Step 1: Write the minimal hook interface**

Create `foundry/src/adapters/superposition-uni-hook/ISuperpositionHook.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ISuperpositionHook
/// @notice Minimal ABI of SuperpositionHook (SolidityDrone/superposition-hook-uni-v4),
///         field-for-field compatible. No Uniswap v4 imports.
interface ISuperpositionHook {
    struct DepositParams {
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
    }

    struct WithdrawParams {
        int24 tickLower;
        int24 tickUpper;
        address owner;
        uint256 shareAmount;
        address recipient;
    }

    struct Bucket {
        int24 lower;
        int24 upper;
        uint128 liquidity;
        uint256 shares;
        uint256 c0;
        uint256 c1;
        bool active;
    }

    function deposit(DepositParams calldata p) external returns (uint256 sharesMinted);
    function withdraw(WithdrawParams calldata p) external returns (uint256 wethOut, uint256 usdcOut);
    function sharesOf(address user, int24 lower, int24 upper) external view returns (uint256);
    function getBuckets() external view returns (Bucket[] memory);
    function shareToken() external view returns (address);
    function currentBalance() external view returns (uint256 wethAmt, uint256 usdcAmt);
    function syncYield() external;
}
```

- [ ] **Step 2: Add the enum value**

In `foundry/src/config/MakerConfig.sol`, change:

```solidity
enum AdapterKind {
    None,
    AaveV3,
    ERC4626,
    Stargate,
    PendlePT
}
```

to:

```solidity
enum AdapterKind {
    None,
    AaveV3,
    ERC4626,
    Stargate,
    PendlePT,
    SuperpositionUniHook
}
```

- [ ] **Step 3: Write the adapter skeleton (views only)**

Create `foundry/src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol`:

```solidity
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

    function deposit(address, address, uint256) external pure {
        revert("not implemented");
    }

    function withdraw(address, address, uint256, uint256, address) external pure {
        revert("not implemented");
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
```

- [ ] **Step 4: Write the failing test**

Add to `foundry/test/fork/EthereumForkSuperposition.t.sol`:

```solidity
import { SuperpositionUniAdapter } from "src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol";
import { MakerConfig, AdapterKind, SideConfig } from "src/config/MakerConfig.sol";
```

and:

```solidity
    function test_fork_adapterViewsOnEmptyBucket() public {
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), address(0xBEEF), USDC, 1, 101, USDT, -101, -1);
        assertEq(adapter.name(), "SuperpositionUniHook");
        assertEq(adapter.yieldToken(USDC), hook.shareToken());
        assertEq(adapter.exchangeRate(USDC), 1e18);
        assertEq(adapter.maxWithdrawable(address(0xA11CE), USDC), 0);
        assertEq(AdapterKind.SuperpositionUniHook, AdapterKind.SuperpositionUniHook);
    }
```

- [ ] **Step 5: Run the tests**

Run: `cd foundry && forge test --match-path 'test/fork/EthereumForkSuperposition.t.sol' -vv`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd /home/drone/projects/superposition
git add foundry/src/adapters/superposition-uni-hook foundry/src/config/MakerConfig.sol foundry/test/fork/EthereumForkSuperposition.t.sol
git commit -m "feat: SuperpositionUniAdapter skeleton + ISuperpositionHook"
```

---

### Task 3: Adapter `deposit` (one-sided buckets)

**Files:**
- Modify: `foundry/src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol`
- Test: `foundry/test/fork/EthereumForkSuperposition.t.sol`

**Interfaces:**
- Consumes: `SuperpositionUniAdapter`, `ISuperpositionHook.deposit`.
- Produces: `deposit(address maker, address underlying, uint256 amount)`.

- [ ] **Step 1: Write the failing test**

Add to `EthereumForkSuperposition.t.sol`:

```solidity
    function test_fork_deposit_usdc_oneSided() public {
        address maker = address(0xA11CE);
        deal(USDC, maker, 1_000e6);
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), address(0xBEEF), USDC, 1, 101, USDT, -101, -1);

        vm.startPrank(maker);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).transfer(address(adapter), 1_000e6);
        adapter.deposit(maker, USDC, 1_000e6);
        vm.stopPrank();

        // the maker holds ERC-1155 bucket shares; the hook holds aUSDC
        assertGt(hook.sharesOf(maker, 1, 101), 0);
        assertGt(IERC20(AUSDC).balanceOf(address(hook)), 990e6);
        // the USDT bucket is untouched
        assertEq(hook.sharesOf(maker, -101, -1), 0);
        assertGt(adapter.maxWithdrawable(maker, USDC), 0);
    }
```

Add the import: `import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd foundry && forge test --match-test test_fork_deposit_usdc_oneSided -vv`
Expected: FAIL with `not implemented`.

- [ ] **Step 3: Implement `deposit`**

In `SuperpositionUniAdapter.sol`, replace the `deposit` stub with:

```solidity
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd foundry && forge test --match-test test_fork_deposit_usdc_oneSided -vv`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/drone/projects/superposition
git add foundry/src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol foundry/test/fork/EthereumForkSuperposition.t.sol
git commit -m "feat: SuperpositionUniAdapter deposit into one-sided buckets"
```

---

### Task 4: Adapter `withdraw` + ERC-1155 operator delegation

**Files:**
- Modify: `foundry/src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol`
- Test: `foundry/test/fork/EthereumForkSuperposition.t.sol`

**Interfaces:**
- Consumes: `ISuperpositionHook.withdraw`, `sharesOf`.
- Produces: `withdraw(address maker, address underlying, uint256 amountOut, uint256 yieldAmount, address recipient)`.

- [ ] **Step 1: Write the failing tests**

Add to `EthereumForkSuperposition.t.sol` (add `import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";`):

```solidity
    function _makerWithUsdcDeposit(address maker, address adapter) internal {
        deal(USDC, maker, 1_000e6);
        vm.startPrank(maker);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).transfer(address(adapter), 1_000e6);
        SuperpositionUniAdapter(adapter).deposit(maker, USDC, 1_000e6);
        IERC1155(hook.shareToken()).setApprovalForAll(adapter, true);
        vm.stopPrank();
    }

    function test_fork_withdrawAsOperator() public {
        address maker = address(0xA11CE);
        address router = address(0xBEEF);
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), router, USDC, 1, 101, USDT, -101, -1);
        _makerWithUsdcDeposit(maker, address(adapter));

        uint256 sharesBefore = hook.sharesOf(maker, 1, 101);
        vm.prank(router);
        adapter.withdraw(maker, USDC, 100e6, 0, maker);

        assertApproxEqAbs(IERC20(USDC).balanceOf(maker), 100e6, 2);
        assertLt(hook.sharesOf(maker, 1, 101), sharesBefore);
    }

    function test_fork_withdrawNotOperatorReverts() public {
        address maker = address(0xA11CE);
        address router = address(0xBEEF);
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), router, USDC, 1, 101, USDT, -101, -1);
        deal(USDC, maker, 1_000e6);
        vm.startPrank(maker);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).transfer(address(adapter), 1_000e6);
        adapter.deposit(maker, USDC, 1_000e6);
        vm.stopPrank(); // NB: no setApprovalForAll

        vm.prank(router);
        vm.expectRevert(); // hook: NotAuthorized
        adapter.withdraw(maker, USDC, 100e6, 0, maker);
    }

    function test_fork_withdrawOnlyRouter() public {
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), address(0xBEEF), USDC, 1, 101, USDT, -101, -1);
        vm.expectRevert(SuperpositionUniAdapter.NotRouter.selector);
        adapter.withdraw(address(0xA11CE), USDC, 100e6, 0, address(0xA11CE));
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd foundry && forge test --match-test test_fork_withdraw -vv`
Expected: FAIL with `not implemented`.

- [ ] **Step 3: Implement `withdraw`**

In `SuperpositionUniAdapter.sol`, replace the `withdraw` stub with:

```solidity
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd foundry && forge test --match-test test_fork_withdraw -vv`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/drone/projects/superposition
git add foundry/src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol foundry/test/fork/EthereumForkSuperposition.t.sol
git commit -m "feat: SuperpositionUniAdapter delegated withdraw (router-only)"
```

---

### Task 5: Full Supercazzola JIT fill

**Files:**
- Test: `foundry/test/fork/EthereumForkSuperposition.t.sol`

**Interfaces:**
- Consumes: everything above; `MakerConfig.setSides`, `SupercazzolaRouter`, Aqua.
- Produces: a passing end-to-end test.

- [ ] **Step 1: Write the failing test**

Add imports and the test:

```solidity
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";
```

```solidity
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function test_fork_supercazzolaJitFill() public {
        address maker = address(0xA11CE);
        address taker = address(0xB0B);

        MakerConfig mc = new MakerConfig();
        SupercazzolaRouter router =
            new SupercazzolaRouter(AQUA, WETH, address(this), "SupercazzolaRouter", "1", address(mc));
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), address(router), USDC, 1, 101, USDT, -101, -1);

        // maker LPs USDC into the hook bucket, keeps USDT passthrough
        deal(USDC, maker, 5_000e6);
        deal(USDT, maker, 6_000e6);
        vm.startPrank(maker);
        IERC20(USDC).approve(address(adapter), type(uint256).max);
        IERC20(USDC).transfer(address(adapter), 5_000e6);
        adapter.deposit(maker, USDC, 5_000e6);
        IERC1155(hook.shareToken()).setApprovalForAll(address(adapter), true);
        IERC20(USDC).approve(address(router), type(uint256).max);
        IERC20(USDT).approve(address(router), type(uint256).max);
        IERC20(USDC).approve(AQUA, type(uint256).max);
        IERC20(USDT).approve(AQUA, type(uint256).max);

        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig(USDC, address(adapter), AdapterKind.SuperpositionUniHook, true);
        sides[1] = SideConfig(USDT, address(adapter), AdapterKind.SuperpositionUniHook, true);
        mc.setSides(sides);

        // strategy: maker sells USDC for USDT; USDC virtual backed by the bucket
        ISwapVM.Order memory order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: true,
                hasPreTransferOutHook: true,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(router),
                postTransferInData: "",
                preTransferOutTarget: address(router),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: abi.encodePacked(
                    uint8(YIELD_ADJUSTED_RATE_XD),
                    uint8(104),
                    YieldArgsBuilder.build(USDT, USDC, 1e18, 1e18),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0),
                    uint8(35), uint8(20),
                    CapitalArgsBuilder.build(USDC)
                )
            })
        );
        address[] memory tokens = new address[](2);
        tokens[0] = USDT;
        tokens[1] = USDC;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5_000e6; // USDT virtual (passthrough)
        amounts[1] = 5_000e6; // USDC virtual (bucket-backed)
        IAqua(AQUA).ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopPrank();

        deal(USDT, taker, 1_000e6);
        vm.startPrank(taker);
        IERC20(USDT).approve(address(router), type(uint256).max);
        (uint256 amountIn, uint256 amountOut,) = router.swap(order, USDT, USDC, 1_000e6, _takerTraits());
        vm.stopPrank();

        assertGt(amountOut, 990e6, "USDC out");
        assertEq(IERC20(USDC).balanceOf(taker), amountOut);
        // the USDT revenue was deposited into the USDT bucket
        assertGt(hook.sharesOf(maker, -101, -1), 0);
    }
```

Add the `_takerTraits` helper (copy from `BaseForkStargate.t.sol:157-181` verbatim). Add `import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd foundry && forge test --match-test test_fork_supercazzolaJitFill -vv`
Expected: FAIL (e.g., side not registered, or the guard fails) until approvals/program are correct.

- [ ] **Step 3: Fix until green**

Likely adjustments: the taker-traits `useTransferFromAndAquaPush` flag, the virtual amounts, and the `CapitalArgsBuilder.build(USDC)` arg must match the out token. Iterate with `-vvvv`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd foundry && forge test --match-test test_fork_supercazzolaJitFill -vv`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/drone/projects/superposition
git add foundry/test/fork/EthereumForkSuperposition.t.sol
git commit -m "test: full Supercazzola JIT fill through the Superposition adapter"
```

---

### Task 6: Yield attribution

**Files:**
- Test: `foundry/test/fork/EthereumForkSuperposition.t.sol`

- [ ] **Step 1: Write the failing test**

```solidity
    function test_fork_yieldGrowsClaim() public {
        address maker = address(0xA11CE);
        address router = address(0xBEEF);
        SuperpositionUniAdapter adapter =
            new SuperpositionUniAdapter(address(hook), router, USDC, 1, 101, USDT, -101, -1);
        _makerWithUsdcDeposit(maker, address(adapter));

        uint256 before = adapter.maxWithdrawable(maker, USDC);
        vm.warp(block.timestamp + 365 days);
        hook.syncYield();
        uint256 afterWarp = adapter.maxWithdrawable(maker, USDC);
        assertGt(afterWarp, before, "Aave yield grows the claim");
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd foundry && forge test --match-test test_fork_yieldGrowsClaim -vv`
Expected: FAIL if `vm.warp` does not accrue on the fork snapshot; if so, `vm.roll` the block and check. Adjust with `vm.warp` + a `mock` of the reserve index only if needed.

- [ ] **Step 3: Make it pass**

If the fork's Aave index does not accrue with `vm.warp`, use `vm.warp` to a future timestamp and `vm.roll` forward, or call `hook.syncYield()` after `vm.warp`. The mechanical assertion (claim grows) must hold.

- [ ] **Step 4: Commit**

```bash
cd /home/drone/projects/superposition
git add foundry/test/fork/EthereumForkSuperposition.t.sol
git commit -m "test: Aave yield grows the bucket claim"
```

---

### Task 7: Self-deploy the hook inside `DeployAndSetup` (Ethereum)

**Files:**
- Modify: `foundry/script/DeployAndSetup.s.sol`
- Test: `foundry/test/fork/EthereumForkSuperposition.t.sol` (dry-run assertion)

**Interfaces:**
- Consumes: `HookMiner`, `SuperpositionHook`, `SuperpositionUniAdapter`.
- Produces: artifact fields `SuperpositionHook`, `SuperpositionUniHook`.

- [ ] **Step 1: Add imports and constants**

In `DeployAndSetup.s.sol`:

```solidity
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { SuperpositionHook } from "superposition-hook/SuperpositionHook.sol";
import { HookMiner } from "superposition-hook/libraries/HookMiner.sol";
import { SuperpositionUniAdapter } from "src/adapters/superposition-uni-hook/SuperpositionUniAdapter.sol";

address constant ETH_PM = 0x000000000004444c5dc75cB358380D2e3dE08A90;
address constant ETH_AUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
address constant ETH_AUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78bFb26c0B4956C;
```

- [ ] **Step 2: Deploy hook + adapter in the ethereum branch of `_deploy`**

Replace the ethereum `else` in `_deploy` so that when `chain == "ethereum"` it does:

```solidity
        } else if (_eq(chain, "ethereum")) {
            // self-deploy the Superposition hook conditionally (CREATE2, mined salt)
            address hook = _deploySuperpositionHookIfNeeded(deployerKey);
            address sup = address(
                new SuperpositionUniAdapter(hook, router, ETH_USDC, 1, 101, ETH_USDT, -101, -1)
            );
            vm.stopBroadcast();
            _persist(path, address(mc), router, address(0), address(0), address(0), hook, sup);
        } else {
            vm.stopBroadcast();
            _persist(path, address(mc), router, address(0), address(0), address(0), address(0), address(0));
        }
```

Add helpers:

```solidity
    /// @dev Deploys the Superposition hook on Ethereum if it has no code yet.
    function _deploySuperpositionHookIfNeeded(uint256 deployerKey) internal returns (address hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args = abi.encode(
            IPoolManager(ETH_PM), ETH_AAVE, ETH_USDC, ETH_USDT, ETH_AUSDC, ETH_AUSDT,
            uint24(100), int24(1), vm.addr(deployerKey)
        );
        (address predicted, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(SuperpositionHook).creationCode, args);
        hook = predicted;
        if (hook.code.length > 0) return hook; // re-run: reuse

        bytes memory initCode = abi.encodePacked(type(SuperpositionHook).creationCode, args);
        vm.startBroadcast(deployerKey);
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, initCode));
        require(ok, "create2 hook deploy failed");
        SuperpositionHook(hook).initializePool(79228162514264337593543950336);
        vm.stopBroadcast();
    }
```

(`ETH_AAVE`, `ETH_USDC`, `ETH_USDT` constants already exist in the file.)

- [ ] **Step 3: Extend `_persist`**

Change the artifact writer to accept the two new addresses and include them:

```solidity
    function _persist(
        string memory path,
        address mc,
        address router,
        address aave,
        address erc,
        address stg,
        address supHook,
        address supAdapter
    ) internal {
        string memory artifact = string.concat(
            '{"makerConfig":"', vm.toString(mc), '","router":"', vm.toString(router),
            '","AaveV3":"', vm.toString(aave), '","ERC4626":"', vm.toString(erc),
            '","Stargate":"', vm.toString(stg), '","SuperpositionHook":"', vm.toString(supHook),
            '","SuperpositionUniHook":"', vm.toString(supAdapter), '"}'
        );
        vm.writeFile(path, artifact);
    }
```

- [ ] **Step 4: Verify it compiles and the dry-run works**

Run: `cd foundry && forge build`
Then run against an Ethereum fork (no broadcast):
`CHAIN=ethereum forge script script/DeployAndSetup.s.sol --fork-url https://ethereum-rpc.publicnode.com --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 -vvvv` (expect a simulated deploy, or a nonce/gas error only).
Expected: no compile error and no `HookAddressNotValid`.

- [ ] **Step 5: Commit**

```bash
cd /home/drone/projects/superposition
git add foundry/script/DeployAndSetup.s.sol
git commit -m "feat: DeployAndSetup self-deploys the Superposition hook on ethereum"
```

---

### Task 8: Anvil scenario + USDT funding

**Files:**
- Create: `foundry/script/ethereum/SuperpositionScenario.s.sol`
- Modify: `foundry/script/start-anvil.sh`
- Modify: `foundry/script/AnvilScenario.s.sol` (add the `_superposition` path)

**Interfaces:**
- Consumes: the ethereum artifact (`SuperpositionHook`, `SuperpositionUniHook`).
- Produces: a runnable `forge script script/ethereum/SuperpositionScenario.s.sol`.

- [ ] **Step 1: Fund USDT on ethereum in `start-anvil.sh`**

In the `ethereum)` case, add a USDT poke loop (probe slots 0..24, same pattern as the PT probe):

```bash
      USDT=0xdAC17F958D2ee523a2206206994597C13D831ec7
      for S in $(seq 0 24); do
        poke "$USDT" "$S" "$MAKER" 1000000000000   # 1,000,000 USDT
        [ "$(cast call "$USDT" "balanceOf(address)(uint256)" "$MAKER" --rpc-url "$RPC" 2>/dev/null || echo 0)" = "1000000000000" ] && break
      done
      for S in $(seq 0 24); do
        poke "$USDT" "$S" "$TAKER" 10000000000      # 10,000 USDT
        [ "$(cast call "$USDT" "balanceOf(address)(uint256)" "$TAKER" --rpc-url "$RPC" 2>/dev/null || echo 0)" = "10000000000" ] && break
      done
```

- [ ] **Step 2: Add the scenario path in `AnvilScenario.s.sol`**

Add a dispatch branch `if (_eq(_scenario, "superposition-uni")) { _superpositionUni(artifact); return; }`. Implement `_superpositionUni(string memory artifact)` by copying the working flow from `foundry/test/fork/EthereumForkSuperposition.t.sol::test_fork_supercazzolaJitFill` (the maker LP + `setSides` + `ship` + `swap` sequence), replacing the in-test `new` deployments with:
- `hook = ISuperpositionHook(vm.parseAddress(vm.parseJsonString(artifact, ".SuperpositionHook")));`
- `adapter = SuperpositionUniAdapter(vm.parseAddress(vm.parseJsonString(artifact, ".SuperpositionUniHook")));`
- the router from the artifact (`.router`), and the maker/taker keys from `MAKER_KEY`/`TAKER_KEY`.
Add a thin wrapper `script/ethereum/SuperpositionScenario.s.sol` that sets `_scenario = "superposition-uni"` and calls the shared `run()`.

- [ ] **Step 3: Run the demo on an anvil Ethereum fork**

```bash
cd foundry && pkill -9 -x anvil 2>/dev/null; ./script/start-anvil.sh ethereum
# wait for "ready: pick a scenario", then:
forge script script/ethereum/SuperpositionScenario.s.sol --fork-url http://localhost:8547 --broadcast --skip-simulation
```

Expected: `SCENARIO PASS` (maker LPs the hook bucket, ships the 1inch strategy, a fill cycles JIT through the adapter).

- [ ] **Step 4: Commit**

```bash
cd /home/drone/projects/superposition
git add foundry/script/ethereum/SuperpositionScenario.s.sol foundry/script/AnvilScenario.s.sol foundry/script/start-anvil.sh
git commit -m "feat: ethereum Superposition scenario + USDT funding"
```

---

### Task 9: Docs

**Files:**
- Create: `docs/superposition-uni-adapter.md`
- Modify: `README.md`
- Modify: `foundry/script/README.md`

- [ ] **Step 1: Write the adapter doc**

Cover: what the adapter is; the ERC-1155 delegation model; the two one-sided buckets; `pullPlan = (0,0,0)`; the router-only `withdraw`; the self-deploy in `DeployAndSetup`; Ethereum addresses; how to run the fork test and the anvil demo; limitations (crossed bucket flips the token; dust; cached claims).

- [ ] **Step 2: Link it from the READMEs**

Add a bullet under the adapters section of `README.md` and a line in `foundry/script/README.md` for `SuperpositionScenario.s.sol`.

- [ ] **Step 3: Commit**

```bash
cd /home/drone/projects/superposition
git add docs/superposition-uni-adapter.md README.md foundry/script/README.md
git commit -m "docs: SuperpositionUniAdapter"
```

---

## Self-Review

- **Spec coverage:** adapter (Tasks 2–4), enum (Task 2), ERC-1155 delegation (Task 4), self-deploy in DeployAndSetup (Task 7), scenario + anvil demo (Task 8), docs (Task 9), fork tests (Tasks 1, 3–6). The security amendment (router-only withdraw) is in Global Constraints and Task 4.
- **Placeholders:** no "TBD"/"fill in later". Tasks 5 and 6 explicitly require iterating until green (fork mechanics: taker-traits flags, Aave index accrual) with the acceptance command and expected result stated. Task 8 Step 2 points at the concrete test file that contains the working flow, not at a task number.
- **Type consistency:** `Side{int24 lower; int24 upper; bool isToken0; bool set}`, `DepositParams`, `WithdrawParams`, `Bucket` are used identically across the adapter, interface, and tests. `_deployHook(uint24,int24)` matches all callers.
