import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Superposition-Liquid — yield-backed liquidity for 1inch Aqua",
  description:
    "Aqua liquidity positions backed 100% by yield protocols (Aave, Morpho, Euler, Pendle, Stargate) — looking like a plain ETH/USDC pool to the outside world.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
