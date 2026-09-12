// Ethereum Sepolia testnet constants for the SuperPosition maker console.
// Deployed stack: see foundry/script/sepolia/DeploySepolia.s.sol and README.

export const SEPOLIA_CHAIN_ID = 11155111 as const;
export const SEPOLIA_RPC = "https://ethereum-sepolia-rpc.publicnode.com";
export const SEPOLIA_EXPLORER = "https://sepolia.etherscan.io";

export const AQUA = "0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a" as const;
export const WETH9 = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14" as const;

export const STACK = {
  makerConfig: "0xF56EBe6386F40969A9721C6aB3fa07BEaD1Bd926",
  router: "0x201D78030bed2d81F827B7650E2CB7C00Ea0c9EC",
  aaveAdapter: "0xd915d3Db7f18f75D67c63B3Aa00872fbCE793c57",
  erc4626Adapter: "0xb1B9955600DfAF8987da8c9D0A37F2d2ee4B8752",
  vaultUSDC: "0x4F32F6bE82407E7956E5752672677542379a1ec8",
  vaultUSDT: "0x0d98E00F0EFfE80a8Afd23FbA7cd0483E46CAa8D",
  superpositionHook: "0x6A7A2C6495A16f0a4c77E771f8A3945ee3494aC0",
  superpositionUniAdapter: "0x1be3291f7Ef08e56f0141007F49846fB07794C8B",
  aavePool: "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
  aaveDataProvider: "0x3e9708d80f7B3e43118013075F7e95CE3AB31F31",
  aaveFaucet: "0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D",
  faucetBatch: "0xE05742c33bf6b347919B26934fa1Df9eF056F156",
  orderBuilder: "0x593f18800df097f059270357948F24bC677f50c5",
  hookLpHelper: "0x7686615960Ff41551165a27fE63b15917830E04D",
  v4PoolManager: "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543",
  v4StateView: "0xe1dd9c3fa50edb962e442f60dfbc432e24537e4c",
} as const;

/// PoolId of the USDC/USDT fee=100 spacing=1 SuperpositionHook pool (deterministic
/// from the pool key; read from hook.poolId()).
export const EXAMPLE_POOL_ID = "0xc6bf0aaefdb77686efe533d898a4905260dd6c03044350e28501fece1d05f4f1" as const;

export type Address = `0x${string}`;

export type TokenCategory = "stable" | "eth" | "btc" | "defi" | "lst";

export interface TokenDef {
  symbol: string;
  name: string;
  address: Address;
  decimals: number;
  category: TokenCategory;
  /** Listed as a borrowable/supplyable reserve on Aave v3 Sepolia. */
  aaveListed: boolean;
  /** Aave aToken address (holder = supplier). */
  aToken?: Address;
  /** ERC-4626 vault deployed on Sepolia for this token (Aave-backed), if any. */
  erc4626Vault?: Address;
  /** Permissionlessly mintable from the Aave Sepolia faucet (mint(token,to,amount)). */
  faucet: boolean;
  note?: string;
}

/// ~20 popular assets. Aave-listed ones are actionable on Sepolia; the rest are
/// shown greyed out with the testnet-scarcity disclaimer.
export const TOKENS: TokenDef[] = [
  { symbol: "USDC", name: "USD Coin", address: "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8", decimals: 6, category: "stable", aaveListed: true, aToken: "0x16dA4541aD1807f4443d92D26044C1147406EB80", erc4626Vault: "0x4F32F6bE82407E7956E5752672677542379a1ec8", faucet: true },
  { symbol: "USDT", name: "Tether USD", address: "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0", decimals: 6, category: "stable", aaveListed: true, aToken: "0xAF0F6e8b0Dc5c913bbF4d14c22B4E78Dd14310B6", erc4626Vault: "0x0d98E00F0EFfE80a8Afd23FbA7cd0483E46CAa8D", faucet: true },
  { symbol: "DAI", name: "Dai Stablecoin", address: "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357", decimals: 18, category: "stable", aaveListed: true, aToken: "0x29598b72eb5CeBd806C5dCD549490FdA35B13cD8", faucet: true },
  { symbol: "GHO", name: "GHO", address: "0xc4bF5CbDaBE595361438F8c6a187bDc330539c60", decimals: 18, category: "stable", aaveListed: true, aToken: "0xd190eF37dB51Bb955A680fF1A85763CC72d083D4", faucet: false, note: "faucet often reverts (bucket cap)" },
  { symbol: "EURS", name: "STASIS EURS", address: "0x6d906e526a4e2Ca02097BA9d0caA3c382F52278E", decimals: 2, category: "stable", aaveListed: true, aToken: "0xB20691021F9AcED8631eDaa3c0Cd2949EB45662D", faucet: true },
  { symbol: "WETH", name: "Wrapped Ether", address: "0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c", decimals: 18, category: "eth", aaveListed: true, aToken: "0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830", faucet: false, note: "wrap ETH (WETH9.deposit)" },
  { symbol: "WBTC", name: "Wrapped BTC", address: "0x29f2D40B0605204364af54EC677bD022dA425d03", decimals: 8, category: "btc", aaveListed: true, aToken: "0x1804Bf30507dc2EB3bDEbbbdd859991EAeF6EefF", faucet: true },
  { symbol: "LINK", name: "Chainlink", address: "0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5", decimals: 18, category: "defi", aaveListed: true, aToken: "0x3FfAf50D4F4E96eB78f2407c090b72e86eCaed24", faucet: true },
  { symbol: "AAVE", name: "Aave", address: "0x88541670E55cC00bEEFD87eB59EDd1b7C511AC9a", decimals: 18, category: "defi", aaveListed: true, aToken: "0x6b8558764d3b7572136F17174Cb9aB1DDc7E1259", faucet: true },
  // Not Aave-listed on Sepolia — greyed out.
  { symbol: "wstETH", name: "Wrapped stETH", address: "0xB82381A3fBD3FaFA77B3a7bE693342618240067b", decimals: 18, category: "lst", aaveListed: false, faucet: false, note: "deprecated on Sepolia" },
  { symbol: "stETH", name: "Lido stETH", address: "0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af", decimals: 18, category: "lst", aaveListed: false, faucet: false, note: "deprecated on Sepolia" },
  { symbol: "PYUSD", name: "PayPal USD", address: "0xCaC524BcA292aaade2DF8A05cC58F0a65B1B3bB9", decimals: 6, category: "stable", aaveListed: false, faucet: false, note: "Paxos faucet" },
  { symbol: "UNI", name: "Uniswap", address: "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984", decimals: 18, category: "defi", aaveListed: false, faucet: false },
  { symbol: "GHST", name: "Aavegotchi", address: "0xb40b75b4a8e5153357b3e5e4343d997b1a1019f9", decimals: 18, category: "defi", aaveListed: false, faucet: false },
  { symbol: "rETH", name: "Rocket Pool ETH", address: "0x0000000000000000000000000000000000000000", decimals: 18, category: "lst", aaveListed: false, faucet: false, note: "not deployed on Sepolia" },
  { symbol: "cbETH", name: "Coinbase Wrapped ETH", address: "0x0000000000000000000000000000000000000000", decimals: 18, category: "lst", aaveListed: false, faucet: false, note: "not deployed on Sepolia" },
  { symbol: "MKR", name: "Maker", address: "0x0000000000000000000000000000000000000000", decimals: 18, category: "defi", aaveListed: false, faucet: false, note: "not deployed on Sepolia" },
  { symbol: "ENS", name: "Ethereum Name Service", address: "0x0000000000000000000000000000000000000000", decimals: 18, category: "defi", aaveListed: false, faucet: false, note: "token mainnet-only" },
  { symbol: "LDO", name: "Lido DAO", address: "0x0000000000000000000000000000000000000000", decimals: 18, category: "defi", aaveListed: false, faucet: false, note: "not deployed on Sepolia" },
  { symbol: "CRV", name: "Curve DAO", address: "0x0000000000000000000000000000000000000000", decimals: 18, category: "defi", aaveListed: false, faucet: false, note: "not deployed on Sepolia" },
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
  /** Deployed adapter address on Sepolia; undefined = not available here. */
  address?: Address;
  /** Token symbols this adapter can serve; undefined = any Aave-listed token. */
  tokens?: string[];
}

export const ADAPTERS: AdapterDef[] = [
  { id: "erc4626-aave", label: "ERC4626Adapter · Aave v3", short: "Aave · 4626", kind: 2, protocol: "Aave v3 (ERC-4626 vault)", yield: "Aave supply APY (idle while Sepolia caps)", status: "active", address: STACK.erc4626Adapter, tokens: ["USDC", "USDT"] },
  { id: "superposition", label: "SuperpositionUniAdapter", short: "Superposition", kind: 5, protocol: "Superposition v4 hook", yield: "v4 fees (USDC/USDT)", status: "active", address: STACK.superpositionUniAdapter, tokens: ["USDC", "USDT"] },
  { id: "morpho", label: "ERC4626Adapter · Morpho", short: "Morpho", kind: 2, protocol: "MetaMorpho", yield: "curated vault yield", status: "scarcity", reason: "not in testnet" },
  { id: "euler", label: "ERC4626Adapter · Euler v2", short: "Euler v2", kind: 2, protocol: "Euler v2", yield: "EVault yield", status: "scarcity", reason: "not in testnet" },
  { id: "yearn", label: "ERC4626Adapter · Yearn v3", short: "Yearn v3", kind: 2, protocol: "Yearn v3", yield: "vault yield", status: "scarcity", reason: "not in testnet" },
  { id: "stargate", label: "StargateAdapter", short: "Stargate", kind: 3, protocol: "Stargate v2", yield: "bridge rewards", status: "scarcity", reason: "not in testnet" },
  { id: "pendle", label: "PendlePTAdapter", short: "Pendle", kind: 4, protocol: "Pendle", yield: "fixed APY", status: "scarcity", reason: "not in testnet" },
];

export const explorerAddress = (a: string) => `${SEPOLIA_EXPLORER}/address/${a}`;
export const explorerTx = (h: string) => `${SEPOLIA_EXPLORER}/tx/${h}`;
