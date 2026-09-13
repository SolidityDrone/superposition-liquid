"use client";

/**
 * Same visual language as FillDiagram, but for the Uniswap v4 hook:
 * the DATA workflow (calldata -> pullPlan -> vault redeem -> fill -> revenue)
 * plus the ERC-1155 bucket shuttle that authorises the LP operations on the
 * SwapVM (maker approves the router as operator, one id per tick range).
 *
 * Orthogonal loop through six actors, drawn with the shared .flow-line /
 * .d-node primitives; two packets ride it — a cyan DATA packet on the full
 * loop and a magenta 1155 packet shuttling maker <-> router.
 */

const VB = { w: 960, h: 520 };

const NODES = [
  { key: "maker", x: 480, y: 66, name: "MAKER", dot: "#e6f0fa", big: true },
  { key: "resolvers", x: 840, y: 250, name: "RESOLVERS", dot: "#4cc2ff" },
  { key: "router", x: 480, y: 250, name: "AQUA ROUTER", dot: "#4cc2ff", hero: true },
  { key: "hook", x: 135, y: 250, name: "UNISWAP V4 HOOK", dot: "#4cc2ff", hero: true },
  { key: "vault", x: 135, y: 430, name: "ERC-4626 · waToken", dot: "#b6509e" },
  { key: "taker", x: 480, y: 430, name: "TAKER", dot: "#8ba3b8", big: true },
];

const LOOP =
  "M 840 250 L 480 250 L 135 250 L 135 430 L 480 430 L 480 66 L 840 66 L 840 250";

const LANES = [
  { d: "M 840 250 L 480 250", x: 662, y: 238, t: "relayed calldata" },
  { d: "M 480 250 L 135 250", x: 300, y: 238, t: "pullPlan() · ILendingAdapter" },
  { d: "M 135 250 L 135 430", x: 147, y: 356, t: "redeem aToken → underlying" },
  { d: "M 135 430 L 480 430", x: 300, y: 418, t: "fill delivered to taker" },
  { d: "M 480 430 L 480 66", x: 492, y: 372, t: "revenue re-deposited" },
  { d: "M 480 66 L 840 66 L 840 250", x: 662, y: 54, t: "ERC-1155 bucket shares" },
];

export default function HookDiagram() {
  return (
    <div className="diagram-wrap">
      <div className="diagram diagram--hook">
        <svg
          className="d-svg"
          viewBox={`0 0 ${VB.w} ${VB.h}`}
          preserveAspectRatio="xMidYMid meet"
        >
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
            <path
              key={`ln${i}`}
              className="flow-line on"
              d={l.d}
              markerEnd="url(#h-arrow)"
            />
          ))}

          {LANES.map((l, i) => (
            <text
              key={`tx${i}`}
              x={l.x}
              y={l.y}
              fontSize="9.5"
              fontFamily="var(--mono)"
              fill="#566b80"
            >
              {l.t}
            </text>
          ))}

          {/* DATA packet: runs the whole hook loop forever */}
          <g>
            <rect
              x="-15"
              y="-9"
              width="30"
              height="18"
              rx="5"
              fill="#0e1824"
              stroke="#4cc2ff"
              strokeWidth="1.2"
            />
            <text
              textAnchor="middle"
              y="3.4"
              fontSize="8.5"
              fontFamily="var(--mono)"
              fontWeight="700"
              fill="#4cc2ff"
            >
              DATA
            </text>
            <animateMotion dur="11s" repeatCount="indefinite" path={LOOP} />
          </g>

          {/* ERC-1155 shuttle: maker <-> router (bucket shares / operator) */}
          <g>
            <rect
              x="-19"
              y="-9"
              width="38"
              height="18"
              rx="5"
              fill="#0e1824"
              stroke="#ff2bd6"
              strokeWidth="1.2"
            />
            <text
              textAnchor="middle"
              y="3.4"
              fontSize="8.5"
              fontFamily="var(--mono)"
              fontWeight="700"
              fill="#ff2bd6"
            >
              1155
            </text>
            <animateMotion
              dur="4.2s"
              repeatCount="indefinite"
              path="M 480 96 L 480 226 L 480 96"
            />
          </g>
        </svg>

        {NODES.map((n) => (
          <div
            className={
              n.hero ? "d-node d-node--hero" : n.big ? "d-node d-node--big" : "d-node"
            }
            key={n.key}
            style={{ left: `${(n.x / VB.w) * 100}%`, top: `${(n.y / VB.h) * 100}%` }}
          >
            <span className="d-dot" style={{ background: n.dot }} />
            <div className="n-name">{n.name}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
