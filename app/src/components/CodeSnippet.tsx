"use client";

import { useState } from "react";

type Snippet = {
  file: string;
  lang: string;
  lines: string[];
};

const SNIPPETS: Snippet[] = [
  {
    file: "interfaces/ILendingAdapter.sol",
    lang: "solidity",
    lines: [
      "interface ILendingAdapter {",
      "    function name() external view",
      "        returns (string memory);",
      "",
      "    function withdrawTo(",
      "        address maker,",
      "        address underlying,",
      "        uint256 amount,",
      "        address recipient",
      "    ) external;",
      "",
      "    function depositFor(",
      "        address maker,",
      "        address underlying,",
      "        uint256 amount",
      "    ) external;",
      "}",
    ],
  },
  {
    file: "opcodes/ChainlinkGuardOpcode.sol",
    lang: "solidity",
    lines: [
      "function _chainlinkGuardXD(",
      "    Context memory ctx, bytes calldata args",
      ") internal view {",
      "    // reference: Chainlink tokenOut per tokenIn",
      "    uint256 ref = uint256(answerIn) * 1e18",
      "        / uint256(answerOut);",
      "",
      "    // implied: from the swap registers",
      "    uint256 implied = ctx.swap.amountOut * 1e18",
      "        / ctx.swap.amountIn;",
      "",
      "    uint256 dev = implied > ref",
      "        ? implied - ref : ref - implied;",
      "    if (dev * 10_000 > ref * maxBps)",
      "        revert PriceDeviationExceeded();",
      "}",
    ],
  },
  {
    file: "adapters/AaveV3Adapter.sol",
    lang: "solidity",
    lines: [
      "function exchangeRate(address underlying)",
      "    public view returns (uint256)",
      "{",
      "    var reserve = AAVE_POOL",
      "        .getReserveData(underlying);",
      "    uint256 scaled = IAToken(reserve.aToken)",
      "        .scaledTotalSupply();",
      "    uint256 displayed = IERC20(reserve.aToken)",
      "        .totalSupply();",
      "",
      "    // underlying backing per displayed unit",
      "    return scaled",
      "        * uint256(reserve.liquidityIndex)",
      "        * WAD / (displayed * RAY);",
      "}",
    ],
  },
];

function SyntaxLine({ line, lang }: { line: string; lang: string }) {
  if (!line) return <>&nbsp;</>;

  // basic solidity syntax highlighting
  const highlight = (s: string) => {
    const parts: React.ReactNode[] = [];
    // keywords
    const kw = /\b(interface|function|external|view|pure|returns|if|else|revert|uint256|uint32|address|memory|calldata|internal|public|import|contract|library|constant|using|for|struct|return|override|virtual|event|emit|indexed|error|modifier)\b/g;
    // types
    const ty = /\b(string|bool|bytes\d*|int\d*|uint\d*|DataTypes|IERC20|SafeERC20|IPool|IAToken|Context|AggregatorV3Interface)\b/g;
    // strings
    const str = /"[^"]*"/g;
    // comments
    const cmt = /(\/\/.*$)/gm;
    // numbers
    const num = /\b(\d[\d_]*\.?\d*[eE]?\d*|\b0x[\da-fA-F]+)\b/g;

    let result = s;
    // mask out matches to avoid double-highlighting
    const tokens: Array<{ start: number; end: number; el: React.ReactNode }> = [];

    const collect = (regex: RegExp, cls: string) => {
      let m;
      while ((m = regex.exec(result)) !== null) {
        tokens.push({ start: m.index, end: m.index + m[0].length, el: <span className={cls}>{m[0]}</span> });
      }
    };

    collect(str, "hl-str");
    collect(cmt, "hl-cmt");
    collect(kw, "hl-kw");
    collect(ty, "hl-ty");
    collect(num, "hl-num");

    if (tokens.length === 0) return <>{s}</>;

    tokens.sort((a, b) => a.start - b.start);
    const out: React.ReactNode[] = [];
    let pos = 0;
    for (const t of tokens) {
      if (t.start > pos) out.push(<span key={pos}>{result.slice(pos, t.start)}</span>);
      out.push(<span key={`t${t.start}`}>{t.el}</span>);
      pos = t.end;
    }
    if (pos < result.length) out.push(<span key={pos}>{result.slice(pos)}</span>);
    return <>{out}</>;
  };

  return <>{highlight(line)}</>;
}

export default function CodeSnippet() {
  const [tab, setTab] = useState(0);
  const s = SNIPPETS[tab];

  return (
    <div className="code-block">
      <div className="code-tabs">
        {SNIPPETS.map((snip, i) => (
          <button
            key={i}
            className={`code-tab${i === tab ? " active" : ""}`}
            onClick={() => setTab(i)}
          >
            {snip.file}
          </button>
        ))}
      </div>
      <div className="code-editor">
        <div className="code-gutter">
          {s.lines.map((_, i) => (
            <span key={i}>{i + 1}</span>
          ))}
        </div>
        <pre className="code-content">
          <code>
            {s.lines.map((line, i) => (
              <div key={i} className="code-line">
                <SyntaxLine line={line} lang={s.lang} />
              </div>
            ))}
          </code>
        </pre>
      </div>
    </div>
  );
}
