"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

export type DropdownOption = {
  value: string;
  label: string;
  icon?: ReactNode;
  disabled?: boolean;
  note?: string;
};

export function Dropdown({
  value,
  options,
  onChange,
  disabled,
  width,
}: {
  value: string;
  options: DropdownOption[];
  onChange: (v: string) => void;
  disabled?: boolean;
  width?: number;
}) {
  const [open, setOpen] = useState(false);
  const [rect, setRect] = useState<{ top: number; left: number; minWidth: number } | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const sel = options.find((o) => o.value === value);

  function toggle() {
    if (!open && ref.current) {
      const r = ref.current.getBoundingClientRect();
      setRect({ top: r.bottom + 6, left: r.left, minWidth: Math.max(r.width, 170) });
    }
    setOpen((o) => !o);
  }

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      const t = e.target as Node;
      if (ref.current?.contains(t) || menuRef.current?.contains(t)) return;
      setOpen(false);
    };
    const onEsc = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    const onMove = () => setOpen(false);
    document.addEventListener("mousedown", onDoc);
    document.addEventListener("keydown", onEsc);
    window.addEventListener("scroll", onMove, true);
    window.addEventListener("resize", onMove);
    return () => {
      document.removeEventListener("mousedown", onDoc);
      document.removeEventListener("keydown", onEsc);
      window.removeEventListener("scroll", onMove, true);
      window.removeEventListener("resize", onMove);
    };
  }, [open]);

  const menu = open && rect ? (
    <div ref={menuRef} className="dd-menu" role="listbox" style={{ position: "fixed", top: rect.top, left: rect.left, minWidth: rect.minWidth }}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="option"
          aria-selected={o.value === value}
          disabled={o.disabled}
          className={`dd-item ${o.value === value ? "active" : ""}`}
          onClick={() => {
            onChange(o.value);
            setOpen(false);
          }}
        >
          {o.icon}
          <span>{o.label}</span>
          {o.note && <em>{o.note}</em>}
        </button>
      ))}
    </div>
  ) : null;

  return (
    <div className="dd" ref={ref} style={{ width }}>
      <button type="button" className="dd-trigger" disabled={disabled} onClick={toggle} aria-haspopup="listbox" aria-expanded={open}>
        <span className="dd-cur">
          {sel?.icon}
          <span className="dd-label">{sel?.label ?? "—"}</span>
        </span>
        <svg className={`dd-caret ${open ? "up" : ""}`} width="10" height="10" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M4 6l4 4 4-4" />
        </svg>
      </button>
      {typeof document !== "undefined" && menu ? createPortal(menu, document.body) : null}
    </div>
  );
}
