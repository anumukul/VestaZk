import { RpcProvider, Account, Contract, hash, uint256 } from 'starknet';
import { DEPLOYMENTS, getContractAddress } from './deployments';

const VESTA_VAULT_ABI = [
  {
    type: "function",
    name: "deposit",
    inputs: [{ name: "amount", type: "u256" }],
    outputs: [{ name: "commitment", type: "felt252" }],
    state_mutability: "external"
  },
  {
    type: "function",
    name: "withdraw",
    inputs: [
      { name: "commitment", type: "felt252" },
      { name: "amount", type: "u256" }
    ],
    outputs: [{ name: "success", type: "bool" }],
    state_mutability: "external"
  },
  {
    type: "function",
    name: "borrow_with_proof",
    inputs: [
      { name: "amount", type: "u256" },
      { name: "recipient", type: "contract_address" },
      { name: "full_proof_with_hints", type: "span<felt252>" }
    ],
    outputs: [{ name: "success", type: "bool" }],
    state_mutability: "external"
  },
  {
    type: "function",
    name: "repay",
    inputs: [{ name: "amount", type: "u256" }],
    outputs: [{ name: "success", type: "bool" }],
    state_mutability: "external"
  },
  {
    type: "function",
    name: "emergency_exit",
    inputs: [
      { name: "commitment", type: "felt252" },
      { name: "amount", type: "u256" },
      { name: "full_proof_with_hints", type: "span<felt252>" }
    ],
    outputs: [{ name: "success", type: "bool" }],
    state_mutability: "external"
  },
  {
    type: "function",
    name: "get_merkle_root",
    inputs: [],
    outputs: [{ name: "root", type: "felt252" }],
    state_mutability: "view"
  },
  {
    type: "function",
    name: "get_commitment_count",
    inputs: [],
    outputs: [{ name: "count", type: "u64" }],
    state_mutability: "view"
  },
  {
    type: "function",
    name: "is_nullifier_used",
    inputs: [{ name: "nullifier", type: "felt252" }],
    outputs: [{ name: "used", type: "bool" }],
    state_mutability: "view"
  },
  {
    type: "function",
    name: "get_total_deposited",
    inputs: [],
    outputs: [{ name: "total", type: "u256" }],
    state_mutability: "view"
  },
  {
    type: "function",
    name: "get_total_borrowed",
    inputs: [],
    outputs: [{ name: "total", type: "u256" }],
    state_mutability: "view"
  },
  {
    type: "function",
    name: "get_aggregate_health_factor",
    inputs: [],
    outputs: [
      { name: "collateral", type: "u256" },
      { name: "debt", type: "u256" },
      { name: "health", type: "u256" }
    ],
    state_mutability: "view"
  },
  {
    type: "event",
    name: "Deposited",
    inputs: [
      { name: "user", type: "contract_address" },
      { name: "amount", type: "u256" },
      { name: "commitment", type: "felt252" }
    ]
  },
  {
    type: "event",
    name: "Withdrawn",
    inputs: [
      { name: "user", type: "contract_address" },
      { name: "amount", type: "u256" },
      { name: "commitment", type: "felt252" }
    ]
  },
  {
    type: "event",
    name: "Borrowed",
    inputs: [
      { name: "user", type: "contract_address" },
      { name: "amount", type: "u256" },
      { name: "nullifier", type: "felt252" }
    ]
  },
  {
    type: "event",
    name: "Repaid",
    inputs: [
      { name: "user", type: "contract_address" },
      { name: "amount", type: "u256" }
    ]
  },
  {
    type: "event",
    name: "EmergencyExited",
    inputs: [
      { name: "user", type: "contract_address" },
      { name: "amount", type: "u256" },
      { name: "fee", type: "u256" },
      { name: "commitment", type: "felt252" }
    ]
  }
];

export interface VestazkConfig {
  network: 'mainnet' | 'sepolia';
  vaultAddress?: string;
  wbtcAddress?: string;
  usdcAddress?: string;
  vesuPoolAddress?: string;
  verifierAddress?: string;
}

export interface CommitmentData {
  commitment: string;
  btcAmount: string;
  salt: string;
  merkleRoot: string;
  merklePath: string[];
  merkleIndices: number[];
}

export interface HealthFactor {
  collateral: bigint;
  debt: bigint;
  health: bigint;
}

export class VestazkService {
  private provider: RpcProvider;
  private account: Account | null = null;
  private vaultContract: Contract | null = null;
  private config: VestazkConfig;

  constructor(config: VestazkConfig) {
    this.config = config;
    const rpcUrl = DEPLOYMENTS[config.network].rpc_url || 
      'https://starknet-sepolia.public.blastapi.io/rpc/v0_7';
    
    this.provider = new RpcProvider({ nodeUrl: rpcUrl });
    
    if (config.vaultAddress) {
      this.vaultContract = new Contract(
        VESTA_VAULT_ABI,
        config.vaultAddress,
        this.provider
      );
    }
  }

  setAccount(account: Account) {
    this.account = account;
    if (this.vaultContract && account) {
      this.vaultContract.connect(account);
    }
  }

  async deposit(amount: bigint): Promise<{ commitment: string; txHash: string }> {
    if (!this.account || !this.vaultContract) {
      throw new Error('Account or vault not initialized');
    }

    const tx = await this.vaultContract.deposit(amount);
    await this.provider.waitForTransaction(tx.transaction_hash);

    const receipt = await this.provider.getTransactionReceipt(tx.transaction_hash);
    
    const depositedEvent = receipt.events.find(
      (e: any) => e.keys[0] === hash.getSelectorByName('Deposited')
    );

    const commitment = depositedEvent?.data[2] || '0x0';

    return {
      commitment,
      txHash: tx.transaction_hash
    };
  }

  async withdraw(commitment: string, amount: bigint): Promise<{ txHash: string }> {
    if (!this.account || !this.vaultContract) {
      throw new Error('Account or vault not initialized');
    }

    const tx = await this.vaultContract.withdraw(commitment, amount);
    await this.provider.waitForTransaction(tx.transaction_hash);

    return { txHash: tx.transaction_hash };
  }

  async borrowWithProof(
    amount: bigint,
    recipient: string,
    proof: string[]
  ): Promise<{ txHash: string }> {
    if (!this.account || !this.vaultContract) {
      throw new Error('Account or vault not initialized');
    }

    const tx = await this.vaultContract.borrow_with_proof(
      amount,
      recipient,
      proof
    );
    await this.provider.waitForTransaction(tx.transaction_hash);

    return { txHash: tx.transaction_hash };
  }

  async repay(amount: bigint): Promise<{ txHash: string }> {
    if (!this.account || !this.vaultContract) {
      throw new Error('Account or vault not initialized');
    }

    const tx = await this.vaultContract.repay(amount);
    await this.provider.waitForTransaction(tx.transaction_hash);

    return { txHash: tx.transaction_hash };
  }

  async emergencyExit(
    commitment: string,
    amount: bigint,
    proof: string[]
  ): Promise<{ txHash: string }> {
    if (!this.account || !this.vaultContract) {
      throw new Error('Account or vault not initialized');
    }

    const tx = await this.vaultContract.emergency_exit(
      commitment,
      amount,
      proof
    );
    await this.provider.waitForTransaction(tx.transaction_hash);

    return { txHash: tx.transaction_hash };
  }

  async getAggregateHealthFactor(): Promise<HealthFactor> {
    if (!this.vaultContract) {
      throw new Error('Vault not initialized');
    }

    const result = await this.vaultContract.get_aggregate_health_factor();
    
    return {
      collateral: result[0],
      debt: result[1],
      health: result[2]
    };
  }

  async getVaultStats() {
    if (!this.vaultContract) {
      throw new Error('Vault not initialized');
    }

    const [merkleRoot, commitmentCount, totalDeposited, totalBorrowed, health] = 
      await Promise.all([
        this.vaultContract.get_merkle_root(),
        this.vaultContract.get_commitment_count(),
        this.vaultContract.get_total_deposited(),
        this.vaultContract.get_total_borrowed(),
        this.vaultContract.get_aggregate_health_factor()
      ]);

    return {
      merkleRoot,
      commitmentCount,
      totalDeposited: uint256.uint256ToBigInt(totalDeposited as any),
      totalBorrowed: uint256.uint256ToBigInt(totalBorrowed as any),
      healthFactor: {
        collateral: uint256.uint256ToBigInt(health[0] as any),
        debt: uint256.uint256ToBigInt(health[1] as any),
        health: uint256.uint256ToBigInt(health[2] as any)
      }
    };
  }

  isInitialized(): boolean {
    return this.account !== null && this.vaultContract !== null;
  }
}

export function createVestazkService(
  network: 'mainnet' | 'sepolia' = 'sepolia'
): VestazkService {
  const vaultAddress = getContractAddress(network, 'VesuVault');
  
  return new VestazkService({
    network,
    vaultAddress
  });
}
