#!/usr/bin/env bash
# Generate verification key (Barretenberg) and Cairo verifier (Garaga) for the Noir borrow circuit.
# Prerequisites: nargo, bb (Barretenberg), garaga (pip install garaga==1.0.1, Python 3.10).
# After this script, wire the generated verifier into contracts/src/verifier.cairo (see docs/VERIFIER_GENERATION.md).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CIRCUIT_DIR="$REPO_ROOT/circuits/borrow_proof"
ARTIFACT="$CIRCUIT_DIR/target/borrow_proof.json"
VK_PATH="$CIRCUIT_DIR/target/vk"
OUTPUT_DIR="$CIRCUIT_DIR/garaga-output"

cd "$CIRCUIT_DIR"

echo "==> Step 1: Compiling Noir circuit..."
nargo compile
if [[ ! -f "$ARTIFACT" ]]; then
  echo "Expected artifact not found: $ARTIFACT"
  exit 1
fi

echo "==> Step 2: Generating verification key with Barretenberg..."
if command -v bb &>/dev/null; then
  # Try default output path (some bb versions write to -o target and name the file vk)
  if bb write_vk -b "$ARTIFACT" -o target --oracle_hash keccak 2>/dev/null; then
    echo "Verification key written to target/"
  else
    bb write_vk -s ultra_honk --oracle_hash keccak -b "$ARTIFACT" -o "$VK_PATH"
    echo "Verification key written to $VK_PATH"
  fi
else
  echo "Error: 'bb' (Barretenberg) not found. Install it and add to PATH."
  exit 1
fi

# Resolve vk path (bb may write target/vk or a file inside target/)
if [[ -f "$VK_PATH" ]]; then
  VK="$VK_PATH"
elif [[ -f "$CIRCUIT_DIR/target/vk" ]]; then
  VK="$CIRCUIT_DIR/target/vk"
else
  VK=$(find "$CIRCUIT_DIR/target" -maxdepth 1 -type f -name 'vk' 2>/dev/null | head -1)
  if [[ -z "$VK" ]]; then
    echo "Error: Could not find verification key under $CIRCUIT_DIR/target"
    exit 1
  fi
fi

echo "==> Step 3: Generating Cairo verifier with Garaga..."
if ! command -v garaga &>/dev/null; then
  echo "Error: 'garaga' not found. Install with: pip install garaga==1.0.1 (Python 3.10)"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
if garaga gen --system ultra_keccak_zk_honk --vk "$VK" 2>/dev/null; then
  echo "Garaga generated verifier (ultra_keccak_zk_honk)."
elif garaga gen --system ultra_keccak_honk --vk "$VK" 2>/dev/null; then
  echo "Garaga generated verifier (ultra_keccak_honk)."
else
  echo "Run manually and pick the system your Garaga supports:"
  echo "  garaga gen --system <SYSTEM> --vk $VK"
  echo "  e.g. ultra_keccak_zk_honk or ultra_keccak_honk"
  exit 1
fi

echo "Done. Next: copy/wire the generated Cairo verifier into contracts/src/verifier.cairo (see docs/VERIFIER_GENERATION.md)."
