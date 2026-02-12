"use client";

import { StarknetConfig, publicProvider } from "@starknet-react/core";
import { ReactNode } from "react";

const provider = publicProvider();

export function Providers({ children }: { children: ReactNode }) {
  return (
    <StarknetConfig provider={provider}>
      {children}
    </StarknetConfig>
  );
}
