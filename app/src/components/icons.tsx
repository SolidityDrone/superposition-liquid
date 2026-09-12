import type { FC } from "react";
import { Usdc, Usdt, Dai, Eth, Btc, Link, Uni, Mkr, Ldo, Crv } from "react-web3-icons/coin";
import { Aave as AaveToken, Yearn, Spark } from "react-web3-icons/defi";
import { AaveLogo, MorphoLogo, EulerLogo, PendleLogo, StargateLogo, UniswapLogo } from "@/components/logos";

type IconC = FC<{ size?: number }>;

const TOKEN_ICONS: Record<string, IconC> = {
  USDC: Usdc as IconC,
  USDT: Usdt as IconC,
  DAI: Dai as IconC,
  WETH: Eth as IconC,
  ETH: Eth as IconC,
  WBTC: Btc as IconC,
  BTC: Btc as IconC,
  LINK: Link as IconC,
  AAVE: AaveToken as IconC,
  UNI: Uni as IconC,
  MKR: Mkr as IconC,
  LDO: Ldo as IconC,
  CRV: Crv as IconC,
};

export function TokenIcon({ symbol, size = 15 }: { symbol: string; size?: number }) {
  const Icon = TOKEN_ICONS[symbol.toUpperCase()];
  if (Icon) return <Icon size={size} />;
  return (
    <span
      aria-hidden
      style={{
        width: size,
        height: size,
        borderRadius: "50%",
        display: "inline-grid",
        placeItems: "center",
        background: "rgba(76,194,255,.14)",
        border: "1px solid var(--border-bright)",
        color: "var(--text-mid)",
        fontSize: Math.max(8, size * 0.5),
        fontWeight: 700,
        lineHeight: 1,
      }}
    >
      {symbol.slice(0, 2)}
    </span>
  );
}

const PROTOCOL_ICONS: Record<string, IconC> = {
  "erc4626-aave": AaveLogo as IconC,
  aave: AaveLogo as IconC,
  morpho: MorphoLogo as IconC,
  euler: EulerLogo as IconC,
  yearn: Yearn as IconC,
  spark: Spark as IconC,
  superposition: UniswapLogo as IconC,
  stargate: StargateLogo as IconC,
  pendle: PendleLogo as IconC,
};

export function ProtocolIcon({ id, size = 15 }: { id: string; size?: number }) {
  const Icon = PROTOCOL_ICONS[id];
  if (!Icon) return null;
  return <Icon size={size} />;
}

export function TokenLabel({ symbol, size = 15 }: { symbol: string; size?: number }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 7 }}>
      <TokenIcon symbol={symbol} size={size} />
      <b>{symbol}</b>
    </span>
  );
}

export function InfoIcon({ size = 14 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <circle cx="8" cy="8" r="6.4" />
      <path d="M8 7.3v4" />
      <circle cx="8" cy="4.9" r="0.6" fill="currentColor" stroke="none" />
    </svg>
  );
}
