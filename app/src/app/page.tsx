import TileBackground from "@/components/TileBackground";
import FillDiagram from "@/components/FillDiagram";
import CodeSnippet from "@/components/CodeSnippet";
import BackedSection from "@/components/BackedSection";

/* ---------- content ---------- */

const STEPS = [
  {
    no: "01",
    title: "Ship a position. Park the capital.",
    body: (
      <>
        The maker ships an ETH/USDC position on Aqua, like any other liquidity provider.
        The difference is invisible to the taker: the capital doesn't sit in the wallet —
        it lives in a yield protocol. Routers and aggregators read it as <b>a normal
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

/* ---------- page ---------- */

export default function Page() {
  return (
    <>
      <nav className="nav">
        <div className="nav-inner">
          <div className="brand">
            <img src="/logo.png" alt="Superposition" className="brand-logo" width={44} height={44} />
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
        <div className="container hero-grid">
          <div className="hero-text">
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
          </div>
          <div className="hero-logo">
            <img src="/logo.png" alt="Superposition-Liquid" />
          </div>
        </div>
      </header>

      {/* ---------- 01 how a fill works ---------- */}
      <section className="section" id="how">
        <div className="container">
          <div className="panel">
            <h2 className="sec-title">0x01 Three transactions deep, the capital never stops working.</h2>
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
          </div>
          <CodeSnippet />
        </div>
        <div className="container">
          <div className="panel diagram-head">
            <div className="diagram-title">One fill, end to end — the Aave maker, on a Base fork</div>
            <div className="diagram-sub">USDC comes in, wETH goes out. The dotted ring is the money path.</div>
          </div>
          <FillDiagram />
        </div>
      </section>

      {/* ---------- 02 the engine ---------- */}
      <section className="section" id="engine">
        <div className="container">
          <div className="panel">
            <h2 className="sec-title">0x02 The pricing never lies.</h2>
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
      <BackedSection />

      {/* ---------- final ---------- */}
      <section className="final">
        <div className="container">
          <div className="panel">
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
