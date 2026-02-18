#!/bin/bash
# Deploy VestaZk contracts to Starknet Sepolia.
# Requires: STARKNET_ACCOUNT, STARKNET_RPC, and optionally WBTC, USDC, VESU_POOL addresses.
# Set PRAGMA_ORACLE and OWNER if different from defaults.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOYMENTS_DIR="$REPO_ROOT/deployments"
CONTRACTS_DIR="$REPO_ROOT/contracts"

echo "Deploying VestaZk to Sepolia..."

if [ -z "$STARKNET_ACCOUNT" ]; then
    echo "Error: STARKNET_ACCOUNT not set"
    exit 1
fi

if [ -z "$STARKNET_RPC" ]; then
    echo "Error: STARKNET_RPC not set. Example: https://starknet-sepolia.public.blastapi.io/rpc/v0_7"
    exit 1
fi

export STARKNET_NETWORK=sepolia

PRAGMA_ORACLE="${PRAGMA_ORACLE:-0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b}"
WBTC="${WBTC:-}"
USDC="${USDC:-}"
VESU_POOL="${VESU_POOL:-}"
OWNER="${OWNER:-}"

if [ -z "$OWNER" ]; then
    echo "Error: OWNER (deployer/owner address) not set. Set OWNER to the vault owner address."
    exit 1
fi

cd "$CONTRACTS_DIR"
echo "Building contracts..."
scarb build

OUT_DIR="$CONTRACTS_DIR/target/dev"
if [ ! -f "$OUT_DIR/vestazk_vault_Verifier.contract_class.json" ] && [ ! -f "$OUT_DIR/Verifier.contract_class.json" ]; then
    VERIFIER_JSON=$(find "$OUT_DIR" -name "*Verifier*.contract_class.json" 2>/dev/null | head -1)
else
    VERIFIER_JSON="$OUT_DIR/vestazk_vault_Verifier.contract_class.json"
fi
if [ -z "$VERIFIER_JSON" ]; then
    VERIFIER_JSON=$(find "$OUT_DIR" -name "*erifier*.contract_class.json" 2>/dev/null | head -1)
fi
VAULT_JSON=$(find "$OUT_DIR" -name "*Vault*.contract_class.json" 2>/dev/null | head -1)

if [ -z "$VAULT_JSON" ]; then
    echo "Error: Vault contract artifact not found under $OUT_DIR"
    exit 1
fi

echo "Declare Verifier..."
VERIFIER_CLASS_HASH=$(starknet declare --contract "$VERIFIER_JSON" --account "$STARKNET_ACCOUNT" --json | jq -r '.class_hash')
echo "Verifier class hash: $VERIFIER_CLASS_HASH"

echo "Deploy Verifier..."
VERIFIER_ADDRESS=$(starknet deploy --class_hash "$VERIFIER_CLASS_HASH" --account "$STARKNET_ACCOUNT" --json | jq -r '.contract_address')
echo "Verifier deployed at: $VERIFIER_ADDRESS"

echo "Declare Vault..."
VAULT_CLASS_HASH=$(starknet declare --contract "$VAULT_JSON" --account "$STARKNET_ACCOUNT" --json | jq -r '.class_hash')
echo "Vault class hash: $VAULT_CLASS_HASH"

if [ -z "$WBTC" ] || [ -z "$USDC" ] || [ -z "$VESU_POOL" ]; then
    echo "Warning: WBTC, USDC, or VESU_POOL not set. Deploy Vault manually with:"
    echo "  starknet deploy --class_hash $VAULT_CLASS_HASH --account $STARKNET_ACCOUNT --constructor-calldata $WBTC $USDC $VESU_POOL $VERIFIER_ADDRESS $PRAGMA_ORACLE $OWNER"
    VAULT_ADDRESS=""
else
    echo "Deploy Vault..."
    VAULT_ADDRESS=$(starknet deploy \
        --class_hash "$VAULT_CLASS_HASH" \
        --account "$STARKNET_ACCOUNT" \
        --constructor-calldata "$WBTC" "$USDC" "$VESU_POOL" "$VERIFIER_ADDRESS" "$PRAGMA_ORACLE" "$OWNER" \
        --json | jq -r '.contract_address')
    echo "Vault deployed at: $VAULT_ADDRESS"
fi

mkdir -p "$DEPLOYMENTS_DIR"
cat > "$DEPLOYMENTS_DIR/sepolia.json" << EOF
{
  "network": "sepolia",
  "contracts": {
    "vault": "$VAULT_ADDRESS",
    "verifier": "$VERIFIER_ADDRESS",
    "verifier_class_hash": "$VERIFIER_CLASS_HASH",
    "vault_class_hash": "$VAULT_CLASS_HASH",
    "wbtc": "$WBTC",
    "usdc": "$USDC",
    "vesu_pool": "$VESU_POOL",
    "pragma_oracle": "$PRAGMA_ORACLE",
    "owner": "$OWNER"
  },
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployed_by": "$STARKNET_ACCOUNT"
}
EOF

echo "Deployment complete. Addresses written to $DEPLOYMENTS_DIR/sepolia.json"
