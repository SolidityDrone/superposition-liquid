"use client";

import { useState } from "react";
import {
  AaveLogo, MorphoLogo, EulerLogo, LidoLogo, PendleLogo, StargateLogo, CurveLogo,
  LendingIcon, VaultIcon, StakingIcon, FixedIncomeIcon, BridgeIcon,
} from "@/components/logos";

type TokenEntry = { symbol: string; address: string; note?: string };

type ProtocolRow = {
  name: string;
  sub: string;
  icon: React.ReactNode;
  color: string;
  earns: string;
  desc: string;
  prots: { name: string; Logo: React.FC<{ size?: number }> }[];
  mainnet: TokenEntry[];
  testnet: TokenEntry[];
};

const DATA: ProtocolRow[] = [
  {
    name: "Aave v3",
    sub: "AaveV3Adapter",
    icon: <LendingIcon size={19} />,
    color: "#b6509e",
    earns: "Variable supply APY",
    desc: "aWETH and aUSDC across 18 chains, both balance models handled.",
    prots: [{ name: "Aave", Logo: AaveLogo }],
    mainnet: [
      { symbol: "WETH", address: "0x4200…0006", note: "aWETH · Base" },
      { symbol: "USDC", address: "0x8335…2913", note: "aUSDC · Base" },
    ],
    testnet: [
      { symbol: "WETH", address: "0xfff9…8b14", note: "aWETH · Sepolia" },
      { symbol: "USDC", address: "0x94a9…ad48", note: "aUSDC · Sepolia" },
      { symbol: "WETH", address: "0x4200…0006", note: "aWETH · Base Sepolia" },
    ],
  },
  {
    name: "Morpho · Euler",
    sub: "ERC4626Adapter",
    icon: <VaultIcon size={19} />,
    color: "#1b5cff",
    earns: "Curated vault yield",
    desc: "One generic adapter for any ERC-4626 vault — Gauntlet, Steakhouse, Euler EVK…",
    prots: [
      { name: "Morpho", Logo: MorphoLogo },
      { name: "Euler", Logo: EulerLogo },
    ],
    mainnet: [
      { symbol: "WETH", address: "0x6b13…8844", note: "Gauntlet WETH Core" },
      { symbol: "USDC", address: "0xBEEF…83b2", note: "Steakhouse Prime USDC" },
      { symbol: "WETH", address: "0x8591…b410", note: "EVK eWETH-1" },
    ],
    testnet: [],
  },
  {
    name: "Lido wstETH",
    sub: "WstETHAdapter",
    icon: <StakingIcon size={19} />,
    color: "#00a3ff",
    earns: "Staking yield, appreciating vs ETH",
    desc: "JIT unwrap through the real Curve stETH/ETH pool.",
    prots: [
      { name: "Lido", Logo: LidoLogo },
      { name: "Curve", Logo: CurveLogo },
    ],
    mainnet: [
      { symbol: "wstETH", address: "0x59ad…6736", note: "Lido wstETH · Mainnet" },
      { symbol: "stETH", address: "0xae7ab…d494", note: "Lido stETH · Mainnet" },
    ],
    testnet: [],
  },
  {
    name: "Pendle PT",
    sub: "PendlePTAdapter",
    icon: <FixedIncomeIcon size={19} />,
    color: "#7b61ff",
    earns: "Fixed APY, locked at entry",
    desc: "Expired markets redeem 1:1; active ones appreciate toward par in real time.",
    prots: [{ name: "Pendle", Logo: PendleLogo }],
    mainnet: [
      { symbol: "PT-wstETH", address: "Pendle markets", note: "Ethereum" },
      { symbol: "PT-aUSDC", address: "Pendle markets", note: "Arbitrum" },
    ],
    testnet: [],
  },
  {
    name: "Stargate V2",
    sub: "StargateAdapter",
    icon: <BridgeIcon size={19} />,
    color: "#4c6fff",
    earns: "Bridge reward stream",
    desc: "Pool liquidity, staked. Instant unstake → redeem, capped by pool credit.",
    prots: [{ name: "Stargate", Logo: StargateLogo }],
    mainnet: [
      { symbol: "USDC", address: "0x27a1…5d26", note: "PoolUSDC · Base" },
    ],
    testnet: [
      { symbol: "USDC", address: "0x4985…863F0", note: "PoolUSDC · Sepolia" },
    ],
  },
];

function ChevronIcon({ size = 14 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 6l4 4 4-4" />
    </svg>
  );
}

function CloseIcon({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M4 4l8 8M12 4l-8 8" />
    </svg>
  );
}

export default function BackedSection() {
  const [network, setNetwork] = useState<"mainnet" | "testnet">("mainnet");
  const [openModal, setOpenModal] = useState<string | null>(null);

  const active = DATA.find((d) => d.sub === openModal);
  const activeTokens = active ? (network === "mainnet" ? active.mainnet : active.testnet) : null;

  return (
    <>
      {/* toggle + section */}
      <section className="section" id="backed">
        <div className="container">
          <div className="panel">
            <div className="backed-header">
              <div>
                <h2 className="sec-title">0x03 Pick a protocol. Pick a risk.</h2>
                <p className="sec-intro">
                  The adapter layer is the point: the strategy doesn&apos;t change — the maker
                  points one config at a protocol and the position earns that protocol&apos;s
                  yield. Same pool surface, five temperaments.
                </p>
              </div>
              <div className="net-toggle">
                <button
                  className={`net-btn${network === "mainnet" ? " active" : ""}`}
                  onClick={() => setNetwork("mainnet")}
                >
                  Mainnet
                </button>
                <button
                  className={`net-btn${network === "testnet" ? " active" : ""}`}
                  onClick={() => setNetwork("testnet")}
                >
                  Testnet
                </button>
              </div>
            </div>
            <div className="backed">
              {DATA.filter((b) => network === "mainnet" || b.testnet.length > 0).map((b) => {
                const tokens = network === "mainnet" ? b.mainnet : b.testnet;
                const hasPartial = network === "testnet" && b.mainnet.length > 0 && b.testnet.length > 0 && b.testnet.length < b.mainnet.length;
                return (
                  <div className="backed-row" key={b.sub}>
                    <div className="backed-icon" style={{ color: b.color, borderColor: `${b.color}33`, background: `${b.color}14` }}>
                      {b.icon}
                    </div>
                    <div className="backed-name">
                      {b.name}
                      <span className="sub">{b.sub}</span>
                      {network === "testnet" && b.testnet.length === 0 && (
                        <span className="unavailable-badge">unavailable</span>
                      )}
                    </div>
                    <div className="backed-desc">
                      <b style={{ color: "var(--text)", fontWeight: 560 }}>{b.earns}</b> — {b.desc}
                      {hasPartial && (
                        <span className="partial-note">Partial testnet coverage</span>
                      )}
                    </div>
                    <div className="backed-prots">
                      {b.prots.map((pr) => (
                        <span className="prot" key={pr.name}>
                          <div className="prot-logo-wrap">
                            <pr.Logo size={38} />
                            {tokens.length > 0 && (
                              <button
                                className="prot-expand"
                                onClick={() => setOpenModal(openModal === b.sub ? null : b.sub)}
                                aria-label={`Show supported tokens for ${b.name}`}
                              >
                                <ChevronIcon />
                              </button>
                            )}
                          </div>
                          {pr.name}
                        </span>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
            <div className="quiet">
              <span>99 tests, green</span>
              <span className="sep">·</span>
              <span>7 integrations verified against live contracts on Base, Arbitrum and Ethereum forks</span>
              <span className="sep">·</span>
              <span>solidity 0.8.30 · foundry</span>
            </div>
          </div>
        </div>
      </section>

      {/* modal */}
      {active && activeTokens && activeTokens.length > 0 && (
        <div className="modal-backdrop" onClick={() => setOpenModal(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <div className="modal-title">
                {(() => { const Logo = active.prots[0].Logo; return <Logo size={28} />; })()}
                <span>{active.name}</span>
              </div>
              <button className="modal-close" onClick={() => setOpenModal(null)}>
                <CloseIcon />
              </button>
            </div>
            <div className="modal-net-label">
              {network === "mainnet" ? "Mainnet" : "Testnet"} — Supported tokens
            </div>
            <div className="modal-tokens">
              {activeTokens.map((t) => (
                <div className="modal-token" key={t.symbol + t.address}>
                  <div className="token-symbol">{t.symbol}</div>
                  <div className="token-addr">{t.address}</div>
                  {t.note && <div className="token-note">{t.note}</div>}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
