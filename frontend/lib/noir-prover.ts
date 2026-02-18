import { UltraHonkBackend } from "@noir-lang/backend_barretenberg";
import { Noir } from "@noir-lang/noir_js";
import { ProofInputs, GeneratedProof } from "./types";

const CIRCUIT_URL = "/circuits/borrow_proof.json";
let circuitCache: unknown | null = null;

/**
 * Load the compiled Noir circuit from public/circuits/borrow_proof.json.
 * Copy the artifact from circuits/borrow_proof/target/ after running nargo compile.
 */
export async function loadCircuit(): Promise<unknown | null> {
  if (circuitCache) return circuitCache;

  try {
    const res = await fetch(CIRCUIT_URL);
    if (!res.ok) {
      if (res.status === 404) return null;
      throw new Error(`HTTP ${res.status}`);
    }
    circuitCache = (await res.json()) as unknown;
    return circuitCache;
  } catch (e) {
    console.warn("Circuit not loaded:", e);
    return null;
  }
}

export async function generateBorrowProof(
  inputs: ProofInputs
): Promise<GeneratedProof> {
  try {
    const circuitData = await loadCircuit();
    if (!circuitData) {
      throw new Error("Circuit not loaded. Please compile the Noir circuit.");
    }

    // Initialize Noir backend
    const backend = new UltraHonkBackend(circuitData);
    const noir = new Noir(circuitData, backend);

    // Calculate nullifier
    const nullifier = calculateNullifier(
      inputs.owner_address,
      inputs.btc_amount,
      inputs.salt,
      inputs.borrow_amount
    );

    // Format inputs for circuit
    const circuitInputs = {
      public_inputs: {
        merkle_root: inputs.merkle_root,
        borrow_amount: inputs.borrow_amount,
        btc_price: inputs.btc_price,
        usdc_price: inputs.usdc_price,
        min_health_factor: inputs.min_health_factor,
        nullifier: nullifier,
      },
      private_inputs: {
        owner_address: inputs.owner_address,
        btc_amount: inputs.btc_amount,
        salt: inputs.salt,
        merkle_path: inputs.merkle_path,
        merkle_indices: inputs.merkle_indices,
      },
    };

    // Generate proof
    const { witness } = await noir.execute(circuitInputs);
    const proof = await backend.generateProof(witness);

    return {
      proof: proof.proof,
      publicInputs: circuitInputs.public_inputs,
    };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Proof generation failed:", error);
    throw new Error(`Failed to generate proof: ${message}`);
  }
}

function calculateNullifier(
  ownerAddress: string,
  btcAmount: string,
  salt: string,
  borrowAmount: string
): string {
  // Use Poseidon hash (must match circuit logic)
  // For now, use a simple hash combination
  // In production, use proper Poseidon hash from micro-starknet or similar
  const commitment = hashString(`${ownerAddress}-${btcAmount}-${salt}`);
  const nullifier = hashString(`${commitment}-${borrowAmount}`);
  return nullifier;
}

function hashString(str: string): string {
  // Placeholder hash function
  // In production, use proper Poseidon hash
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash; // Convert to 32-bit integer
  }
  return hash.toString();
}
