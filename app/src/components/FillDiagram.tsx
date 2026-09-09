"use client";

import { useEffect, useRef, useState } from "react";
import { AaveLogo } from "@/components/logos";

/**
 * The fill cycle as a narrated ring: five actors on a pentagon, numbered lane
 * badges, and ONE coin packet that walks the loop pausing at every actor —
 * USDC in (taker -> router -> maker -> Aave) where it becomes the WETH
 * delivery (Aave -> maker -> taker). The active legend entry lights up in
 * sync. Explanations live in the legend, not floating on the map.
 */

const NODES = [
  { key: "taker", x: 760, y: 70, name: "TAKER", sub: "pays USDC · gets WETH", dot: "#8ba3b8" },
  { key: "aqua", x: 880, y: 300, name: "1INCH AQUA", sub: "virtual balances", dot: "#4cc2ff" },
  { key: "router", x: 480, y: 500, name: "SUPERPOSITION ROUTER", sub: "hooks + opcodes", dot: "#4cc2ff" },
  { key: "aave", x: 75, y: 360, name: "AAVE v3", sub: "aWETH · aUSDC", dot: "#b6509e" },
  { key: "maker", x: 190, y: 55, name: "MAKER", sub: "wallet = pass-through", dot: "#e6f0fa" },
];

// one STRAIGHT lane per directed edge, generously spaced on the pentagon
const LANES: { n: number; d: string; stage: number; bx: number; by: number }[] = [
  { n: 1, d: "M 725 100 L 552 458", stage: 1, bx: 638.5, by: 279 },
  { n: 2, d: "M 425 468 L 228 100", stage: 2, bx: 326.5, by: 284 },
  { n: 3, d: "M 160 90 L 105 318", stage: 3, bx: 132.5, by: 204 },
  { n: 4, d: "M 122 86 L 60 300", stage: 4, bx: 91, by: 193 },
  { n: 5, d: "M 228 50 L 668 57", stage: 4, bx: 475, by: 28 },
];

const LEGEND = [
  { stage: 1, label: "Taker pays USDC" },
  { stage: 2, label: "Aqua.push → maker" },
  { stage: 3, label: "Hooks: deposit → Aave" },
  { stage: 4, label: "JIT: aWETH → WETH, delivered" },
];

const SEGMENTS = LANES; // same geometry for the walking packet

const MOVE_MS = 1000;
const PAUSE_MS = 600;
const TAKER_PAUSE_MS = 950;

export default function FillDiagram() {
  const packetRef = useRef<SVGGElement>(null);
  const coreRef = useRef<SVGCircleElement>(null);
  const symRef = useRef<SVGTextElement>(null);
  const laneRefs = useRef<(SVGPathElement | null)[]>([]);
  const [active, setActive] = useState(1);

  useEffect(() => {
    const packet = packetRef.current;
    const core = coreRef.current;
    const sym = symRef.current;
    if (!packet || !core || !sym) return;

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const speedScale = reduced ? 1.9 : 1; // reduced motion: slower walk, never frozen
    const laneLens = LANES.map((l, i) => {
      const el = laneRefs.current[i];
      return el ? el.getTotalLength() : 500;
    });

    type Slot = { kind: "move" | "pause"; lane: number; dur: number };
    const timeline: Slot[] = [];
    LANES.forEach((l, i) => {
      timeline.push({ kind: "move", lane: i, dur: MOVE_MS * speedScale });
      timeline.push({
        kind: "pause",
        lane: i,
        dur: i === LANES.length - 1 ? TAKER_PAUSE_MS : PAUSE_MS,
      });
    });
    const totalDur = timeline.reduce((a, s) => a + s.dur, 0);

    function setCoin(x: number, y: number, s: "$" | "Ξ") {
      packet!.setAttribute("transform", `translate(${x} ${y})`);
      const usdc = s === "$";
      core!.setAttribute("fill", usdc ? "#0c1826" : "#0c1826");
      core!.setAttribute("stroke", usdc ? "#4cc2ff" : "#e6f0fa");
      if (sym!.textContent !== s) sym!.textContent = s;
      sym!.setAttribute("fill", usdc ? "#4cc2ff" : "#e6f0fa");
    }

    let vt = 0;
    let last = performance.now();
    let currentStage = 1;
    let currentSym: "$" | "Ξ" = "$";
    let warned = false;

    function frame(now: number) {
      try {
        const dt = Math.min(now - last, 100);
        last = now;
        vt = (vt + dt) % totalDur;

        let acc = 0;
        let slot: Slot = timeline[0];
        let slotT = 0;
        for (const s of timeline) {
          if (vt < acc + s.dur) {
            slot = s;
            slotT = vt - acc;
            break;
          }
          acc += s.dur;
        }

        if (slot.kind === "move") {
          const lanePath = laneRefs.current[slot.lane];
          const len = laneLens[slot.lane];
          if (lanePath && len > 0) {
            const p = lanePath.getPointAtLength(len * (slotT / slot.dur));
            packet!.setAttribute("transform", `translate(${p.x} ${p.y})`);
          }
        }

        const stage = LANES[slot.lane].stage;
        if (stage !== currentStage) {
          currentStage = stage;
          setActive(stage);
        }

        // identity switch at the anchors
        if (slot.kind === "pause" && slot.lane === 2 && currentSym !== "Ξ") {
          currentSym = "Ξ";
          setCoin(75, 360, "Ξ");
        }
        if (slot.kind === "pause" && slot.lane === LANES.length - 1 && currentSym !== "$") {
          currentSym = "$";
          setCoin(760, 92, "$");
        }
      } catch (err) {
        if (!warned) {
          warned = true;
          console.warn("[fill-diagram] frame error", err);
        }
      }
    }

    let raf = requestAnimationFrame(function loop(now) {
      frame(now);
      raf = requestAnimationFrame(loop);
    });

    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <div className="diagram-wrap">
      <div className="diagram">
        <svg className="d-svg" viewBox="0 0 960 560" preserveAspectRatio="xMidYMid meet">
          <defs>
            <marker id="arrow" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M0 0L8 4L0 8" fill="none" stroke="#2a4258" strokeWidth="1.4" />
            </marker>
          </defs>

          {/* dotted lanes with arrows */}
          {LANES.map((l, i) => (
            <path
              key={i}
              ref={(el) => {
                laneRefs.current[i] = el;
              }}
              className="flow-line"
              d={l.d}
              markerEnd="url(#arrow)"
            />
          ))}

          {/* numbered lane badges */}
          {LANES.map((l, i) => (
            <g key={`b${i}`}>
              <circle
                cx={l.bx}
                cy={l.by}
                r="9.5"
                fill={active === l.stage ? "rgba(76,194,255,0.14)" : "#0a1018"}
                stroke={active === l.stage ? "#4cc2ff" : "#2a4258"}
                strokeWidth="1.2"
              />
              <text
                x={l.bx}
                y={l.by + 3}
                textAnchor="middle"
                fontSize="8.5"
                fontFamily="var(--mono)"
                fontWeight="700"
                fill={active === l.stage ? "#4cc2ff" : "#63788c"}
              >
                {l.n}
              </text>
            </g>
          ))}

          {/* the coin packet — badge-style, carries the asset symbol */}
          <g ref={packetRef} transform="translate(725 108)">
            <circle r="13" fill="#0c1826" stroke="#4cc2ff" strokeWidth="1.6" />
            <text
              ref={symRef}
              fontSize="10"
              fontWeight="800"
              textAnchor="middle"
              dy="3.4"
              fill="#4cc2ff"
              fontFamily="var(--mono)"
            >
              $
            </text>
          </g>
        </svg>

        {/* node cards */}
        {NODES.map((n) => (
          <div
            className="d-node"
            key={n.key}
            style={{ left: `${(n.x / 960) * 100}%`, top: `${(n.y / 560) * 100}%` }}
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

      {/* legend — the explanations live here, synced with the packet */}
      <div className="d-legend">
        {LEGEND.map((l) => (
          <span
            className={active === l.stage ? "d-leg active" : "d-leg"}
            key={l.stage}
          >
            <span className="d-leg-n">{l.stage}</span>
            {l.label}
          </span>
        ))}
      </div>
    </div>
  );
}
