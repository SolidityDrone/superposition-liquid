import TileBackground from "@/components/TileBackground";
import {
  AaveLogo, MorphoLogo, EulerLogo, LidoLogo, PendleLogo, StargateLogo, CurveLogo,
  LendingIcon, VaultIcon, StakingIcon, FixedIncomeIcon, BridgeIcon,
} from "@/components/logos";

/* ---------- data ---------- */

const STATS = [
  { num: "5", label: "risk profiles, one AMM" },
  { num: "99", label: "tests, all green" },
  { num: "7", label: "real-protocol fork proofs" },
  { num: "13", label: "chains ready (Aqua set)" },
];

type Prot = { name: string; color: string; state: string; Logo: (p: { size?: number }) => React.JSX.Element };

const TYPOLOGIES: {
  kind: string;
  name: string;
  Icon: (p: { size?: number }) => React.JSX.Element;
  color: string;
  desc: string;
  prots: Prot[];
}[] = [
  {
    kind: "ADAPTER · AAVEV3",
    name: "Lending",
    Icon: LendingIcon,
    color: "#8247e5",
    desc: "Capital supplied into Aave v3 earning variable supply APY. Handles both the legacy index-based aToken model and the v3.2 displayed-balance model.",
    prots: [
      { name: "Aave v3", color: "#b6509e", state: "fork-proven", Logo: AaveLogo },
      { name: "aWETH / aUSDC", color: "#2ca8e0", state: "Base ✅", Logo: AaveLogo },
    ],
  },
  {
    kind: "ADAPTER · ERC-4626",
    name: "Vaults",
    Icon: VaultIcon,
    color: "#1b5cff",
    desc: "One generic adapter covers any ERC-4626 vault — curated lending vaults with their own fee and risk models, discovered per chain.",
    prots: [
      { name: "Morpho", color: "#1b5cff", state: "fork-proven", Logo: MorphoLogo },
      { name: "Euler v2", color: "#14aeea", state: "fork-proven", Logo: EulerLogo },
      { name: "Gauntlet / Steakhouse", color: "#8fa39b", state: "Base ✅", Logo: MorphoLogo },
    ],
  },
  {
    kind: "ADAPTER · WSTETH",
    name: "Liquid staking",
    Icon: StakingIcon,
    color: "#00a3ff",
    desc: "Capital in Lido wstETH — appreciates vs ETH through staking yield. JIT unwrap + a real Curve swap leg delivers WETH atomically.",
    prots: [
      { name: "Lido wstETH", color: "#00a3ff", state: "fork-proven", Logo: LidoLogo },
      { name: "Curve", color: "#f5d020", state: "swap leg", Logo: CurveLogo },
    ],
  },
  {
    kind: "ADAPTER · PENDLE",
    name: "Fixed income",
    Icon: FixedIncomeIcon,
    color: "#7b61ff",
    desc: "Capital in Pendle PT. Expired markets redeem 1:1 with zero swap legs; active markets trade at the implied-yield discount and appreciate toward par in real time.",
    prots: [
      { name: "Pendle PT", color: "#7b61ff", state: "fork-proven ×2", Logo: PendleLogo },
      { name: "PYLpOracle", color: "#5a6b64", state: "TWAP rate", Logo: PendleLogo },
    ],
  },
  {
    kind: "ADAPTER · STARGATE",
    name: "Bridge liquidity",
    Icon: BridgeIcon,
    color: "#4c6fff",
    desc: "Capital staked in a Stargate V2 pool — the maker provides the liquidity the protocol uses for cross-chain swaps and earns its reward stream.",
    prots: [
      { name: "Stargate V2", color: "#4c6fff", state: "fork-proven", Logo: StargateLogo },
      { name: "LayerZero", color: "#8fa39b", state: "under the hood", Logo: StargateLogo },
    ],
  },
];

const FLOW = [
  {
    step: "HOOK · PRE-TRANSFER-OUT",
    title: "JIT unwrap",
    desc: "Seconds before delivery, the hook withdraws, unwraps, redeems or unstakes exactly what the fill needs — directly from the maker's yield position.",
    code: "withdraw / unwrap / redeem / unstake",
  },
  {
    step: "DEFAULT TRANSFER",
    title: "Deliver to taker",
    desc: "The VM's default transfer (or Aqua.pull) moves the freshly-unwrapped tokens from the maker wallet to the taker. Capital held idle for ~0 seconds.",
    code: "Aqua.pull(maker → taker)",
  },
  {
    step: "HOOK · POST-TRANSFER-IN",
    title: "Redeploy revenue",
    desc: "What the taker paid lands in the maker wallet and is instantly re-deployed into the yield protocol — and staked, where the protocol separates the two.",
    code: "deposit + stake",
  },
];

const OPCODES = [
  {
    byte: "0x22",
    label: "BYTE 34",
    title: "YieldAdjustedRateXD",
    desc: "Scales the swap registers by rate(now)/rate(ship) from the backing protocol, so quotes stay accurate in underlying terms while capital sits in yield tokens.",
  },
  {
    byte: "0x23",
    label: "BYTE 35",
    title: "ChainlinkGuardXD",
    desc: "MEV protection: reverts if the implied swap price deviates beyond a bound from the Chainlink reference, or if a feed is stale. Per-feed staleness bounds.",
  },
  {
    byte: "0x24",
    label: "BYTE 36",
    title: "MakerCapitalGuardXD",
    desc: "Makes quote() a complete fill-oracle: reverts unless an actual withdrawal of the delivery amount would succeed right now — position AND protocol liquidity.",
  },
];

const PROOFS = [
  { chain: "Base", what: "Aave v3 + Chainlink feeds — full ship → quote → swap JIT cycle", state: "live fork" },
  { chain: "Base", what: "Morpho Gauntlet WETH Core + Steakhouse Prime USDC — real ERC-4626 vaults", state: "live fork" },
  { chain: "Base", what: "Euler v2 EVK eWETH-1 — generic 4626 adapter across protocols", state: "live fork" },
  { chain: "Base", what: "Stargate V2 PoolUSDC + Staking — deposited, staked, JIT unstake → redeem", state: "live fork" },
  { chain: "Ethereum", what: "Lido wstETH + Curve stETH/ETH — staking rate 1.24, JIT unwrap + swap", state: "live fork" },
  { chain: "Ethereum", what: "Pendle PT-wstETH (ACTIVE, Dec 2027) — fixed income via AMM swap callback", state: "live fork" },
  { chain: "Arbitrum", what: "Pendle PT-aUSDC (EXPIRED) — 1:1 redemption, zero swap legs", state: "live fork" },
];

/* ---------- page ---------- */

export default function Page() {
  return (
    <>
      <nav className="nav">
        <div className="nav-inner">
          <div className="brand">
            <div className="brand-mark">S</div>
            <div>
              Superposition<span className="brand-dim">-Liquid</span>
            </div>
          </div>
          <div className="nav-links">
            <a href="#profiles">Profiles</a>
            <a href="#how">How it works</a>
            <a href="#opcodes">Opcodes</a>
            <a href="#proofs">Proofs</a>
          </div>
          <a className="gh-badge" href="https://github.com/SolidityDrone/superposition-liquid" target="_blank">
            github ↗
          </a>
        </div>
      </nav>

      {/* ---------- hero ---------- */}
      <header className="hero">
        <TileBackground />
        <div className="hero-scrim" aria-hidden />
        <div className="container hero-inner">
          <div className="eyebrow">BUILT ON 1INCH AQUA · ETHONLINE 2026</div>
          <h1>
            Liquidity that earns <span className="accent">yield</span>,
            <br />
            <span className="dim">backed 100% by</span> real protocols.
          </h1>
          <p className="sub">
            Superposition-Liquid is a custom SwapVM router where makers provide ETH/USDC
            liquidity while their capital sits entirely inside yield protocols — Aave,
            Morpho, Euler, Lido, Pendle, Stargate. Every fill cycles the capital
            atomically. The maker earns swap fees <b>on top of</b> the protocol yield,
            on the same capital.
          </p>
          <div className="cta-row">
            <a className="btn btn-primary" href="https://github.com/SolidityDrone/superposition-liquid" target="_blank">
              View on GitHub
            </a>
            <a className="btn btn-ghost" href="#profiles">
              Five risk profiles ↓
            </a>
          </div>

          <div className="stats">
            {STATS.map((s) => (
              <div className="stat" key={s.label}>
                <div className="num">{s.num}</div>
                <div className="label">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </header>

      {/* ---------- typologies ---------- */}
      <section id="profiles">
        <div className="container">
          <div className="sec-head">
            <div className="kicker">Supported typologies</div>
            <h2>Five risk profiles. One pool surface.</h2>
            <p>
              The adapter layer is the product: any yield protocol plugs in per-maker, and
              the strategy — the AMM program, the hooks, the Aqua position — does not
              change. The maker picks their risk profile by pointing one config at an
              adapter.
            </p>
          </div>
          <div className="typo-grid">
            {TYPOLOGIES.map((t) => (
              <div className="typo-row" key={t.kind}>
                <div className="typo-type">
                  <div className="typo-icon" style={{ background: `${t.color}1a`, color: t.color, border: `1px solid ${t.color}33` }}>
                    <t.Icon size={20} />
                  </div>
                  <div>
                    <div className="name">{t.name}</div>
                    <div className="kind">{t.kind}</div>
                  </div>
                </div>
                <div className="typo-desc">{t.desc}</div>
                <div className="typo-prots">
                  {t.prots.map((pr) => (
                    <span className="prot" key={pr.name}>
                      <pr.Logo size={14} />
                      {pr.name}
                      <span className="state">{pr.state}</span>
                    </span>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ---------- flow ---------- */}
      <section id="how" style={{ borderTop: "1px solid var(--border)" }}>
        <div className="container">
          <div className="sec-head">
            <div className="kicker">How a fill works</div>
            <h2>Capital cycles atomically. Idle balance: always zero.</h2>
            <p>
              The taker sees a plain ETH/USDC pool. Inside the swap transaction, the
              maker's hooks cycle the capital through the yield protocol — the wallet only
              holds tokens for the duration of one transaction.
            </p>
          </div>
          <div className="flow">
            {FLOW.map((f) => (
              <div className="flow-step" key={f.step}>
                <div className="step">{f.step}</div>
                <h3>{f.title}</h3>
                <p>{f.desc}</p>
                <code>{f.code}</code>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ---------- opcodes ---------- */}
      <section id="opcodes" style={{ borderTop: "1px solid var(--border)" }}>
        <div className="container">
          <div className="sec-head">
            <div className="kicker">Custom SwapVM opcodes</div>
            <h2>Three instructions appended to the deployed table.</h2>
            <p>
              The router is a modified SwapVM redeploy (explicitly allowed by 1inch).
              Opcodes are appended at the end of the dispatch table, so every existing
              instruction keeps its index. They run identically in quote() and swap().
            </p>
          </div>
          <div className="op-grid">
            {OPCODES.map((o) => (
              <div className="op" key={o.title}>
                <div className="byte">{o.byte}</div>
                <div className="byte-label">{o.label}</div>
                <h3>{o.title}</h3>
                <p>{o.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ---------- proofs ---------- */}
      <section id="proofs" style={{ borderTop: "1px solid var(--border)" }}>
        <div className="container">
          <div className="sec-head">
            <div className="kicker">Verified on real protocols</div>
            <h2>Seven fork proofs. Zero mocks where it counts.</h2>
            <p>
              Every adapter is proven against the real deployed contracts on a mainnet
              fork: real Aqua registry, real Chainlink feeds, real lending markets. Real
              -vault testing caught bugs no mock could have shown.
            </p>
          </div>
          <div className="proof-list">
            {PROOFS.map((p) => (
              <div className="proof" key={p.chain + p.what}>
                <div className="check">✓</div>
                <div className="chain">{p.chain}</div>
                <div className="what">{p.what}</div>
                <div className="badge">TESTED ON-CHAIN</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ---------- final cta ---------- */}
      <section>
        <div className="container">
          <div className="final-cta">
            <h2>99 tests. 7 fork proofs. 5 risk profiles.</h2>
            <p>
              The full source — router, opcodes, adapters, tests and design decision log —
              is open. Build a maker position that earns protocol yield on 100% of its
              capital.
            </p>
            <div className="cta-row">
              <a className="btn btn-primary" href="https://github.com/SolidityDrone/superposition-liquid" target="_blank">
                GitHub repository
              </a>
              <a className="btn btn-ghost" href="https://app.pendle.finance" target="_blank" style={{ display: "none" }}>
                .
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* ---------- footer ---------- */}
      <footer className="footer">
        <div className="container footer-inner">
          <div>SUPERPOSITION-LIQUID · ETHONLINE 2026</div>
          <div>
            <a href="https://github.com/SolidityDrone/superposition-liquid">SOURCE ↗</a> ·{" "}
            <a href="https://docs.pendle.finance">DOCS ↗</a>
          </div>
        </div>
      </footer>
    </>
  );
}
