import { cookieStorage, createStorage } from "wagmi";
import { WagmiAdapter } from "@reown/appkit-adapter-wagmi";
import { sepolia, type AppKitNetwork } from "@reown/appkit/networks";

export const projectId = process.env.NEXT_PUBLIC_PROJECT_ID ?? "";

export const networks: [AppKitNetwork, ...AppKitNetwork[]] = [sepolia];

export const metadata = {
  name: "SuperPosition Liquid",
  description: "Yield-backed liquidity for 1inch Aqua — maker console",
  url: "https://superposition.liquid",
  icons: ["/logo.png"],
};

export const wagmiAdapter = new WagmiAdapter({
  storage: createStorage({ storage: cookieStorage }),
  ssr: true,
  projectId,
  networks,
});

export const wagmiConfig = wagmiAdapter.wagmiConfig;
