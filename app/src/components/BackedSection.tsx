"use client";

import { useState } from "react";
import {
  AaveLogo, MorphoLogo, EulerLogo, PendleLogo, StargateLogo,
  UniswapLogo,
  LendingIcon, VaultIcon, FixedIncomeIcon, BridgeIcon, HookIcon,
} from "@/components/logos";
import { Yearn as YearnLogo, Spark as SparkLogo, Ethena as EthenaLogo, Frax as FraxLogo } from "react-web3-icons/defi";
import { CHAINS, type ChainKey } from "@/components/chains";

type ProtocolRow = {
  name: string;
  sub: string;
  icon: React.ReactNode;
  color: string;
  earns: string;
  desc: string;
  prots: { name: string; Logo: React.FC<{ size?: number }> }[];
  /** chains where the protocol is actually live, so the adapter can target it */
  chains: ChainKey[];
  /** render the protocols as an icon cluster (many protocols, e.g. ERC-4626) */
  compact?: boolean;
};

const DATA: ProtocolRow[] = [
  {
    name: "Aave v3",
    sub: "AaveV3Adapter",
    icon: <LendingIcon size={19} />,
    color: "#b6509e",
    earns: "Variable supply APY",
    desc: "aWETH and aUSDC, both balance models handled.",
    prots: [{ name: "Aave", Logo: AaveLogo }],
    chains: [
      "ethereum", "base", "arbitrum", "optimism", "polygon", "bnb", "avalanche",
      "gnosis", "scroll", "zksync", "linea", "celo", "metis", "ink",
    ],
  },
  {
    name: "ERC-4626 vaults",
    sub: "ERC4626Adapter",
    icon: <VaultIcon size={19} />,
    color: "#1b5cff",
    earns: "Curated vault yield",
    desc: "One generic adapter for ANY ERC-4626 vault — Morpho, Euler v2, Yearn v3, Spark, Sky, Ethena, Fluid, Silo, Maple, Frax, Aave wrappers…",
    prots: [
      { name: "Morpho", Logo: MorphoLogo },
      { name: "Euler", Logo: EulerLogo },
      { name: "Yearn", Logo: YearnLogo },
      { name: "Spark", Logo: SparkLogo },
      { name: "Ethena", Logo: EthenaLogo },
      { name: "Frax", Logo: FraxLogo },
    ],
    chains: ["ethereum", "base", "arbitrum", "optimism", "polygon", "bnb", "avalanche", "scroll", "linea", "mantle", "worldchain", "ink", "fraxtal"],
    compact: true,
  },
  {
    name: "Pendle PT",
    sub: "PendlePTAdapter",
    icon: <FixedIncomeIcon size={19} />,
    color: "#7b61ff",
    earns: "Fixed APY, locked at entry",
    desc: "Expired markets redeem 1:1; active ones appreciate toward par in real time.",
    prots: [{ name: "Pendle", Logo: PendleLogo }],
    chains: ["ethereum", "arbitrum", "base", "optimism", "bnb", "mantle", "berachain", "ink"],
  },
  {
    name: "Stargate V2",
    sub: "StargateAdapter",
    icon: <BridgeIcon size={19} />,
    color: "#4c6fff",
    earns: "Bridge reward stream",
    desc: "Pool liquidity, staked. Instant unstake → redeem, capped by pool credit.",
    prots: [{ name: "Stargate", Logo: StargateLogo }],
    chains: ["ethereum", "base", "arbitrum", "optimism", "polygon", "bnb", "avalanche", "linea", "mantle", "metis", "scroll"],
  },
  {
    name: "Superposition · Uniswap v4",
    sub: "SuperpositionUniAdapter",
    icon: <HookIcon size={19} />,
    color: "#ff37c7",
    earns: "Aave yield + v4 fees",
    desc: "A one-sided bucket on a Uniswap v4 concentrated-liquidity hook, capital in ERC-4626 vaults (Aave's waToken wrappers).",
    prots: [{ name: "Uniswap v4", Logo: UniswapLogo }],
    chains: ["ethereum", "base", "arbitrum", "optimism", "polygon", "bnb", "avalanche", "blast", "zora", "worldchain", "ink", "celo", "zksync", "linea", "scroll"],
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
  const [openModal, setOpenModal] = useState<string | null>(null);
  const active = DATA.find((d) => d.sub === openModal);

  return (
    <>
      <section className="section" id="backed">
        <div className="container">
          <div className="panel">
            <div className="backed-header">
              <div>
                <h2 className="sec-title">0x01 Pick a protocol. Pick a chain.</h2>
                <p className="sec-intro">
                  The adapter layer is the point: the strategy doesn&apos;t change — the maker
                  points one config at a protocol and the position earns that protocol&apos;s
                  yield. Adapters are chain-agnostic; click a protocol to see where it&apos;s live.
                </p>
              </div>
            </div>
            <div className="backed">
              {DATA.map((b) => (
                <div className="backed-row" key={b.sub}>
                  <div className="backed-icon" style={{ color: b.color, borderColor: `${b.color}33`, background: `${b.color}14` }}>
                    {b.icon}
                  </div>
                  <div className="backed-name">
                    {b.name}
                    <span className="sub">{b.sub}</span>
                  </div>
                  <div className="backed-desc">
                    <b style={{ color: "var(--text)", fontWeight: 560 }}>{b.earns}</b> — {b.desc}
                  </div>
                  <div className={"backed-prots" + (b.compact ? " compact" : "")}>
                    {b.prots.map((pr) => (
                      <span className="prot" key={pr.name} title={pr.name}>
                        <div className="prot-logo-wrap">
                          <pr.Logo size={b.compact ? 30 : 38} />
                          {!b.compact && (
                            <button
                              className="prot-expand"
                              onClick={() => setOpenModal(openModal === b.sub ? null : b.sub)}
                              aria-label={`Show chains where ${b.name} is live`}
                              title="Show available chains"
                            >
                              <ChevronIcon />
                            </button>
                          )}
                        </div>
                        {!b.compact && pr.name}
                      </span>
                    ))}
                    {b.compact && (
                      <button
                        className="prot-expand inline"
                        onClick={() => setOpenModal(openModal === b.sub ? null : b.sub)}
                        aria-label={`Show chains where ${b.name} is live`}
                        title="Show available chains"
                      >
                        <ChevronIcon />
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
            <div
              style={{
                marginTop: 18,
                padding: "16px 18px",
                border: "1px solid var(--border)",
                borderRadius: 16,
                background: "var(--bg-raise)",
                display: "flex",
                gap: 16,
                flexWrap: "wrap",
                alignItems: "baseline",
              }}
            >
              <span className="kicker" style={{ color: "var(--accent)", textTransform: "uppercase", letterSpacing: ".12em", fontSize: 12 }}>
                Borrow mode
              </span>
              <p style={{ margin: 0, color: "var(--text-mid)", maxWidth: 760 }}>
                An adapter is also a <b>source of capital</b>: with{" "}
                <code>MakerConfig.BorrowConfig</code> (<code>enabled</code>, <code>collateral</code>,{" "}
                <code>maxDebt</code>) a maker can quote an asset they <b>don&apos;t hold</b> — borrowed
                against yield-bearing collateral, and the matching in-fill repays the debt first. The
                configured collateral + risk capacitor are the soft isolation.{" "}
                <a href="/app" style={{ color: "var(--accent)" }}>Configure it in the console →</a>
              </p>
            </div>
          </div>
        </div>
      </section>

      {active && (
        <div className="modal-backdrop" onClick={() => setOpenModal(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <div className="modal-title">
                {(() => { const Logo = active.prots[0].Logo; return <Logo size={28} />; })()}
                <span>{active.name}</span>
                <span className="modal-sub">{active.sub}</span>
              </div>
              <button className="modal-close" onClick={() => setOpenModal(null)}>
                <CloseIcon />
              </button>
            </div>
            <div className="modal-net-label">
              Live on {active.chains.length} chains — the adapter can back a position on any of them
            </div>
            <div className="chain-grid">
              {active.chains.map((k) => {
                const { name, Icon } = CHAINS[k];
                return (
                  <div className="chain-chip" key={k}>
                    <Icon size={30} />
                    <span>{name}</span>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
