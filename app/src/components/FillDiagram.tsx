import { AaveLogo } from "@/components/logos";

/**
 * The end-to-end cycle of one fill (Aave maker example) as a living diagram.
 * Geometry is laid out on a 900x520 grid with separate lanes per directed edge:
 * the Aave<->Maker pair runs on two parallel lanes (deposit lane x~158,
 * JIT-delivery lane x~200), so nothing overlaps. Token packets travel the loop
 * via SMIL animateMotion: USDC in (edges 1-2-3), WETH out (edges 4-5).
 */

const NODES = [
  { key: "taker", x: 700, y: 55, name: "TAKER", sub: "pays USDC · gets WETH", dot: "#8ba3b8" },
  { key: "aqua", x: 815, y: 255, name: "1INCH AQUA", sub: "virtual balances", dot: "#4cc2ff" },
  { key: "router", x: 470, y: 445, name: "SUPERPOSITION ROUTER", sub: "hooks + opcodes", dot: "#4cc2ff" },
  { key: "aave", x: 80, y: 330, name: "AAVE v3", sub: "aWETH · aUSDC", dot: "#b6509e" },
  { key: "maker", x: 235, y: 70, name: "MAKER", sub: "wallet = pass-through", dot: "#e6f0fa" },
];

const STEPS = [
  { x: 640, y: 250, label: "1 · taker pays USDC" },
  { x: 285, y: 250, label: "2 · Aqua.push → maker" },
  { x: 470, y: 68, label: "4 · delivered via Aqua.pull" },
];

export default function FillDiagram() {
  return (
    <div className="diagram-wrap">
      <div className="diagram">
        <svg className="d-svg" viewBox="0 0 900 520" preserveAspectRatio="xMidYMid meet">
          <defs>
            <marker id="arrow" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M0 0L8 4L0 8" fill="none" stroke="#2a4258" strokeWidth="1.4" />
            </marker>
          </defs>

          {/* dotted connectors — one lane per directed edge, no overlaps */}
          {/* 1 · taker -> router (right lane) */}
          <path className="flow-line" d="M668 92 Q 630 265 505 402" markerEnd="url(#arrow)" />
          {/* 2 · router -> maker (inner right lane) */}
          <path className="flow-line" d="M432 410 Q 330 280 262 108" markerEnd="url(#arrow)" />
          {/* 3 · maker -> aave (deposit lane, x~158) */}
          <path className="flow-line" d="M210 108 Q 158 195 125 288" markerEnd="url(#arrow)" />
          {/* 4 · aave -> maker (JIT delivery lane, x~200) */}
          <path className="flow-line" d="M95 285 Q 200 198 218 112" markerEnd="url(#arrow)" />
          {/* 5 · maker -> taker (top arc) */}
          <path className="flow-line" d="M272 62 Q 468 8 663 53" markerEnd="url(#arrow)" />

          {/* packet guides (invisible) */}
          <path id="usdc-path" fill="none" stroke="none" d="M668 92 Q 630 265 505 402 Q 330 280 262 108 Q 158 195 125 288" />
          <path id="weth-path" fill="none" stroke="none" d="M95 285 Q 200 198 218 112 Q 470 5 663 53" />

          {/* USDC packet: taker -> router -> maker -> aave */}
          <g>
            <circle r="11" fill="rgba(76,194,255,0.16)" />
            <circle r="5.5" fill="#4cc2ff" />
            <text fontSize="7" fill="#031018" fontWeight="700" textAnchor="middle" dy="2.4">$</text>
            <animateMotion dur="7s" repeatCount="indefinite" keyPoints="0;1" keyTimes="0;1" calcMode="linear">
              <mpath href="#usdc-path" />
            </animateMotion>
          </g>

          {/* WETH packet: aave -> maker -> taker (counter-phase) */}
          <g>
            <circle r="11" fill="rgba(230,240,250,0.14)" />
            <circle r="5.5" fill="#e6f0fa" />
            <text fontSize="7" fill="#031018" fontWeight="700" textAnchor="middle" dy="2.4">Ξ</text>
            <animateMotion dur="7s" begin="-2.6s" repeatCount="indefinite" keyPoints="0;1" keyTimes="0;1" calcMode="linear">
              <mpath href="#weth-path" />
            </animateMotion>
          </g>
        </svg>

        {/* step labels — placed clear of every lane */}
        <span className="d-step" style={{ left: `${(640 / 900) * 100}%`, top: `${(250 / 520) * 100}%` }}>
          1 · taker pays USDC
        </span>
        <span className="d-step" style={{ left: `${(285 / 900) * 100}%`, top: `${(250 / 520) * 100}%` }}>
          2 · Aqua.push → maker
        </span>
        <span className="d-step" style={{ left: `${(470 / 900) * 100}%`, top: `${(68 / 520) * 100}%` }}>
          4 · delivered via Aqua.pull
        </span>

        {/* the two-lane pair gets its own margin label */}
        <div className="d-step d-step-left">
          3 · hooks:<br />deposit ⇄ JIT deliver
        </div>

        {/* node cards */}
        {NODES.map((n) => (
          <div
            className="d-node"
            key={n.key}
            style={{ left: `${(n.x / 900) * 100}%`, top: `${(n.y / 520) * 100}%` }}
          >
            <span className="d-dot" style={{ background: n.dot }} />
            <div>
              <div className="n-name">
                {n.key === "aave" && <AaveLogo size={12} />}
                {n.name}
              </div>
              <div className="n-sub">{n.sub}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
