"use client";

import { useState } from "react";
import { useAppKit } from "@reown/appkit/react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { parseUnits } from "viem";
import { usePathname } from "next/navigation";
import Brand from "@/components/Brand";
import { SEPOLIA_CHAIN_ID, STACK, TOKENS, explorerTx } from "@/lib/sepolia";
import { faucetAbi } from "@/lib/abis";
import { projectId } from "@/lib/wagmi";

const APP_KIT_READY = !!projectId;

export default function Navbar() {
  const pathname = usePathname();
  const onConsole = pathname?.startsWith("/app");

  return (
    <nav className="nav">
      <div className="nav-inner">
        <a className="brand" href="/">
          <Brand />
        </a>
        <div className="nav-right">
          <a className="nav-hide" href="/">Home</a>
          <a className="nav-mono" href="/app" style={onConsole ? { color: "var(--accent)", borderColor: "var(--accent-glow)" } : undefined}>
            console
          </a>
          {APP_KIT_READY ? (
            <WalletControls />
          ) : (
            <span className="nav-wallet" style={{ opacity: 0.55 }} title="Set NEXT_PUBLIC_PROJECT_ID to enable wallet connect">
              wallet off
            </span>
          )}
        </div>
      </div>
    </nav>
  );
}

function WalletControls() {
  const { open } = useAppKit();
  const { address, isConnected, chainId } = useAccount();
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();
  const [minting, setMinting] = useState(false);

  const wrong = isConnected && chainId !== SEPOLIA_CHAIN_ID;
  const canMint = isConnected && !wrong;

  async function mintAll() {
    if (!address) return;
    setMinting(true);
    try {
      // Base Sepolia: the Aave faucet has no `isMintable`; mint each faucet token directly
      // (it enforces a per-recipient timelock, so a token may revert if you minted recently).
      for (const t of TOKENS.filter((t) => t.faucet)) {
        const hash = await writeContractAsync({
          address: STACK.aaveFaucet,
          abi: faucetAbi,
          functionName: "mint",
          args: [t.address, address, parseUnits("1000", t.decimals)],
        });
        window.open(explorerTx(hash), "_blank", "noopener,noreferrer");
        try {
          await publicClient?.waitForTransactionReceipt({ hash, timeout: 60_000 });
        } catch { /* tx may still land */ }
      }
    } catch { /* wallet rejection */ }
    finally {
      setMinting(false);
    }
  }

  return (
    <>
      {canMint && (
        <button className="nav-mint" onClick={mintAll} disabled={minting} title="Mint 1,000 of every test token in one transaction">
          {minting ? "minting…" : "Mint all"}
        </button>
      )}
      <button className="nav-wallet" onClick={() => open()} title={wrong ? "Wrong network — switch to Sepolia" : undefined}>
        <span className={`nav-dot ${isConnected && !wrong ? "on" : "off"}`} />
        {isConnected ? `${address?.slice(0, 6)}…${address?.slice(-4)}` : "Connect wallet"}
      </button>
    </>
  );
}
