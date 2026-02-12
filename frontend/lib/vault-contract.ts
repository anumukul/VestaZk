import { Contract, Account, RpcProvider } from "starknet";
import { provider, VAULT_ADDRESS } from "./starknet";

// Vault ABI - simplified for now, would be imported from compiled contract
const VAULT_ABI = [
  {
    type: "function",
    name: "deposit",
    inputs: [{ name: "amount", type: "u256" }],
    outputs: [{ name: "commitment", type: "felt252" }],
    state_mutability: "external",
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

  async deposit(amount: bigint): Promise<string> {
    try {
      if (!this.contract.account) {
        throw new Error("Account required for deposit");
      }

      const tx = await this.contract.deposit(amount);
      await this.provider.waitForTransaction(tx.transaction_hash);

      // Parse commitment from events
      const receipt = await this.provider.getTransactionReceipt(tx.transaction_hash);
      const commitment = this.parseCommitmentFromReceipt(receipt);

      return commitment;
    } catch (error: any) {
      throw new Error(`Deposit failed: ${error.message}`);
    }
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

  private parseCommitmentFromReceipt(receipt: any): string {
    // Parse DepositEvent from transaction receipt
    const event = receipt.events?.find((e: any) =>
      e.keys?.[0]?.toString().includes("Deposit")
    );
    if (!event) throw new Error("Commitment not found in receipt");
    return event.data[0].toString(); // First data field is commitment
  }
}
