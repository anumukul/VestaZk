#!/bin/bash
# Deploy VestaZk to local devnet (starknet-devnet).
# Start devnet first: starknet-devnet --seed 42 --port 5050
# Then run: ./scripts/deploy-local.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOYMENTS_DIR="$REPO_ROOT/deployments"
CONTRACTS_DIR="$REPO_ROOT/contracts"

RPC="${STARKNET_RPC:-http://127.0.0.1:5050/rpc}"
ACCOUNT="${STARKNET_ACCOUNT:-__default__}"

echo "Deploying VestaZk to local devnet at $RPC"

cd "$CONTRACTS_DIR"
scarb build

OUT_DIR="$CONTRACTS_DIR/target/dev"
VERIFIER_JSON=$(find "$OUT_DIR" -name "*erifier*.contract_class.json" 2>/dev/null | head -1)
VAULT_JSON=$(find "$OUT_DIR" -name "*Vault*.contract_class.json" 2>/dev/null | head -1)

if [ -z "$VERIFIER_JSON" ] || [ -z "$VAULT_JSON" ]; then
    echo "Error: Contract artifacts not found. Run scarb build first."
    exit 1
fi

export STARKNET_RPC="$RPC"

echo "Declare and deploy Verifier..."
VERIFIER_CLASS_HASH=$(starknet declare --contract "$VERIFIER_JSON" --account "$ACCOUNT" --json 2>/dev/null | jq -r '.class_hash')
VERIFIER_ADDRESS=$(starknet deploy --class_hash "$VERIFIER_CLASS_HASH" --account "$ACCOUNT" --json 2>/dev/null | jq -r '.contract_address')

echo "Declare Vault..."
VAULT_CLASS_HASH=$(starknet declare --contract "$VAULT_JSON" --account "$ACCOUNT" --json 2>/dev/null | jq -r '.class_hash')

# Use placeholder addresses for local dev (replace with mock contracts if you deploy them)
WBTC="${WBTC:-0x1}"
USDC="${USDC:-0x2}"
VESU_POOL="${VESU_POOL:-0x3}"
PRAGMA_ORACLE="${PRAGMA_ORACLE:-0x4}"
OWNER="${OWNER:-0x5}"

echo "Deploy Vault..."
VAULT_ADDRESS=$(starknet deploy \
    --class_hash "$VAULT_CLASS_HASH" \
    --account "$ACCOUNT" \
    --constructor-calldata "$WBTC" "$USDC" "$VESU_POOL" "$VERIFIER_ADDRESS" "$PRAGMA_ORACLE" "$OWNER" \
    --json 2>/dev/null | jq -r '.contract_address')

mkdir -p "$DEPLOYMENTS_DIR"
cat > "$DEPLOYMENTS_DIR/local.json" << EOF
{
  "network": "local",
  "rpc": "$RPC",
  "contracts": {
    "vault": "$VAULT_ADDRESS",
    "verifier": "$VERIFIER_ADDRESS",
    "wbtc": "$WBTC",
    "usdc": "$USDC",
    "vesu_pool": "$VESU_POOL",
    "pragma_oracle": "$PRAGMA_ORACLE",
    "owner": "$OWNER"
  },
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Local deployment complete."
echo "Vault: $VAULT_ADDRESS"
echo "Verifier: $VERIFIER_ADDRESS"
echo "Addresses saved to $DEPLOYMENTS_DIR/local.json"
echo ""
echo "For frontend, set in .env.local:"
echo "NEXT_PUBLIC_VAULT_ADDRESS=$VAULT_ADDRESS"
echo "NEXT_PUBLIC_RPC_URL=$RPC"
