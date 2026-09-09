import { AaveLogo } from "@/components/logos";

/**
 * The end-to-end cycle of one fill, drawn as a living diagram (Aave maker example).
 * Dotted "marching ants" connectors + two token packets (USDC in, WETH out)
 * travelling the loop via SMIL animateMotion. Nodes are HTML cards layered
 * over the SVG so they can carry logos.
 *
 * Layout coordinates are in a 900x520 viewBox; node cards are positioned in %.
 */

const NODES = [
  { key: "taker", x: 700, y: 55, name: "TAKER", sub: "pays USDC · gets WETH", dot: "#8ba3b8" },
  { key: "aqua", x: 815, y: 255, name: "1INCH AQUA", sub: "virtual balances", dot: "#4cc2ff" },
  { key: "router", x: 470, y: 445, name: "SUPERPOSITION ROUTER", sub: "hooks + custom opcodes", dot: "#4cc2ff" },
  { key: "aave", x: 105, y: 330, name: "AAVE v3", sub: "aWETH · aUSDC", dot: "#b6509e" },
  { key: "maker", x: 235, y: 70, name: "MAKER", sub: "wallet = pass-through", dot: "#e6f0fa" },
];

const STEPS = [
  { n: "1", x: 600, y: 195, label: "taker pays 1000 USDC" },
  { n: "2", x: 350, y: 260, label: "Aqua.push → USDC lands" },
  { n: "3", x: 175, y: 210, label: "hook: deposit → Aave" },
  { n: "4", x: 150, y: 200, label: "", hide: true }, // merged visually with 3
  { n: "5", x: 460, y: 60, label: "hook: aWETH → WETH · delivered" },
];

export default function FillDiagram() {
  return (
    <div className="diagram-wrap">
      <div className="diagram">
        <svg className="d-svg" viewBox="0 0 900 520" preserveAspectRatio="xMidYMid meet">
          <defs>
            <marker id="arrow" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M0 0L8 4L0 8" fill="none" stroke="#1d2c3f" strokeWidth="1.4" />
            </marker>
          </defs>

          {/* dotted connectors (marching ants via CSS) */}
          {/* 1 taker -> router */}
          <path id="p1" className="flow-line" d="M672 78 C 610 170, 560 300, 512 408" markerEnd="url(#arrow)" />
          {/* 2 router -> maker */}
          <path id="p2" className="flow-line" d="M432 415 C 360 320, 300 200, 258 100" markerEnd="url(#arrow)" />
          {/* 3 maker -> aave */}
          <path id="p3" className="flow-line" d="M212 100 C 160 160, 128 230, 116 292" markerEnd="url(#arrow)" />
          {/* 4 aave -> maker (JIT, offset from p3) */}
          <path id="p4" className="flow-line" d="M128 305 C 165 230, 195 165, 228 105" markerEnd="url(#arrow)" />
          {/* 5 maker -> taker */}
          <path id="p5" className="flow-line" d="M280 70 C 420 20, 560 20, 662 50" markerEnd="url(#arrow)" />

          {/* packet paths (invisible guides for the travelling tokens) */}
          <path id="usdc-path" fill="none" stroke="none" d="M700 55 C 610 170, 560 300, 470 445 C 380 320, 310 200, 235 70 C 190 160, 140 230, 105 330" />
          <path id="weth-path" fill="none" stroke="none" d="M105 330 C 150 240, 200 160, 235 70 C 420 20, 560 20, 700 55" />

          {/* USDC packet: taker -> router -> maker -> aave */}
          <g>
            <circle r="11" fill="rgba(76,194,255,0.18)" />
            <circle r="5.5" fill="#4cc2ff" />
            <text fontSize="7" fill="#031018" fontWeight="700" textAnchor="middle" dy="2.4" x="0" y="0">$</text>
            <animateMotion dur="7s" repeatCount="indefinite" keyPoints="0;1" keyTimes="0;1" calcMode="linear">
              <mpath href="#usdc-path" />
            </animateMotion>
          </g>

          {/* WETH packet: aave -> maker -> taker (counter-phase) */}
          <g>
            <circle r="11" fill="rgba(230,240,250,0.14)" />
            <circle r="5.5" fill="#e6f0fa" />
            <text fontSize="7" fill="#031018" fontWeight="700" textAnchor="middle" dy="2.4" x="0" y="0">Ξ</text>
            <animateMotion dur="7s" begin="-2.6s" repeatCount="indefinite" keyPoints="0;1" keyTimes="0;1" calcMode="linear">
              <mpath href="#weth-path" />
            </animateMotion>
          </g>
        </svg>

        {/* step labels */}
        {STEPS.filter((s) => s.label).map((s) => (
          <span className="d-step" key={s.n} style={{ left: `${(s.x / 900) * 100}%`, top: `${(s.y / 520) * 100}%` }}>
            {s.n} · {s.label}
          </span>
        ))}

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
