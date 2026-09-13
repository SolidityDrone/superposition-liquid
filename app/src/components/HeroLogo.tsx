"use client";

import { Oneinch, Uniswap } from "react-web3-icons/dex";

export default function HeroLogo() {
  return (
    <span className="logo-badge lg">
      <span className="brand-ghosts" aria-hidden>
        <span className="brand-ghost g1">
          <Oneinch size={196} />
        </span>
        <span className="brand-ghost g2">
          <Uniswap size={235} />
        </span>
      </span>
      <img src="/logo.png" alt="Superposition-Liquid" className="brand-logo" />
    </span>
  );
}
