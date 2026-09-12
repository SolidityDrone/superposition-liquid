import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Providers } from "./providers";
import Navbar from "@/components/Navbar";

export const metadata: Metadata = {
  title: "Maker console — SuperPosition Liquid",
  description: "Configure adapters, stake into Aave, LP the v4 hook, and manage borrow modes.",
};

export default function ConsoleLayout({ children }: { children: ReactNode }) {
  return (
    <Providers>
      <Navbar />
      {children}
    </Providers>
  );
}
