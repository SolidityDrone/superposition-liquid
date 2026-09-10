import {
  type PublicClient,
  decodeAbiParameters,
  formatUnits,
  getAddress,
  keccak256,
  encodePacked,
  type Address,
  zeroAddress,
} from "viem";
import {
  AQUA_ABI,
  ADAPTER_ABI,
  ERC20_ABI,
  MAKER_CONFIG_ABI,
  ROUTER_ABI,
  TAKER_TRAITS_DATA,
  type Order,
} from "./abi.js";

/** One shipped strategy discovered on Aqua. */
export interface Strategy {
  maker: Address;
  strategyHash: `0x${string}`;
  order: Order;
  /** block number the Shipped event was seen at */
  block: bigint;
}

/** Full on-chain state of one strategy, resolved at current block. */
export interface Position {
  strategy: Strategy;
  router: Address;
  makerConfig: {
    underlyingIn: Address;
    underlyingOut: Address;
    sideIn: { adapter: Address; kind: number; autoManaged: boolean };
    sideOut: { adapter: Address; kind: number; autoManaged: boolean };
  };
  adapterNames: { [k: string]: string };
  tokens: {
    [k: string]: {
      address: Address;
      symbol: string;
      decimals: number;
      /** raw aToken count sitting as Aqua virtual balance */
      virtualRaw: bigint;
      /** aToken × exchangeRate = real underlying the fill can draw */
      effective: bigint;
      exchangeRate: bigint;
      /** adapter.simulated withdrawal: position AND protocol liquidity */
      maxWithdrawable: bigint;
      yieldToken: Address;
    };
  };
}

/** Scan Aqua `Shipped` logs and keep only strategies aimed at our router. */
export async function discover(
  client: PublicClient,
  aqua: Address,
  router: Address,
  fromBlock: bigint,
): Promise<Strategy[]> {
  const logs = await client.getLogs({
    address: aqua,
    event: AQUA_ABI[0],
    fromBlock,
    toBlock: "latest",
  });

  const out: Strategy[] = [];
  for (const log of logs) {
    if (getAddress(log.args.app!) !== getAddress(router)) continue;
    // strategy bytes = abi.encode(Order{maker, traits, data})
    const [order] = decodeAbiParameters(
      [{ type: "tuple", components: [
        { type: "address", name: "maker" },
        { type: "uint256", name: "traits" },
        { type: "bytes", name: "data" },
      ]}],
      log.args.strategy!,
    ) as unknown as [{ maker: Address; traits: bigint; data: `0x${string}` }];
    out.push({
      maker: order.maker,
      strategyHash: log.args.strategyHash!,
      order: { maker: order.maker, traits: order.traits, data: order.data },
      block: log.blockNumber!,
    });
  }
  return out;
}

/** Aqua order hash = keccak256(abi.encode(order)) — cross-check against the event. */
export function orderHash(order: Order): `0x${string}` {
  return keccak256(
    encodePacked(
      ["address", "uint256", "bytes"],
      [order.maker, order.traits, order.data],
    ),
  );
}

/** Resolve everything the fill oracle needs about one strategy. Each side
 *  resolves ITS adapter from the maker's registry: (maker, token) -> adapter. */
export async function resolvePosition(
  client: PublicClient,
  strategy: Strategy,
  aqua: Address,
  router: Address,
  underlyingIn: Address,
  underlyingOut: Address,
): Promise<Position> {
  const configAddress = await client.readContract({
    address: router,
    abi: ROUTER_ABI,
    functionName: "MAKER_CONFIG",
  });

  // per-side adapter resolution: one registry lookup per token
  type SideCfg = { underlying: Address; adapter: Address; kind: number; autoManaged: boolean };
  const [sideIn, sideOut] = (await Promise.all([
    client.readContract({
      address: configAddress,
      abi: MAKER_CONFIG_ABI,
      functionName: "sides",
      args: [strategy.maker, underlyingIn],
    }),
    client.readContract({
      address: configAddress,
      abi: MAKER_CONFIG_ABI,
      functionName: "sides",
      args: [strategy.maker, underlyingOut],
    }),
  ])) as [SideCfg, SideCfg];

  const names = await Promise.all([
    sideIn.adapter !== zeroAddress
      ? client.readContract({ address: sideIn.adapter, abi: ADAPTER_ABI, functionName: "name" })
      : Promise.resolve("(unregistered)"),
    sideOut.adapter !== zeroAddress
      ? client.readContract({ address: sideOut.adapter, abi: ADAPTER_ABI, functionName: "name" })
      : Promise.resolve("(unregistered)"),
  ]);

  const position: Position = {
    strategy,
    router,
    makerConfig: {
      underlyingIn,
      underlyingOut,
      sideIn: { adapter: sideIn.adapter, kind: Number(sideIn.kind), autoManaged: sideIn.autoManaged },
      sideOut: { adapter: sideOut.adapter, kind: Number(sideOut.kind), autoManaged: sideOut.autoManaged },
    },
    adapterNames: { [sideIn.adapter]: names[0], [sideOut.adapter]: names[1] },
    tokens: {},
  };

  // virtual balances per token (yield-token counts), then price through ITS adapter
  const [balIn, balOut] = await client.readContract({
    address: aqua,
    abi: AQUA_ABI,
    functionName: "safeBalances",
    args: [strategy.maker, router, strategy.strategyHash, underlyingIn, underlyingOut],
  });

  const tokens: [Address, Address, bigint][] = [
    [underlyingIn, sideIn.adapter, balIn],
    [underlyingOut, sideOut.adapter, balOut],
  ];
  for (const [token, adapter, virtualRaw] of tokens) {
    if (adapter === zeroAddress) continue; // unregistered side: nothing to price
    const [symbol, decimals, rate, maxWd, yieldToken] = await Promise.all([
      client.readContract({ address: token, abi: ERC20_ABI, functionName: "symbol" }),
      client.readContract({ address: token, abi: ERC20_ABI, functionName: "decimals" }),
      client.readContract({ address: adapter, abi: ADAPTER_ABI, functionName: "exchangeRate", args: [token] }),
      client.readContract({ address: adapter, abi: ADAPTER_ABI, functionName: "maxWithdrawable", args: [strategy.maker, token] }),
      client.readContract({ address: adapter, abi: ADAPTER_ABI, functionName: "yieldToken", args: [token] }),
    ]);
    position.tokens[token] = {
      address: token,
      symbol,
      decimals,
      virtualRaw,
      exchangeRate: rate,
      effective: (virtualRaw * rate) / 10n ** 18n,
      maxWithdrawable: maxWd,
      yieldToken,
    };
  }
  return position;
}

/** Quote a fill through the router itself — the full fill oracle. Returns the
 *  revert reason on failure (Simulator.quote surfaces the exact on-chain error). */
export async function quoteFill(
  client: PublicClient,
  position: Position,
  tokenIn: Address,
  tokenOut: Address,
  amount: bigint,
): Promise<{ ok: true; amountOut: bigint } | { ok: false; reason: string }> {
  try {
    const [, amountOut] = await client.readContract({
      address: position.router,
      abi: ROUTER_ABI,
      functionName: "quote",
      args: [
        { maker: position.strategy.order.maker, traits: position.strategy.order.traits, data: position.strategy.order.data },
        tokenIn,
        tokenOut,
        amount,
        TAKER_TRAITS_DATA,
      ],
    });
    return { ok: true, amountOut };
  } catch (err) {
    return { ok: false, reason: revertReason(err) };
  }
}

/** Best-effort extraction of a revert message from a viem error. */
function revertReason(err: unknown): string {
  const e = err as { details?: string; shortMessage?: string; message?: string };
  return e.details || e.shortMessage || e.message || "unknown error";
}

/** Format a token amount for display. */
export function fmt(amount: bigint, decimals: number): string {
  return formatUnits(amount, decimals);
}
