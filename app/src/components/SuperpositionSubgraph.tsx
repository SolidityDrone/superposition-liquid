"use client";

import { useEffect, useState } from "react";
import {
  fetchSuperposition,
  formatUSD,
  type SuperVault,
  type SuperFlow,
  type SuperMaker,
} from "@/lib/thegraph";
import { STACK } from "@/lib/sepolia";
import { TokenIcon } from "@/components/icons";

const vaultSymbol = (id: string) => {
  const a = id.toLowerCase();
  if (a === STACK.vaultUSDC.toLowerCase()) return "USDC";
  if (a === STACK.vaultUSDT.toLowerCase()) return "USDT";
  return id.slice(0, 8);
};

/** Our two vaults are 6-decimal stables. */
const decimalsOf = (sym: string) => (sym === "USDC" || sym === "USDT" ? 6 : 18);
const fmtAmt = (v: string | number, sym: string) => {
  const n = Number(v) / 10 ** decimalsOf(sym);
  return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
};

const ago = (ts: string) => {
  const s = Math.max(0, Math.floor(Date.now() / 1000) - Number(ts));
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
};

export default function SuperpositionSubgraph() {
  const [vaults, setVaults] = useState<SuperVault[]>([]);
  const [flows, setFlows] = useState<SuperFlow[]>([]);
  const [makers, setMakers] = useState<SuperMaker[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const d = await fetchSuperposition();
        setVaults(d.vaults);
        setFlows(d.flows);
        setMakers(d.makers);
      } catch (e) {
        setErr((e as Error).message.split("\n")[0]);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  return (
    <div className="pnl">
      <div className="pnl-head">
        <div className="pnl-title">SuperPosition subgraph · live</div>
      </div>

      {loading ? (
        <div className="pnl-note" style={{ borderTop: "none" }}>querying the SuperPosition subgraph…</div>
      ) : err ? (
        <div className="pnl-note" style={{ borderTop: "none", color: "var(--red)" }}>{err}</div>
      ) : (
        <>
          <div className="grid-scroll">
            <table className="dtable">
              <thead>
                <tr>{["Vault", "Deposits", "Withdrawals", "Assets in", "Assets out", "Net"].map((h) => <th key={h}>{h}</th>)}</tr>
              </thead>
              <tbody>
                {vaults.length === 0 ? (
                  <tr><td colSpan={6} className="num" style={{ color: "var(--text-dim)" }}>no vault flows indexed yet</td></tr>
                ) : (
                  vaults.map((v) => {
                    const sym = vaultSymbol(v.id);
                    const net = (Number(v.totalAssetsIn) - Number(v.totalAssetsOut)) / 10 ** decimalsOf(sym);
                    return (
                      <tr key={v.id}>
                        <td>
                          <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                            <TokenIcon symbol={sym} size={14} />
                            <b>{sym}</b>
                          </span>
                        </td>
                        <td className="num">{v.deposits}</td>
                        <td className="num">{v.withdrawals}</td>
                        <td className="num">{fmtAmt(v.totalAssetsIn, sym)}</td>
                        <td className="num">{fmtAmt(v.totalAssetsOut, sym)}</td>
                        <td className="num">{net >= 0 ? "+" : ""}{net.toLocaleString(undefined, { maximumFractionDigits: 2 })}</td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>

          <div className="grid-scroll" style={{ marginTop: 12 }}>
            <table className="dtable">
              <thead>
                <tr>{["Recent vault flow", "Vault", "Assets", "Shares", "Owner", "Age"].map((h) => <th key={h}>{h}</th>)}</tr>
              </thead>
              <tbody>
                {flows.length === 0 ? (
                  <tr><td colSpan={6} className="num" style={{ color: "var(--text-dim)" }}>no flows yet — deposit into a vault to index one</td></tr>
                ) : (
                  flows.map((f) => (
                    <tr key={f.id}>
                      <td><span className={`pill ${f.kind === "deposit" ? "on" : "off"}`}>{f.kind}</span></td>
                      <td><span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><TokenIcon symbol={vaultSymbol(f.vault.id)} size={14} />{vaultSymbol(f.vault.id)}</span></td>
                      <td className="num">{fmtAmt(f.assets, vaultSymbol(f.vault.id))}</td>
                      <td className="num">{fmtAmt(f.shares, vaultSymbol(f.vault.id))}</td>
                      <td className="num">{f.owner.slice(0, 6)}…{f.owner.slice(-4)}</td>
                      <td className="num">{ago(f.timestamp)}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          <div className="pnl-note">
            <b>{makers.length}</b> maker{makers.length === 1 ? "" : "s"} ·{" "}
            {makers.slice(0, 3).map((m) => `${m.id.slice(0, 6)}… ${m.fillCount} fills`).join(" · ") || "no fills indexed yet"} ·
            indexed from the ERC-4626 <code>Deposit</code>/<code>Withdraw</code> + router <code>Swapped</code> events.
          </div>
        </>
      )}
    </div>
  );
}
