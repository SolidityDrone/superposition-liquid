"use client";

export type LiquidityRange = {
  lower: number;
  upper: number;
  liquidity: bigint;
  c0: bigint;
  c1: bigint;
  active: boolean;
};

const fmtCompact = (n: number) =>
  n === 0 ? "0" : new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 }).format(n);

/**
 * Liquidity-by-tick-range chart (Uniswap v4 style). One bar per bucket, spanning
 * its tick range; the marker is the pool's current tick. Shows where the maker's
 * capital sits relative to spot.
 */
export default function PoolCurve({
  ranges,
  tick,
  price,
  feeBps = 100,
}: {
  ranges: LiquidityRange[];
  tick?: number;
  price?: number;
  feeBps?: number;
}) {
  const W = 640;
  const H = 180;
  const padL = 14;
  const padR = 14;
  const padT = 16;
  const padB = 26;

  const ts = ranges.flatMap((r) => [r.lower, r.upper]);
  ts.push(tick ?? 0, 0);
  const dMin = Math.min(...ts);
  const dMax = Math.max(...ts);
  const span = Math.max(1, dMax - dMin);
  const x = (t: number) => padL + ((t - dMin) / span) * (W - padL - padR);

  const maxVal = Math.max(1, ...ranges.map((r) => Number(r.c0 + r.c1)));
  const barTop = (v: number) => H - padB - (v / maxVal) * (H - padT - padB);

  const zeroX = x(0);
  const tickX = x(tick ?? 0);
  const gridTicks = [dMin, Math.round((dMin + dMax) / 2), dMax];
  const totalLiq = ranges.reduce((s, r) => s + Number(r.liquidity), 0);

  return (
    <div className="pool-curve">
      <div className="pool-curve-head">
        <span className="pc-label">Liquidity by tick range</span>
        <span className="pc-meta">
          fee {(feeBps / 10000).toFixed(2)}% · tick <b>{tick ?? "—"}</b> · price <b>{price !== undefined ? price.toFixed(4) : "—"}</b> · L{" "}
          <b>{fmtCompact(totalLiq)}</b>
        </span>
      </div>

      <svg viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label="pool liquidity by tick range">
        <defs>
          <linearGradient id="pc-bar" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#8fd8ff" />
            <stop offset="100%" stopColor="#1f6bff" />
          </linearGradient>
        </defs>

        {/* grid */}
        {gridTicks.map((t) => (
          <g key={`g${t}`}>
            <line x1={x(t)} y1={padT} x2={x(t)} y2={H - padB} stroke="rgba(77,184,255,.14)" strokeWidth="1" />
            <text x={x(t)} y={H - 8} fill="#5f7a96" fontSize="10" textAnchor="middle" fontFamily="monospace">
              {t}
            </text>
          </g>
        ))}

        {/* zero-tick baseline */}
        <line x1={zeroX} y1={padT} x2={zeroX} y2={H - padB} stroke="rgba(255,255,255,.18)" strokeWidth="1" strokeDasharray="3 3" />

        {/* one bar per bucket */}
        {ranges.map((r, i) => {
          const bx = x(r.lower);
          const bw = Math.max(2, x(r.upper) - x(r.lower));
          const v = Number(r.c0 + r.c1);
          const by = barTop(v);
          return (
            <g key={i}>
              <rect x={bx} y={by} width={bw} height={H - padB - by} fill="url(#pc-bar)" opacity={r.active ? 0.95 : 0.4} />
              <text x={bx + bw / 2} y={by - 4} fill="#9db8d4" fontSize="10" textAnchor="middle" fontFamily="monospace">
                {r.lower}…{r.upper}
              </text>
            </g>
          );
        })}

        {/* current tick marker */}
        <line x1={tickX} y1={padT - 6} x2={tickX} y2={H - padB} stroke="#ff2bd6" strokeWidth="1.5" />
        <polygon points={`${tickX - 5},${padT - 6} ${tickX + 5},${padT - 6} ${tickX},${padT + 1}`} fill="#ff2bd6" />
        <text x={tickX} y={padT - 9} fill="#ff9de6" fontSize="10" textAnchor="middle" fontFamily="monospace">
          spot
        </text>
      </svg>
    </div>
  );
}
