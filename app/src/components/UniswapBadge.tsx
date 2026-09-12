"use client";

import { Uniswap } from "react-web3-icons/dex";

/** Circular Uniswap mark used as the header badge of the hook section.
 *  Client component: the icon library needs `createContext`, which is not
 *  available while server-rendering a static page. */
export default function UniswapBadge({ size = 30 }: { size?: number }) {
  return (
    <div className="hook-badge">
      <Uniswap size={size} />
    </div>
  );
}
