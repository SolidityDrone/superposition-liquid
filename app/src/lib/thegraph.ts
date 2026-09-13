/**
 * The Graph — Messari Standardized Lending Subgraph Client
 *
 * One query pattern, many protocols. The schema is identical across every
 * Messari deployment, so the same query works on Aave, Morpho, Compound, Spark
 * and Euler — and the same daily-snapshot entity gives a rate history for any
 * of them. This is the leverage of a standardized schema.
 */

const API_KEY = process.env.NEXT_PUBLIC_THEGRAPH_API_KEY ?? "";

export const HAS_GRAPH_KEY = API_KEY.length > 0;

/**
 * Our own SuperPosition subgraph on Subgraph Studio — queryable WITHOUT an API
 * key (Studio `.../query/<id>/<slug>/version/latest` endpoint). This is the
 * protocol's own data: adapter config, borrow config, router fills and the
 * ERC-4626 vault flows.
 */
export const SUPERPOSITION_SUBGRAPH =
  process.env.NEXT_PUBLIC_SUPERPOSITION_SUBGRAPH ??
  "https://api.studio.thegraph.com/query/115755/superpos/version/latest";

export type SuperVault = {
  id: string;
  deposits: number;
  withdrawals: number;
  totalAssetsIn: string;
  totalAssetsOut: string;
};

export type SuperFlow = {
  id: string;
  kind: string;
  assets: string;
  shares: string;
  owner: string;
  timestamp: string;
  vault: { id: string };
};

export type SuperMaker = { id: string; fillCount: number; volumeIn: string };

const SUPER_QUERY = `
  query {
    vaults(first: 10) { id deposits withdrawals totalAssetsIn totalAssetsOut }
    vaultFlows(first: 8, orderBy: blockNumber, orderDirection: desc) {
      id kind assets shares owner timestamp vault { id }
    }
    makers(first: 10, orderBy: volumeIn, orderDirection: desc) { id fillCount volumeIn }
  }
`;

export async function fetchSuperposition(): Promise<{ vaults: SuperVault[]; flows: SuperFlow[]; makers: SuperMaker[] }> {
  const data = await gql<{ vaults: SuperVault[]; vaultFlows: SuperFlow[]; makers: SuperMaker[] }>(
    SUPERPOSITION_SUBGRAPH,
    SUPER_QUERY,
    {},
  );
  return { vaults: data.vaults ?? [], flows: data.vaultFlows ?? [], makers: data.makers ?? [] };
}

type SubgraphEntry = { name: string; slug: string; endpoint: string };

export const LENDING_SUBGRAPHS: SubgraphEntry[] = [
  { name: "Aave v3", slug: "aave-v3", endpoint: `https://gateway.thegraph.com/api/${API_KEY}/subgraphs/id/JCNWRypm7FYwV8fx5HhzZPSFaMxgkPuw4TnR3Gpi81zk` },
  { name: "Compound v3", slug: "compound-v3", endpoint: `https://gateway.thegraph.com/api/${API_KEY}/subgraphs/id/AwoxEZbiWLvv6e3QdvdMZw4WDURdGbvPfHmZRc8Dpfz9` },
  { name: "Morpho", slug: "morpho", endpoint: `https://gateway.thegraph.com/api/${API_KEY}/subgraphs/id/FKe6ANnWmGPE6hajGLoTgPrVF2jYPHiRu2Jwcg9ZmG9A` },
  { name: "Spark", slug: "spark", endpoint: `https://gateway.thegraph.com/api/${API_KEY}/subgraphs/id/GbKdmBe4ycCYCQLQSjqGg6UHYoYfbyJyq5WrG35pv1si` },
];

/* ---------- types ---------- */

export type MarketRate = { rate: string; side: "LENDER" | "BORROWER"; type: "VARIABLE" | "FIXED" | "STABLE" };

type Market = {
  id: string;
  name: string;
  inputToken: { symbol: string; address: string };
  totalValueLockedUSD: string;
  totalDepositBalanceUSD: string;
  totalBorrowBalanceUSD: string;
  maximumLTV?: string | null;
  liquidationThreshold?: string | null;
  canUseAsCollateral?: boolean | null;
  canBorrowFrom?: boolean | null;
  rates: MarketRate[];
  protocol: { name: string; slug: string };
};

export type YieldResult = {
  protocol: string;
  slug: string;
  market: string;
  marketId: string;
  token: string;
  tvlUSD: string;
  depositUSD: string;
  borrowUSD: string;
  utilization: number; // borrows / deposits, 0..1
  depositAPY: string;
  depositAPYBps: number;
  borrowAPY: string;
  borrowAPYBps: number;
  spreadBps: number; // borrow APY - supply APY
  ltv: number | null; // maximumLTV (%)
  liqThreshold: number | null; // liquidation threshold (%)
  history: number[]; // supply-rate bps, oldest -> newest (may be empty)
};

/* ---------- queries ---------- */

const FIELDS_BASE = `
  id name
  inputToken { symbol address }
  totalValueLockedUSD
  totalDepositBalanceUSD
  totalBorrowBalanceUSD
  rates { rate side type }
  protocol { name slug }`;
const FIELDS_RISK = `
  maximumLTV liquidationThreshold canUseAsCollateral canBorrowFrom`;

const marketQuery = (extra: string) => `
  query LendingMarkets($token: String!, $first: Int!) {
    markets(first: $first, where: { inputToken: $token, isActive: true }, orderBy: totalValueLockedUSD, orderDirection: desc) {
      ${FIELDS_BASE}${extra}
    }
  }
`;

const SNAPSHOT_QUERY = `
  query Snapshots($market: String!, $first: Int!) {
    marketDailySnapshots(first: $first, orderBy: timestamp, orderDirection: desc, where: { market: $market }) {
      timestamp
      rates { rate side }
    }
  }
`;

/* ---------- fetchers ---------- */

async function gql<T>(endpoint: string, query: string, variables: Record<string, unknown>): Promise<T> {
  const res = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) throw new Error(`Graph ${res.status}: ${await res.text()}`);
  const json = await res.json();
  if (json.errors?.length) throw new Error(json.errors[0].message);
  return json.data as T;
}

/** One query, every protocol. Tries the richer (risk) fields, falls back to the base schema. */
export async function fetchYields(tokenAddress: string): Promise<YieldResult[]> {
  const results = await Promise.allSettled(
    LENDING_SUBGRAPHS.map(async (sub) => {
      let markets: Market[];
      try {
        const data = await gql<{ markets: Market[] }>(sub.endpoint, marketQuery(FIELDS_RISK), { token: tokenAddress.toLowerCase(), first: 5 });
        markets = data.markets;
      } catch {
        const data = await gql<{ markets: Market[] }>(sub.endpoint, marketQuery(""), { token: tokenAddress.toLowerCase(), first: 5 });
        markets = data.markets;
      }
      return markets.map((m) => parseMarket(sub, m));
    }),
  );
  const all = results
    .filter((r): r is PromiseFulfilledResult<YieldResult[]> => r.status === "fulfilled")
    .flatMap((r) => r.value);
  return all.sort((a, b) => b.depositAPYBps - a.depositAPYBps);
}

/** Daily supply-rate history for a market — the same snapshot entity across protocols. */
export async function fetchApyHistory(slug: string, marketId: string, days = 14): Promise<number[]> {
  const sub = LENDING_SUBGRAPHS.find((s) => s.slug === slug);
  if (!sub) return [];
  try {
    const data = await gql<{ marketDailySnapshots: { timestamp: string; rates: MarketRate[] }[] }>(
      sub.endpoint,
      SNAPSHOT_QUERY,
      { market: marketId, first: days },
    );
    return data.marketDailySnapshots
      .map((s) => {
        const r = s.rates.find((x) => x.side === "LENDER");
        return r ? parseFloat(r.rate) * 100 : 0;
      })
      .reverse();
  } catch {
    return [];
  }
}

function bps(rate?: MarketRate): number {
  // Messari `rate` is already a percentage (e.g. 3.5252 = 3.53%); bps = pct * 100.
  return rate ? parseFloat(rate.rate) * 100 : 0;
}
const fmtBps = (b: number) => (b >= 100 ? `${(b / 100).toFixed(2)}%` : `${b.toFixed(1)} bps`);

function parseMarket(sub: SubgraphEntry, m: Market): YieldResult {
  const supply = bps(m.rates.find((r) => r.side === "LENDER"));
  const borrow = bps(m.rates.find((r) => r.side === "BORROWER"));
  const deposit = parseFloat(m.totalDepositBalanceUSD || "0");
  const borrowed = parseFloat(m.totalBorrowBalanceUSD || "0");
  const ltvRaw = m.maximumLTV != null ? parseFloat(m.maximumLTV) : NaN;
  const liqRaw = m.liquidationThreshold != null ? parseFloat(m.liquidationThreshold) : NaN;
  return {
    protocol: sub.name,
    slug: sub.slug,
    market: m.name,
    marketId: m.id,
    token: m.inputToken.symbol,
    tvlUSD: m.totalValueLockedUSD,
    depositUSD: m.totalDepositBalanceUSD,
    borrowUSD: m.totalBorrowBalanceUSD,
    utilization: deposit > 0 ? Math.min(borrowed / deposit, 1) : 0,
    depositAPY: fmtBps(supply),
    depositAPYBps: supply,
    borrowAPY: fmtBps(borrow),
    borrowAPYBps: borrow,
    spreadBps: borrow - supply,
    ltv: Number.isNaN(ltvRaw) ? null : ltvRaw,
    liqThreshold: Number.isNaN(liqRaw) ? null : liqRaw,
    history: [],
  };
}

export function formatUSD(val: string): string {
  const n = parseFloat(val);
  if (n >= 1e9) return `$${(n / 1e9).toFixed(1)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}
