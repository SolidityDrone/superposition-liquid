"use client";

import { useEffect, useState } from "react";
import {
  LENDING_SUBGRAPHS,
  fetchYields,
  fetchApyHistory,
  formatUSD,
  HAS_GRAPH_KEY,
  type YieldResult,
} from "@/lib/thegraph";
import { TokenIcon, ProtocolIcon } from "@/components/icons";

/** Mainnet addresses used by the Messari standardized lending subgraphs. */
const MAINNET = {
  USDC: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  DAI: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
} as const;

const TOKEN_CHOICES = [
  { sym: "USDC", addr: MAINNET.USDC },
  { sym: "WETH", addr: MAINNET.WETH },
  { sym: "DAI", addr: MAINNET.DAI },
];

const protocolId = (slug: string) =>
  slug.includes("aave") ? "aave" : slug.includes("morpho") ? "morpho" : slug.includes("spark") ? "spark" : slug.includes("euler") ? "euler" : "morpho";

function Spark({ data }: { data: number[] }) {
  if (!data || data.length < 2) return <span style={{ color: "var(--text-dim)" }}>—</span>;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const w = 64;
  const h = 18;
  const pts = data.map((v, i) => `${(i / (data.length - 1)) * w},${(h - ((v - min) / range) * h).toFixed(1)}`).join(" ");
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} aria-hidden>
      <polyline points={pts} fill="none" stroke="#fff" strokeWidth="1.2" />
    </svg>
  );
}

export default function YieldLeaderboard() {
  const [token, setToken] = useState(TOKEN_CHOICES[0]);
  const [rows, setRows] = useState<YieldResult[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function load(t: (typeof TOKEN_CHOICES)[number]) {
    setLoading(true);
    setErr(null);
    setRows(null);
    try {
      const data = await fetchYields(t.addr);
      setRows(data);
      const top = data.slice(0, 6);
      const hist = await Promise.all(top.map((r) => fetchApyHistory(r.slug, r.marketId, 14)));
      setRows(data.map((r, i) => (i < top.length ? { ...r, history: hist[i] } : r)));
    } catch (e) {
      setErr((e as Error).message.split("\n")[0]);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (HAS_GRAPH_KEY) load(token);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="pnl">
      <div className="pnl-head">
        <div className="pnl-title">Yield leaderboard · one standardized query</div>
        <span className="pill on">{LENDING_SUBGRAPHS.length} protocols · schema-identical</span>
      </div>

      <div className="tabs" style={{ marginBottom: 10 }}>
        {TOKEN_CHOICES.map((t) => (
          <button
            key={t.sym}
            className={`tab-logo sm ${token.sym === t.sym ? "active" : ""}`}
            onClick={() => {
              setToken(t);
              if (HAS_GRAPH_KEY) load(t);
            }}
            title={`Best standardized lending venue for ${t.sym}`}
          >
            <TokenIcon symbol={t.sym} size={20} />
          </button>
        ))}
      </div>

      {!HAS_GRAPH_KEY ? (
        <div className="pnl-note" style={{ borderTop: "none" }}>
          Set <b>NEXT_PUBLIC_THEGRAPH_API_KEY</b> in <code>app/.env</code> and restart (Next inlines
          <code>NEXT_PUBLIC_*</code> at build time) to hit the live Graph gateway.
        </div>
      ) : loading ? (
        <div className="pnl-note" style={{ borderTop: "none" }}>querying {LENDING_SUBGRAPHS.length} standardized subgraphs…</div>
      ) : err ? (
        <div className="pnl-note" style={{ borderTop: "none", color: "var(--red)" }}>{err}</div>
      ) : rows && rows.length > 0 ? (
        <div className="grid-scroll">
          <table className="dtable">
            <thead>
              <tr>
                {["#", "Venue", "Token", "TVL", "Deposits", "Borrows", "Util.", "Supply APY", "Borrow APY", "Spread", "LTV", "14d"].map((h) => (
                  <th key={h}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.slice(0, 8).map((r, i) => (
                <tr key={`${r.slug}-${r.marketId}-${i}`}>
                  <td className="num">{i + 1}</td>
                  <td>
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                      <ProtocolIcon id={protocolId(r.slug)} />
                      <b>{r.protocol}</b>
                    </span>
                  </td>
                  <td><TokenIcon symbol={r.token} size={14} /></td>
                  <td className="num">{formatUSD(r.tvlUSD)}</td>
                  <td className="num">{formatUSD(r.depositUSD)}</td>
                  <td className="num">{formatUSD(r.borrowUSD)}</td>
                  <td className="num">
                    <span className="utilbar"><span style={{ width: `${Math.round(r.utilization * 100)}%` }} /></span>
                    {Math.round(r.utilization * 100)}%
                  </td>
                  <td className="num" style={{ color: i === 0 ? "#fff" : undefined, fontWeight: i === 0 ? 700 : 400 }}>{r.depositAPY}</td>
                  <td className="num">{r.borrowAPY}</td>
                  <td className="num">{r.spreadBps > 0 ? `+${(r.spreadBps / 100).toFixed(2)}%` : "—"}</td>
                  <td className="num">{r.ltv != null ? `${r.ltv.toFixed(0)}%` : "—"}</td>
                  <td><Spark data={r.history} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="pnl-note" style={{ borderTop: "none" }}>no active market for {token.sym} across the standardized subgraphs.</div>
      )}

      <div className="pnl-note">
        Same <b>schema</b>, same entities across {LENDING_SUBGRAPHS.length} protocols ({LENDING_SUBGRAPHS.map((s) => s.name).join(" · ")}):
        markets + <code>marketDailySnapshots</code> give APY, TVL, deposits, borrows, utilization, borrow spread, LTV and a rate history
        for <i>any</i> of them through one query shape. Superposition&apos;s ERC-4626 / Aave-backed vaults route the underlying to whichever
        venue tops the supply-APY column.
      </div>
    </div>
  );
}
