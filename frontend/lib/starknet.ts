import { RpcProvider } from "starknet";

const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL || "https://starknet-sepolia.public.blastapi.io/rpc/v0_7";

export const provider = new RpcProvider({
  nodeUrl: RPC_URL,
});

export const VAULT_ADDRESS = process.env.NEXT_PUBLIC_VAULT_ADDRESS || "";
export const WBTC_ADDRESS = process.env.NEXT_PUBLIC_WBTC_ADDRESS || "";
export const USDC_ADDRESS = process.env.NEXT_PUBLIC_USDC_ADDRESS || "";
