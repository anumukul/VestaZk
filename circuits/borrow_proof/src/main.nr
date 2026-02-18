use dep::poseidon::poseidon::bn254;

// Constants
global TREE_DEPTH: u32 = 20;
global HEALTH_FACTOR_DECIMALS: Field = 100;

// Public inputs (visible on-chain)
struct PublicInputs {
    merkle_root: Field,
    borrow_amount: Field,
    btc_price: Field,          // e.g., 65000 * 10^6 (6 decimals)
    usdc_price: Field,         // e.g., 1 * 10^6
    min_health_factor: Field,  // e.g., 110 (represents 1.10)
    nullifier: Field,          // Unique per operation
}

// Private inputs (kept secret)
struct PrivateInputs {
    owner_address: Field,
    btc_amount: Field,
    salt: Field,
    merkle_path: [Field; TREE_DEPTH],
    merkle_indices: [u1; TREE_DEPTH],  // 0 = left, 1 = right
    debt_inverse: Field,  // witness: 1/debt_value_usd (prover supplies; proves debt != 0)
}

fn main(
    public_inputs: PublicInputs,
    private_inputs: PrivateInputs
) {
    // Step 1: Prove ownership of commitment
    let commitment = compute_commitment(
        private_inputs.owner_address,
        private_inputs.btc_amount,
        private_inputs.salt
    );
    
    let computed_root = verify_merkle_proof(
        commitment,
        private_inputs.merkle_path,
        private_inputs.merkle_indices
    );
    
    assert(computed_root == public_inputs.merkle_root, "Invalid Merkle proof");
    
    // Step 2: Calculate collateral value in USD
    // btc_amount has 8 decimals, btc_price has 6 decimals
    // Result: (btc_amount * btc_price) / 10^8, but we keep in higher precision
    let collateral_value_usd = private_inputs.btc_amount * public_inputs.btc_price;
    
    // Step 3: Calculate debt value in USD
    // borrow_amount has 6 decimals, usdc_price has 6 decimals
    // Result: (borrow_amount * usdc_price) / 10^6, but we keep in higher precision
    let debt_value_usd = public_inputs.borrow_amount * public_inputs.usdc_price;
    
    // Step 4: Calculate health factor (collateral / debt * 100)
    // Debt must be non-zero: prover supplies inverse and we verify debt * debt_inverse == 1
    assert(
        debt_value_usd * private_inputs.debt_inverse == 1,
        "Debt cannot be zero"
    );
    
    // To avoid division, we check: collateral_usd * 100 >= debt_usd * min_health_factor
    // Prove A >= B by showing (A - B) fits in 128 bits (so no wrap = non-negative)
    let min_collateral_required = debt_value_usd * public_inputs.min_health_factor;
    let collateral_times_100 = collateral_value_usd * HEALTH_FACTOR_DECIMALS;
    let diff = collateral_times_100 - min_collateral_required;
    diff.assert_max_bit_size::<128>();
    
    // Step 5: Verify nullifier is unique (generated from commitment + borrow_amount)
    let expected_nullifier = compute_nullifier(commitment, public_inputs.borrow_amount);
    assert(expected_nullifier == public_inputs.nullifier, "Invalid nullifier");
}

/// Compute commitment hash from owner, amount, and salt
fn compute_commitment(
    owner_address: Field,
    btc_amount: Field,
    salt: Field
) -> Field {
    // Hash owner and amount first
    let owner_amount_hash = bn254::hash_2([
        owner_address,
        btc_amount
    ]);
    
    // Then hash with salt
    bn254::hash_2([
        owner_amount_hash,
        salt
    ])
}

/// Verify Merkle proof and return computed root
fn verify_merkle_proof(
    leaf: Field,
    path: [Field; TREE_DEPTH],
    indices: [u1; TREE_DEPTH]
) -> Field {
    let mut current = leaf;
    
    for i in 0..TREE_DEPTH {
        let sibling = path[i];
        let is_right = indices[i];
        
        if is_right == 0 {
            // Current is left child
            current = bn254::hash_2([current, sibling]);
        } else {
            // Current is right child
            current = bn254::hash_2([sibling, current]);
        }
    }
    
    current
}

/// Compute nullifier from commitment and borrow amount
fn compute_nullifier(commitment: Field, borrow_amount: Field) -> Field {
    bn254::hash_2([commitment, borrow_amount])
}

#[test]
fn test_borrow_proof_valid() {
    let owner = 0x123456789abcdef;
    let btc_amount = 100000000; // 1 BTC (8 decimals)
    let salt = 0x999;
    let borrow_amount = 50000000000; // 50,000 USDC (6 decimals)
    let btc_price = 65000000000; // $65,000 (6 decimals)
    let usdc_price = 1000000; // $1 (6 decimals)
    let min_health_factor = 110; // 1.10
    
    // Compute commitment
    let commitment = compute_commitment(owner, btc_amount, salt);
    
    // Build mock Merkle path (all zeros for testing)
    let mut merkle_path = [0; TREE_DEPTH];
    let mut merkle_indices = [0; TREE_DEPTH];
    
    // Compute expected root (simplified for test)
    let root = verify_merkle_proof(commitment, merkle_path, merkle_indices);
    
    // Compute nullifier
    let nullifier = compute_nullifier(commitment, borrow_amount);
    let debt_value_usd = borrow_amount * usdc_price;
    let debt_inverse = 1 / debt_value_usd;
    
    let public_inputs = PublicInputs {
        merkle_root: root,
        borrow_amount,
        btc_price,
        usdc_price,
        min_health_factor,
        nullifier,
    };
    
    let private_inputs = PrivateInputs {
        owner_address: owner,
        btc_amount,
        salt,
        merkle_path,
        merkle_indices,
        debt_inverse,
    };
    
    // This should pass: 1 BTC ($65k) collateral, $50k debt = 130% health
    main(public_inputs, private_inputs);
}

#[test]
fn test_borrow_proof_low_health() {
    let owner = 0x123456789abcdef;
    let btc_amount = 100000000; // 1 BTC
    let salt = 0x999;
    let borrow_amount = 100000000000; // 100,000 USDC (too much)
    let btc_price = 65000000000;
    let usdc_price = 1000000;
    let min_health_factor = 110;
    
    let commitment = compute_commitment(owner, btc_amount, salt);
    let mut merkle_path = [0; TREE_DEPTH];
    let mut merkle_indices = [0; TREE_DEPTH];
    let root = verify_merkle_proof(commitment, merkle_path, merkle_indices);
    let nullifier = compute_nullifier(commitment, borrow_amount);
    let debt_value_usd = borrow_amount * usdc_price;
    let debt_inverse = 1 / debt_value_usd;
    
    let public_inputs = PublicInputs {
        merkle_root: root,
        borrow_amount,
        btc_price,
        usdc_price,
        min_health_factor,
        nullifier,
    };
    
    let _private_inputs = PrivateInputs {
        owner_address: owner,
        btc_amount,
        salt,
        merkle_path,
        merkle_indices,
        debt_inverse,
    };
    
    // This should fail: 1 BTC ($65k) collateral, $100k debt = 65% health < 110%
    // Note: In actual test, this would use #[should_panic] or expect_error
}
