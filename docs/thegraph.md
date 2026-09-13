# The Graph — composable & standardized data layer

This is the data side of Superposition: it turns the protocol's JIT capital movement into a
**standardized, composable** data product, so one query pattern spans many protocols and one
subgraph is reused across the app and the standardized queries.

## What we composed

| Product | What | Why it matters |
|---|---|---|
| **Messari Standardized Lending Subgraphs** | one schema across **Aave v3 · Compound v3 · Morpho · Spark** | the *same GraphQL query* returns supply APY per protocol — one pattern, many protocols |
| **SuperPosition Subgraph** (Studio) | our router fills, per-token adapter config, borrow config, ERC-4626 vault flows, v4-hook bucket flows | the protocol's own data, on the same event model for every adapter |

The leverage: Superposition already abstracts *many yield protocols behind one adapter
interface*. The data layer mirrors that — a single standardized query ranks venues, and a
single subgraph models every adapter's flows, because the underlying standard (ERC-4626) is
shared.

## One query, many protocols

`app/src/lib/thegraph.ts` — the same query runs against four Messari standardized deployments:

```graphql
query LendingMarkets($token: String!) {
  markets(where: { inputToken: $token, isActive: true }, orderBy: totalValueLockedUSD) {
    id name totalValueLockedUSD
    inputToken { symbol address }
    rates { rate side type }
  }
}
```

`fetchYields(token)` fans the query out across the four deployments and sorts by supply rate.
The console's **Lending intelligence** panel shows the result live; a maker can point its USDC/ETH
side at whichever venue tops the list.

## One pipeline, reused: ERC-4626 flows

Every Superposition adapter family reduces to **ERC-4626** (`Aave4626Vault`, `ERC4626Adapter`,
and the two vaults backing the Uniswap-v4 hook). The subgraph indexes the standard
`Deposit`/`Withdraw` events, so a single mapping models capital flows for any 4626 venue — the
same "reusable module for an emerging standard" the track asks for, expressed as a shared
entity (`VaultFlow`) rather than per-protocol code:

```graphql
type Vault { id: ID! asset: Bytes! deposits: Int! withdrawals: Int! totalAssetsIn: BigInt! totalAssetsOut: BigInt! }
type VaultFlow @entity(immutable: true) { vault: Vault! kind: String! assets: BigInt! shares: BigInt! ... }
```

## Deploy the SuperPosition subgraph (Subgraph Studio)

```bash
cd subgraph
npm install
npx graph codegen
npx graph build
graph auth <DEPLOY_KEY>   # once (Subgraph Studio → your deploy key)
npx graph deploy superposition-liquid-sepolia -l 0.0.1
```

Then set:

| Env var | Where | Used by |
|---|---|---|
| `NEXT_PUBLIC_THEGRAPH_API_KEY` | `app/.env` / Vercel | the lending-intelligence panel (Graph gateway) |

## Files

```
subgraph/            schema.graphql · subgraph.yaml · networks.json · abis/ · src/ (AssemblyScript)
app/src/lib/thegraph.ts        the standardized lending client (one query, four protocols)
app/src/components/LendingIntel.tsx   live lending-intelligence panel in the console
```

Indexed data sources on Sepolia (`chains.sepolia`, startBlock `11686230`): router `Swapped`,
MakerConfig `SideSet`/`BorrowSet`, the two ERC-4626 vaults `Deposit`/`Withdraw`, the
Superposition hook `Deposited`/`Withdrawn`.
