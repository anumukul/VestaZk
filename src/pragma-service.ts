import { Provider, Contract, num } from 'starknet';

const PRAGMA_ABI = [
  {
    type: "function",
    name: "get_data_median",
    inputs: [{ name: "data_type", type: "felt252" }],
    outputs: [
      { name: "price", type: "felt252" },
      { name: "decimals", type: "felt252" },
      { name: "last_updated_timestamp", type: "felt252" },
      { name: "num_sources_aggregated", type: "felt252" }
    ],
    state_mutability: "view"
  }
];

const PRAGMA_SEPOLIA = "0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b";

export interface PriceData {
  price: bigint;
  decimals: number;
  lastUpdated: bigint;
  numSources: number;
}

export class PragmaService {
  private provider: Provider;
  private contract: Contract;

  constructor(network: 'mainnet' | 'sepolia' = 'sepolia') {
    const rpcUrl = network === 'sepolia'
      ? 'https://starknet-sepolia.public.blastapi.io/rpc/v0_7'
      : 'https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_7';
    
    this.provider = new Provider({ nodeUrl: rpcUrl });
    this.contract = new Contract(PRAGMA_ABI, PRAGMA_SEPOLIA, this.provider);
  }

  async getPrice(pair: string): Promise<PriceData> {
    const result = await this.contract.get_data_median(pair);
    
    return {
      price: BigInt(result[0].toString()),
      decimals: parseInt(result[1].toString()),
      lastUpdated: BigInt(result[2].toString()),
      numSources: parseInt(result[3].toString())
    };
  }

  async getBTCPrice(): Promise<PriceData> {
    return this.getPrice('BTC/USD');
  }

  async getETHPrice(): Promise<PriceData> {
    return this.getPrice('ETH/USD');
  }

  async getUSDCPrice(): Promise<PriceData> {
    return this.getPrice('USDC/USD');
  }
}

export function createPragmaService(network: 'mainnet' | 'sepolia' = 'sepolia'): PragmaService {
  return new PragmaService(network);
}
