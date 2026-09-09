"use client";

import { useEffect, useRef } from "react";

/**
 * Fluid "aqua" background: the tile grid behaves like a liquid surface.
 * Concentric ripples travel across the grid and light the tiles up as they
 * pass; the pointer spawns ripples of its own (touching water). Rendered on
 * canvas for 60fps with glow; falls back to a static frame under
 * prefers-reduced-motion. The parent (.tile-bg) masks/positions it — the
 * right-side placement and the readability scrim in globals.css still apply.
 */

const TILE = 38;
const GAP = 22;
const PITCH = TILE + GAP;
const SPEED = 240; // ripple speed, px/s
const SIGMA = 55; // ring thickness, px
const LIFE = 4200; // ripple lifetime, ms
const MAX_RIPPLES = 8;

type Ripple = { x: number; y: number; t0: number; amp: number };

export default function TileBackground({ opacity = 1 }: { opacity?: number }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let raf = 0;
    let w = 0;
    let h = 0;
    let cols = 0;
    let rows = 0;
    let ripples: Ripple[] = [];
    let nextSpawn = 0;
    let lastPointerRipple = 0;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    function intensityAt(px: number, py: number, now: number): number {
      let i = 0;
      for (const r of ripples) {
        const age = now - r.t0;
        const decay = 1 - age / LIFE;
        if (decay <= 0) continue;
        const ring = (age / 1000) * SPEED;
        const d = Math.hypot(px - r.x, py - r.y);
        const g = Math.exp(-((d - ring) * (d - ring)) / (2 * SIGMA * SIGMA));
        i += r.amp * g * decay;
      }
      return Math.min(i, 1.4);
    }

    function draw(now: number) {
      ctx!.clearRect(0, 0, w, h);
      for (let c = 0; c < cols; c++) {
        for (let r = 0; r < rows; r++) {
          const x = c * PITCH + GAP / 2;
          const y = r * PITCH + GAP / 2;
          const i = intensityAt(x + TILE / 2, y + TILE / 2, now);
          const alpha = 0.025 + Math.min(0.72, i * 0.75);
          ctx!.beginPath();
          if (typeof ctx!.roundRect === "function") {
            ctx!.roundRect(x, y, TILE, TILE, 6);
          } else {
            ctx!.rect(x, y, TILE, TILE);
          }
          if (i > 0.18) {
            ctx!.shadowColor = "rgba(56, 189, 248, 0.5)";
            ctx!.shadowBlur = 20 * Math.min(i, 1);
          } else {
            ctx!.shadowBlur = 0;
          }
          ctx!.fillStyle = `rgba(56, 189, 248, ${alpha.toFixed(3)})`;
          ctx!.fill();
        }
      }
      ctx!.shadowBlur = 0;
    }

    function resize() {
      const rect = (canvas as HTMLCanvasElement).parentElement!.getBoundingClientRect();
      w = rect.width;
      h = rect.height;
      canvas!.width = Math.floor(w * dpr);
      canvas!.height = Math.floor(h * dpr);
      canvas!.style.width = `${w}px`;
      canvas!.style.height = `${h}px`;
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      cols = Math.ceil(w / PITCH) + 1;
      rows = Math.ceil(h / PITCH) + 1;
    }

    function spawn(x: number, y: number, amp: number) {
      if (ripples.length >= MAX_RIPPLES) ripples.shift();
      ripples.push({ x, y, t0: performance.now(), amp });
    }

    function spawnRandom() {
      spawn(
        w * (0.35 + Math.random() * 0.65), // bias to the right (the visible side)
        h * (0.1 + Math.random() * 0.8),
        0.65 + Math.random() * 0.5
      );
    }

    function onPointerMove(e: PointerEvent) {
      const now = performance.now();
      if (now - lastPointerRipple < 160) return;
      const rect = canvas!.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      if (x < 0 || y < 0 || x > w || y > h) return;
      lastPointerRipple = now;
      spawn(x, y, 0.55);
    }

    // ---- initial frame: start "wet" with two ripples already travelling ----
    resize();
    const now0 = performance.now();
    ripples = [
      { x: w * 0.75, y: h * 0.3, t0: now0 - 1200, amp: 0.9 },
      { x: w * 0.55, y: h * 0.7, t0: now0 - 600, amp: 0.7 },
    ];
    draw(now0);
    nextSpawn = now0 + 1400;

    if (reduced) {
      // static surface: no animation loop, no listeners
      return () => {};
    }

    function loop() {
      const now = performance.now();
      ripples = ripples.filter((r) => now - r.t0 < LIFE);
      if (now > nextSpawn) {
        spawnRandom();
        nextSpawn = now + 2200 + Math.random() * 2000;
      }
      draw(now);
      raf = requestAnimationFrame(loop);
    }
    raf = requestAnimationFrame(loop);

    const onResize = () => {
      resize();
      draw(performance.now());
    };
    window.addEventListener("resize", onResize);
    window.addEventListener("pointermove", onPointerMove);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", onResize);
      window.removeEventListener("pointermove", onPointerMove);
    };
  }, []);

  return (
    <div className="tile-bg" aria-hidden style={{ opacity }}>
      <canvas ref={canvasRef} />
    </div>
  );
}
