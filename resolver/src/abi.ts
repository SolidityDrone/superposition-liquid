import { parseAbi } from "viem";

/** Minimal ABIs the resolver needs on-chain. */
export const AQUA_ABI = parseAbi([
  "event Shipped(address indexed maker, address indexed app, bytes32 indexed strategyHash, bytes strategy)",
  "event Docked(address indexed maker, address indexed app, bytes32 indexed strategyHash)",
  "function rawBalances(address maker, address app, bytes32 strategyHash, address token) view returns (uint248 balance, uint8 tokensCount)",
  "function safeBalances(address maker, address app, bytes32 strategyHash, address token0, address token1) view returns (uint256 balance0, uint256 balance1)",
]);

export const ROUTER_ABI = parseAbi([
  "function MAKER_CONFIG() view returns (address)",
  "function quote((address maker, uint256 traits, bytes data) order, address tokenIn, address tokenOut, uint256 amount, bytes takerTraitsAndData) view returns (uint256 amountIn, uint256 amountOut, bytes32 orderHash)",
]);

export const MAKER_CONFIG_ABI = parseAbi([
  "function sides(address maker, address underlying) view returns (tuple(address underlying, address adapter, uint8 kind, bool autoManaged))",
  "event SideSet(address indexed maker, address indexed underlying, address indexed adapter, uint8 kind, bool autoManaged)",
]);

export const ADAPTER_ABI = parseAbi([
  "function name() view returns (string)",
  "function exchangeRate(address underlying) view returns (uint256)",
  "function maxWithdrawable(address maker, address underlying) view returns (uint256)",
  "function yieldToken(address underlying) view returns (address)",
]);

export const ERC20_ABI = parseAbi([
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
]);

export const ADAPTER_KINDS = ["None", "AaveV3", "ERC4626", "Stargate", "PendlePT"] as const;

/** The maker's strategy: Order{maker, traits, data} shipped to Aqua. */
export type Order = { maker: `0x${string}`; traits: bigint; data: `0x${string}` };

/**
 * TakerTraits packing (swap-vm TakerTraitsLib): 22-byte header =
 * 20 bytes of slice indexes (all zero: no threshold/to/deadline/hooks/signature)
 * + 2 bytes of flags. Demo taker: isExactIn (0x0001) | useTransferFromAndAquaPush (0x0040).
 */
export const TAKER_TRAITS_DATA = `0x${"00".repeat(20)}0041` as const;
