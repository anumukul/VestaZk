export interface CommitmentData {
  btcAmount: string;
  salt: string;
  merklePath: string[];
  merkleIndices: number[];
  merkleRoot: string;
  commitment: string;
  timestamp: number;
}

export interface ProofInputs {
  owner_address: string;
  btc_amount: string;
  salt: string;
  merkle_path: string[];
  merkle_indices: number[];
  borrow_amount: string;
  btc_price: string;
  usdc_price: string;
  min_health_factor: string;
  merkle_root: string;
}

export interface GeneratedProof {
  proof: Uint8Array;
  publicInputs: {
    merkle_root: string;
    borrow_amount: string;
    btc_price: string;
    usdc_price: string;
    min_health_factor: string;
    nullifier: string;
  };
}

export interface AggregateHealth {
  collateralUsd: bigint;
  debtUsd: bigint;
  healthFactor: number;
}
