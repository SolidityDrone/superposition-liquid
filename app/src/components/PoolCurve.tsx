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

const priceAt = (tick: number) => Math.pow(1.0001, tick);

/**
 * Liquidity-depth curve — the Uniswap-style chart: liquidity L plotted against
 * price, the maker's tick ranges as a filled depth profile, the active range
 * shaded and the current tick marked. The area is filled with a custom
 * checker/dither pattern built from the site's azure palette.
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
  const H = 200;
  const padL = 38;
  const padR = 16;
  const padT = 22;
  const padB = 28;
  const baseY = H - padB;

  const ts = ranges.flatMap((r) => [r.lower, r.upper]);
  ts.push(tick ?? 0, 0);
  const dMin = Math.min(...ts);
  const dMax = Math.max(...ts);
  const span = Math.max(1, dMax - dMin);
  const x = (t: number) => padL + ((t - dMin) / span) * (W - padL - padR);

  const maxL = Math.max(1, ...ranges.map((r) => Number(r.liquidity)));
  const yL = (v: number) => baseY - (v / maxL) * (H - padT - padB);

  const sorted = [...ranges].sort((a, b) => a.lower - b.lower);
  const active = ranges.find((r) => r.active) ?? ranges[0];

  // depth profile: one plateau per tick range (step area)
  let d = "";
  if (sorted.length) {
    d = `M ${x(sorted[0].lower)} ${baseY}`;
    for (const r of sorted) {
      const x0 = x(r.lower);
      const x1 = x(r.upper);
      const y = yL(Number(r.liquidity));
      d += ` L ${x0} ${y} L ${x1} ${y}`;
    }
    d += ` L ${x(sorted[sorted.length - 1].upper)} ${baseY} Z`;
  }

  const totalL = ranges.reduce((s, r) => s + Number(r.liquidity), 0);
  const inRange = ranges.filter((r) => r.active);
  const tvlInRange = inRange.reduce((s, r) => s + Number(r.c0 + r.c1), 0);
  const spotX = x(tick ?? 0);
  const gridTicks = [dMin, Math.round((dMin + dMax) / 2), dMax];

  return (
    <div className="pool-curve">
      <div className="pool-curve-head">
        <span className="pc-label">Liquidity depth curve</span>
        <span className="pc-meta">
          fee {(feeBps / 10000).toFixed(2)}% · tick <b>{tick ?? "—"}</b> · price{" "}
          <b>{price !== undefined ? price.toFixed(4) : priceAt(tick ?? 0).toFixed(4)}</b> · in-range{" "}
          <b>{fmtCompact(tvlInRange)}</b> · L <b>{fmtCompact(totalL)}</b>
        </span>
      </div>

      <svg viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label="liquidity depth by tick range">
        <defs>
          {/* custom pixel checker / ordered-dither fill */}
          <pattern id="pc-checker" width="8" height="8" patternUnits="userSpaceOnUse">
            <rect width="8" height="8" fill="#0a1c33" />
            <rect width="4" height="4" fill="#2f8fe6" />
            <rect x="4" y="4" width="4" height="4" fill="#2f8fe6" />
            <rect width="8" height="1" fill="#8fd8ff" opacity="0.25" />
          </pattern>
          <pattern id="pc-checker-dim" width="8" height="8" patternUnits="userSpaceOnUse">
            <rect width="8" height="8" fill="#081324" />
            <rect width="4" height="4" fill="#1d5fa0" opacity="0.7" />
            <rect x="4" y="4" width="4" height="4" fill="#1d5fa0" opacity="0.7" />
          </pattern>
        </defs>

        {/* grid */}
        {gridTicks.map((t, gi) => (
          <g key={`g${gi}`}>
            <line x1={x(t)} y1={padT} x2={x(t)} y2={baseY} stroke="rgba(77,184,255,.14)" strokeWidth="1" />
            <text x={x(t)} y={H - 8} fill="#5f7a96" fontSize="10" textAnchor="middle" fontFamily="monospace">
              {t}
            </text>
          </g>
        ))}
        <line x1={padL} y1={baseY} x2={W - padR} y2={baseY} stroke="rgba(77,184,255,.25)" strokeWidth="1" />

        {/* active range shade */}
        {active && (
          <rect
            x={x(active.lower)}
            y={padT}
            width={Math.max(2, x(active.upper) - x(active.lower))}
            height={baseY - padT}
            fill="rgba(77,184,255,.06)"
            stroke="rgba(77,184,255,.35)"
            strokeDasharray="3 3"
          />
        )}

        {/* inactive depth profile then active bucket on top */}
        {sorted
          .filter((r) => !r.active)
          .map((r, i) => {
            const w = Math.max(2, x(r.upper) - x(r.lower));
            const y = yL(Number(r.liquidity));
            return (
              <rect
                key={`b${i}`}
                x={x(r.lower)}
                y={y}
                width={w}
                height={baseY - y}
                fill="url(#pc-checker-dim)"
              />
            );
          })}
        {inRange.map((r, i) => {
          const w = Math.max(2, x(r.upper) - x(r.lower));
          const y = yL(Number(r.liquidity));
          return (
            <rect
              key={`a${i}`}
              x={x(r.lower)}
              y={y}
              width={w}
              height={baseY - y}
              fill="url(#pc-checker)"
            />
          );
        })}

        {/* bright step outline over the profile */}
        {sorted.length > 0 && (
          <path d={d} fill="none" stroke="#8fd8ff" strokeWidth="1.4" opacity="0.9" />
        )}

        {/* current tick / spot */}
        <line x1={spotX} y1={padT - 6} x2={spotX} y2={baseY} stroke="#ff2bd6" strokeWidth="1.5" />
        <polygon points={`${spotX - 5},${padT - 6} ${spotX + 5},${padT - 6} ${spotX},${padT + 1}`} fill="#ff2bd6" />
        <text x={spotX} y={padT - 9} fill="#ff9de6" fontSize="10" textAnchor="middle" fontFamily="monospace">
          spot
        </text>
      </svg>
    </div>
  );
}
