# Testnet Support Design — Superposition-Liquid

## Context and motivation

All Superposition-Liquid testing currently runs against mainnet forks (Base,
Ethereum, Arbitrum). This works well for proving correctness against live
protocol state, but creates two problems:

1. **No public testnet deployment path.** Makers, integrators, and judges cannot
   try the system on public testnets without deploying their own infrastructure.
2. **Protocol unavailability.** Several adapters (Morpho, Euler v2, Pendle) have
   no testnet deployments — they are permissionless deploy-your-own. Without a
   chain-config layer that documents what exists where, new users hit silent
   failures.

This design adds testnet chain configuration files that mirror the mainnet
`BaseChain.s.sol` pattern, and documents which adapters are available on each
target testnet.

## Target testnets

| Chain | Chain ID | RPC |
|---|---|---|
| Ethereum Sepolia | 11155111 | `https://ethereum-sepolia.publicnode.com` |
| Base Sepolia | 84532 | `https://sepolia.base.org` |

Both are the standard public test infrastructure for Ethereum and Base.

## Address tables

### Ethereum Sepolia (11155111)

| Contract | Address | Notes |
|---|---|---|
| Aqua registry | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` | Same vanity address as mainnet |
| SwapVM router | `0x111111338c5091E8440b67B168bAe16a668AC0De` | Same vanity address as mainnet |
| Aave v3 Pool | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` | Sepolia market |
| WETH | `0xfff9976782d46cc05630d1f6ebab18b2324d6b14` | Canonical testnet WETH |
| USDC | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` | Aave testnet USDC |
| aWETH | `0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830` | |
| aUSDC | `0x16dA4541aD1807f4443d92D26044C1147406EB80` | |
| Chainlink ETH/USD | `0x694AA1769357215DE4FAC081bf1f309aDC325306` | Sepolia feed |
| Chainlink USDC/USD | `TBD — verify on-chain before hardcoding` | |
| Stargate V2 PoolUSDC | `0x4985b8fcEA3659FD801a5b857dA1D00e985863F0` | |
| Stargate V2 Staking | `0xE62F51D9DA2b082abed838E9Ac48D0EDFFbfedaE` | |

### Base Sepolia (84532)

| Contract | Address | Notes |
|---|---|---|
| Aqua registry | `0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a` | Same vanity address as mainnet |
| SwapVM router | `0x111111338c5091E8440b67B168bAe16a668AC0De` | Same vanity address as mainnet |
| Aave v3 Pool | `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27` | Sepolia market |
| WETH | `0x4200000000000000000000000000000000000006` | Canonical L2 WETH |
| USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | Circle USDC |
| aWETH | `0x73a5bB60b0B0fc35710DDc0ea9c407031E31Bdbb` | Verified on-chain (underlying = WETH) |
| aUSDC | — | USDC not registered as a reserve on this pool |
| Chainlink ETH/USD | `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1` | |
| Chainlink USDC/USD | `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` | |
| Stargate V2 | **NOT available on Base Sepolia** | |

## Adapter availability matrix

| Adapter | Ethereum Sepolia | Base Sepolia |
|---|---|---|
| `AaveV3Adapter` | ✅ (Pool + aTokens) | ✅ (Pool + aTokens) |
| `StargateAdapter` | ✅ (Pool + Staking) | ❌ Not deployed |
| `ERC4626Adapter` (Morpho) | ❌ Permissionless deploy | ❌ Permissionless deploy |
| `ERC4626Adapter` (Euler) | ❌ Permissionless deploy | ❌ Permissionless deploy |
| `PendlePTAdapter` | ❌ Permissionless deploy | ❌ Permissionless deploy |

**Summary per testnet:**

- **Ethereum Sepolia:** Full adapter support (AaveV3 + Stargate) + Chainlink guard.
  Best testnet for end-to-end validation.
- **Base Sepolia:** AaveV3 adapter only + Chainlink guard. Stargate not deployed.

## Design decisions

### D1. Follow the BaseChain.s.sol pattern exactly

Each testnet chain file is a Solidity `library` with `internal constant`
addresses, matching the convention in `foundry/script/BaseChain.s.sol`. This
keeps fork tests and deployment scripts identical in structure — swap the import
and the constants just work.

```
script/
  BaseChain.s.sol              # mainnet (existing)
  SepoliaChain.s.sol           # Ethereum Sepolia (new)
  BaseSepoliaChain.s.sol       # Base Sepolia (new)
```

### D2. Mark unavailable addresses with explicit comments

Addresses that do not exist on a testnet are **not** set to `address(0)` or
omitted. They are declared as commented-out constants with a clear explanation:

```solidity
// NOT available on Base Sepolia — permissionless, deploy your own
// address internal constant MORPHO_WETH_VAULT = 0x...;
```

This way:
- The compiler catches accidental references to missing addresses at build time.
- Developers see exactly what is missing and why when reading the file.
- No silent `address(0)` bugs that pass compilation but revert at runtime.

### D3. aToken addresses require on-chain resolution

Base Sepolia aWETH/aUSDC addresses are marked `0xTODO` because they must be
queried from the deployed Aave Pool contract:

```bash
cast call 0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27 \
  "getReserveData(address)(tuple(uint256,uint256,uint256,...,address,address,address,address))" \
  0x4200000000000000000000000000000000000006
```

These will be resolved and committed before the fork tests are written.

### D4. Separate testnet fork test files

Each testnet gets its own fork test files under `foundry/test/fork/`, named to
match the convention:

```
test/fork/
  SepoliaForkAave.t.sol            # AaveV3 + Stargate on Ethereum Sepolia
  BaseSepoliaForkAave.t.sol        # AaveV3 on Base Sepolia
```

### D5. RPC URL resolution via env var with fallback

Fork tests use the same pattern as existing tests:

```solidity
vm.createSelectFork(vm.envOr("RPC_URL_SEPOLIA", string(SepoliaChain.RPC_URL)));
```

This lets CI override RPC URLs via environment variables while keeping local
development zero-config.

## Implementation plan

### Phase 1: Chain configuration files ✅

| File | Status |
|---|---|
| `foundry/script/SepoliaChain.s.sol` | ✅ Created — Ethereum Sepolia library with all addresses |
| `foundry/script/BaseSepoliaChain.s.sol` | ✅ Created — Base Sepolia library; aWETH resolved, USDC not listed |

### Phase 2: Resolve missing addresses ✅

| Action | Result |
|---|---|
| Query Base Sepolia aWETH | `0x73a5bb60b0b0fc35710ddc0ea9c407031e31bdbb` — verified underlying = WETH |
| Query Base Sepolia aUSDC | USDC not registered as a reserve on this pool (only WETH + 5 other tokens listed) |

### Phase 3: Fork tests

| File | What it tests |
|---|---|
| `test/fork/SepoliaForkAave.t.sol` | Full AaveV3 JIT cycle on Ethereum Sepolia: ship → quote → swap, real aTokens, real Chainlink guard |
| `test/fork/SepoliaForkStargate.t.sol` | Stargate V2 deposit + stake + JIT unstake on Ethereum Sepolia |
| `test/fork/BaseSepoliaForkAave.t.sol` | AaveV3 JIT cycle on Base Sepolia |

Each test mirrors the structure of the existing mainnet fork tests (e.g.
`BaseFork.t.sol`, `BaseForkStargate.t.sol`) — same `setUp()` pattern, same
invariant assertions (`real >= virtual`, `quote == swap`, idle balance == 0).

### Phase 4: Documentation and README updates

| File | Change |
|---|---|
| `README.md` | Add testnet section under "Demo" with run commands for each testnet fork |
| `docs/ADDRESSES.md` | Add testnet address tables to each protocol section (Aave, Stargate, Chainlink) |
| `foundry/script/BaseChain.s.sol` | No changes — mainnet config stays untouched |

### Phase 5: Deploy script variant (optional)

| File | Change |
|---|---|
| `foundry/script/Deploy.s.sol` | Generalize to accept a chain library (or create `DeploySepolia.s.sol`) so the full stack can be deployed to testnets |

## Testing strategy

### Fork tests against live testnets

All testnet fork tests follow the same pattern as existing mainnet fork tests:

1. **`setUp()`** — `vm.createSelectFork()` against the testnet RPC, `deal()`
   tokens to maker, set up adapter + router + Aqua position, ship the order.
2. **`test_fork_*()`** — perform a fill cycle, assert invariants.

The key difference: testnet forks run against **real testnet state** (real Aave
pools, real Chainlink feeds, real Stargate pools). This catches deployment
differences between mainnet and testnet (different addresses, different pool
parameters, missing tokens).

### What testnet fork tests prove

| Test | Proves |
|---|---|
| AaveV3 JIT cycle (Sepolia) | AaveV3Adapter works against the Sepolia Aave deployment (different pool address, same interface) |
| Stargate JIT cycle (Sepolia) | StargateAdapter works against Sepolia Stargate (different pool, different credit limits) |
| Missing adapter reverts | Attempting to use ERC4626/Pendle/WstETH on testnets without deployments produces clear errors |

### CI integration

Add a `testnet-fork` test profile in `foundry.toml` (or a Makefile target) that
runs testnet fork tests with the appropriate RPC URLs:

```bash
RPC_URL_SEPOLIA=https://ethereum-sepolia.publicnode.com \
RPC_URL_BASE_SEPOLIA=https://sepolia.base.org \
forge test --match-path "test/fork/*Sepolia*" -vvv
```

### Not in scope (deferred)

- **Deploying to testnets** — the deploy script generalization is Phase 5 and
  can be picked up separately.
- **Permissionless protocol testnets** (Morpho, Euler, Pendle) — these require
  deploying the protocol itself on testnet, which is a separate project.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Testnet contracts differ from mainnet (different ABI, different behavior) | Fork tests catch this — same pattern as mainnet tests, just different state |
| Testnet RPCs rate-limit or go down | Env var override for RPC URLs; public fallback RPCs as defaults |
| aToken addresses change on Aave testnet upgrades | Query from Pool contract at test time (or resolve before commit) |
| Stargate testnet credit limits are tiny | Use smaller fill amounts in tests, adjust dust buffers |

## File summary

| File | Action | Purpose |
|---|---|---|
| `foundry/script/SepoliaChain.s.sol` | Create | Ethereum Sepolia chain constants |
| `foundry/script/BaseSepoliaChain.s.sol` | Create | Base Sepolia chain constants |
| `foundry/test/fork/SepoliaForkAave.t.sol` | Create | AaveV3 fork test on Ethereum Sepolia |
| `foundry/test/fork/SepoliaForkStargate.t.sol` | Create | Stargate fork test on Ethereum Sepolia |
| `foundry/test/fork/BaseSepoliaForkAave.t.sol` | Create | AaveV3 fork test on Base Sepolia |
| `README.md` | Modify | Add testnet documentation section |
| `docs/ADDRESSES.md` | Modify | Add testnet address tables |
