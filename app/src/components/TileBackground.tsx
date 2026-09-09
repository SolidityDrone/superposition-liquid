"use client";

import { useEffect, useRef } from "react";

/**
 * Fluid "aqua" background — the tile grid is a real liquid surface.
 *
 * A height field drives every tile: continuous directional waves travel across
 * the grid (tiles rise/fall, scale and brighten on crests, dim in troughs),
 * while ripples — ambient and pointer-spawned — push the surface like touches
 * of water. Drawn back-to-front on canvas at 60fps.
 *
 * prefers-reduced-motion: the surface keeps moving only very slowly (gentle
 * drift, no splashes) instead of freezing on a single frame.
 *
 * The parent (.tile-bg) masks/positions it: the right-side placement and the
 * readability scrim still apply.
 */

const TILE = 38;
const GAP = 20;
const PITCH = TILE + GAP;
const MAX_RIPPLES = 9;

type Wave = { dx: number; dy: number; len: number; speed: number; amp: number };

// continuous ambient currents (direction, wavelength px, rad/s, amplitude)
const WAVES: Wave[] = [
  { dx: 1, dy: 0.35, len: 380, speed: 1.15, amp: 1.0 },
  { dx: -0.55, dy: 1, len: 560, speed: 0.75, amp: 0.65 },
  { dx: 0.8, dy: -0.6, len: 240, speed: 1.7, amp: 0.35 },
];

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

    // virtual clock: under reduced-motion time flows at 0.3x (calm drift)
    const timeScale = reduced ? 0.3 : 1;

    function resize() {
      const rect = (canvas as HTMLCanvasElement).parentElement!.getBoundingClientRect();
      w = rect.width;
      h = rect.height;
      canvas!.width = Math.floor(w * dpr);
      canvas!.height = Math.floor(h * dpr);
      canvas!.style.width = `${w}px`;
      canvas!.style.height = `${h}px`;
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      cols = Math.ceil(w / PITCH) + 2;
      rows = Math.ceil(h / PITCH) + 3;
    }

    function spawn(x: number, y: number, amp: number) {
      if (ripples.length >= MAX_RIPPLES) ripples.shift();
      ripples.push({ x, y, t0: vt, amp });
    }

    function spawnRandom() {
      spawn(
        w * (0.4 + Math.random() * 0.6),
        h * (0.1 + Math.random() * 0.8),
        1.0 + Math.random() * 0.6
      );
    }

    /** combined surface height at a point, roughly in [-1.6, +1.6] */
    function heightAt(px: number, py: number, t: number): number {
      let sum = 0;
      for (const wv of WAVES) {
        const phase = (px * wv.dx + py * wv.dy) / wv.len + t * wv.speed;
        sum += wv.amp * Math.sin(phase * Math.PI * 2);
      }
      for (const rp of ripples) {
        const age = (t * 1000 - rp.t0) / 1000;
        const decay = Math.max(0, 1 - age / 3.2);
        if (decay <= 0) continue;
        const ring = age * 210;
        const d = Math.hypot(px - rp.x, py - rp.y);
        const g = Math.exp(-((d - ring) * (d - ring)) / (2 * 62 * 62));
        sum += rp.amp * g * decay * Math.cos((d - ring) / 14);
      }
      return sum;
    }

    function draw(t: number) {
      ctx!.clearRect(0, 0, w, h);

      // back-to-front so lifted tiles overlap correctly
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          const cx = c * PITCH + PITCH / 2;
          const cy = r * PITCH + PITCH / 2;
          const height = heightAt(cx, cy, t);

          const lift = height * 9; // vertical liquid motion
          const scale = 1 + height * 0.055; // crests closer to the eye
          const size = TILE * scale;

          // color: crests bright azure, troughs sink dark
          const crest = Math.max(0, height);
          const trough = Math.max(0, -height);
          const alpha = 0.03 + crest * 0.38 + trough * 0.012;
          const mixCrest = Math.min(1, crest / 1.1);

          const rC = Math.round(56 + mixCrest * 69); // 56 → 125 (azure → light)
          const gC = Math.round(189 + mixCrest * 24); // 189 → 213
          const bC = 248;

          ctx!.save();
          ctx!.translate(cx, cy - lift);
          ctx!.scale(scale, scale);
          ctx!.beginPath();
          if (typeof ctx!.roundRect === "function") {
            ctx!.roundRect(-TILE / 2, -TILE / 2, TILE, TILE, 6);
          } else {
            ctx!.rect(-TILE / 2, -TILE / 2, TILE, TILE);
          }
          if (crest > 0.55) {
            ctx!.shadowColor = "rgba(125, 211, 252, 0.55)";
            ctx!.shadowBlur = 24 * crest;
          } else {
            ctx!.shadowBlur = 0;
          }
          ctx!.fillStyle = `rgba(${rC}, ${gC}, ${bC}, ${alpha.toFixed(3)})`;
          ctx!.fill();
          ctx!.restore();
        }
      }
      ctx!.shadowBlur = 0;
    }

    function onPointerMove(e: PointerEvent) {
      if (reduced) return; // no splashes under reduced motion
      const now = performance.now();
      if (now - lastPointerRipple < 140) return;
      const rect = canvas!.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      if (x < 0 || y < 0 || x > w || y > h) return;
      lastPointerRipple = now;
      spawn(x, y, 1.5); // a real splash pushes the surface
    }

    // ---- start "wet": waves already travelling ----
    resize();
    let last = performance.now();
    let vt = 0; // virtual clock (ms), advances at timeScale
    ripples = [
      { x: w * 0.8, y: h * 0.25, t0: -900, amp: 1.4 },
      { x: w * 0.55, y: h * 0.7, t0: -300, amp: 1.1 },
    ];
    nextSpawn = 1800;

    function loop() {
      try {
        const now = performance.now();
        vt += (now - last) * timeScale;
        last = now;

        ripples = ripples.filter((rp) => vt - rp.t0 < 3200);
        if (vt > nextSpawn) {
          if (!reduced) spawnRandom();
          nextSpawn = vt + 2400 + Math.random() * 2400;
        }
        draw(vt / 1000);
      } catch (err) {
        // never let one bad frame kill the loop
        console.warn("[aqua-bg] frame error", err);
      }
      raf = requestAnimationFrame(loop);
    }
    raf = requestAnimationFrame(loop);

    const onResize = () => {
      resize();
      draw(vt / 1000);
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
