import { parseAbi } from "viem";

export const erc20Abi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)",
]);

export const weth9Abi = parseAbi([
  "function deposit() payable",
  "function withdraw(uint256 amount)",
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
]);

// Aave v3 Sepolia testnet faucet: permissionless mint(token, to, amount).
export const faucetAbi = parseAbi([
  "function mint(address token, address to, uint256 amount) returns (uint256)",
  "function isMintable(address token) view returns (bool)",
]);

// Batch faucet: mints every mintable token to `to` in a single transaction.
export const faucetBatchAbi = parseAbi([
  "function mintAll(address to, uint256 wholeAmount) returns (uint256 minted)",
  "function tokenCount() view returns (uint256)",
]);

// Per-maker, per-token adapter registry + borrow config.
export const makerConfigAbi = parseAbi([
  "function setSides((address underlying, address adapter, uint8 kind, bool autoManaged)[] newSides)",
  "function sides(address maker, address underlying) view returns ((address underlying, address adapter, uint8 kind, bool autoManaged))",
  "function setBorrowConfigs(address[] underlyings, (bool enabled, address collateral, uint256 maxDebt)[] configs)",
  "function borrowConfigOf(address maker, address underlying) view returns ((bool enabled, address collateral, uint256 maxDebt))",
]);

export const aaveAdapterAbi = parseAbi([
  "function name() view returns (string)",
  "function yieldToken(address underlying) view returns (address)",
  "function exchangeRate(address underlying) view returns (uint256)",
  "function underlyingToYield(address underlying, uint256 amount) view returns (uint256)",
  "function yieldToUnderlying(address underlying, uint256 amount) view returns (uint256)",
  "function maxWithdrawable(address maker, address underlying) view returns (uint256)",
  "function deposit(address maker, address underlying, uint256 amount)",
  "function withdraw(address maker, address underlying, uint256 underlyingAmount, uint256 yieldAmount, address recipient)",
]);

// Aave v3 Pool (reduced).
export const aavePoolAbi = parseAbi([
  "function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)",
  "function withdraw(address asset, uint256 amount, address to) returns (uint256)",
  "function setUserUseReserveAsCollateral(address asset, bool useAsCollateral)",
  "function getUserAccountData(address user) view returns (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor)",
]);

// Our Aave-backed ERC-4626 vault.
export const erc4626Abi = parseAbi([
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function maxDeposit(address) view returns (uint256)",
  "function previewDeposit(uint256 assets) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256)",
  "function withdraw(uint256 assets, address receiver, address owner) returns (uint256)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
]);

export const superpositionAdapterAbi = parseAbi([
  "function name() view returns (string)",
  "function maxWithdrawable(address maker, address underlying) view returns (uint256)",
  "function sideOf(address underlying) view returns (int24 lower, int24 upper, bool isToken0, bool set)",
  "function deposit(address maker, address underlying, uint256 amount)",
  "function withdraw(address maker, address underlying, uint256 amountOut, uint256 unused, address recipient)",
]);

export const superpositionHookAbi = parseAbi([
  "function sharesOf(address user, int24 lower, int24 upper) view returns (uint256)",
  "function totalSharesOf(int24 lower, int24 upper) view returns (uint256)",
  "function bucketValue(int24 lower, int24 upper) view returns (uint256)",
  "function currentBalance() view returns (uint256 amount0, uint256 amount1)",
  "function virtualBalance() view returns (uint256 amount0, uint256 amount1)",
  "function totalClaim() view returns (uint256, uint256)",
  "function initialized() view returns (bool)",
  "function poolId() view returns (bytes32)",
  "function shareToken() view returns (address)",
  "function vault0() view returns (address)",
  "function vault1() view returns (address)",
  "function poolKey() view returns (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks)",
  "function getBuckets() view returns ((int24 lower, int24 upper, uint128 liquidity, uint256 shares, uint256 c0, uint256 c1, bool active)[])",
  "function deposit((int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address recipient))",
  "function withdraw((int24 tickLower, int24 tickUpper, address owner, uint256 shareAmount, address recipient))",
]);

// Uniswap v4 StateView: read pool slot0 + active liquidity by poolId.
export const v4StateViewAbi = parseAbi([
  "function getSlot0(bytes32 id) view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)",
  "function getLiquidity(bytes32 id) view returns (uint128 liquidity)",
]);

// One-transaction LP helper for the Superposition hook (caller-chosen ranges).
export const hookLpHelperAbi = parseAbi([
  "function provide(address maker, address token0, address token1, uint256 amount0, uint256 amount1, int24 lower0, int24 upper0, int24 lower1, int24 upper1)",
  "function redeem(address maker, int24 lower0, int24 upper0, uint256 shares0, int24 lower1, int24 upper1, uint256 shares1)",
]);

export const erc1155Abi = parseAbi([
  "function isApprovedForAll(address account, address operator) view returns (bool)",
  "function setApprovalForAll(address operator, bool approved)",
]);

// Aave v3 ProtocolDataProvider: reserve caps, config flags, aToken supply.
export const aaveDataProviderAbi = parseAbi([
  "function getReserveCaps(address asset) view returns (uint256 borrowCap, uint256 supplyCap)",
  "function getReserveConfigurationData(address asset) view returns (uint256 decimals, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor, bool usageAsCollateralEnabled, bool borrowingEnabled, bool stableBorrowRateEnabled, bool isActive, bool isFrozen)",
  "function getATokenTotalSupply(address asset) view returns (uint256)",
  "function getReserveData(address asset) view returns (uint256 availableLiquidity, uint256 totalStableDebt, uint256 totalVariableDebt, uint256 liquidityRate, uint256 variableBorrowRate, uint256 stableBorrowRate, uint256 averageStableBorrowRate, uint256 liquidityIndex, uint256 variableBorrowIndex, uint40 lastUpdateTimestamp)",
]);

// 1inch Aqua: ship a strategy on-chain.
export const aquaAbi = parseAbi([
  "function ship(address app, bytes strategy, address[] tokens, uint256[] amounts)",
  "function dock(address app, bytes strategy, address[] tokens)",
]);

// On-chain order encoder: returns abi.encode(ISwapVM.Order) for aqua.ship.
export const orderBuilderAbi = parseAbi([
  "function build(address maker, address router, address tokenIn, address tokenOut, address guardToken, uint32 feeBps, uint256 rateIn, uint256 rateOut) pure returns (bytes)",
]);
