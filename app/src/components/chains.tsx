/**
 * Chain registry for the adapter sections. Icons come from `react-web3-icons`
 * (`/chain` subpath — tree-shakeable, MIT). Only chains that actually show up
 * in an adapter's availability list are listed here.
 */

import {
  Ethereum,
  Base,
  ArbitrumOne,
  Optimism,
  Polygon,
  BinanceSmartChain,
  Avalanche,
  Scroll,
  Linea,
  Mantle,
  Metis,
  ZkSync,
  Celo,
  GnosisChain,
  Berachain,
  Blast,
  Zora,
  WorldChain,
  Ink,
  Fraxtal,
} from "react-web3-icons/chain";

type ChainIcon = React.ComponentType<{ size?: number; className?: string }>;

export type ChainKey =
  | "ethereum" | "base" | "arbitrum" | "optimism" | "polygon" | "bnb"
  | "avalanche" | "scroll" | "linea" | "mantle" | "metis" | "zksync"
  | "celo" | "gnosis" | "berachain" | "blast" | "zora" | "worldchain"
  | "ink" | "fraxtal";

export const CHAINS: Record<ChainKey, { name: string; Icon: ChainIcon }> = {
  ethereum: { name: "Ethereum", Icon: Ethereum },
  base: { name: "Base", Icon: Base },
  arbitrum: { name: "Arbitrum", Icon: ArbitrumOne },
  optimism: { name: "Optimism", Icon: Optimism },
  polygon: { name: "Polygon", Icon: Polygon },
  bnb: { name: "BNB Chain", Icon: BinanceSmartChain },
  avalanche: { name: "Avalanche", Icon: Avalanche },
  scroll: { name: "Scroll", Icon: Scroll },
  linea: { name: "Linea", Icon: Linea },
  mantle: { name: "Mantle", Icon: Mantle },
  metis: { name: "Metis", Icon: Metis },
  zksync: { name: "zkSync", Icon: ZkSync },
  celo: { name: "Celo", Icon: Celo },
  gnosis: { name: "Gnosis", Icon: GnosisChain },
  berachain: { name: "Berachain", Icon: Berachain },
  blast: { name: "Blast", Icon: Blast },
  zora: { name: "Zora", Icon: Zora },
  worldchain: { name: "World Chain", Icon: WorldChain },
  ink: { name: "Ink", Icon: Ink },
  fraxtal: { name: "Fraxtal", Icon: Fraxtal },
};
