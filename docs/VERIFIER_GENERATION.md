# Generating the Cairo verifier for the Noir borrow circuit

This guide walks through generating a real Cairo verifier from the compiled Noir circuit using **Barretenberg** (for the verification key) and **Garaga** (for the Cairo contract), then wiring it into the Vault.

## Prerequisites

- **Noir** and **Nargo** (you already have this; circuit compiles).
- **Barretenberg** (`bb` CLI) **must match your Nargo version**, or you may get errors like `Length is too large`. Install the matching version with **bbup**:
  ```bash
  curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/next/barretenberg/bbup/install | bash
  source ~/.zshrc   # or source ~/.bashrc
  bbup   # installs the bb version compatible with your current nargo
  bb --version
  ```
  (Use the `next` branch URL; `master` may return 404.)
  If you installed Noir with [noirup](https://github.com/noir-lang/noirup), use `bbup` as above. Do not mix an old standalone `bb` with a recent Nargo.
- **Python 3.10** (required by Garaga).
- **Garaga**:
  ```bash
  pip install garaga==1.0.1
  ```
  Then run `garaga --help` to confirm the CLI is available.

## Step 1: Compile the Noir circuit

From the repo root:

```bash
cd circuits/borrow_proof
nargo compile
```

This produces `target/borrow_proof.json`. Leave this path as-is; `bb` will read it.

## Step 2: Generate the verification key with Barretenberg

In the same directory (`circuits/borrow_proof`):

```bash
bb write_vk -b target/borrow_proof.json -o target --oracle_hash keccak
```

Some setups require an explicit proof system; if the above fails, try:

```bash
bb write_vk -s ultra_honk --oracle_hash keccak -b target/borrow_proof.json -o target/vk
```

This creates a verification key (often `target/vk` or a file under `target/`). Note the exact path (e.g. `target/vk`) for the next step.

## Step 3: Generate the Cairo verifier with Garaga

**Note (bb 3.0.0-nightly):** If `garaga gen --system ultra_keccak_zk_honk` fails with `assert len(public_inputs) > 0`, the VK from bb has `public_inputs_size=0`. Apply these patches in your Garaga venv (e.g. `.venv-garaga/lib/python3.10/site-packages/garaga/`):

1. **zk_honk.py** (in `precompiled_circuits/`): In `HonkVk.from_bytes`, after parsing `public_inputs_size`, add:
   ```python
   if public_inputs_size < PAIRING_POINT_OBJECT_LENGTH:
       public_inputs_size = 6 + PAIRING_POINT_OBJECT_LENGTH  # 22
   ```
2. **ultra_honk.py** (in `precompiled_circuits/compilable_circuits/`): In `ZKSumCheckCircuit.input_map`, force at least 6 public inputs:
   ```python
   num_pubs = self.vk.public_inputs_size - PAIRING_POINT_OBJECT_LENGTH
   if num_pubs <= 0:
       num_pubs = 6
   imap["p_public_inputs"] = (structs.u256Span, num_pubs), ...
   ```
   And in `_execute_circuit_logic`, pass list elements to `compute_public_input_delta`: use `_to_list(vars["p_public_inputs"])` and `_to_list(vars["p_pairing_point_object"])` where `_to_list(x) = getattr(x, "elmts", x) if not isinstance(x, list) else x`.

Still from `circuits/borrow_proof`, run:

```bash
garaga gen --system ultra_keccak_zk_honk --vk target/vk
```

If that system name is not recognized, try:

```bash
garaga gen --system ultra_keccak_honk --vk target/vk
```

Garaga will create a **folder** (e.g. `garaga-env/` or a named project folder) containing Cairo files, including the main verifier logic (often something like `honk_verifier.cairo` or a `verifier.cairo`).

## Step 4: Wire the generated verifier into the project (VestaZk setup)

The generated verifier exposes `verify_ultra_keccak_zk_honk_proof(full_proof_with_hints: Span<felt252>) -> Result<Span<u256>, felt252>`. The Vault expects **IVerifier**: `verify_proof(proof, public_inputs) -> bool`.

**VestaZk does the following:**

1. **vestazk_verifier** (Garaga output) is added as a path dependency in `contracts/Scarb.toml`.
2. **contracts/src/verifier.cairo** is an **adapter** that implements IVerifier: it stores the Garaga verifier contract address and forwards `verify_proof(proof, _)` to `verify_ultra_keccak_zk_honk_proof(proof)`. So the `proof` parameter must be the **full_proof_with_hints** blob (from `garaga calldata`), not raw proof + public_inputs.
3. **Deploy order:** Deploy the Garaga verifier contract first (from `vestazk_verifier`), then deploy the adapter Verifier with that address, then deploy the Vault with the adapter’s address.
4. **Frontend:** Generate proof with `bb prove`, then run `garaga calldata` (or the Garaga flow) to produce the single blob to send as `proof` to `borrow()`.

### Manual wiring

**Replace stub with generated contract:** If the generated contract exposes a function with the same semantics as `verify_proof`:

1. Copy the generated verifier module/file(s) into `contracts/src/` (e.g. replace or add next to `verifier.cairo`).
2. Ensure the contract implements `IVerifier` from `vestazk_vault::interfaces`:
   - Either the generated code already matches `verify_proof(self, proof, public_inputs) -> bool`, or
   - Add a thin wrapper in `contracts/src/verifier.cairo` that imports the generated verifier and implements `IVerifier` by calling the generated verify function with `proof` and `public_inputs`.

**Keep a wrapper:** If the generated code lives in a separate module (e.g. `honk_verifier`) with a function like `verify(proof, public_inputs)`:

1. Place the generated files under `contracts/src/` (or a submodule).
2. In `contracts/src/verifier.cairo`, keep the current contract structure but replace the stub body of `verify_proof` with a call to the generated verifier, passing through `proof` and `public_inputs`.

In both cases, the **order and format of public inputs** must match what the circuit expects:

- Borrow proof: `merkle_root`, `borrow_amount`, `btc_price`, `usdc_price`, `min_health_factor`, `nullifier` (each as felt252; u256 fields as `.low` in the Vault’s serialization).

## Step 5: Build and test

From the repo root:

```bash
cd contracts
scarb build
```

Fix any import or path errors so that the verifier module compiles. Then run your tests (e.g. `scarb test` or your deploy script) to ensure the Vault still compiles and, once you have a real proof, that verification succeeds on-chain.

## Troubleshooting

- **`Length is too large` when running `bb write_vk`**  
  Your Barretenberg (`bb`) version does not match your Noir/Nargo version. Install the matching backend with **bbup** (see Prerequisites), then run `bb write_vk` again.

- **`bb: command not found`**  
  Install Barretenberg with bbup (see Prerequisites) and ensure the install directory is on your `PATH`.

- **`garaga: command not found`**  
  Use Python 3.10 and run `pip install garaga==1.0.1`; ensure the pip bin directory is in your `PATH`.

- **Unknown system name**  
  Run `garaga gen --help` and try the system names listed (e.g. `ultra_keccak_zk_honk`, `ultra_keccak_honk`).

- **Public input mismatch**  
  Ensure the Vault’s `serialize_public_inputs` (and any frontend proof generation) sends the same number and order of field elements as the Noir circuit’s public inputs.

- **Version compatibility**  
  Garaga 1.0.1 is tested with Noir 1.0.0-beta.16 and Barretenberg 3.0.0-nightly.20251104. If you use different versions, you may need to align them or check Garaga/Noir release notes.
