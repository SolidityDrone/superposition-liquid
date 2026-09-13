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
  slug.includes("aave") ? "aave" : slug.includes("morpho") ? "morpho" : slug.includes("spark") ? "spark" : "morpho";

const LINE_COLORS = ["#8fd8ff", "#4db8ff", "#ff2bd6", "#ffffff"];

const fmtInt = (n: number) => new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 }).format(n);

/** Multi-protocol supply-APY history (bps) as overlaid lines — same snapshot entity everywhere. */
function ApyChart({ series }: { series: { name: string; data: number[] }[] }) {
  const W = 640;
  const H = 140;
  const padL = 34;
  const padR = 10;
  const padT = 12;
  const padB = 20;
  const all = series.flatMap((s) => s.data).filter((v) => v > 0);
  if (all.length < 2) return null;
  const min = Math.min(...all);
  const max = Math.max(...all);
  const range = max - min || 1;
  const n = Math.max(...series.map((s) => s.data.length));
  const x = (i: number) => padL + (i / Math.max(1, n - 1)) * (W - padL - padR);
  const y = (v: number) => padT + (1 - (v - min) / range) * (H - padT - padB);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label="supply APY history">
      {[min, (min + max) / 2, max].map((v, i) => (
        <g key={i}>
          <line x1={padL} y1={y(v)} x2={W - padR} y2={y(v)} stroke="rgba(77,184,255,.12)" />
          <text x={padL - 4} y={y(v) + 3} textAnchor="end" fontSize="9" fill="#5f7a96" fontFamily="monospace">
            {v.toFixed(0)}
          </text>
        </g>
      ))}
      {series.map((s, si) => (
        <polyline
          key={s.name}
          points={s.data.map((v, i) => `${x(i)},${y(v)}`).join(" ")}
          fill="none"
          stroke={LINE_COLORS[si % LINE_COLORS.length]}
          strokeWidth="1.6"
          opacity="0.9"
        />
      ))}
    </svg>
  );
}

export default function LendingIntel() {
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
      const top = data.slice(0, 4);
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

  const best = rows && rows.length ? rows[0] : null;

  return (
    <div className="pnl">
      <div className="pnl-head">
        <div className="pnl-title">Lending intelligence · Messari standardized subgraphs</div>
        <span className="pill on">{LENDING_SUBGRAPHS.length} protocols · one schema</span>
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
            title={`Cross-protocol lending intelligence for ${t.sym}`}
          >
            <TokenIcon symbol={t.sym} size={20} />
          </button>
        ))}
      </div>

      {!HAS_GRAPH_KEY ? (
        <div className="pnl-note" style={{ borderTop: "none" }}>
          Set <b>NEXT_PUBLIC_THEGRAPH_API_KEY</b> in <code>app/.env</code> and restart.
        </div>
      ) : loading ? (
        <div className="pnl-note" style={{ borderTop: "none" }}>querying {LENDING_SUBGRAPHS.length} standardized subgraphs…</div>
      ) : err ? (
        <div className="pnl-note" style={{ borderTop: "none", color: "var(--red)" }}>{err}</div>
      ) : rows && rows.length > 0 ? (
        <>
          <div className="grid-scroll">
            <table className="dtable">
              <thead>
                <tr>
                  {["#", "Venue", "Market", "TVL", "Deposits", "Borrows", "Util.", "Supply", "Borrow", "Spread", "Revenue", "Liqs", "Liq $", "Users", "Pos.", "14d"].map((h) => (
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
                    <td style={{ color: "var(--text-dim)", fontSize: 12 }}>{r.market}</td>
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
                    <td className="num">{formatUSD(r.revenueUSD)}</td>
                    <td className="num">{fmtInt(r.liqCount)}</td>
                    <td className="num">{formatUSD(r.liqUSD)}</td>
                    <td className="num">{fmtInt(r.borrowers)}</td>
                    <td className="num">{fmtInt(r.positions)}</td>
                    <td>
                      {r.history.length > 1 ? (
                        <svg width={56} height={18} viewBox="0 0 56 18" aria-hidden>
                          {(() => {
                            const mn = Math.min(...r.history);
                            const mx = Math.max(...r.history);
                            const rg = mx - mn || 1;
                            return (
                              <polyline
                                points={r.history.map((v, j) => `${(j / (r.history.length - 1)) * 56},${(18 - ((v - mn) / rg) * 18).toFixed(1)}`).join(" ")}
                                fill="none"
                                stroke="#8fd8ff"
                                strokeWidth="1.2"
                              />
                            );
                          })()}
                        </svg>
                      ) : (
                        <span style={{ color: "var(--text-dim)" }}>—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div style={{ marginTop: 14 }}>
            <div className="pc-label" style={{ marginBottom: 6 }}>
              Supply APY · 14d · {rows.slice(0, 4).map((r) => r.protocol).join(" · ")}
            </div>
            <ApyChart series={rows.slice(0, 4).map((r) => ({ name: r.protocol, data: r.history }))} />
          </div>

          {best && (
            <div className="pnl-note">
              Best <b>{token.sym}</b> supply right now: <b style={{ color: "var(--cyan)" }}>{best.protocol}</b> at{" "}
              <b>{best.depositAPY}</b> ({formatUSD(best.tvlUSD)} TVL, {Math.round(best.utilization * 100)}% utilization,
              reserve factor {best.reserveFactor != null ? `${best.reserveFactor.toFixed(1)}%` : "—"}). Same GraphQL
              shape for all {LENDING_SUBGRAPHS.length} protocols — only the subgraph id changes.
            </div>
          )}
        </>
      ) : (
        <div className="pnl-note" style={{ borderTop: "none" }}>no active market for {token.sym}.</div>
      )}
    </div>
  );
}
