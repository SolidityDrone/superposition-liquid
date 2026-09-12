import TileBackground from "@/components/TileBackground";
import FillDiagram from "@/components/FillDiagram";
import CodeSnippet from "@/components/CodeSnippet";
import BackedSection from "@/components/BackedSection";
import UniswapBadge from "@/components/UniswapBadge";

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
        <em>preTransferOut</em> → <em>pullPlan</em> + <em>withdraw</em> → default transfer → taker
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
        Aqua transfer → <em>postTransferIn</em> → <em>deposit</em> → re-staked
      </>
    ),
  },
];

const LAYERS = [
  {
    tag: "curve",
    name: "Your SwapVM strategy",
    body: "Any pricing program — xyk, curved, flat-price, or a custom curve. Superposition never touches it.",
    hi: false,
  },
  {
    tag: "adapters",
    name: "Capital adapters",
    body: "One config entry per token saying where the capital rests between fills — Aave, any ERC-4626 vault, Stargate, Pendle, or a Uniswap v4 hook.",
    hi: false,
  },
  {
    tag: "meta-opcodes",
    name: "Meta-opcodes",
    body: "Extra instructions appended to the program, running alongside the pricing opcode: scale balances by the live yield rate, and reject any fill the maker's real capital can't cover.",
    hi: true,
  },
  {
    tag: "hooks",
    name: "Hook orchestration",
    body: "The router's pre/post-transfer hooks do the work — withdraw from the yield protocol, deliver the fill, re-deposit the proceeds — inside one atomic transaction.",
    hi: false,
  },
];

const HOOK = [
  {
    k: "vault",
    title: "Capital in ERC-4626",
    body: "Between swaps, 100% of the pooled tokens sit in ERC-4626 lending vaults — on Aave through its official waToken wrapper, created permissionlessly via the StataToken factory when one doesn't exist yet.",
  },
  {
    k: "erc-1155",
    title: "Positions as tokens",
    body: "Every tick range is a bucket with its own ERC-1155 id. The maker holds the shares and approves the router as an operator; the router withdraws on the maker's behalf, one bucket per side.",
  },
  {
    k: "one-sided",
    title: "Limit orders for free",
    body: "A range fully below spot needs only token1, fully above only token0 — so a one-sided, out-of-range deposit is a real limit order, and it withdraws one-sided once the price crosses.",
  },
  {
    k: "adapter",
    title: "Same Aqua surface",
    body: "Exposed as an ILendingAdapter: the router JIT-withdraws the backing out of the hook to deliver a fill, then re-deposits the received revenue into the maker's buckets, all in one transaction.",
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
            <a className="nav-hide" href="#backed">Adapters</a>
            <a className="nav-hide" href="#how">How it works</a>
            <a className="nav-hide" href="#hook">Uniswap hook</a>
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
            <span className="hero-tag">META-LAYER FOR 1INCH AQUA — ETHONLINE 2026</span>
            <h1>
              Liquidity that
              <br />
              never sleeps<em>.</em>
            </h1>
            <p className="lede">
              Superposition-Liquid is a <b>meta-layer for 1inch Aqua</b> — <b>capital
              adapters</b> and <b>meta-opcodes</b> that wrap any SwapVM curve. The maker&apos;s
              capital sits in yield protocols (Aave, Morpho, Euler, Pendle, Stargate,
              Uniswap v4) and cycles in and out <b>atomically on every fill</b>; to the outside
              world it reads as a plain ETH/USDC pool.
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

      {/* ---------- layer stack ---------- */}
      <section className="section" id="layers">
        <div className="container">
          <div className="panel">
            <h2 className="sec-title">One strategy. Composable layers around it.</h2>
            <p className="sec-intro">
              Superposition is not a pricing curve — it wraps the one you ship. Each layer below
              is independent, and the pricing math at the bottom is never modified.
            </p>
            <div className="layers-stack">
              {LAYERS.map((l) => (
                <div className={l.hi ? "layer hi" : "layer"} key={l.tag}>
                  <div className="layer-tag">{l.tag}</div>
                  <div className="layer-name">{l.name}</div>
                  <div className="layer-body">{l.body}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ---------- 01 protocols / adapters ---------- */}
      <BackedSection />

      {/* ---------- 02 how a fill works ---------- */}
      <section className="section" id="how">
        <div className="container">
          <div className="panel">
            <h2 className="sec-title">0x02 One transaction, and the capital never stops working.</h2>
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
            <div className="diagram-sub">
              S1–S3 run once, before any fill. Numbers 1–6 are the fill sequence — click one to replay it.
            </div>
          </div>
          <FillDiagram />
        </div>
      </section>

      {/* ---------- 02 uniswap hook ---------- */}
      <section className="section" id="hook">
        <div className="container">
          <div className="panel">
            <UniswapBadge />
            <span className="kicker">SUPERPOSITION · UNISWAP V4</span>
            <h2 className="sec-title">0x03 The Uniswap hook.</h2>
            <p className="sec-intro">
              Superposition also reaches into Uniswap v4. The <b>SuperpositionUniAdapter</b> turns
              a v4 concentrated-liquidity hook into a yield venue the Aqua router can back a
              position with — the same pull / withdraw / deposit surface, a different engine
              underneath.
            </p>
            <div className="hook-grid">
              {HOOK.map((c) => (
                <div className="hook-card" key={c.k}>
                  <div className="hook-k">{c.k}</div>
                  <h3>{c.title}</h3>
                  <p>{c.body}</p>
                </div>
              ))}
            </div>
            <a
              className="hook-doc"
              href="https://github.com/SolidityDrone/superposition-liquid/blob/main/docs/superposition-uni-adapter.md"
              target="_blank"
            >
              Read the Superposition hook deep-dive ↗
            </a>
          </div>
        </div>
      </section>

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
