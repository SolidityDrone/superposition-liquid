/**
 * Superposition-Liquid — off-chain resolver / discovery demo.
 *
 * Proves the core claim: "the outside world sees a plain ETH/USDC pool".
 * No special access, no indexer from 1inch (they only index the official
 * router): anyone can reconstruct every fillable position from public state.
 *
 *   1. Discovery   — Aqua `Shipped` events filtered by app = our router;
 *                    the event carries abi.encode(Order) so the full order
 *                    (program bytecode included) is recoverable on-chain.
 *   2. Position    — MakerConfig (adapter + underlyings + flags), adapter
 *                    exchange rates, Aqua virtual balances (aToken counts)
 *                    priced to effective underlying, simulated withdrawable.
 *   3. Fill oracle — router.quote() for sample sizes in both directions;
 *                    a passing quote means fillable NOW, a failing one
 *                    returns the exact on-chain revert reason.
 *
 * Usage:
 *   RPC_URL=http://localhost:8545 npm run demo
 *   # defaults: Base mainnet RPC + Base addresses (docs/ADDRESSES.md)
 *   # FROM_BLOCK=0 AQUA=0x.. ROUTER=0x.. to override discovery scope
 */

import { createPublicClient, http, type Address, type PublicClient } from "viem";
import { discover, fmt, quoteFill, resolvePosition, type Position } from "./discovery.js";

const RPC_URL = process.env.RPC_URL ?? "https://mainnet.base.org";
const FROM_BLOCK = BigInt(process.env.FROM_BLOCK ?? "0");

// Base mainnet defaults (verified on-chain, docs/ADDRESSES.md + script/BaseChain.s.sol)
const AQUA: Address = (process.env.AQUA ?? "0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a") as Address;
const ROUTER: Address = (process.env.ROUTER ?? "0x111111338c5091E8440b67B168bAe16a668AC0De") as Address;

const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
const cyan = (s: string) => `\x1b[36m${s}\x1b[0m`;
const green = (s: string) => `\x1b[32m${s}\x1b[0m`;
const red = (s: string) => `\x1b[31m${s}\x1b[0m`;
const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;

const client: PublicClient = createPublicClient({ transport: http(RPC_URL) });

async function main() {
  const chainId = await client.getChainId();
  const block = await client.getBlockNumber();
  console.log(bold("\nSuperposition-Liquid resolver"));
  console.log(dim(`rpc ${RPC_URL} · chain ${chainId} · block ${block}\n`));

  // --- 1. discovery ----------------------------------------------------------
  const strategies = await discover(client, AQUA, ROUTER, FROM_BLOCK);
  if (strategies.length === 0) {
    console.log(
      dim(`no strategies shipped to ${ROUTER} in blocks ${FROM_BLOCK}–${block}.`),
      dim("\nRun the fork demo first: `forge script script/Demo.s.sol` against the fork,\nthen point RPC_URL at the forked anvil."),
    );
    return;
  }
  console.log(cyan(`▶ discovery: ${strategies.length} strategy(ies) shipped to the router\n`));

  // --- 2. position state ------------------------------------------------------
  const positions: Position[] = [];
  // the pair comes from env (defaults = Base WETH/USDC): the Shipped event
  // carries the order but not the token list — production resolvers parse the
  // shipped program's yield-opcode args (same pattern as aqua-api).
  const UNDERLYING_IN = (process.env.UNDERLYING_IN ?? "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913") as Address;
  const UNDERLYING_OUT = (process.env.UNDERLYING_OUT ?? "0x4200000000000000000000000000000000000006") as Address;
  for (const s of strategies) {
    const pos = await resolvePosition(client, s, AQUA, ROUTER, UNDERLYING_IN, UNDERLYING_OUT);
    positions.push(pos);
    const tIn = pos.tokens[pos.makerConfig.underlyingIn];
    const tOut = pos.tokens[pos.makerConfig.underlyingOut];
    console.log(bold(`strategy ${s.strategyHash.slice(0, 10)}…`), dim(`maker ${s.maker}`));
    console.log(
      `  sides          ${tIn ? pos.adapterNames[pos.makerConfig.sideIn.adapter] : "(unregistered)"}`
      + ` / ${tOut ? pos.adapterNames[pos.makerConfig.sideOut.adapter] : "(unregistered)"}`,
    );
    for (const t of [tIn, tOut].filter(Boolean)) {
      const rate = fmt(t.exchangeRate, 18);
      console.log(
        `  ${t.symbol.padEnd(6)} virtual ${fmt(t.virtualRaw, t.decimals).padStart(14)} ${dim(`yield tokens`)}`
        + ` → effective ${green(fmt(t.effective, t.decimals))} ${dim(`× rate ${Number(rate).toExponential(4)}`)}`
        + ` · sim-withdrawable ${fmt(t.maxWithdrawable, t.decimals)}`,
      );
    }
    console.log();
  }

  // --- 3. fill oracle ---------------------------------------------------------
  console.log(cyan("▶ fill oracle — router.quote() (AMM + yield rate + guard + capital check)\n"));
  for (const pos of positions) {
    const tIn = pos.tokens[pos.makerConfig.underlyingIn];
    const tOut = pos.tokens[pos.makerConfig.underlyingOut];
    const legs = [
      { from: tIn, to: tOut, amount: 10n ** BigInt(tIn.decimals) * 1000n },  // 1,000 tokenIn
      { from: tOut, to: tIn, amount: 10n ** BigInt(tOut.decimals) / 2n },    // 0.5 tokenOut
    ];
    for (const leg of legs) {
      const label = `1,000 ${leg.from.symbol} → ${leg.to.symbol}`
        .replace("1,000", leg.amount === 10n ** BigInt(leg.from.decimals) / 2n ? "0.5" : "1,000");
      const q = await quoteFill(client, pos, leg.from.address, leg.to.address, leg.amount);
      if (q.ok) {
        const px = Number(fmt(q.amountOut, leg.to.decimals)) / Number(fmt(leg.amount, leg.from.decimals));
        console.log(
          `  ${label.padEnd(22)} ${green("FILLABLE")} → ${fmt(q.amountOut, leg.to.decimals)} ${leg.to.symbol}`
          + dim(`  (fill price ${px.toPrecision(4)} ${leg.to.symbol}/${leg.from.symbol})`),
        );
      } else {
        console.log(`  ${label.padEnd(22)} ${red("REVERTED")} — ${red(q.reason)}`);
      }
    }
  }

  console.log(dim("\nDone. A passing quote = the position is fillable atomically right now."));
}

main().catch((err) => {
  console.error(red(`resolver failed: ${String(err)}`));
  process.exit(1);
});
