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
      "    function exchangeRate(address underlying)",
      "        external view returns (uint256);",
      "",
      "    // the router executes this pull with its OWN allowance",
      "    function pullPlan(",
      "        address maker, address underlying,",
      "        uint256 amount",
      "    ) external view returns (",
      "        address token, uint256 count, address to",
      "    );",
      "",
      "    function withdraw(",
      "        address maker, address underlying,",
      "        uint256 amount, uint256 yieldAmount,",
      "        address recipient",
      "    ) external;",
      "",
      "    function deposit(",
      "        address maker, address underlying,",
      "        uint256 amount",
      "    ) external;",
      "}",
    ],
  },
  {
    file: "opcodes/MakerCapitalGuardOpcode.sol",
    lang: "solidity",
    lines: [
      "function _makerCapitalGuardXD(",
      "    Context memory ctx, bytes calldata args",
      ") internal view {",
      "    address out = address(bytes20(args.slice(0, 20)));",
      "    address adapter = _makerConfig()",
      "        .sides(ctx.query.maker, out).adapter;",
      "",
      "    if (ctx.swap.amountOut == 0) return;",
      "",
      "    // simulated withdrawal: position AND protocol liquidity",
      "    uint256 available = ILendingAdapter(adapter)",
      "        .maxWithdrawable(ctx.query.maker, out);",
      "    if (available < ctx.swap.amountOut) {",
      "        revert MakerCapitalInsufficient(",
      "            available, ctx.swap.amountOut);",
      "    }",
      "}",
    ],
  },
  {
    file: "adapters/SuperpositionUniAdapter.sol",
    lang: "solidity",
    lines: [
      "function withdraw(",
      "    address maker, address underlying,",
      "    uint256 amountOut, uint256,",
      "    address recipient",
      ") external {",
      "    if (msg.sender != ROUTER) revert NotRouter();",
      "    Side memory s = _side(underlying);",
      "    (uint256 shares, uint256 c0, uint256 c1) = _bucket(s);",
      "    uint256 claim = s.isToken0 ? c0 : c1;",
      "",
      "    // round shares up so the pro-rata payout covers amountOut",
      "    uint256 shareAmount = (amountOut * shares",
      "        + claim - 1) / claim;",
      "",
      "    // the adapter is an ERC-1155 operator: burn the maker's",
      "    // bucket shares and pay the underlying to the recipient",
      "    HOOK.withdraw(",
      "        ISuperpositionHook.WithdrawParams({",
      "            tickLower: s.lower, tickUpper: s.upper,",
      "            owner: maker, shareAmount: shareAmount,",
      "            recipient: recipient",
      "        })",
      "    );",
      "}",
    ],
  },
];

const MAX_LINES = Math.max(...SNIPPETS.map((s) => s.lines.length));

const RULES: Array<{ re: RegExp; cls: string }> = [
  { re: /"[^"]*"/g, cls: "hl-str" },
  { re: /\/\/[^\n]*/g, cls: "hl-cmt" },
  {
    re: /\b(interface|function|external|view|pure|returns|if|else|revert|uint256|uint32|address|memory|calldata|internal|public|import|contract|library|constant|using|for|struct|return|override|virtual|event|emit|indexed|error|modifier)\b/g,
    cls: "hl-kw",
  },
  {
    re: /\b(string|bool|bytes\d*|int\d*|uint\d*|DataTypes|IERC20|SafeERC20|IPool|IAToken|Context|AggregatorV3Interface|ILendingAdapter|ISuperpositionHook|Side|WithdrawParams)\b/g,
    cls: "hl-ty",
  },
  { re: /\b(\d[\d_]*\.?\d*[eE]?\d*|0x[\da-fA-F]+)\b/g, cls: "hl-num" },
];

type Token = { start: number; end: number; cls: string };

/** Tokenize one line; overlapping matches resolve to the first rule (comments,
 *  strings, keywords, types, numbers) and never produce duplicate keys. */
function tokenize(code: string): Token[] {
  const all: Token[] = [];
  for (const { re, cls } of RULES) {
    re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(code)) !== null) {
      all.push({ start: m.index, end: m.index + m[0].length, cls });
      if (m.index === re.lastIndex) re.lastIndex += 1;
    }
  }
  all.sort((a, b) => a.start - b.start || a.end - b.end);

  const out: Token[] = [];
  let last = 0;
  for (const t of all) {
    if (t.start >= last) {
      out.push(t);
      last = t.end;
    }
  }
  return out;
}

function SyntaxLine({ line }: { line: string }) {
  if (!line) return <>&nbsp;</>;
  const tokens = tokenize(line);
  if (tokens.length === 0) return <>{line}</>;

  const parts: React.ReactNode[] = [];
  let pos = 0;
  tokens.forEach((t, i) => {
    if (t.start > pos) parts.push(<span key={`p${i}`}>{line.slice(pos, t.start)}</span>);
    parts.push(
      <span className={t.cls} key={`t${i}`}>
        {line.slice(t.start, t.end)}
      </span>,
    );
    pos = t.end;
  });
  if (pos < line.length) parts.push(<span key="tail">{line.slice(pos)}</span>);
  return <>{parts}</>;
}

export default function CodeSnippet() {
  const [tab, setTab] = useState(0);
  const s = SNIPPETS[tab];
  // every snippet renders the same number of lines, so the block never resizes
  const lines = [...s.lines, ...Array(MAX_LINES - s.lines.length).fill("")];

  return (
    <div className="code-block">
      <div className="code-tabs">
        {SNIPPETS.map((snip, i) => (
          <button
            key={snip.file}
            className={`code-tab${i === tab ? " active" : ""}`}
            onClick={() => setTab(i)}
          >
            {snip.file}
          </button>
        ))}
      </div>
      <div className="code-editor">
        <div className="code-gutter">
          {lines.map((_, i) => (
            <span key={i}>{i + 1}</span>
          ))}
        </div>
        <pre className="code-content">
          <code>
            {lines.map((line, i) => (
              <div key={i} className="code-line">
                <SyntaxLine line={line} />
              </div>
            ))}
          </code>
        </pre>
      </div>
    </div>
  );
}
