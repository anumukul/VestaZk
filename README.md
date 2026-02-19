# VestaZk

Privacy-preserving lending vault on Starknet that prevents liquidation hunting by using zero-knowledge proofs to hide individual user positions.

## Problem

Public lending protocols expose all user positions, enabling:
- MEV bots to manipulate markets and trigger liquidations
- Liquidation hunters to target specific users
- Privacy violations for high-net-worth individuals and institutions

## Solution

VestaZk aggregates user positions in a privacy vault and uses zero-knowledge proofs to enable borrowing without revealing:
- How much collateral each user deposited
- Individual debt levels
- Specific liquidation prices

Only the aggregate health factor is public, preventing targeted attacks.

## Architecture

The system consists of:

1. **Frontend (Next.js)**: User interface for deposits, borrows, and dashboard
2. **Vault Contract (Cairo)**: Main contract managing commitments and verifying proofs
3. **ZK Circuit (Noir)**: Generates proofs for private borrowing
4. **Verifier Contract**: On-chain proof verification. A **Garaga-generated** UltraKeccak ZK Honk verifier is used; an adapter contract implements `IVerifier` and forwards to it. The proof passed to `borrow()` must be the **full_proof_with_hints** blob (from `garaga calldata`), not raw bb output.
5. **Vesu Pool**: Handles actual lending operations
6. **Oracle**: Provides price feeds for health factor calculations

### Data Flow

**Deposit:**
- User deposits WBTC → Vault receives → Supplies to Vesu → Generates commitment → Adds to Merkle tree

**Borrow:**
- User generates ZK proof (client-side) → Submits proof + public inputs → Vault verifies → Borrows from Vesu → Transfers USDC to user

## Technology Stack

- **Cairo**: 2.6.3+ (Smart Contracts)
- **Noir**: 1.0.0-beta.1 (ZK Circuits)
- **Garaga**: 0.15.5+ (Proof Verification)
- **Starknet.js**: 6.0+ (Frontend Integration)
- **Next.js**: 14+ (Frontend Framework)
- **Bun**: Latest (Package Management)

## Quick Start

### Prerequisites

- Node.js 18+
- Bun
- Scarb 2.6.3+
- Noir 1.0.0-beta.1
- Starknet wallet (ArgentX or Braavos)

### Installation

```bash
# Install all dependencies
make install

# Or manually:
cd contracts && scarb build
cd circuits/borrow_proof && nargo check
cd frontend && bun install
```

### Run Locally

```bash
# Start local devnet
make devnet

# In another terminal, deploy contracts
cd contracts
scarb build
# Deploy using scripts/deploy-local.sh

# Start frontend
cd frontend
bun dev
```

## Development

### Run Tests

```bash
# Run all checks
make verify-all

# Or individually:
make cairo-check    # Contract tests
make noir-check      # Circuit tests
make frontend-check  # Frontend tests
```

### Build Contracts

```bash
cd contracts
scarb build
scarb test
```

### Build Circuits

```bash
cd circuits/borrow_proof
nargo compile
nargo test
```

### Run Frontend

```bash
cd frontend
bun install
bun dev
```

### Project Structure

```
.
├── contracts/          # Cairo smart contracts
│   ├── src/
│   │   ├── vault.cairo
│   │   ├── merkle_tree.cairo
│   │   └── interfaces.cairo
│   └── tests/
├── circuits/           # Noir ZK circuits
│   └── borrow_proof/
│       ├── src/
│       └── tests/
├── frontend/           # Next.js application
│   ├── app/
│   ├── components/
│   └── lib/
├── scripts/            # Deployment scripts
└── docs/               # Documentation
```

## Security

- **Reentrancy Protection**: All external calls protected
- **Access Control**: Admin functions restricted to owner
- **Pause Mechanism**: Emergency pause functionality
- **Proof Verification**: Always verify proof before state changes
- **Nullifier Tracking**: Prevents double-spending
- **Merkle Root Checks**: Ensures proofs are not stale
- **Health Factor Buffer**: Vault maintains 120% aggregate health
- **Input Validation**: All inputs validated before processing

## Gas Costs

- **Deposit**: ~150K gas
- **Borrow**: ~250K gas (includes proof verification)
- **Health Check**: ~50K gas (view function)

## Privacy Model

1. **Commitments**: User positions hidden via cryptographic commitments
2. **Merkle Tree**: Only root hash stored on-chain
3. **ZK Proofs**: Borrowing verified without revealing position details
4. **Aggregate Metrics**: Only vault-level metrics are public
5. **Nullifiers**: Prevent double-spending while maintaining privacy

## License

MIT
