# Circuit artifacts

Place the compiled Noir circuit here for the frontend to load:

1. Compile the circuit: `cd ../../circuits/borrow_proof && nargo compile`
2. Copy the artifact: copy `target/borrow_proof.json` (or the equivalent JSON output) to this directory as `borrow_proof.json`

The borrow page will load `/circuits/borrow_proof.json` at runtime to generate proofs. If the file is missing, proof generation will show a clear error asking to compile the circuit first.
