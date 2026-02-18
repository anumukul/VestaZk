import { Contract, Account, RpcProvider } from "starknet";
import { provider, VAULT_ADDRESS } from "./starknet";

// Vault ABI - simplified for now, would be imported from compiled contract
const VAULT_ABI = [
  {
    type: "function",
    name: "deposit",
    inputs: [{ name: "amount", type: "u256" }],
    outputs: [
      { name: "commitment", type: "felt252" },
      { name: "leaf_index", type: "u64" },
      { name: "salt", type: "felt252" },
    ],
    state_mutability: "external",
  },
  {
    type: "function",
    name: "get_merkle_proof",
    inputs: [{ name: "leaf_index", type: "u64" }],
    outputs: [
      { name: "path", type: "Array<felt252>" },
      { name: "indices", type: "Array<u64>" },
    ],
    state_mutability: "view",
  },
  {
    type: "function",
    name: "borrow",
    inputs: [
      { name: "proof", type: "Span<felt252>" },
      { name: "public_inputs", type: "BorrowPublicInputs" },
      { name: "recipient", type: "ContractAddress" },
    ],
    outputs: [{ name: "success", type: "bool" }],
    state_mutability: "external",
  },
  {
    type: "function",
    name: "get_aggregate_health_factor",
    inputs: [],
    outputs: [
      { name: "collateral_usd", type: "u256" },
      { name: "debt_usd", type: "u256" },
      { name: "health_factor", type: "u256" },
    ],
    state_mutability: "view",
  },
  {
    type: "function",
    name: "get_merkle_root",
    inputs: [],
    outputs: [{ name: "root", type: "felt252" }],
    state_mutability: "view",
  },
  {
    type: "function",
    name: "get_total_deposited",
    inputs: [],
    outputs: [{ name: "amount", type: "u256" }],
    state_mutability: "view",
  },
  {
    type: "function",
    name: "get_total_borrowed",
    inputs: [],
    outputs: [{ name: "amount", type: "u256" }],
    state_mutability: "view",
  },
];

export class VaultClient {
  private contract: Contract;
  private provider: RpcProvider;

  constructor(account?: Account) {
    this.provider = provider;

    if (account) {
      this.contract = new Contract(VAULT_ABI, VAULT_ADDRESS, account);
    } else {
      this.contract = new Contract(VAULT_ABI, VAULT_ADDRESS, this.provider);
    }
  }

  async deposit(amount: bigint): Promise<{ commitment: string; leafIndex: number; salt: string }> {
    try {
      if (!this.contract.account) {
        throw new Error("Account required for deposit");
      }

      const tx = await this.contract.deposit(amount);
      await this.provider.waitForTransaction(tx.transaction_hash);

      const receipt = await this.provider.getTransactionReceipt(tx.transaction_hash);
      const { commitment, leafIndex, salt } = this.parseDepositReceipt(receipt);

      return { commitment, leafIndex, salt };
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`Deposit failed: ${message}`);
    }
  }

  async getMerkleProof(leafIndex: number): Promise<{ path: string[]; indices: number[] }> {
    const result = await this.contract.get_merkle_proof(leafIndex);
    const path = (result[0] as bigint[]).map((p) => p.toString());
    const indices = (result[1] as bigint[]).map((i) => Number(i));
    return { path, indices };
  }

  async borrow(
    proof: Uint8Array,
    publicInputs: any,
    recipient: string
  ): Promise<string> {
    try {
      if (!this.contract.account) {
        throw new Error("Account required for borrow");
      }

      // Convert proof to felt252 array
      const proofFelts = this.serializeProof(proof);

      const tx = await this.contract.borrow(proofFelts, publicInputs, recipient);

      await this.provider.waitForTransaction(tx.transaction_hash);
      return tx.transaction_hash;
    } catch (error: any) {
      throw new Error(`Borrow failed: ${error.message}`);
    }
  }

  async getAggregateHealth(): Promise<{
    collateralUsd: bigint;
    debtUsd: bigint;
    healthFactor: number;
  }> {
    const result = await this.contract.get_aggregate_health_factor();
    return {
      collateralUsd: BigInt(result[0].toString()),
      debtUsd: BigInt(result[1].toString()),
      healthFactor: Number(result[2]) / 100, // Convert to decimal
    };
  }

  async getMerkleRoot(): Promise<string> {
    const result = await this.contract.get_merkle_root();
    return result.toString();
  }

  async getTotalDeposited(): Promise<bigint> {
    const result = await this.contract.get_total_deposited();
    return BigInt(result.toString());
  }

  async getTotalBorrowed(): Promise<bigint> {
    const result = await this.contract.get_total_borrowed();
    return BigInt(result.toString());
  }

  private serializeProof(proof: Uint8Array): string[] {
    // Convert proof bytes to felt252 array
    // Implementation depends on Garaga's expected format
    const felts: string[] = [];
    for (let i = 0; i < proof.length; i += 31) {
      const chunk = proof.slice(i, Math.min(i + 31, proof.length));
      const hex = Array.from(chunk)
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      const felt = BigInt("0x" + hex);
      felts.push(felt.toString());
    }
    return felts;
  }

  private parseDepositReceipt(receipt: {
    events?: Array< { keys?: unknown[]; data?: unknown[] } >;
  }): { commitment: string; leafIndex: number; salt: string } {
    const event = receipt.events?.find((e) =>
      e.keys?.[0]?.toString().includes("Deposit")
    );
    if (!event?.data || event.data.length < 4) {
      throw new Error("Deposit event not found in receipt");
    }
    return {
      commitment: event.data[1].toString(),
      leafIndex: Number(event.data[2]),
      salt: event.data[3].toString(),
    };
  }
}
