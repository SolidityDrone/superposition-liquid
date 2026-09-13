#!/usr/bin/env node
/**
 * Subgraph MCP — cross-protocol analysis on The Graph.
 *
 * Composes The Graph's products behind two MCP tools:
 *   - lending_yields      → one standardized (Messari) query across Aave v3,
 *                          Compound v3, Morpho, Spark via the Graph gateway.
 *   - superposition_flows → the SuperPosition subgraph (router fills + ERC-4626
 *                          vault flows), so agent analysis spans BOTH the
 *                          standardized protocol schema AND our own protocol.
 *
 * Env:
 *   THEGRAPH_API_KEY          Graph gateway API key (Subgraph Studio / Market)
 *   SUPERPOSITION_SUBGRAPH_ID deployment id of the SuperPosition subgraph
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const KEY = process.env.THEGRAPH_API_KEY ?? "";
const SUPER = process.env.SUPERPOSITION_SUBGRAPH_ID ?? "";
const gateway = (id) => `https://gateway.thegraph.com/api/${KEY}/subgraphs/id/${id}`;

/* The Messari Standardized Lending schema — identical across deployments. */
const LENDING = {
  "Aave v3": "JCNWRypm7FYwV8fx5HhzZPSFaMxgkPuw4TnR3Gpi81zk",
  "Compound v3": "AwoxEZbiWLvv6e3QdvdMZw4WDURdGbvPfHmZRc8Dpfz9",
  Morpho: "FKe6ANnWmGPE6hajGLoTgPrVF2jYPHiRu2Jwcg9ZmG9A",
  Spark: "GbKdmBe4ycCYCQLQSjqGg6UHYoYfbyJyq5WrG35pv1si",
};

const LENDING_QUERY = `
  query ($token: String!, $first: Int!) {
    markets(first: $first, where: { inputToken: $token, isActive: true }, orderBy: totalValueDepositedUSD, orderDirection: desc) {
      id name totalValueDepositedUSD
      inputToken { symbol }
      rates { rate side }
    }
  }
`;

async function gql(endpoint, query, variables) {
  const res = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) throw new Error(`Graph ${res.status}: ${await res.text()}`);
  const json = await res.json();
  if (json.errors?.length) throw new Error(json.errors[0].message);
  return json.data;
}

const server = new McpServer({ name: "superposition-subgraph-mcp", version: "0.1.0" });

server.tool(
  "lending_yields",
  "Supply APY for a token across the standardized Messari lending subgraphs (one query, many protocols).",
  { token: z.string().describe("token address (lowercase)"), first: z.number().int().positive().max(10).optional() },
  async ({ token, first }) => {
    if (!KEY) return { content: [{ type: "text", text: "THEGRAPH_API_KEY not set" }] };
    const rows = [];
    for (const [protocol, id] of Object.entries(LENDING)) {
      try {
        const data = await gql(gateway(id), LENDING_QUERY, { token: token.toLowerCase(), first: first ?? 3 });
        for (const m of data.markets) {
          const r = m.rates.find((x) => x.side === "LENDER");
          rows.push({ protocol, market: m.name, symbol: m.inputToken.symbol, tvlUSD: Number(m.totalValueDepositedUSD), supplyRate: r ? Number(r.rate) : 0 });
        }
      } catch { /* a protocol without this market is skipped */ }
    }
    rows.sort((a, b) => b.supplyRate - a.supplyRate);
    return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
  },
);

server.tool(
  "superposition_flows",
  "SuperPosition subgraph: maker fills and ERC-4626 vault flows (the protocol's own data).",
  { maker: z.string().optional(), first: z.number().int().positive().max(100).optional() },
  async ({ maker, first }) => {
    if (!KEY || !SUPER) return { content: [{ type: "text", text: "THEGRAPH_API_KEY / SUPERPOSITION_SUBGRAPH_ID not set" }] };
    const q = `
      query ($maker: String, $first: Int!) {
        fills(first: $first, orderBy: timestamp, orderDirection: desc, where: { maker: $maker }) {
          id tokenIn tokenOut amountIn amountOut timestamp maker { id fillCount }
        }
      }
    `;
    const data = await gql(gateway(SUPER), q, { maker: maker ?? null, first: first ?? 20 });
    return { content: [{ type: "text", text: JSON.stringify(data.fills, null, 2) }] };
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
