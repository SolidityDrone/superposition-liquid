"use client";

import { useMemo, useState } from "react";
import { useAccount, usePublicClient, useReadContracts, useWriteContract } from "wagmi";
import { formatUnits, parseUnits, maxUint256, type Address } from "viem";

import TileBackground from "@/components/TileBackground";
import { TokenIcon, ProtocolIcon, TokenLabel, InfoIcon } from "@/components/icons";
import { Dropdown } from "@/components/Dropdown";
import { OneinchMono, Uniswap } from "react-web3-icons/dex";
import { STACK, TOKENS, ADAPTERS, SEPOLIA_CHAIN_ID, AQUA, EXAMPLE_POOL_ID, explorerAddress, explorerTx, type TokenDef } from "@/lib/sepolia";
import { erc20Abi, makerConfigAbi, aavePoolAbi, aaveAdapterAbi, aaveDataProviderAbi, erc4626Abi, superpositionAdapterAbi, superpositionHookAbi, v4StateViewAbi, aquaAbi, orderBuilderAbi, hookLpHelperAbi, erc1155Abi } from "@/lib/abis";

const ZERO = "0x0000000000000000000000000000000000000000" as Address;
const MAX = 2n ** 256n - 1n;
const pick = (arr: unknown, i: number): unknown => (arr as { result?: unknown }[] | undefined)?.[i]?.result;
function field<T = unknown>(v: unknown, i: number, name: string): T | undefined {
  if (v === undefined || v === null) return undefined;
  if (Array.isArray(v)) return v[i] as T;
  const o = v as Record<string, unknown>;
  return (name in o ? o[name] : undefined) as T | undefined;
}
function fmt(v: bigint | undefined, decimals: number, digits = 4) {
  if (v === undefined) return "—";
  const n = Number(formatUnits(v, decimals));
  if (n === 0) return "0";
  if (n < 0.0001) return "<0.0001";
  return n.toLocaleString(undefined, { maximumFractionDigits: digits });
}
/// Compact integer formatter (K/M/B/T) for raw values like v4 liquidity `L`.
function compact(v: bigint | number | undefined) {
  if (v === undefined) return "—";
  const n = typeof v === "bigint" ? Number(v) : v;
  if (n === 0) return "0";
  return new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 2 }).format(n);
}
const usd = (v?: bigint) => (v === undefined ? "—" : `$${Number(formatUnits(v, 8)).toLocaleString(undefined, { maximumFractionDigits: 2 })}`);
const pct = (ray?: bigint) => (ray === undefined ? "—" : `${(Number(ray) / 1e27 * 100).toFixed(2)}%`);

export default function ConsolePage() {
  const { address, isConnected, chainId } = useAccount();
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();
  const [busy, setBusy] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [tab, setTab] = useState<"1inch" | "uni">("1inch");
  const [info, setInfo] = useState<string | null>(null);
  const [shipOpen, setShipOpen] = useState(false);
  const [shipIn, setShipIn] = useState<Address>(TOKENS[0].address);
  const [shipOut, setShipOut] = useState<Address>(TOKENS[1].address);
  const [shipInAmt, setShipInAmt] = useState("100");
  const [shipOutAmt, setShipOutAmt] = useState("100");
  const [shipFee, setShipFee] = useState("3000000");
  const [depProto, setDepProto] = useState("aave");
  const [depToken, setDepToken] = useState<Address>((TOKENS.find((t) => t.symbol === "LINK") ?? TOKENS[0]).address);
  const [depAmt, setDepAmt] = useState("100");
  const [lp0, setLp0] = useState("100");
  const [lp1, setLp1] = useState("100");
  const [rangeId, setRangeId] = useState("strategy");
  const initSides = () =>
    Object.fromEntries(TOKENS.filter((t) => t.aaveListed).map((t) => [t.address, { adapterId: "erc4626-aave", auto: true, sel: false }]));
  const initBorrows = () =>
    Object.fromEntries(TOKENS.filter((t) => t.aaveListed).map((t) => [t.address, { on: false, collateral: TOKENS[0].address, maxDebt: "", sel: false }]));
  const [sideCfg, setSideCfg] = useState<Record<string, { adapterId: string; auto: boolean; sel: boolean }>>(initSides);
  const [borrowCfg, setBorrowCfg] = useState<Record<string, { on: boolean; collateral: Address; maxDebt: string; sel: boolean }>>(initBorrows);
  const [vaultToken, setVaultToken] = useState<Address>(TOKENS[0].address);
  const [vaultAmt, setVaultAmt] = useState("100");

  const onWrongChain = isConnected && chainId !== SEPOLIA_CHAIN_ID;
  const me = address;
  const active = !!me && !onWrongChain;
  const aaveTokens = useMemo(() => TOKENS.filter((t) => t.aaveListed), []);

  const account = useReadContracts({
    contracts: me ? [{ address: STACK.aavePool, abi: aavePoolAbi, functionName: "getUserAccountData", args: [me] }] : [],
    query: { enabled: active },
  });

  const markets = useReadContracts({
    contracts: active
      ? aaveTokens.flatMap((t) => [
          { address: STACK.aaveDataProvider, abi: aaveDataProviderAbi, functionName: "getReserveCaps", args: [t.address] },
          { address: STACK.aaveDataProvider, abi: aaveDataProviderAbi, functionName: "getReserveConfigurationData", args: [t.address] },
          { address: STACK.aaveDataProvider, abi: aaveDataProviderAbi, functionName: "getATokenTotalSupply", args: [t.address] },
          { address: STACK.aaveDataProvider, abi: aaveDataProviderAbi, functionName: "getReserveData", args: [t.address] },
          { address: t.address, abi: erc20Abi, functionName: "balanceOf", args: [me] },
          { address: (t.aToken ?? ZERO) as Address, abi: erc20Abi, functionName: "balanceOf", args: [me] },
          { address: STACK.aaveAdapter, abi: aaveAdapterAbi, functionName: "maxWithdrawable", args: [me, t.address] },
        ])
      : [],
    query: { enabled: active },
  });

  const hook = useReadContracts({
    contracts: active
      ? [
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "currentBalance" },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "totalClaim" },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "sharesOf", args: [me, 1, 101] },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "sharesOf", args: [me, -101, -1] },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "totalSharesOf", args: [1, 101] },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "totalSharesOf", args: [-101, -1] },
          { address: STACK.superpositionUniAdapter, abi: superpositionAdapterAbi, functionName: "maxWithdrawable", args: [me, TOKENS[0].address] },
          { address: STACK.superpositionUniAdapter, abi: superpositionAdapterAbi, functionName: "maxWithdrawable", args: [me, TOKENS[1].address] },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "virtualBalance" },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "initialized" },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "getBuckets" },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "vault0" },
          { address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "vault1" },
        ]
      : [],
    query: { enabled: active },
  });

  const poolInfo = useReadContracts({
    contracts: active
      ? [
          { address: STACK.v4StateView, abi: v4StateViewAbi, functionName: "getSlot0", args: [EXAMPLE_POOL_ID] },
          { address: STACK.v4StateView, abi: v4StateViewAbi, functionName: "getLiquidity", args: [EXAMPLE_POOL_ID] },
        ]
      : [],
    query: { enabled: active },
  });

  const vaults = useReadContracts({
    contracts: active
      ? [STACK.vaultUSDC, STACK.vaultUSDT].flatMap((v) => [
          { address: v, abi: erc4626Abi, functionName: "totalAssets" },
          { address: v, abi: erc4626Abi, functionName: "totalSupply" },
          { address: v, abi: erc4626Abi, functionName: "balanceOf", args: [me] },
        ])
      : [],
    query: { enabled: active },
  });

  const config = useReadContracts({
    contracts: active
      ? aaveTokens.flatMap((t) => [
          { address: STACK.makerConfig, abi: makerConfigAbi, functionName: "sides", args: [me, t.address] },
          { address: STACK.makerConfig, abi: makerConfigAbi, functionName: "borrowConfigOf", args: [me, t.address] },
        ])
      : [],
    query: { enabled: active },
  });

  const approvals = useReadContracts({
    contracts: active
      ? aaveTokens.flatMap((t) => [
          { address: t.address, abi: erc20Abi, functionName: "allowance", args: [me, STACK.router] },
          { address: t.address, abi: erc20Abi, functionName: "allowance", args: [me, AQUA] },
          { address: (t.aToken ?? ZERO) as Address, abi: erc20Abi, functionName: "allowance", args: [me, STACK.router] },
        ])
      : [],
    query: { enabled: active },
  });

  function refetchAll() {
    account.refetch(); markets.refetch(); hook.refetch(); poolInfo.refetch(); vaults.refetch(); config.refetch();
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function errMsg(e: any) {
    return e?.shortMessage ?? e?.details ?? (e as Error)?.message?.split("\n")[0] ?? "error";
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  async function send(cfg: any) {
    const hash = await writeContractAsync(cfg);
    window.open(explorerTx(hash), "_blank", "noopener,noreferrer");
    // Never let a receipt-wait hiccup hide a tx that actually went through.
    try {
      if (publicClient) await publicClient.waitForTransactionReceipt({ hash, timeout: 90_000 });
    } catch {
      /* tx may still be pending; refetch below */
    }
    refetchAll();
    return hash;
  }
  async function run(label: string, fn: () => Promise<void>) {
    setBusy(label);
    try {
      await fn();
      setStatus(`${label} ✓`);
    } catch (e) {
      setStatus(`${label} — ${errMsg(e)}`);
    } finally {
      refetchAll();
      setBusy(null);
      window.setTimeout(() => setStatus(null), 6000);
    }
  }

  // --- actions -------------------------------------------------------------
  async function stakeAave(t: TokenDef, amount: string) {
    await run(`stake ${amount} ${t.symbol}`, async () => {
      const amt = parseUnits(amount, t.decimals);
      if (t.erc4626Vault) {
        await send({ address: t.address, abi: erc20Abi, functionName: "approve", args: [t.erc4626Vault, amt] });
        await send({ address: t.erc4626Vault, abi: erc4626Abi, functionName: "deposit", args: [amt, me as Address] });
      } else {
        await send({ address: t.address, abi: erc20Abi, functionName: "approve", args: [STACK.aavePool, amt] });
        await send({ address: STACK.aavePool, abi: aavePoolAbi, functionName: "supply", args: [t.address, amt, me as Address, 0] });
      }
    });
  }
  async function unstakeAave(t: TokenDef, amount: string) {
    await run(`unstake ${amount} ${t.symbol}`, async () => {
      const amt = parseUnits(amount, t.decimals);
      if (t.erc4626Vault) {
        await send({ address: t.erc4626Vault, abi: erc4626Abi, functionName: "withdraw", args: [amt, me as Address, me as Address] });
      } else {
        await send({ address: STACK.aavePool, abi: aavePoolAbi, functionName: "withdraw", args: [t.address, amt, me as Address] });
      }
    });
  }
  /// Direct Aave supply → the maker receives aTokens (the yield-bearing token).
  async function depositAToken(t: TokenDef, amount: string) {
    await run(`deposit ${amount} ${t.symbol} → aToken`, async () => {
      const amt = parseUnits(amount, t.decimals);
      await send({ address: t.address, abi: erc20Abi, functionName: "approve", args: [STACK.aavePool, amt] });
      await send({ address: STACK.aavePool, abi: aavePoolAbi, functionName: "supply", args: [t.address, amt, me as Address, 0] });
    });
  }
  async function withdrawAToken(t: TokenDef, amount: string) {
    await run(`withdraw ${amount} ${t.symbol} aToken`, async () => {
      await send({ address: STACK.aavePool, abi: aavePoolAbi, functionName: "withdraw", args: [t.address, parseUnits(amount, t.decimals), me as Address] });
    });
  }
  /// One run: approvals + setSides + setBorrowConfigs for every token.
  async function setAllConfig() {
    if (aaveTokens.length === 0) return;
    await run("set all config", async () => {
      if (!publicClient || !me) return;
      const sides: { underlying: Address; adapter: Address; kind: number; autoManaged: boolean }[] = [];
      for (const t of aaveTokens) {
        const c = sideCfg[t.address];
        const adapter = ADAPTERS.find((a) => a.id === c.adapterId);
        if (!adapter?.address) throw new Error(`${adapter?.label ?? c.adapterId} not available on Sepolia`);
        const need: [Address, Address][] = [
          [t.address, STACK.router],
          [t.address, AQUA],
          ...(t.aToken ? ([[t.aToken, STACK.router]] as [Address, Address][]) : []),
        ];
        for (const [tok, spender] of need) {
          const allow = (await publicClient.readContract({ address: tok, abi: erc20Abi, functionName: "allowance", args: [me, spender] })) as bigint;
          if (allow < maxUint256) await send({ address: tok, abi: erc20Abi, functionName: "approve", args: [spender, maxUint256] });
        }
        sides.push({ underlying: t.address, adapter: adapter.address, kind: adapter.kind, autoManaged: c.auto });
      }
      await send({ address: STACK.makerConfig, abi: makerConfigAbi, functionName: "setSides", args: [sides] });
      const configs = aaveTokens.map((t) => {
        const c = borrowCfg[t.address];
        return { enabled: c.on, collateral: c.collateral, maxDebt: c.maxDebt && Number(c.maxDebt) > 0 ? parseUnits(c.maxDebt, t.decimals) : 0n };
      });
      await send({ address: STACK.makerConfig, abi: makerConfigAbi, functionName: "setBorrowConfigs", args: [aaveTokens.map((t) => t.address), configs] });
    });
  }
  /// Build the SwapVM order on-chain (OrderBuilder) and ship it on Aqua.
  async function shipStrategy() {
    const ti = TOKENS.find((t) => t.address === shipIn)!;
    const to = TOKENS.find((t) => t.address === shipOut)!;
    if (!publicClient || !me) return;
    await run(`ship ${ti.symbol}/${to.symbol}`, async () => {
      const rate = 10n ** 18n; // Sepolia capital is idle (no yield) → rate 1e18
      const order = (await publicClient.readContract({
        address: STACK.orderBuilder,
        abi: orderBuilderAbi,
        functionName: "build",
        args: [me, STACK.router, ti.address, to.address, to.address, Number(shipFee), rate, rate],
      })) as `0x${string}`;
      await send({
        address: AQUA,
        abi: aquaAbi,
        functionName: "ship",
        args: [STACK.router, order, [ti.address, to.address], [parseUnits(shipInAmt, ti.decimals), parseUnits(shipOutAmt, to.decimals)]],
      });
      setShipOpen(false);
    });
  }
  /// One tx: provide both stables in the selected range via the HookLpHelper (atomic).
  async function hookDepositBoth() {
    const t0 = TOKENS[0];
    const t1 = TOKENS[1];
    const range = RANGE_PRESETS.find((r) => r.id === rangeId) ?? RANGE_PRESETS[0];
    const a0 = parseUnits(lp0 || "0", t0.decimals);
    const a1 = parseUnits(lp1 || "0", t1.decimals);
    await run(`add LP ${lp0}/${lp1} · ${range.label} · 1 tx`, async () => {
      if (!publicClient || !me) return;
      const [b0, b1] = await Promise.all([
        publicClient.readContract({ address: t0.address, abi: erc20Abi, functionName: "balanceOf", args: [me] }),
        publicClient.readContract({ address: t1.address, abi: erc20Abi, functionName: "balanceOf", args: [me] }),
      ]);
      if ((b0 as bigint) < a0) throw new Error(`insufficient ${t0.symbol} (wallet ${fmt(b0 as bigint, t0.decimals)})`);
      if ((b1 as bigint) < a1) throw new Error(`insufficient ${t1.symbol} (wallet ${fmt(b1 as bigint, t1.decimals)})`);
      for (const [t, amt] of [[t0, a0], [t1, a1]] as const) {
        const allow = (await publicClient.readContract({ address: t.address, abi: erc20Abi, functionName: "allowance", args: [me, STACK.hookLpHelper] })) as bigint;
        if (allow < amt) await send({ address: t.address, abi: erc20Abi, functionName: "approve", args: [STACK.hookLpHelper, maxUint256] });
      }
      await send({ address: STACK.hookLpHelper, abi: hookLpHelperAbi, functionName: "provide", args: [me, t0.address, t1.address, a0, a1, range.usdc[0], range.usdc[1], range.usdt[0], range.usdt[1]] });
    });
  }
  /// One tx: withdraw from both buckets of the selected range. Empty/0 = all.
  async function hookWithdrawAmount() {
    const range = RANGE_PRESETS.find((r) => r.id === rangeId) ?? RANGE_PRESETS[0];
    await run(`withdraw LP ${lp0 || "all"}/${lp1 || "all"} · ${range.label} · 1 tx`, async () => {
      if (!publicClient || !me) return;
      const a0 = parseUnits(lp0 && Number(lp0) > 0 ? lp0 : "0", 6);
      const a1 = parseUnits(lp1 && Number(lp1) > 0 ? lp1 : "0", 6);
      const minB = (a: bigint, b: bigint) => (a < b ? a : b);
      const sharesOfRange = (lower: number, upper: number) =>
        publicClient.readContract({ address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "sharesOf", args: [me, lower, upper] }) as Promise<bigint>;
      const s0all = await sharesOfRange(range.usdc[0], range.usdc[1]);
      const s1all = await sharesOfRange(range.usdt[0], range.usdt[1]);
      const s0 = a0 === 0n ? s0all : minB(a0, s0all);
      const s1 = a1 === 0n ? s1all : minB(a1, s1all);
      if (s0 === 0n && s1 === 0n) throw new Error("nothing to withdraw in this range");
      const shareToken = (await publicClient.readContract({ address: STACK.superpositionHook, abi: superpositionHookAbi, functionName: "shareToken" })) as Address;
      const approved = (await publicClient.readContract({ address: shareToken, abi: erc1155Abi, functionName: "isApprovedForAll", args: [me, STACK.hookLpHelper] })) as boolean;
      if (!approved) await send({ address: shareToken, abi: erc1155Abi, functionName: "setApprovalForAll", args: [STACK.hookLpHelper, true] });
      await send({ address: STACK.hookLpHelper, abi: hookLpHelperAbi, functionName: "redeem", args: [me, range.usdc[0], range.usdc[1], s0, range.usdt[0], range.usdt[1], s1] });
    });
  }

  // --- derived -------------------------------------------------------------
  const accColl = field<bigint>(pick(account.data, 0), 0, "totalCollateralBase");
  const accDebt = field<bigint>(pick(account.data, 0), 1, "totalDebtBase");
  const accBorrow = field<bigint>(pick(account.data, 0), 2, "availableBorrowsBase");
  const accHf = field<bigint>(pick(account.data, 0), 5, "healthFactor");

  const rows = aaveTokens.map((t, i) => {
    const b = i * 7;
    const caps = pick(markets.data, b);
    const cfg = pick(markets.data, b + 1);
    const aSupply = pick(markets.data, b + 2) as bigint | undefined;
    const rd = pick(markets.data, b + 3);
    const wallet = pick(markets.data, b + 4) as bigint | undefined;
    const aBal = pick(markets.data, b + 5) as bigint | undefined;
    const maxW = pick(markets.data, b + 6) as bigint | undefined;
    const supplyCap = field<bigint>(caps, 1, "supplyCap");
    const supplyCapRaw = supplyCap !== undefined ? supplyCap * 10n ** BigInt(t.decimals) : undefined;
    const headroom = supplyCapRaw !== undefined && aSupply !== undefined ? (supplyCapRaw > aSupply ? supplyCapRaw - aSupply : 0n) : undefined;
    const ltv = Number(field<bigint>(cfg, 1, "ltv") ?? 0n) || undefined;
    const rate = field<bigint>(rd, 3, "liquidityRate");
    return { t, supplyCapRaw, aSupply, headroom, ltv, rate, wallet, aBal, maxW };
  });

  const claim = pick(hook.data, 1);
  const myS0 = pick(hook.data, 2) as bigint | undefined;
  const myS1 = pick(hook.data, 3) as bigint | undefined;
  const totS0 = pick(hook.data, 4) as bigint | undefined;
  const totS1 = pick(hook.data, 5) as bigint | undefined;
  const hMax0 = pick(hook.data, 6) as bigint | undefined;
  const hMax1 = pick(hook.data, 7) as bigint | undefined;
  const poolClaim0 = field<bigint>(claim, 0, "0");
  const poolClaim1 = field<bigint>(claim, 1, "1");
  const myClaim0 = totS0 && totS0 > 0n && poolClaim0 !== undefined ? ((myS0 ?? 0n) * poolClaim0) / totS0 : 0n;
  const myClaim1 = totS1 && totS1 > 0n && poolClaim1 !== undefined ? ((myS1 ?? 0n) * poolClaim1) / totS1 : 0n;
  const yield0 = myClaim0 > (myS0 ?? 0n) ? myClaim0 - (myS0 ?? 0n) : 0n;
  const yield1 = myClaim1 > (myS1 ?? 0n) ? myClaim1 - (myS1 ?? 0n) : 0n;
  const yieldTotal = yield0 + yield1;
  const principal = (myS0 ?? 0n) + (myS1 ?? 0n);

  const idle = pick(hook.data, 0);
  const idle0 = field<bigint>(idle, 0, "amount0");
  const idle1 = field<bigint>(idle, 1, "amount1");
  const virt = pick(hook.data, 8);
  const virt0 = field<bigint>(virt, 0, "amount0");
  const virt1 = field<bigint>(virt, 1, "amount1");
  const initialized = pick(hook.data, 9) as boolean | undefined;
  const buckets = pick(hook.data, 10) as unknown[] | undefined;
  const slot0 = pick(poolInfo.data, 0);
  const sqrtP = field<bigint>(slot0, 0, "sqrtPriceX96");
  const tick = field<number | bigint>(slot0, 1, "tick");
  const jitLiq = pick(poolInfo.data, 1) as bigint | undefined;
  const price = sqrtP !== undefined ? (Number(sqrtP) / 2 ** 96) ** 2 : undefined;
  const bLiq = (i: number) => field<bigint>(buckets?.[i], 2, "liquidity");
  const hv0 = pick(hook.data, 11) as Address | undefined;
  const hv1 = pick(hook.data, 12) as Address | undefined;

  const vRow = (i: number, t: TokenDef) => ({
    t,
    assets: pick(vaults.data, i * 3) as bigint | undefined,
    supply: pick(vaults.data, i * 3 + 1) as bigint | undefined,
    mine: pick(vaults.data, i * 3 + 2) as bigint | undefined,
  });
  const v0 = vRow(0, TOKENS[0]);
  const v1 = vRow(1, TOKENS[1]);
  const vaultRow = [v0, v1].find((v) => v.t.address === vaultToken) ?? v0;
  const vaultTok = vaultRow.t;
  const vaultWallet = rows.find((r) => r.t.address === vaultToken)?.wallet;
  const vaultMineAssets =
    vaultRow.mine !== undefined && vaultRow.supply && vaultRow.supply > 0n && vaultRow.assets !== undefined
      ? (vaultRow.mine * vaultRow.assets) / vaultRow.supply
      : 0n;

  const readSide = (i: number) => {
    const raw = pick(config.data, i * 2) as Record<string, unknown> | undefined;
    if (!raw) return undefined;
    return { adapter: (raw.adapter ?? (raw as unknown as unknown[])[1]) as Address | undefined, kind: Number(raw.kind ?? 0), autoManaged: Boolean(raw.autoManaged) };
  };
  const readBorrow = (i: number) => {
    const raw = pick(config.data, i * 2 + 1) as Record<string, unknown> | undefined;
    if (!raw) return undefined;
    return { enabled: Boolean(raw.enabled ?? (raw as unknown as unknown[])[0]), collateral: (raw.collateral ?? (raw as unknown as unknown[])[1]) as Address | undefined, maxDebt: (raw.maxDebt ?? (raw as unknown as unknown[])[2]) as bigint | undefined };
  };
  /// token -> router, token -> aqua, aToken -> router all at MAX.
  const isApproved = (i: number) => {
    const b = i * 3;
    return (pick(approvals.data, b) as bigint | undefined) === maxUint256
      && (pick(approvals.data, b + 1) as bigint | undefined) === maxUint256
      && (pick(approvals.data, b + 2) as bigint | undefined) === maxUint256;
  };

  const depTok = TOKENS.find((t) => t.address === depToken) ?? TOKENS[0];
  const depRow = rows.find((r) => r.t.address === depToken);
  /// Sensible default for the borrow maxDebt field (per asset category).
  const suggestedMaxDebt = (t: TokenDef) => (t.category === "stable" ? "1000" : t.category === "btc" ? "0.1" : "1");
  const depBal = depRow?.aBal;
  const depWallet = depRow?.wallet;
  const maxOf = (v: bigint | undefined, d: number) => (v !== undefined && v > 0n ? formatUnits(v, d) : "0");

  const infoDot = (k: string) => (
    <button className={`info-dot ${info === k ? "active" : ""}`} onClick={() => setInfo((v) => (v === k ? null : k))} aria-label={`info-${k}`}>
      <InfoIcon size={13} />
    </button>
  );

  return (
    <div style={{ position: "relative", minHeight: "100vh" }}>
      <div style={{ position: "fixed", inset: 0, zIndex: 0 }}>
        <TileBackground />
      </div>
      <div style={{ position: "fixed", inset: 0, zIndex: 0, background: "linear-gradient(180deg, rgba(4,7,12,.28) 0%, rgba(4,7,12,.6) 55%, rgba(4,7,12,.82) 100%)" }} />

      <main className="container console" style={{ padding: "104px 20px 80px", maxWidth: 1360 }}>
        <header className="console-head">
          <div>
            <a href="/" className="console-kicker">SuperPosition Liquid</a>
            <div className="console-title-row">
              <h1 className="console-title">Maker console</h1>
              <div className="tabs" role="tablist" aria-label="Protocol">
                <button className={`tab-logo oneinch ${tab === "1inch" ? "active" : ""}`} onClick={() => setTab("1inch")} title="1inch Aqua — maker sides, Aave, vaults, borrow" aria-pressed={tab === "1inch"}>
                  <OneinchMono size={26} style={{ color: "#0b0b0b" }} />
                </button>
                <button className={`tab-logo uni ${tab === "uni" ? "active" : ""}`} onClick={() => setTab("uni")} title="Uniswap v4 — Superposition hook pool" aria-pressed={tab === "uni"}>
                  <Uniswap size={28} />
                </button>
              </div>
            </div>
            <p className="console-sub">
              Ethereum Sepolia · <a href={explorerAddress(STACK.router)} target="_blank" rel="noreferrer" style={{ color: "var(--accent)" }}>{STACK.router.slice(0, 10)}…</a>
              {" · "}
              <span className={`pill ${isConnected && !onWrongChain ? "on" : "off"}`}>{isConnected ? (onWrongChain ? "wrong chain" : "Sepolia") : "disconnected"}</span>
            </p>
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            {(busy || status) && <span className="pill off">{busy ? `${busy}…` : status}</span>}
          </div>
        </header>

        {tab === "1inch" && (
          <>
        {/* --- deposit --- */}
        <div className="dash">
          <div className="pnl">
            <div className="pnl-head"><div className="pnl-title">Deposit · yield tokens</div>{infoDot("deposit")}</div>
            <div className="tabs" style={{ marginBottom: 10 }}>
              {DEPOSIT_PROTOCOLS.map((p) => (
                <button
                  key={p.id}
                  className={`tab-logo sm ${depProto === p.id ? "active" : ""}`}
                  disabled={p.status !== "active"}
                  onClick={() => setDepProto(p.id)}
                  title={p.status === "active" ? p.label : `${p.label} — not in testnet`}
                  aria-pressed={depProto === p.id}
                >
                  <ProtocolIcon id={p.id} size={20} />
                </button>
              ))}
            </div>
            <Dropdown value={depToken} onChange={(v) => setDepToken(v as Address)} width={170}
              options={aaveTokens.map((t) => {
                const r = rows.find((x) => x.t.address === t.address);
                return { value: t.address, label: t.symbol, icon: <TokenIcon symbol={t.symbol} />, note: r?.headroom === 0n ? "at cap" : "ok" };
              })} />
            <div className="act-bar">
              <div className="amt">
                <input value={depAmt} onChange={(e) => setDepAmt(e.target.value)} placeholder="0.0" inputMode="decimal" />
                <button className="amt-max" onClick={() => setDepAmt(maxOf(depWallet, depTok.decimals))}>MAX</button>
              </div>
              <span className="pair-hint">
                wallet <b>{fmt(depWallet, depTok.decimals)}</b> · aToken <button className="linkbtn" onClick={() => setDepAmt(maxOf(depBal, depTok.decimals))}>{fmt(depBal, depTok.decimals)}</button>
              </span>
              <div className="act-btns">
                <button className="btn-sm primary" disabled={!active || busy !== null || depProto !== "aave"} onClick={() => depositAToken(depTok, depAmt)}>Deposit</button>
                <button className="btn-sm" disabled={!active || busy !== null || depProto !== "aave"} onClick={() => withdrawAToken(depTok, depAmt)}>Withdraw</button>
              </div>
            </div>
            <div className="pnl-note" style={{ marginTop: 8 }}>Depositing to Aave mints <b>aTokens</b> to your wallet. Sepolia stables are at cap (deposit reverts); WETH/WBTC/LINK/AAVE/EURS are uncapped.</div>
          </div>
        </div>

        {/* --- positions + markets --- */}
        <div className="dash dash-2">
          <div className="pnl">
            <div className="pnl-head"><div className="pnl-title">Aave v3 · aToken (direct route)</div>{infoDot("aave")}</div>
            <div className="grid-scroll">
              <table className="dtable">
                <thead><tr>{["Asset", "Wallet", "aToken", "Max withdraw"].map((h) => <th key={h}>{h}</th>)}</tr></thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.t.symbol}>
                      <td><TokenLabel symbol={r.t.symbol} /></td>
                      <td className="num">{fmt(r.wallet, r.t.decimals)}</td>
                      <td className="num">{fmt(r.aBal, r.t.decimals)}</td>
                      <td className="num">{fmt(r.maxW, r.t.decimals)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="pnl">
            <div className="pnl-head"><div className="pnl-title">Aave markets · capacity</div>{infoDot("markets")}</div>
            <div className="grid-scroll">
              <table className="dtable">
                <thead><tr>{["Asset", "APY", "LTV", "Cap", "Supply"].map((h) => <th key={h}>{h}</th>)}</tr></thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.t.symbol}>
                      <td><TokenLabel symbol={r.t.symbol} /></td>
                      <td className="num">{pct(r.rate)}</td>
                      <td className="num">{r.ltv !== undefined ? `${(r.ltv / 100).toFixed(1)}%` : "—"}</td>
                      <td className="num">{fmt(r.supplyCapRaw, r.t.decimals, 0)}</td>
                      <td className="num">{fmt(r.aSupply, r.t.decimals, 0)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {/* --- vaults --- */}
        <div className="dash">
          <div className="pnl">
            <div className="pnl-head"><div className="pnl-title">ERC-4626 vaults · Aave-backed</div>{infoDot("vaults")}</div>
            <Dropdown value={vaultToken} onChange={(v) => setVaultToken(v as Address)} width={170}
              options={[v0, v1].map((v) => ({ value: v.t.address, label: v.t.symbol, icon: <TokenIcon symbol={v.t.symbol} /> }))} />
            <div className="act-bar">
              <div className="amt">
                <input value={vaultAmt} onChange={(e) => setVaultAmt(e.target.value)} placeholder="0.0" inputMode="decimal" />
                <button className="amt-max" onClick={() => setVaultAmt(maxOf(vaultWallet, vaultTok.decimals))}>MAX</button>
              </div>
              <span className="pair-hint">
                wallet <b>{fmt(vaultWallet, vaultTok.decimals)}</b> · vault <button className="linkbtn" onClick={() => setVaultAmt(maxOf(vaultMineAssets, vaultTok.decimals))}>{fmt(vaultMineAssets, vaultTok.decimals)}</button>
              </span>
              <div className="act-btns">
                <button className="btn-sm primary" disabled={!active || busy !== null} onClick={() => stakeAave(vaultTok, vaultAmt)}>Stake</button>
                <button className="btn-sm" disabled={!active || busy !== null} onClick={() => unstakeAave(vaultTok, vaultAmt)}>Unstake</button>
              </div>
            </div>
            <div className="grid-scroll">
              <table className="dtable">
                <thead><tr>{["Vault", "Assets", "Supply", "Your shares", "Rate"].map((h) => <th key={h}>{h}</th>)}</tr></thead>
                <tbody>
                  {[v0, v1].map((v) => (
                    <tr key={v.t.symbol}>
                      <td><TokenLabel symbol={v.t.symbol} /></td>
                      <td className="num">{fmt(v.assets, v.t.decimals)}</td>
                      <td className="num">{fmt(v.supply, v.t.decimals)}</td>
                      <td className="num">{fmt(v.mine, v.t.decimals)}</td>
                      <td className="num">{v.assets !== undefined && v.supply ? (Number(formatUnits(v.assets, v.t.decimals)) / Number(formatUnits(v.supply, v.t.decimals))).toFixed(4) : "1.0000"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {/* --- configure (sides + borrow in one table) --- */}
        <div className="dash">
          <div className="pnl">
            <div className="pnl-head">
              <div className="pnl-title">Token configuration · sides &amp; borrow</div>
              <div className="pnl-head-right">
                <button className="btn-sm primary" disabled={!active || busy !== null} onClick={() => setShipOpen(true)}>Ship strategy</button>
                {infoDot("sides")}
              </div>
            </div>
            <div className="acct-strip">
              <span>Collateral <b>{usd(accColl)}</b></span>
              <span>Debt <b>{usd(accDebt)}</b></span>
              <span>Borrow power <b>{usd(accBorrow)}</b></span>
              <span>Health <b>{accHf ? (accHf >= MAX / 2n ? "∞" : (Number(accHf) / 1e18).toFixed(2)) : "—"}</b></span>
            </div>
            <p className="pnl-note" style={{ marginTop: 0, marginBottom: 8 }}>
              Per token: pick the <b>adapter</b> (where the capital sits), tick <b>Auto</b>, and optionally enable <b>Borrow</b> with collateral + max debt. <b>Set all</b> applies every row (approvals done automatically).
            </p>
            <div className="grid-scroll">
              <table className="dtable">
                <thead><tr>
                  <th>Token</th>
                  <th>Adapter</th>
                  <th title="Auto-managed: the router deposits on receive and withdraws on send, atomically per fill">Auto</th>
                  <th title="Borrow mode: source this token by borrowing against the collateral">Borrow</th>
                  <th>Collateral</th>
                  <th>Max debt</th>
                  <th>Current</th>
                  <th>Approvals</th>
                </tr></thead>
                <tbody>
                  {aaveTokens.map((t, i) => (
                    <TokenRow
                      key={t.symbol}
                      token={t}
                      tokens={aaveTokens}
                      side={readSide(i)}
                      borrow={readBorrow(i)}
                      sideForm={sideCfg[t.address]}
                      borrowForm={borrowCfg[t.address]}
                      approved={isApproved(i)}
                      disabled={!active}
                      onSide={(p) => setSideCfg((s) => ({ ...s, [t.address]: { ...s[t.address], ...p } }))}
                      onBorrow={(p) => setBorrowCfg((s) => { const next = { ...s[t.address], ...p }; if (p.on === true && !next.maxDebt) next.maxDebt = suggestedMaxDebt(t); return { ...s, [t.address]: next }; })}
                    />
                  ))}
                </tbody>
              </table>
            </div>
            <div className="act-bar">
              <span className="pair-hint">applies <b>all</b> tokens · approvals + sides + borrow in one run</span>
              <div className="act-btns">
                <button className="btn-sm primary" disabled={!active || busy !== null} onClick={setAllConfig}>Set all</button>
              </div>
            </div>
          </div>
        </div>
          </>
        )}

        {tab === "uni" && (
        <div className="dash">
          <div className="pnl">
            <div className="pnl-head"><div className="pnl-title rose">Uni V4 Hook — Example Pool</div>{infoDot("hook")}</div>
            <div className="pool-pair">
              <span className="pair"><TokenLabel symbol="USDC" size={18} /> / <TokenLabel symbol="USDT" size={18} /></span>
              <span className="pill on">fee 0.01%</span>
              <span className="pill on">tick spacing 1</span>
              <span className={`pill ${initialized === true ? "on" : initialized === false ? "off" : ""}`}>{initialized === undefined ? "…" : initialized ? "initialized" : "not initialized"}</span>
              <span className="pill on">concentrated liquidity · JIT</span>
            </div>

            <div className="kpis">
              <div className="kpi"><div className="k">Idle · in vaults</div><div className="v">{fmt(idle0, 6)}</div><div className="sub">USDC · {fmt(idle1, 6)} USDT</div></div>
              <div className="kpi"><div className="k">Pool claim</div><div className="v">{fmt(poolClaim0, 6)}</div><div className="sub">USDC · {fmt(poolClaim1, 6)} USDT</div></div>
              <div className="kpi"><div className="k">JIT liquidity</div><div className="v">{compact(jitLiq)}</div><div className="sub">materialized on swap</div></div>
              <div className="kpi"><div className="k">Price</div><div className="v">{price !== undefined ? price.toFixed(4) : "—"}</div><div className="sub">tick {tick !== undefined ? String(tick) : "—"}</div></div>
              <div className="kpi"><div className="k">Your LP</div><div className="v">{fmt(hMax0, 6)}</div><div className="sub">USDC · {fmt(hMax1, 6)} USDT</div></div>
              <div className="kpi"><div className="k">Est. yield</div><div className="v" style={{ color: yieldTotal > 0n ? "#6be3b0" : undefined }}>+{fmt(yieldTotal, 6)}</div><div className="sub">{principal > 0n ? `${(Number(yieldTotal) / Number(principal) * 100).toFixed(4)}%` : "—"} · claim − shares</div></div>
            </div>

            <div className="act-bar">
              <div className="amt">
                <TokenIcon symbol="USDC" size={15} />
                <input value={lp0} onChange={(e) => setLp0(e.target.value)} placeholder="0.0" inputMode="decimal" />
                <button className="amt-max" onClick={() => setLp0(maxOf(rows.find((r) => r.t.symbol === "USDC")?.wallet, 6))}>MAX</button>
              </div>
              <div className="amt">
                <TokenIcon symbol="USDT" size={15} />
                <input value={lp1} onChange={(e) => setLp1(e.target.value)} placeholder="0.0" inputMode="decimal" />
                <button className="amt-max" onClick={() => setLp1(maxOf(rows.find((r) => r.t.symbol === "USDT")?.wallet, 6))}>MAX</button>
              </div>
              <div className="act-btns">
                <button className="btn-sm primary" disabled={!active || busy !== null} onClick={hookDepositBoth}>Add LP</button>
                <button className="btn-sm" disabled={!active || busy !== null} onClick={hookWithdrawAmount}>Withdraw</button>
              </div>
            </div>
            <div className="presets" style={{ marginTop: 2 }}>
              <span className="presets-lbl">Range</span>
              {RANGE_PRESETS.map((r) => (
                <button key={r.id} className={`chip-preset ${rangeId === r.id ? "active" : ""}`} onClick={() => setRangeId(r.id)}>
                  {r.label}{r.managed ? " · auto" : ""}
                </button>
              ))}
            </div>
            <p className="hint">yours <b style={{ color: "var(--text-mid)" }}>{fmt(hMax0, 6)}</b> / <b style={{ color: "var(--text-mid)" }}>{fmt(hMax1, 6)}</b> · one-sided buckets (USDC above spot, USDT below) · empty = all</p>

            <div className="grid-scroll">
              <table className="dtable">
                <thead><tr>{["Bucket", "Liquidity (L)", "Total shares", "Pool claim", "Your shares", "Your claim", "Yield", "Max w/d"].map((h) => <th key={h}>{h}</th>)}</tr></thead>
                <tbody>
                  <tr>
                    <td><TokenLabel symbol="USDC" /></td>
                    <td className="num" title={`L = ${bLiq(0)?.toString() ?? "—"}`}>{compact(bLiq(0))}</td>
                    <td className="num">{fmt(totS0, 6)}</td>
                    <td className="num">{fmt(poolClaim0, 6)}</td>
                    <td className="num">{fmt(myS0, 6)}</td>
                    <td className="num">{fmt(myClaim0, 6)}</td>
                    <td className="num" style={{ color: yield0 > 0n ? "#6be3b0" : undefined }}>+{fmt(yield0, 6)}</td>
                    <td className="num">{fmt(hMax0, 6)}</td>
                  </tr>
                  <tr>
                    <td><TokenLabel symbol="USDT" /></td>
                    <td className="num" title={`L = ${bLiq(1)?.toString() ?? "—"}`}>{compact(bLiq(1))}</td>
                    <td className="num">{fmt(totS1, 6)}</td>
                    <td className="num">{fmt(poolClaim1, 6)}</td>
                    <td className="num">{fmt(myS1, 6)}</td>
                    <td className="num">{fmt(myClaim1, 6)}</td>
                    <td className="num" style={{ color: yield1 > 0n ? "#6be3b0" : undefined }}>+{fmt(yield1, 6)}</td>
                    <td className="num">{fmt(hMax1, 6)}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div className="pool-meta">
              <span>Hook <a href={explorerAddress(STACK.superpositionHook)} target="_blank" rel="noreferrer">{STACK.superpositionHook.slice(0, 10)}…</a></span>
              <span>PoolManager <a href={explorerAddress(STACK.v4PoolManager)} target="_blank" rel="noreferrer">{STACK.v4PoolManager.slice(0, 10)}…</a></span>
              <span>PoolId <b>{EXAMPLE_POOL_ID.slice(0, 12)}…</b></span>
              <span>sqrtPriceX96 <b>{sqrtP !== undefined ? `${sqrtP.toString().slice(0, 10)}…` : "—"}</b></span>
              <span>Virtual <b>{virt0 !== undefined ? `${fmt(virt0, 6)} / ${fmt(virt1, 6)}` : "—"}</b></span>
              <span>Vault USDC {hv0 ? <a href={explorerAddress(hv0)} target="_blank" rel="noreferrer">{hv0.slice(0, 8)}…</a> : "—"} <ProtocolIcon id="erc4626-aave" size={11} /></span>
              <span>Vault USDT {hv1 ? <a href={explorerAddress(hv1)} target="_blank" rel="noreferrer">{hv1.slice(0, 8)}…</a> : "—"} <ProtocolIcon id="erc4626-aave" size={11} /></span>
            </div>
          </div>
        </div>
        )}

        {info && (
          <div className="modal-backdrop" onClick={() => setInfo(null)}>
            <div className="modal" onClick={(e) => e.stopPropagation()}>
              <div className="modal-head">
                <div className="modal-title"><span>{INFO[info].title}</span></div>
                <button className="modal-close" onClick={() => setInfo(null)} aria-label="close">✕</button>
              </div>
              <div className="infobody" style={{ color: "var(--text-mid)", fontSize: 14, lineHeight: 1.65 }}>{INFO[info].body}</div>
            </div>
          </div>
        )}

        {shipOpen && (
          <div className="modal-backdrop" onClick={() => setShipOpen(false)}>
            <div className="modal" onClick={(e) => e.stopPropagation()}>
              <div className="modal-head">
                <div className="modal-title"><span>Ship strategy</span></div>
                <button className="modal-close" onClick={() => setShipOpen(false)} aria-label="close">✕</button>
              </div>
              <div className="infobody" style={{ color: "var(--text-mid)", fontSize: 13.5, lineHeight: 1.6 }}>
                <p>Ship a maker order on <b>Aqua</b>. Program template: <b>yield-adjusted rate → fee → xyc swap → capital guard</b>. Pair and amounts are yours; approvals come from <b>Token configuration</b>.</p>
              </div>
              <div className="ship-form">
                <div className="ship-row">
                  <span className="ship-lbl">Token in</span>
                  <Dropdown value={shipIn} onChange={(v) => setShipIn(v as Address)} width={150}
                    options={aaveTokens.map((t) => ({ value: t.address, label: t.symbol, icon: <TokenIcon symbol={t.symbol} /> }))} />
                  <input className="inp" style={{ width: 110 }} value={shipInAmt} onChange={(e) => setShipInAmt(e.target.value)} />
                </div>
                <div className="ship-row">
                  <span className="ship-lbl">Token out</span>
                  <Dropdown value={shipOut} onChange={(v) => setShipOut(v as Address)} width={150}
                    options={aaveTokens.map((t) => ({ value: t.address, label: t.symbol, icon: <TokenIcon symbol={t.symbol} /> }))} />
                  <input className="inp" style={{ width: 110 }} value={shipOutAmt} onChange={(e) => setShipOutAmt(e.target.value)} />
                </div>
                <div className="ship-row">
                  <span className="ship-lbl">Fee (1e9)</span>
                  <input className="inp" style={{ width: 120 }} value={shipFee} onChange={(e) => setShipFee(e.target.value)} />
                  <span className="ship-lbl">{(Number(shipFee) / 1e7).toFixed(2)}%</span>
                </div>
                <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 8 }}>
                  <button className="btn-sm" onClick={() => setShipOpen(false)}>Cancel</button>
                  <button className="btn-sm primary" disabled={!active || busy !== null} onClick={shipStrategy}>Ship on Aqua</button>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

function TokenRow({ token, tokens, side, borrow, sideForm, borrowForm, approved, disabled, onSide, onBorrow }: {
  token: TokenDef;
  tokens: TokenDef[];
  side?: { adapter?: Address; kind: number; autoManaged: boolean };
  borrow?: { enabled: boolean; collateral?: Address; maxDebt?: bigint };
  sideForm: { adapterId: string; auto: boolean; sel: boolean };
  borrowForm: { on: boolean; collateral: Address; maxDebt: string; sel: boolean };
  approved: boolean;
  disabled: boolean;
  onSide: (patch: Partial<{ adapterId: string; auto: boolean; sel: boolean }>) => void;
  onBorrow: (patch: Partial<{ on: boolean; collateral: Address; maxDebt: string; sel: boolean }>) => void;
}) {
  const known = side?.adapter ? ADAPTERS.find((a) => a.address && a.address.toLowerCase() === side.adapter!.toLowerCase()) : undefined;
  const collSym = tokens.find((c) => c.address.toLowerCase() === borrowForm.collateral?.toLowerCase())?.symbol ?? "USDC";
  const suggested = token.category === "stable" ? "1000" : token.category === "btc" ? "0.1" : "1";
  return (
    <tr>
      <td><TokenLabel symbol={token.symbol} /></td>
      <td>
        <Dropdown
          value={sideForm.adapterId}
          onChange={(v) => onSide({ adapterId: v })}
          disabled={disabled}
          width={176}
          options={ADAPTERS.map((a) => ({
            value: a.id,
            label: a.label,
            icon: <ProtocolIcon id={a.id} />,
            disabled: !(a.status === "active" && (!a.tokens || a.tokens.includes(token.symbol))),
            note: a.status === "active" ? undefined : "not in testnet",
          }))}
        />
      </td>
      <td><input type="checkbox" checked={sideForm.auto} onChange={(e) => onSide({ auto: e.target.checked })} title="Auto-managed: router deposits on receive and withdraws on send" /></td>
      <td><input type="checkbox" checked={borrowForm.on} onChange={(e) => onBorrow({ on: e.target.checked })} title="Enable borrow mode for this token" /></td>
      <td>
        <Dropdown
          value={borrowForm.collateral}
          onChange={(v) => onBorrow({ collateral: v as Address })}
          disabled={disabled || !borrowForm.on}
          width={140}
          options={tokens.map((c) => ({ value: c.address, label: c.symbol, icon: <TokenIcon symbol={c.symbol} /> }))}
        />
      </td>
      <td><input className="inp" style={{ width: 90 }} placeholder={`0 – ${suggested}`} value={borrowForm.maxDebt} onChange={(e) => onBorrow({ maxDebt: e.target.value })} disabled={!borrowForm.on} title={`Sensible cap for ${token.symbol}: up to ${suggested}`} /></td>
      <td style={{ fontSize: 11 }}>
        {side?.adapter && side.adapter !== ZERO ? (
          <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            {known && <ProtocolIcon id={known.id} />}
            <a href={explorerAddress(side.adapter)} target="_blank" rel="noreferrer" style={{ color: "var(--accent)" }}>
              {known?.short ?? known?.label ?? `${side.adapter.slice(0, 6)}…`}
            </a>
            <span className={`pill ${side.autoManaged ? "on" : "off"}`}>{side.autoManaged ? "auto" : "manual"}</span>
            {borrow?.enabled && <span className="pill on">borrow {collSym}</span>}
          </span>
        ) : (
          <span style={{ color: "var(--text-dim)" }}>{borrow?.enabled ? `borrow ${collSym}` : "not set"}</span>
        )}
      </td>
      <td>{approved ? <span className="pill on">approved</span> : <span className="pill off">needs approve</span>}</td>
    </tr>
  );
}

const RANGE_PRESETS = [
  { id: "strategy", label: "Strategy (1,101)", usdc: [1, 101] as [number, number], usdt: [-101, -1] as [number, number], managed: true },
  { id: "tight", label: "Tight ±0.1%", usdc: [1, 10] as [number, number], usdt: [-10, -1] as [number, number], managed: false },
  { id: "wide", label: "Wide ±10%", usdc: [1, 1001] as [number, number], usdt: [-1001, -1] as [number, number], managed: false },
  { id: "full", label: "Full range", usdc: [1, 887272] as [number, number], usdt: [-887272, -1] as [number, number], managed: false },
];

const DEPOSIT_PROTOCOLS = [
  { id: "aave", label: "Aave v3", status: "active" as const },
  { id: "morpho", label: "Morpho", status: "scarcity" as const },
  { id: "euler", label: "Euler v2", status: "scarcity" as const },
  { id: "yearn", label: "Yearn v3", status: "scarcity" as const },
  { id: "spark", label: "Spark", status: "scarcity" as const },
];

const INFO: Record<string, { title: string; body: React.ReactNode }> = {
  deposit: {
    title: "Deposit · yield tokens",
    body: (
      <>
        <p>Deposit an underlying into a lending protocol and receive its <b>yield-bearing token</b>.</p>
        <ul>
          <li><b>Aave v3</b> (active): <code>supply()</code> mints <b>aTokens</b> (aUSDC, aWETH, …) to your wallet; <code>withdraw()</code> burns them back to the underlying.</li>
          <li>Morpho, Euler v2, Yearn v3, Spark are shown greyed: <b>not on this testnet</b>.</li>
        </ul>
        <p>On Sepolia the stables are at their supply cap, so depositing USDC/USDT/DAI reverts; the uncapped reserves (WETH, WBTC, LINK, AAVE, EURS) deposit fine.</p>
      </>
    ),
  },
  aave: {
    title: "Aave v3 · aToken (direct route)",
    body: (
      <>
        <p>Capital supplied <b>directly to Aave v3</b>; the maker holds <b>aTokens</b> (interest-bearing, tracking the underlying 1:1).</p>
        <ul>
          <li>On every fill the router pulls the needed aTokens from the maker and <code>withdraw</code>s them from the pool, atomically.</li>
          <li>This is also the collateral used by <b>Borrow mode</b>.</li>
          <li>On Sepolia the stable reserves are <b>at their supply cap</b>, so new supply reverts (<code>SUPPLY_CAP_EXCEEDED</code>) — use the ERC-4626 vaults instead.</li>
        </ul>
      </>
    ),
  },
  markets: {
    title: "Aave markets · capacity",
    body: (
      <>
        <p>Live Aave v3 Sepolia reserve data (ProtocolDataProvider):</p>
        <ul>
          <li><b>APY</b> — reserve supply rate (annualised).</li>
          <li><b>LTV</b> — max borrow against this collateral.</li>
          <li><b>Cap</b> — supply cap; <b>Supply</b> — current aToken supply.</li>
        </ul>
        <p>When <code>Supply = Cap</code> the headroom is 0 and the next <code>supply()</code> reverts — that is why every Sepolia stable shows the same capped picture.</p>
      </>
    ),
  },
  vaults: {
    title: "ERC-4626 vaults · Aave-backed",
    body: (
      <>
        <p>Thin <b>ERC-4626</b> wrappers that supply their asset to Aave and hold the aTokens, so shares track the position and yield accrues via <code>totalAssets()</code>.</p>
        <ul>
          <li>They back the <b>Uniswap v4 hook</b> (its two currencies) and are a selectable maker adapter route via <code>ERC4626Adapter</code>.</li>
          <li>If Aave&apos;s supply is capped the deposit falls back to <b>idle</b> (assets stay in the vault) instead of reverting.</li>
          <li>On mainnet Aave isn&apos;t capped, so the same route earns the Aave APY.</li>
        </ul>
      </>
    ),
  },
  sides: {
    title: "Token configuration",
    body: (
      <>
        <p>Per token, pick the <b>adapter</b> that holds that token&apos;s capital — a single registry entry the router resolves at fill time.</p>
        <p><b>The dropdowns pick the adapter per token, they do not define a pair.</b> To actually offer a market (e.g. USDC/USDT) use <b>Ship strategy</b>: it builds the SwapVM order and ships it on Aqua.</p>
        <ul>
          <li><b>ERC4626Adapter · Aave v3</b> — our Aave-backed vault (USDC/USDT on Sepolia).</li>
          <li><b>SuperpositionUniAdapter</b> — the v4 hook buckets (USDC/USDT on Sepolia).</li>
          <li>Morpho, Euler v2, Yearn v3, Stargate, Pendle are greyed: <b>not on this testnet</b>.</li>
        </ul>
        <p>Configuring a token also grants the router + Aqua the approvals and the aToken pull allowance.</p>
      </>
    ),
  },
  borrow: {
    title: "Borrow mode",
    body: (
      <>
        <p>A side can be <b>sourced by borrowing</b> instead of held inventory, against yield-bearing collateral.</p>
        <ul>
          <li><code>BorrowConfig &#123; enabled, collateral, maxDebt &#125;</code> per token.</li>
          <li><b>withdraw</b>: uses the maker&apos;s position first, then borrows the shortfall up to capacity.</li>
          <li><b>deposit</b>: repay the debt first, then supply the rest — the matching in-fill closes the position.</li>
          <li><code>maxWithdrawable = min(availableBorrows, collateral x LTV, maxDebt)</code> — the capital guard uses it.</li>
        </ul>
        <p><b>Soft isolation</b>: we only offer what the configured collateral and the <code>maxDebt</code> capacitor back. Aave debt is account-level, so hard isolation needs a dedicated strategy account or isolation mode. Morpho Blue (per-market, naturally isolated) is the next venue.</p>
      </>
    ),
  },
  hook: {
    title: "Uni V4 Hook — Example Pool",
    body: (
      <>
        <p>A Uniswap v4 <b>concentrated-liquidity hook</b> where 100% of pooled capital sits in ERC-4626 vaults between swaps.</p>
        <ul>
          <li><b>Fully JIT</b>: v4 liquidity is 0 between swaps. <code>beforeSwap</code> redeems the vaults and materializes every bucket as real v4 liquidity; <code>afterSwap</code> removes the ranges, attributes PnL + fees, and re-deposits everything.</li>
          <li>Two <b>one-sided buckets</b>: USDC above spot <code>(1, 101)</code>, USDT below spot <code>(-101, -1)</code> — genuine limit orders.</li>
          <li>Ownership is <b>ERC-1155 bucket shares</b>; the adapter routes deposits/withdrawals and the router pulls them JIT.</li>
          <li>Each currency's capital sits in an <b>ERC-4626 vault</b> (<code>vault0</code>/<code>vault1</code>). On Sepolia both are our Aave-backed vaults — see the two vault addresses in the strip above; yield accrues to the vault shares.</li>
          <li>This pool is <b>USDC/USDT</b>, fee <code>0.01%</code>, tick spacing <code>1</code>.</li>
        </ul>
      </>
    ),
  },
};
