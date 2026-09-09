import TileBackground from "@/components/TileBackground";
import FillDiagram from "@/components/FillDiagram";
import {
  AaveLogo, MorphoLogo, EulerLogo, LidoLogo, PendleLogo, StargateLogo, CurveLogo,
  LendingIcon, VaultIcon, StakingIcon, FixedIncomeIcon, BridgeIcon,
} from "@/components/logos";

/* ---------- content ---------- */

const HERO_FACTS = [
  "99 tests, green",
  "7 protocols verified against live contracts",
  "Solidity 0.8.30 · Foundry",
];

const STEPS = [
  {
    no: "01",
    title: "Ship a position. Park the capital.",
    body: (
      <>
        The maker ships an ETH/USDC position on Aqua, like any other liquidity provider.
        The difference is invisible to the taker: the capital doesn't sit in the wallet —
        it lives in a yield protocol. Resolvers and aggregators read it as <b>a normal
        pool with normal balances</b>.
      </>
    ),
    mech: (
      <>
        Aqua <em>ship()</em> → virtual balances in underlying terms · MakerConfig →
        adapter, per maker
      </>
    ),
  },
  {
    no: "02",
    title: "A fill arrives. The capital surfaces.",
    body: (
      <>
        Before the tokens move, a hook pulls the exact delivery amount out of the yield
        position — redeem, unwrap, unstake, depending on the protocol — and puts it in
        the maker's wallet. The default transfer then hands it to the taker.{" "}
        <b>One transaction, fully atomic</b>: the capital is only out of the protocol for
        the duration of the fill.
      </>
    ),
    mech: (
      <>
        <em>preTransferOut</em> hook → adapter.withdrawTo() → default transfer → taker
      </>
    ),
  },
  {
    no: "03",
    title: "The revenue redeploy. Immediately.",
    body: (
      <>
        What the taker paid lands in the maker's wallet and is instantly re-deployed
        into the yield protocol — deposited, wrapped, staked. The wallet never holds an
        idle balance: <b>the position never stops earning</b>, even between fills.
      </>
    ),
    mech: (
      <>
        Aqua <em>push()</em> → <em>postTransferIn</em> hook → adapter.depositFor() →
        staked
      </>
    ),
  },
];

const ENGINE = [
  {
    byte: "0x22",
    name: "Honest rates",
    desc: "Pricing is scaled by the live exchange rate of the backing protocol. The ship-time rate is baked into the strategy, so only yield accrued after shipping moves the price — the fixed yield of a Pendle PT or the staking drift of wstETH shows up in real time.",
  },
  {
    byte: "0x23",
    name: "Manipulation gets rejected",
    desc: "Every fill is checked against Chainlink reference prices before anything moves. A price beyond the maker's tolerance band, or a stale feed, reverts the fill with the exact reason — on-chain, before execution.",
  },
  {
    byte: "0x24",
    name: "No fake depth",
    desc: "quote() simulates the actual withdrawal: if the maker's position — and the protocol's own liquidity — can't cover the delivery, the fill is rejected at quote time. Takers never see a promise the pool can't keep.",
  },
];

const BACKED = [
  {
    name: "Aave v3",
    sub: "AaveV3Adapter",
    icon: <LendingIcon size={19} />,
    color: "#b6509e",
    earns: "Variable supply APY",
    desc: "aWETH and aUSDC across 18 chains, both balance models handled.",
    prots: [
      { name: "Aave", Logo: AaveLogo },
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
  },
  {
    name: "Pendle PT",
    sub: "PendlePTAdapter",
    icon: <FixedIncomeIcon size={19} />,
    color: "#7b61ff",
    earns: "Fixed APY, locked at entry",
    desc: "Expired markets redeem 1:1; active ones appreciate toward par in real time.",
    prots: [{ name: "Pendle", Logo: PendleLogo }],
  },
  {
    name: "Stargate V2",
    sub: "StargateAdapter",
    icon: <BridgeIcon size={19} />,
    color: "#4c6fff",
    earns: "Bridge reward stream",
    desc: "Pool liquidity, staked. Instant unstake → redeem, capped by pool credit.",
    prots: [{ name: "Stargate", Logo: StargateLogo }],
  },
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
          <div className="nav-right">
            <a className="nav-hide" href="#how">How it works</a>
            <a className="nav-hide" href="#engine">The engine</a>
            <a className="nav-hide" href="#backed">Backed by</a>
            <a className="nav-mono" href="https://github.com/SolidityDrone/superposition-liquid" target="_blank">
              github ↗
            </a>
          </div>
        </div>
      </nav>

      {/* ---------- hero ---------- */}
      <header className="hero">
        <TileBackground />
        <div className="hero-scrim" aria-hidden />
        <div className="container hero-inner">
          <span className="hero-tag">BUILT ON 1INCH AQUA — ETHONLINE 2026</span>
          <h1>
            Liquidity that
            <br />
            never sleeps<em>.</em>
          </h1>
          <p className="lede">
            Superposition-Liquid is a custom Aqua router where <b>100% of the maker's
            capital</b> sits in yield protocols — Aave, Morpho, Euler, Lido, Pendle,
            Stargate — and cycles in and out <b>atomically on every fill</b>. To the
            outside world, it reads as a plain ETH/USDC pool.
          </p>
          <div className="cta-row">
            <a className="btn btn-primary" href="#how">How it works ↓</a>
            <a className="btn btn-ghost" href="https://github.com/SolidityDrone/superposition-liquid" target="_blank">
              Source
            </a>
          </div>
          <div className="hero-foot">
            {HERO_FACTS.map((f, i) => (
              <span key={f}>
                {i > 0 && <span className="sep"> · </span>}
                {f}
              </span>
            ))}
          </div>
        </div>
      </header>

      {/* ---------- 01 how a fill works ---------- */}
      <section className="section" id="how">
        <div className="container section-grid">
          <div className="sec-label">
            <span className="num">01</span>
            How a fill works
          </div>
          <div>
            <h2 className="sec-title">Three transactions deep, the capital never stops working.</h2>
            <p className="sec-intro">
              Every fill is one atomic transaction where the maker's capital resurfaces,
              changes hands, and dives back in.
            </p>
            <div className="steps">
              {STEPS.map((s) => (
                <div className="step" key={s.no}>
                  <div className="step-no">{s.no}</div>
                  <div>
                    <h3>{s.title}</h3>
                    <p>{s.body}</p>
                    <div className="mech">{s.mech}</div>
                  </div>
                </div>
              ))}
            </div>
            <div className="diagram-head">
              <div className="diagram-title">One fill, end to end — the Aave maker, on a Base fork</div>
              <div className="diagram-sub">USDC comes in, wETH goes out. The dotted ring is the money path.</div>
            </div>
            <FillDiagram />
          </div>
        </div>
      </section>

      {/* ---------- 02 the engine ---------- */}
      <section className="section" id="engine">
        <div className="container section-grid">
          <div className="sec-label">
            <span className="num">02</span>
            Built into the VM
          </div>
          <div>
            <h2 className="sec-title">The pricing never lies.</h2>
            <p className="sec-intro">
              Three custom instructions appended to the SwapVM dispatch table. They run
              identically in quote and execution — a quote that passes is a fill that
              works.
            </p>
            <div className="engine">
              {ENGINE.map((e) => (
                <div className="engine-row" key={e.byte}>
                  <div className="engine-byte">{e.byte}</div>
                  <div className="engine-name">{e.name}</div>
                  <div className="engine-desc">{e.desc}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ---------- 03 backed by ---------- */}
      <section className="section" id="backed">
        <div className="container section-grid">
          <div className="sec-label">
            <span className="num">03</span>
            Backed by
          </div>
          <div>
            <h2 className="sec-title">Pick a protocol. Pick a risk.</h2>
            <p className="sec-intro">
              The adapter layer is the point: the strategy doesn't change — the maker
              points one config at a protocol and the position earns that protocol's
              yield. Same pool surface, five temperaments.
            </p>
            <div className="backed">
              {BACKED.map((b) => (
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
                  <div className="backed-prots">
                    {b.prots.map((pr) => (
                      <span className="prot" key={pr.name}>
                        <pr.Logo size={15} />
                        {pr.name}
                      </span>
                    ))}
                  </div>
                </div>
              ))}
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

      {/* ---------- final ---------- */}
      <section className="final">
        <div className="container">
          <h2>
            Your liquidity.
            <br />
            <em>Actually working.</em>
          </h2>
          <p>
            The full source — router, opcodes, adapters, tests and the complete design
            decision log — is open.
          </p>
          <div className="cta-row">
            <a className="btn btn-primary" href="https://github.com/SolidityDrone/superposition-liquid" target="_blank">
              Read the source
            </a>
          </div>
        </div>
      </section>

      {/* ---------- footer ---------- */}
      <footer className="footer">
        <div className="container footer-inner">
          <div>SUPERPOSITION-LIQUID — ETHONLINE 2026</div>
          <div>
            <a href="https://github.com/SolidityDrone/superposition-liquid">SOURCE ↗</a>
          </div>
        </div>
      </footer>
    </>
  );
}
