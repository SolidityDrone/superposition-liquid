/**
 * The Graph — Messari Standardized Lending Subgraph Client
 *
 * One query pattern, five protocols. The schema is identical across
 * every Messari deployment, so the same query works on Aave, Morpho,
 * Compound, Spark, and Euler.
 */

const API_KEY = process.env.NEXT_PUBLIC_THEGRAPH_API_KEY ?? "";

/* ---------- subgraph endpoints ---------- */

type SubgraphEntry = {
  name: string;
  slug: string;
  endpoint: string;
};

export const LENDING_SUBGRAPHS: SubgraphEntry[] = [
  {
    name: "Aave v3",
    slug: "aave-v3",
    endpoint: `https://gateway.thegraph.com/api/${API_KEY}/subgraphs/id/JCNWRypm7FYwV8fx5HhzZPSFaMxgkPuw4TnR3Gpi81zk`,
  },
  {
    name: "Compound v3",
    slug: "compound-v3",
    endpoint: `https://gateway.thegraph.com/api/${API_KEY}/subgraphs/id/AwoxEZbiWLvv6e3QdvdMZw4WDURdGbvPfHmZRc8Dpfz9`,
  },
  {
    name: "Morpho",
    slug: "morpho",
    endpoint: `https://gateway.thegraph.com/api/${API_KEY}/subgraphs/id/FKe6ANnWmGPE6hajGLoTgPrVF2jYPHiRu2Jwcg9ZmG9A`,
  },
  {
    name: "Spark",
    slug: "spark",
    endpoint: `https://gateway.thegraph.com/api/${API_KEY}/subgraphs/id/GbKdmBe4ycCYCQLQSjqGg6UHYoYfbyJyq5WrG35pv1si`,
  },
];

/* ---------- types ---------- */

export type MarketRate = {
  rate: string;
  side: "LENDER" | "BORROWER";
  type: "VARIABLE" | "FIXED" | "STABLE";
};

export type Market = {
  id: string;
  name: string;
  inputToken: { symbol: string; address: string };
  totalValueLockedUSD: string;
  totalDepositBalanceUSD: string;
  rates: MarketRate[];
  protocol: { name: string; slug: string };
};

export type YieldResult = {
  protocol: string;
  slug: string;
  market: string;
  token: string;
  tvlUSD: string;
  depositAPY: string;
  depositAPYBps: number;
};

/* ---------- the one query ---------- */

const LENDING_QUERY = `
  query LendingMarkets($token: String!, $first: Int!, $skip: Int!) {
    markets(
      first: $first
      skip: $skip
      where: { inputToken: $token, isActive: true }
      orderBy: totalValueLockedUSD
      orderDirection: desc
    ) {
      id
      name
      inputToken { symbol address }
      totalValueLockedUSD
      totalDepositBalanceUSD
      rates {
        rate
        side
        type
      }
      protocol { name slug }
    }
  }
`;

/* ---------- fetcher ---------- */

async function querySubgraph<T>(
  endpoint: string,
  query: string,
  variables: Record<string, unknown>,
): Promise<T> {
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

/* ---------- public API ---------- */

/**
 * Fetch USDC (or any token) supply APY across all standardized subgraphs.
 * Same query — different endpoint per protocol. That's the composition.
 */
export async function fetchYields(
  tokenAddress: string,
): Promise<YieldResult[]> {
  const results = await Promise.allSettled(
    LENDING_SUBGRAPHS.map(async (sub) => {
      const data = await querySubgraph<{ markets: Market[] }>(
        sub.endpoint,
        LENDING_QUERY,
        { token: tokenAddress.toLowerCase(), first: 5, skip: 0 },
      );
      return data.markets.map((m) => parseMarket(sub, m));
    }),
  );

  const all = results
    .filter((r): r is PromiseFulfilledResult<YieldResult[]> => r.status === "fulfilled")
    .flatMap((r) => r.value);

  return all.sort((a, b) => b.depositAPYBps - a.depositAPYBps);
}

function parseMarket(sub: SubgraphEntry, m: Market): YieldResult {
  const supplyRate = m.rates.find((r) => r.side === "LENDER");
  const apyBps = supplyRate ? parseFloat(supplyRate.rate) * 10000 : 0;
  return {
    protocol: sub.name,
    slug: sub.slug,
    market: m.name,
    token: m.inputToken.symbol,
    tvlUSD: m.totalValueLockedUSD,
    depositAPY: apyBps >= 100 ? `${(apyBps / 100).toFixed(2)}%` : `${apyBps.toFixed(1)} bps`,
    depositAPYBps: apyBps,
  };
}

/* ---------- helpers ---------- */

export function formatUSD(val: string): string {
  const n = parseFloat(val);
  if (n >= 1e9) return `$${(n / 1e9).toFixed(1)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}
