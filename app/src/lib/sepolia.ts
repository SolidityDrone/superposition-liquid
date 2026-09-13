// Base Sepolia (chainId 84532) constants for the SuperPosition maker console.
// The stack is deployed by foundry/script/base-sepolia/DeployBaseSepolia.s.sol
// (Aqua is NOT deployed on Base Sepolia -> we deploy our own). Every address is
// Sourcify `exact_match`. Full list: docs/ADDRESSES.md.

export const SEPOLIA_CHAIN_ID = 84532 as const;
export const SEPOLIA_RPC = "https://sepolia.base.org";
export const SEPOLIA_EXPLORER = "https://sepolia.basescan.org";

/// Aqua we deployed (the 1inch Aqua is absent on Base Sepolia).
export const AQUA = "0x06DC4edCF4F3ABdFa65Cc4fD58AB459B5ff20F9e" as const;
export const WETH9 = "0x4200000000000000000000000000000000000006" as const;

export const STACK = {
  makerConfig: "0x0196eeF216fAF47DE34bcbEd5fB1ab4f97A932ee",
  router: "0x4fefc5D38eE27f09F68484574A3B4AAC914d4097",
  aaveAdapter: "0x56BE9DC69c798BC8B7567958b1B45f4b6e4502eb",
  erc4626Adapter: "0x0f47Ca0065B7f0Ff00eEDf6D92D977389Aa8CcbF",
  vaultUSDC: "0x126b97C6AF4748118504A993e97EbAA1cb863576",
  vaultUSDT: "0x682E0DBEF9Ce3487b06F961A8667fBdcb2093396",
  superpositionHook: "0x2F6bA013a29967F3A638887f8BefB18424658Ac0",
  superpositionUniAdapter: "0x81e92e910B978e5F3865E4E815660725662EE236",
  aavePool: "0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27",
  aaveDataProvider: "0xBc9f5b7E248451CdD7cA54e717a2BFe1F32b566b",
  aaveFaucet: "0xD9145b5F45Ad4519c7ACcD6E0A4A82e83bB8A6Dc",
  faucetBatch: "0xbe135721492C6525cAf47454aEEFc37B378bf895",
  orderBuilder: "0x7a8F11c29FD46e21aA70638f8f6BA62777cf920C",
  hookLpHelper: "0x24F0A572A6A7Ae73322aB5B19Ee83d50343A5D23",
  v4PoolManager: "0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408",
  v4StateView: "0x571291b572ed32ce6751a2cb2486ebee8defb9b4",
} as const;

/// PoolId of the USDT/USDC fee=100 spacing=1 SuperpositionHook pool (read from hook.poolId()).
export const EXAMPLE_POOL_ID = "0x61ba18cc22f164da8266f5335986bc2d38edd40a8e997c413376b70ea2dc98bf" as const;

export type Address = `0x${string}`;

export type TokenCategory = "stable" | "eth" | "btc" | "defi" | "lst";

export interface TokenDef {
  symbol: string;
  name: string;
  address: Address;
  decimals: number;
  category: TokenCategory;
  /** Listed as a borrowable/supplyable reserve on Aave v3 Base Sepolia. */
  aaveListed: boolean;
  /** Aave aToken address (holder = supplier). */
  aToken?: Address;
  /** ERC-4626 vault deployed on Base Sepolia for this token (Aave-backed), if any. */
  erc4626Vault?: Address;
  /** Permissionlessly mintable from the Aave Base Sepolia faucet (mint(token,to,amount)). */
  faucet: boolean;
  /** Whole-token amount the Aave faucet allows per mint (per-token cap). */
  faucetAmount?: string;
  note?: string;
}

export const TOKENS: TokenDef[] = [
  { symbol: "USDC", name: "USD Coin", address: "0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f", decimals: 6, category: "stable", aaveListed: true, aToken: "0x10F1A9D11CDf50041f3f8cB7191CBE2f31750ACC", erc4626Vault: "0x126b97C6AF4748118504A993e97EbAA1cb863576", faucet: true, faucetAmount: "10000" },
  { symbol: "USDT", name: "Tether USD", address: "0x0a215D8ba66387DCA84B284D18c3B4ec3de6E54a", decimals: 6, category: "stable", aaveListed: true, aToken: "0xcE3CAae5Ed17A7AafCEEbc897DE843fA6CC0c018", erc4626Vault: "0x682E0DBEF9Ce3487b06F961A8667fBdcb2093396", faucet: true, faucetAmount: "10000" },
  { symbol: "WETH", name: "Wrapped Ether", address: "0x4200000000000000000000000000000000000006", decimals: 18, category: "eth", aaveListed: true, aToken: "0x73a5bB60b0B0fc35710DDc0ea9c407031E31Bdbb", faucet: false, note: "wrap ETH (WETH9.deposit)" },
  { symbol: "WBTC", name: "Wrapped BTC", address: "0x54114591963CF60EF3aA63bEfD6eC263D98145a4", decimals: 8, category: "btc", aaveListed: true, faucet: true, faucetAmount: "1" },
  { symbol: "LINK", name: "Chainlink", address: "0x810D46F9a9027E28F9B01F75E2bdde839dA61115", decimals: 18, category: "defi", aaveListed: true, faucet: true, faucetAmount: "1000" },
  { symbol: "cbETH", name: "Coinbase Wrapped ETH", address: "0xD171b9694f7A2597Ed006D41f7509aaD4B485c4B", decimals: 18, category: "lst", aaveListed: true, faucet: true, faucetAmount: "1" },
];

export interface AdapterDef {
  id: string;
  label: string;
  short?: string;
  kind: number; // AdapterKind enum in MakerConfig
  protocol: string;
  yield: string;
  status: "active" | "scarcity";
  reason?: string;
  /** Deployed adapter address on Base Sepolia; undefined = not available here. */
  address?: Address;
  /** Token symbols this adapter can serve; undefined = any Aave-listed token. */
  tokens?: string[];
}

export const ADAPTERS: AdapterDef[] = [
  { id: "erc4626-aave", label: "ERC4626Adapter · Aave v3", short: "Aave · 4626", kind: 2, protocol: "Aave v3 (ERC-4626 vault)", yield: "Aave supply APY (real aTokens)", status: "active", address: STACK.erc4626Adapter, tokens: ["USDC", "USDT"] },
  { id: "superposition", label: "SuperpositionUniAdapter", short: "Superposition", kind: 5, protocol: "Superposition v4 hook", yield: "v4 fees (USDC/USDT)", status: "active", address: STACK.superpositionUniAdapter, tokens: ["USDC", "USDT"] },
  { id: "morpho", label: "ERC4626Adapter · Morpho", short: "Morpho", kind: 2, protocol: "MetaMorpho", yield: "curated vault yield", status: "scarcity", reason: "not in testnet" },
  { id: "stargate", label: "StargateAdapter", short: "Stargate", kind: 3, protocol: "Stargate v2", yield: "bridge rewards", status: "scarcity", reason: "not in testnet" },
  { id: "pendle", label: "PendlePTAdapter", short: "Pendle", kind: 4, protocol: "Pendle", yield: "fixed APY", status: "scarcity", reason: "not in testnet" },
];

export const explorerAddress = (a: string) => `${SEPOLIA_EXPLORER}/address/${a}`;
export const explorerTx = (h: string) => `${SEPOLIA_EXPLORER}/tx/${h}`;
