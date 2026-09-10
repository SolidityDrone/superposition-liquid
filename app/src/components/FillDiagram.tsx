"use client";

import { useEffect, useRef, useState } from "react";
import { AaveLogo, USDCLogo, ETHLogo } from "@/components/logos";

/**
 * Orthogonal layout, aligned columns: MAKER above the ROUTER, TAKER below,
 * AAVE to the left. Two vertical rails through the router (x=450 up,
 * x=510 down) and four horizontal lanes to Aave.
 *
 * The coin follows the REAL token path (maker wallet = pass-through, router
 * executes):
 *   1  TX                          the router runs the whole fill
 *   2  taker -> router             pays USDC            (up rail)
 *   3  router -> aave              deposit USDC         (lane y=260, left)
 *   4  aave -> router -> maker     aUSDC back to owner  (lane y=280, up rail)
 *   5  maker -> router -> aave     aWETH in withdrawal  (down rail, y=300)
 *   6  aave -> router -> taker     WETH delivered       (lane y=320, down rail)
 *
 * The coin is an HTML overlay (rides ON TOP of the cards) driven by one rAF
 * clock that also drives badges and legend. It FADES OUT approaching an
 * actor, switches identity while invisible (the corner jogs happen inside
 * those invisible windows), and FADES IN on exit.
 */

const X = { aave: 140, router: 480, taker: 480, maker: 480, aqua: 820 };
const Y = { maker: 90, row: 290, taker: 480 };
const RAIL_UP = 450; // upward flows: taker->router, aUSDC->maker
const RAIL_DOWN = 510; // downward flows: aWETH->router, WETH->taker
const LANE_Y = { out: 282, back: 298 }; // aave <-> router lanes: out=leftward, back=rightward
const AAVE_EDGE = 202; // aave card right edge
const ROUTER_EDGE = 370; // router card left edge
const MAKER_BOT = 118; // maker card bottom edge (big card: y 62-118)
const ROUTER_TOP = 248; // router card top edge (hero card)
const ROUTER_BOT = 332; // router card bottom edge
const TAKER_TOP = 452; // taker card top edge (big card: y 452-508)

const NODES = [
  { key: "maker", x: X.maker, y: Y.maker, name: "MAKER", dot: "#e6f0fa", big: true },
  { key: "aqua", x: X.aqua, y: Y.row, name: "RESOLVERS", dot: "#4cc2ff" },
  { key: "aave", x: X.aave, y: Y.row, name: "AAVE v3", dot: "#b6509e", hero: true },
  { key: "router", x: X.router, y: Y.row, name: "SUPERPOSITION ROUTER", dot: "#4cc2ff", hero: true },
  { key: "taker", x: X.taker, y: Y.taker, name: "TAKER", dot: "#8ba3b8", big: true },
];

// straight token lanes with arrows; `stage` = the step that travels it.
// Just TWO aave lanes through the card centers: out=leftward (deposit +
// aWETH-in), back=rightward (aUSDC + WETH return) — both fully hidden
// behind the taller hero cards. The first lane carries the tx relay.
const LANES = [
  { d: `M 745 290 L 598 290`, stage: 1 }, // tx relay: aqua -> router (left)
  { d: `M ${RAIL_UP} ${TAKER_TOP - 1} L ${RAIL_UP} ${ROUTER_BOT + 2}`, stage: 2 }, // pays USDC (up)
  { d: `M ${ROUTER_EDGE} ${LANE_Y.out} L ${AAVE_EDGE} ${LANE_Y.out}`, stage: 3 }, // deposit (left)
  { d: `M ${ROUTER_EDGE} ${LANE_Y.out} L ${AAVE_EDGE} ${LANE_Y.out}`, stage: 5 }, // aWETH to aave (left)
  { d: `M ${AAVE_EDGE} ${LANE_Y.back} L ${ROUTER_EDGE} ${LANE_Y.back}`, stage: 4 }, // aUSDC back (right)
  { d: `M ${AAVE_EDGE} ${LANE_Y.back} L ${ROUTER_EDGE} ${LANE_Y.back}`, stage: 6 }, // WETH out (right)
  { d: `M ${RAIL_UP} ${ROUTER_TOP - 2} L ${RAIL_UP} ${MAKER_BOT + 2}`, stage: 4 }, // aUSDC up, behind the maker
  { d: `M ${RAIL_DOWN} ${MAKER_BOT + 2} L ${RAIL_DOWN} ${ROUTER_TOP - 2}`, stage: 5 }, // aWETH down
  { d: `M ${RAIL_DOWN} ${ROUTER_BOT + 2} L ${RAIL_DOWN} ${TAKER_TOP - 1}`, stage: 6 }, // deliver (down)
];

// port stubs on the aave edge (each lane docks there)
const PORTS = [
  { d: `M ${AAVE_EDGE} ${LANE_Y.out} L ${AAVE_EDGE + 12} ${LANE_Y.out}`, stages: [3, 5] },
  { d: `M ${AAVE_EDGE} ${LANE_Y.back} L ${AAVE_EDGE + 12} ${LANE_Y.back}`, stages: [4, 6] },
];

// --- the coin's orthogonal journey (real token path) ---------------------------
// the rails pass BEHIND the actor cards: the coin dives behind their center,
// switches identity there, and re-emerges on the other rail/port.
const VERTS: Array<[number, number]> = [
  [480, 490], // behind the taker card — loop start (hidden)
  [RAIL_UP, 490], // still behind the card
  [RAIL_UP, 470], // behind, about to emerge
  [RAIL_UP, 290], // up the rail, into the router — hold (hidden)
  [RAIL_UP, LANE_Y.out],
  [ROUTER_EDGE, LANE_Y.out], // exits toward aave
  [140, LANE_Y.out], // behind the aave center — hold: USDC -> aUSDC (hidden)
  [140, LANE_Y.back], // behind, jog to the return lane
  [ROUTER_EDGE, LANE_Y.back], // emerges from aave
  [RAIL_UP, LANE_Y.back], // into the router (hidden mid)
  [RAIL_UP, 90], // up behind the maker card
  [480, 90], // behind the maker center — hold: aUSDC -> aWETH (hidden)
  [RAIL_DOWN, 90], // behind, over to the down rail
  [RAIL_DOWN, 290], // down into the router — hold (hidden)
  [RAIL_DOWN, LANE_Y.out], // jog up to the leftward lane (hidden)
  [ROUTER_EDGE, LANE_Y.out], // exits toward aave
  [140, LANE_Y.out], // behind the aave center — hold: aWETH -> WETH (hidden)
  [140, LANE_Y.back], // behind, jog to the return lane
  [RAIL_DOWN, LANE_Y.back], // through the router (hidden mid)
  [RAIL_DOWN, 470], // down the rail, behind the taker card
  [RAIL_DOWN, 490], // behind the card
  [480, 490], // behind the taker center — cycle closes (hidden)
];
const CUM: number[] = (() => {
  const c = [0];
  for (let i = 1; i < VERTS.length; i++) {
    const [x0, y0] = VERTS[i - 1];
    const [x1, y1] = VERTS[i];
    c.push(c[i - 1] + Math.abs(x1 - x0) + Math.abs(y1 - y0));
  }
  return c;
})();
const TOTAL = CUM[CUM.length - 1];

const DUR_MS = 21000;

// constant-speed timeline, derived analytically: every hold lasts a fixed
// 700ms, the remaining time is split across the legs PROPORTIONALLY to their
// length — so the coin moves at one single speed for the whole cycle.
// event vertices: taker(0) · router-in · aave · maker · router-in · aave ·
// taker · close  (cumulative: 0, 230, 548, 1112, 1342, 1720, 2278, 2328)
const KT = [0, 0.0636, 0.1185, 0.1821, 0.2579, 0.3215, 0.4559, 0.5195, 0.5744, 0.638, 0.7281, 0.7917, 0.9246, 0.9883, 1];
const KP = [0, 0, 0.0988, 0.0988, 0.2354, 0.2354, 0.4777, 0.4777, 0.5764, 0.5764, 0.7388, 0.7388, 0.9784, 0.9784, 1];

// replay windows per step (click a chip to loop it)
const STAGE_CUTS = [0.0636, 0.1821, 0.3215, 0.5195, 0.7917];
const STAGE_WINDOWS: Array<[number, number]> = [
  [0, 0.0636],
  [0.0636, 0.1821],
  [0.1821, 0.3215],
  [0.3215, 0.5195],
  [0.5195, 0.7917],
  [0.7917, 1],
];

// coin identity windows (switches happen mid-hold, behind the actor cards)
const PHASE_CUTS = [0.2897, 0.4877, 0.7599]; // usdc -> aUSDC -> aWETH -> WETH

const LEGEND = [
  { stage: 1, label: "Resolvers relay the tx → router" },
  { stage: 2, label: "Taker pays USDC → router" },
  { stage: 3, label: "Hooks: USDC deposited → aUSDC" },
  { stage: 4, label: "aUSDC → maker (position grows)" },
  { stage: 5, label: "Maker's aWETH → aave (JIT withdraw)" },
  { stage: 6, label: "WETH → taker (delivered)" },
];

type Phase = "usdc" | "ausdc" | "aweth" | "eth";

function interp(f: number, xs: number[], ys: number[]): number {
  let i = 0;
  while (i < xs.length - 2 && f >= xs[i + 1]) i++;
  const t = (f - xs[i]) / (xs[i + 1] - xs[i] || 1);
  return ys[i] + (ys[i + 1] - ys[i]) * t;
}

/** Position on the orthogonal journey at cycle fraction f — plus the facing
 *  angle, so the chase face always lies ALONG the trajectory (ghost behind
 *  the token in the direction of travel, never beside it or off the line). */
function coinAt(f: number): [number, number, number] {
  const kp = interp(f, KT, KP);
  const dist = kp * TOTAL;
  let j = 0;
  while (j < CUM.length - 2 && dist > CUM[j + 1]) j++;
  const seg = CUM[j + 1] - CUM[j] || 1;
  const k = Math.min(1, Math.max(0, (dist - CUM[j]) / seg));
  const [x0, y0] = VERTS[j];
  const [x1, y1] = VERTS[j + 1];
  const angle = x1 > x0 ? 0 : x1 < x0 ? 180 : y1 < y0 ? -90 : 90;
  return [
    x0 + (x1 - x0) * k,
    y0 + (y1 - y0) * k,
    angle,
  ];
}

/** The WHITE ghost that chases the aToken — always upright, whatever the
 *  travel direction (its chase offset is applied by the rAF loop). */
function GhostSprite() {
  return (
    <svg width={34} height={34} viewBox="0 0 24 24" aria-hidden className="ghost-bob">
      <path
        fill="#e6f0fa"
        d="M 4 22 V 11 A 8 8 0 0 1 20 11 V 22 L 17.3 19.5 L 14.6 22 L 12 19.5 L 9.4 22 L 6.7 19.5 Z"
      >
        <animate
          attributeName="d"
          dur="0.7s"
          repeatCount="indefinite"
          values="M 4 22 V 11 A 8 8 0 0 1 20 11 V 22 L 17.3 19.5 L 14.6 22 L 12 19.5 L 9.4 22 L 6.7 19.5 Z;
                  M 4 22 V 11 A 8 8 0 0 1 20 11 V 22 L 17.3 22 L 14.6 19.5 L 12 22 L 9.4 19.5 L 6.7 22 Z;
                  M 4 22 V 11 A 8 8 0 0 1 20 11 V 22 L 17.3 19.5 L 14.6 22 L 12 19.5 L 9.4 22 L 6.7 19.5 Z"
        />
      </path>
      <ellipse cx="9" cy="10" rx="1.9" ry="2.3" fill="#0b1420" />
      <ellipse cx="15" cy="10" rx="1.9" ry="2.3" fill="#0b1420" />
      <circle cx="9" cy="10.2" r="0.9" fill="#fff">
        <animate attributeName="cx" dur="1.6s" repeatCount="indefinite" values="9;10.2;9;10.2;9" />
      </circle>
      <circle cx="15" cy="10.2" r="0.9" fill="#fff">
        <animate attributeName="cx" dur="1.6s" repeatCount="indefinite" values="15;16.2;15;16.2;15" />
      </circle>
    </svg>
  );
}

/** The coin face: always the plain circle with the real logo (the chase by
 *  the ghost marks the aToken phases). */
function CoinFace({ phase }: { phase: Phase }) {
  if (phase === "usdc" || phase === "ausdc") {
    return <USDCLogo size={27} />;
  }
  return <ETHLogo size={27} />;
}

export default function FillDiagram() {
  const coinRef = useRef<SVGGElement>(null);
  const ghostRef = useRef<SVGGElement>(null);
  const txRef = useRef<SVGGElement>(null);
  const [active, setActive] = useState(1);
  const [phase, setPhase] = useState<Phase>("usdc");
  const [selected, setSelected] = useState<number | null>(null);
  const selectedRef = useRef<number | null>(null);
  const t0Ref = useRef(performance.now());

  useEffect(() => {
    let raf = 0;

    const loop = (now: number) => {
      const sel = selectedRef.current;
      // full cycle, or loop the selected step's window on repeat
      let f: number;
      let stage: number;
      if (sel === null) {
        f = ((now - t0Ref.current) % DUR_MS) / DUR_MS;
        stage =
          f < STAGE_CUTS[0] ? 1
          : f < STAGE_CUTS[1] ? 2
          : f < STAGE_CUTS[2] ? 3
          : f < STAGE_CUTS[3] ? 4
          : f < STAGE_CUTS[4] ? 5
          : 6;
      } else {
        const [a, b] = STAGE_WINDOWS[sel - 1];
        const dur = Math.max(2200, (b - a) * DUR_MS);
        f = a + (((now - t0Ref.current) % dur) / dur) * (b - a);
        stage = sel;
      }

      const [x, y, angle] = coinAt(f);
      coinRef.current?.setAttribute("transform", `translate(${x} ${y})`);
      // the ghost runs the SAME trajectory from the SAME spots — it just
      // starts later: its position is the token's position, lagged in time.
      // both spawn behind the same card center, the ghost departs after.
      let gf = f - 0.03;
      if (sel === null) {
        gf = (gf + 1) % 1; // wraps: at cycle start it is still at the taker tail
      } else {
        gf = Math.max(STAGE_WINDOWS[sel - 1][0], gf); // waits at the start spot
      }
      const [gx, gy, gAngle] = coinAt(gf);
      const ghostEl = ghostRef.current;
      if (ghostEl) {
        ghostEl.setAttribute("transform", `translate(${gx} ${gy})`);
        // the ghost only joins on the aToken legs (usdc -> aUSDC -> aWETH -> WETH)
        const ghostOn = f >= PHASE_CUTS[0] && f < PHASE_CUTS[2];
        const wantDisplay = ghostOn ? "" : "none";
        if (ghostEl.getAttribute("display") !== wantDisplay) {
          ghostEl.setAttribute("display", wantDisplay);
        }
      }

      // the tx relay: shuttles Resolvers -> router during step 1 (constant
      // speed), stays tucked at the router edge afterwards
      const txT = f < 0.008 ? 0 : f < 0.055 ? (f - 0.008) / 0.047 : 1;
      txRef.current?.setAttribute("transform", `translate(${820 + (600 - 820) * txT} 290)`);

      setActive((prev) => (prev === stage ? prev : stage));

      const ph = f < PHASE_CUTS[0] ? "usdc" : f < PHASE_CUTS[1] ? "ausdc" : f < PHASE_CUTS[2] ? "aweth" : "eth";
      setPhase((prev) => (prev === ph ? prev : ph));

      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);

  const pick = (n: number) => {
    selectedRef.current = selected === n ? null : n;
    setSelected(selectedRef.current);
    t0Ref.current = performance.now(); // replay the picked window from its start
  };

  return (
    <div className="diagram-wrap">
      <div className="diagram">
        <svg className="d-svg" viewBox="0 0 960 560" preserveAspectRatio="xMidYMid meet">
          <defs>
            <marker id="arrow-on" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M 0 0 L 8 4 L 0 8" fill="none" stroke="#4cc2ff" strokeWidth="1.4" />
            </marker>
            <marker id="arrow-off" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M 0 0 L 8 4 L 0 8" fill="none" stroke="#3a4a5c" strokeWidth="1.4" />
            </marker>
          </defs>

          {/* aave-edge port stubs */}
          {PORTS.map((p, i) => (
            <path
              key={`p${i}`}
              className={p.stages.includes(active) ? "flow-line flow-port on" : "flow-line flow-port"}
              d={p.d}
            />
          ))}

          {/* straight token lanes — blue while the coin travels them, gray otherwise */}
          {LANES.map((l, i) => {
            const on = active === l.stage;
            return (
              <path
                key={`l${i}`}
                className={on ? "flow-line on" : "flow-line"}
                d={l.d}
                markerEnd={`url(#arrow-${on ? "on" : "off"})`}
              />
            );
          })}

          {/* the tx relay icon: shuttles from Resolvers into the router (step 1),
              then stays tucked against the router edge for the rest of the fill */}
          <g ref={txRef} transform="translate(820 290)">
            <circle
              r="13"
              fill={active === 1 ? "rgba(76,194,255,0.14)" : "#0e1824"}
              stroke={active === 1 ? "#4cc2ff" : "#2e4a63"}
              strokeWidth="1.3"
            />
            <text
              y="3.4"
              textAnchor="middle"
              fontSize="9.5"
              fontFamily="var(--mono)"
              fontWeight="700"
              fill={active === 1 ? "#4cc2ff" : "#63788c"}
            >
              TX
            </text>
          </g>

          {/* dashed ownership/config links (no token flow) */}
          <path
            d="M 400 90 L 140 90 L 140 250"
            stroke="#3a4a5c"
            strokeWidth="1.2"
            strokeDasharray="5 6"
            fill="none"
          />
          <text x="152" y="170" fontSize="9.5" fontFamily="var(--mono)" fill="#566b80">
            owns aWETH · aUSDC
          </text>
          <text x="152" y="186" fontSize="9.5" fontFamily="var(--mono)" fill="#566b80">
            approvals → adapter
          </text>
          <path
            d="M 560 90 L 820 90 L 820 264"
            stroke="#3a4a5c"
            strokeWidth="1.2"
            strokeDasharray="5 6"
            fill="none"
          />
          <text x="590" y="72" fontSize="9.5" fontFamily="var(--mono)" fill="#566b80">
            ships the strategy · virtual balances
          </text>

          {/* the chasing ghost — always upright, one body behind the token
              along the travel direction; only visible on aToken phases */}
          <g
            ref={ghostRef}
            transform="translate(446 490)"
            display="none"
            style={{ filter: "drop-shadow(0 0 7px rgba(230, 240, 250, 0.35))" }}
          >
            <g transform="translate(-13.5 -13.5)"><GhostSprite /></g>
          </g>

          {/* the walking token — inside the SVG: rides behind the actor cards,
              disappearing naturally into them (router dips, aave, taker) */}
          <g
            ref={coinRef}
            transform="translate(480 490)"
            style={{ filter: "drop-shadow(0 0 9px rgba(76, 194, 255, 0.55))" }}
          >
            <g transform="translate(-13.5 -13.5)"><CoinFace phase={phase} /></g>
          </g>
        </svg>

        {/* node cards */}
        {NODES.map((n) => (
          <div
            className={
              n.hero ? "d-node d-node--hero" : n.big ? "d-node d-node--big" : "d-node"
            }
            key={n.key}
            style={{ left: `${(n.x / 960) * 100}%`, top: `${(n.y / 560) * 100}%` }}
          >
            <span className="d-dot" style={{ background: n.dot }} />
            <div className="n-name">
              {n.key === "aave" && <AaveLogo size={15} />}
              {n.name}
            </div>
          </div>
        ))}
      </div>

      {/* legend — clickable: pick a step to replay it in a loop */}
      <div className="d-legend">
        {LEGEND.map((l) => (
          <button
            type="button"
            className={
              selected === l.stage || (selected === null && active === l.stage)
                ? "d-leg active"
                : "d-leg"
            }
            key={l.stage}
            onClick={() => pick(l.stage)}
            aria-pressed={selected === l.stage}
          >
            {l.label}
          </button>
        ))}
      </div>
    </div>
  );
}
