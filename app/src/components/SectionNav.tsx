"use client";

import { useEffect, useState } from "react";

const SECTIONS = [
  { id: "top", label: "Overview" },
  { id: "layers", label: "Layers" },
  { id: "backed", label: "Adapters" },
  { id: "how", label: "How it works" },
  { id: "hook", label: "Uniswap hook" },
  { id: "final", label: "Source" },
];

export default function SectionNav() {
  const [active, setActive] = useState("top");

  useEffect(() => {
    const els = SECTIONS.map((s) => document.getElementById(s.id)).filter((e): e is HTMLElement => !!e);
    if (els.length === 0) return;
    const onScroll = () => {
      const mid = window.innerHeight * 0.4;
      let current = els[0].id;
      for (const el of els) {
        if (el.getBoundingClientRect().top <= mid) current = el.id;
      }
      setActive(current);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, []);

  return (
    <nav className="secnav" aria-label="Section summary">
      {SECTIONS.map((s) => (
        <a key={s.id} href={`#${s.id}`} className={`secnav-item ${active === s.id ? "active" : ""}`}>
          <span className="secnav-label">{s.label}</span>
          <span className="secnav-dot" />
        </a>
      ))}
    </nav>
  );
}
