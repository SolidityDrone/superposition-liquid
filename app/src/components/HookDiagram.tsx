"use client";

import { TokenIcon } from "@/components/icons";
import { AaveLogo } from "@/components/logos";

/**
 * The Uniswap v4 hook, as a swap — the real flow of funds.
 *
 * Layout mirrors a trade: the maker's ERC-1155 buckets back the pool, the Aqua
 * router drives the fill, and the two pool tokens (USDC / USDT) actually move:
 *   - USDC the taker PAYS   : taker -> router -> hook -> ERC-4626 vault
 *   - USDT the taker RECEIVES: vault -> hook -> router -> taker
 * while the relayed calldata reaches the router and the maker's ERC-1155
 * buckets back the pool (one id per tick range).
 */

const VB = { w: 960, h: 560 };

type Node = {
  key: string;
  x: number;
  y: number;
  name: string;
  dot: string;
  big?: boolean;
  hero?: boolean;
  pair?: boolean;
};

const NODES: Node[] = [
  { key: "maker", x: 480, y: 64, name: "MAKER", dot: "#e6f0fa", big: true },
  { key: "resolvers", x: 840, y: 300, name: "RESOLVERS", dot: "#4cc2ff" },
  { key: "router", x: 480, y: 300, name: "AQUA ROUTER", dot: "#4cc2ff", hero: true },
  { key: "hook", x: 150, y: 300, name: "UNISWAP V4 HOOK", dot: "#4cc2ff", hero: true, pair: true },
  { key: "vault", x: 150, y: 480, name: "AAVE · waToken", dot: "#b6509e" },
  { key: "taker", x: 480, y: 480, name: "TAKER", dot: "#8ba3b8", big: true },
];

/* straight money lanes (arrows), with a label placed in open space */
const LANES = [
  { d: "M 840 300 L 480 300", x: 662, y: 288, t: "relayed calldata" },
  { d: "M 480 300 L 150 300", x: 315, y: 288, t: "swap in the v4 curve" },
  { d: "M 150 300 L 150 480", x: 162, y: 402, t: "aToken ⇄ underlying" },
  { d: "M 480 300 L 480 480", x: 492, y: 402, t: "fill delivered to taker" },
  { d: "M 480 64 L 480 300", x: 468, y: 200, t: "ERC-1155 buckets", anchor: "end" as const },
];

/* the two token coins travel the swap: USDC paid in, USDT paid out */
const USDC_PATH = "M 480 480 L 480 300 L 150 300 L 150 480";
const USDT_PATH = "M 150 480 L 150 300 L 480 300 L 480 480";

function Coin({ symbol, size = 26 }: { symbol: string; size?: number }) {
  return (
    <>
      <circle r={size / 2 + 4} fill="#0e1824" stroke="#2e4a63" strokeWidth="1" />
      <g transform={`translate(${-size / 2} ${-size / 2})`}>
        <TokenIcon symbol={symbol} size={size} />
      </g>
    </>
  );
}

export default function HookDiagram() {
  return (
    <div className="diagram-wrap">
      <div className="diagram diagram--hook">
        <svg className="d-svg" viewBox={`0 0 ${VB.w} ${VB.h}`} preserveAspectRatio="xMidYMid meet">
          <defs>
            <marker
              id="h-arrow"
              viewBox="0 0 8 8"
              refX="6"
              refY="4"
              markerWidth="6"
              markerHeight="6"
              orient="auto-start-reverse"
            >
              <path d="M 0 0 L 8 4 L 0 8" fill="none" stroke="#4cc2ff" strokeWidth="1.4" />
            </marker>
          </defs>

          {LANES.map((l, i) => (
            <path key={`ln${i}`} className="flow-line on" d={l.d} markerEnd="url(#h-arrow)" />
          ))}

          {LANES.map((l, i) => (
            <text
              key={`tx${i}`}
              x={l.x}
              y={l.y}
              fontSize="9.5"
              fontFamily="var(--mono)"
              fill="#566b80"
              textAnchor={l.anchor ?? "start"}
            >
              {l.t}
            </text>
          ))}

          {/* the paid token: USDC (taker -> router -> hook -> vault) */}
          <g>
            <Coin symbol="USDC" />
            <animateMotion dur="9s" repeatCount="indefinite" path={USDC_PATH} />
            <animate attributeName="opacity" dur="9s" repeatCount="indefinite" values="0;1;1;0" keyTimes="0;0.12;0.82;1" />
          </g>

          {/* the delivered token: USDT (vault -> hook -> router -> taker) */}
          <g>
            <Coin symbol="USDT" />
            <animateMotion dur="9s" repeatCount="indefinite" path={USDT_PATH} />
            <animate attributeName="opacity" dur="9s" repeatCount="indefinite" values="0;1;1;0" keyTimes="0;0.12;0.82;1" />
          </g>
        </svg>

        {NODES.map((n) => (
          <div
            className={n.hero ? "d-node d-node--hero" : n.big ? "d-node d-node--big" : "d-node"}
            key={n.key}
            style={{ left: `${(n.x / VB.w) * 100}%`, top: `${(n.y / VB.h) * 100}%` }}
          >
            <span className="d-dot" style={{ background: n.dot }} />
            <div className="n-name">
              {n.key === "vault" && <AaveLogo size={16} />}
              {n.name}
              {n.pair && (
                <span className="d-pair">
                  <TokenIcon symbol="USDC" size={16} />
                  <TokenIcon symbol="USDT" size={16} />
                </span>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
