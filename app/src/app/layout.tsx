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
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Press+Start+2P&family=VT323&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <div className="crt-overlay" aria-hidden>
          <i className="crt-scratch" />
          <i className="crt-scratch" />
          <i className="crt-scratch" />
        </div>
        {children}
      </body>
    </html>
  );
}
