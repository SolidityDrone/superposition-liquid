"use client";

import { useEffect, useRef } from "react";
import { ProtocolIcon } from "@/components/icons";

/** Every yield source a Superposition adapter can point at. */
const SOURCES = [
  "aave",
  "morpho",
  "euler",
  "yearn",
  "spark",
  "pendle",
  "stargate",
  "superposition",
  "oneinch",
] as const;

/**
 * 3D-ish orbit: the yield-source logos circle the main logo on a tilted ring
 * (y compressed to ~23% of x, like a carousel seen at an angle). Depth drives
 * scale + opacity + z-order so the ring reads as spheres rotating in space.
 */
export default function HeroOrbit() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const items = Array.from(el.querySelectorAll<HTMLElement>("[data-orbit]"));
    let raf = 0;
    const start = performance.now();
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    // keep the carousel moving even with reduced-motion (just slower)
    const speed = reduce ? 0.2 : 0.9;
    let width = el.clientWidth || 480;
    const ro = new ResizeObserver(() => {
      width = el.clientWidth || width;
    });
    ro.observe(el);

    const tick = (now: number) => {
      const t = ((now - start) / 1000) * speed;
      const Rx = width * 0.5;
      const Ry = Rx * 0.23; // tilt: y/z ≈ 23% of x
      items.forEach((it, i) => {
        const a = t + (i / items.length) * Math.PI * 2;
        const x = Math.cos(a) * Rx;
        const y = Math.sin(a) * Ry;
        const depth = (Math.sin(a) + 1) / 2; // 0 = back, 1 = front
        const scale = 0.62 + depth * 0.58;
        it.style.transform = `translate(-50%, -50%) translate(${x}px, ${y}px) scale(${scale})`;
        it.style.opacity = String(0.28 + depth * 0.72);
        it.style.zIndex = String(Math.round(depth * 100));
      });
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
    };
  }, []);

  return (
    <div className="hero-orbit" ref={ref} aria-hidden>
      <img src="/logo.png" alt="Superposition-Liquid" className="hero-orbit-core brand-logo" />
      {SOURCES.map((id) => (
        <span key={id} data-orbit className="orbit-chip">
          <ProtocolIcon id={id} size={34} />
        </span>
      ))}
    </div>
  );
}
