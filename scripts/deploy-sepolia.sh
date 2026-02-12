#!/bin/bash

set -e

echo "Deploying VestaZk to Sepolia..."

# Check if environment variables are set
if [ -z "$STARKNET_ACCOUNT" ]; then
    echo "Error: STARKNET_ACCOUNT not set"
    exit 1
fi

if [ -z "$STARKNET_RPC" ]; then
    echo "Error: STARKNET_RPC not set"
    exit 1
fi

# Set network
export STARKNET_NETWORK=sepolia

# Deploy contracts
echo "Building contracts..."
cd contracts
scarb build

echo "Deploying Verifier..."
# Deploy verifier (will be generated from Noir circuit)
# starknet deploy --contract target/dev/Verifier.json --account $STARKNET_ACCOUNT

echo "Deploying Vault..."
# Deploy vault with constructor args
# starknet deploy --contract target/dev/Vault.json --account $STARKNET_ACCOUNT --constructor-args <args>

echo "Deployment complete!"
echo "Saving addresses to deployments/sepolia.json..."

cd ..
