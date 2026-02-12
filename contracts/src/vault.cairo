use starknet::ContractAddress;
use starknet::get_caller_address;
use starknet::get_contract_address;
use starknet::get_block_timestamp;

mod interfaces;
use interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, IVesuPoolDispatcher, IVesuPoolDispatcherTrait, IVerifierDispatcher, IVerifierDispatcherTrait, IPragmaOracleDispatcher, IPragmaOracleDispatcherTrait};

const TREE_DEPTH: u32 = 20;

/// Main Vault contract for privacy-preserving lending
#[starknet::contract]
mod Vault {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    
    use super::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, IVesuPoolDispatcher, IVesuPoolDispatcherTrait, IVerifierDispatcher, IVerifierDispatcherTrait, IPragmaOracleDispatcher, IPragmaOracleDispatcherTrait};

    #[storage]
    struct Storage {
        // Merkle tree state (incremental tree)
        merkle_levels: Map<(u32, u64), felt252>,
        merkle_next_index: u64,
        merkle_zero_values: Map<u32, felt252>,
        
        // Vault state
        merkle_root: felt252,
        total_deposited: u256,
        total_borrowed: u256,
        commitment_count: u64,
        
        // Nullifier tracking (prevent double-spending)
        nullifiers: Map<felt252, bool>,
        
        // Configuration
        min_health_factor: u256,
        buffer_percentage: u256,
        
        // External contract addresses
        wbtc_address: ContractAddress,
        usdc_address: ContractAddress,
        vesu_pool_address: ContractAddress,
        verifier_address: ContractAddress,
        oracle_address: ContractAddress,
        
        // Security
        paused: bool,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Borrow: Borrow,
        EmergencyExit: EmergencyExit,
        Paused: Paused,
        Unpaused: Unpaused,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        user: ContractAddress,
        commitment: felt252,
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Borrow {
        user: ContractAddress,
        nullifier: felt252,
        borrow_amount: u256,
        recipient: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyExit {
        user: ContractAddress,
        commitment: felt252,
        amount: u256,
        fee: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Paused {
        account: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Unpaused {
        account: ContractAddress,
    }

    /// Constructor
    /// Sets up the vault with required contract addresses
    fn constructor(
        ref self: ContractState,
        wbtc_address: ContractAddress,
        usdc_address: ContractAddress,
        vesu_pool_address: ContractAddress,
        verifier_address: ContractAddress,
        oracle_address: ContractAddress,
        owner: ContractAddress
    ) {
        self.wbtc_address.write(wbtc_address);
        self.usdc_address.write(usdc_address);
        self.vesu_pool_address.write(vesu_pool_address);
        self.verifier_address.write(verifier_address);
        self.oracle_address.write(oracle_address);
        self.owner.write(owner);
        
        // Initialize Merkle tree zero values
        self.merkle_zero_values.write(0, 0);
        let mut current = 0;
        for i in 1..=TREE_DEPTH {
            current = poseidon_hash_2(current, current);
            self.merkle_zero_values.write(i, current);
        }
        
        // Set initial root
        self.merkle_root.write(self.merkle_zero_values.read(TREE_DEPTH));
        
        // Set default health factor to 110 (1.10)
        self.min_health_factor.write(110);
        
        // Set buffer to 120% (vault maintains 120% aggregate health)
        self.buffer_percentage.write(120);
        
        self.paused.write(false);
    }

    /// Deposit WBTC and receive a privacy-preserving commitment
    /// 
    /// # Arguments
    /// * `amount` - Amount of WBTC to deposit (8 decimals)
    ///
    /// # Returns
    /// * `felt252` - Commitment hash for the deposit
    ///
    /// # Panics
    /// * If amount is zero
    /// * If WBTC transfer fails
    /// * If contract is paused
    #[external(v0)]
    fn deposit(ref self: ContractState, amount: u256) -> felt252 {
        self.assert_not_paused();
        assert(amount > 0, "Amount must be positive");
        
        let caller = get_caller_address();
        
        // Transfer WBTC from user to vault
        let wbtc = IERC20Dispatcher { contract_address: self.wbtc_address.read() };
        wbtc.transfer_from(caller, get_contract_address(), amount);
        
        // Approve Vesu pool to spend WBTC
        wbtc.approve(self.vesu_pool_address.read(), amount);
        
        // Supply WBTC to Vesu pool
        let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool_address.read() };
        vesu_pool.supply(self.wbtc_address.read(), amount);
        
        // Generate commitment = Hash(owner, amount, salt)
        // Salt is generated from block timestamp and caller address
        let salt = generate_salt(caller);
        let commitment = generate_commitment(caller, amount, salt);
        
        // Insert commitment into Merkle tree
        let new_root = self.merkle_insert(commitment);
        self.merkle_root.write(new_root);
        
        // Update state
        self.total_deposited.write(self.total_deposited.read() + amount);
        self.commitment_count.write(self.commitment_count.read() + 1);
        
        // Emit event
        self.emit(Deposit {
            user: caller,
            commitment,
            amount,
            timestamp: get_block_timestamp()
        });
        
        commitment
    }

    /// Insert a leaf into the Merkle tree and return new root
    fn merkle_insert(ref self: ContractState, leaf: felt252) -> felt252 {
        let index = self.merkle_next_index.read();
        
        // Store leaf at level 0
        self.merkle_levels.write((0, index), leaf);
        
        // Compute path up to root
        let mut current_hash = leaf;
        let mut current_index = index;
        
        for level in 0..TREE_DEPTH {
            let is_right = current_index % 2 == 1;
            let sibling_index = if is_right {
                current_index - 1
            } else {
                current_index + 1
            };
            
            let sibling = self.merkle_levels.read((level, sibling_index));
            let zero_val = self.merkle_zero_values.read(level);
            let sibling_hash = if sibling == 0 { zero_val } else { sibling };
            
            // Compute parent hash
            current_hash = if is_right {
                poseidon_hash_2(sibling_hash, current_hash)
            } else {
                poseidon_hash_2(current_hash, sibling_hash)
            };
            
            // Move to parent level
            current_index = current_index / 2;
            self.merkle_levels.write((level + 1, current_index), current_hash);
        }
        
        self.merkle_next_index.write(index + 1);
        current_hash
    }

    /// Generate commitment hash from user address, amount, and salt
    fn generate_commitment(owner: ContractAddress, amount: u256, salt: felt252) -> felt252 {
        let owner_amount_hash = starknet::pedersen_hash(owner.into(), amount.low.into());
        starknet::pedersen_hash(owner_amount_hash, salt)
    }

    /// Generate a unique salt for commitment
    fn generate_salt(owner: ContractAddress) -> felt252 {
        let timestamp = get_block_timestamp();
        starknet::pedersen_hash(owner.into(), timestamp.into())
    }

    /// Poseidon hash function (using Pedersen as equivalent)
    fn poseidon_hash_2(a: felt252, b: felt252) -> felt252 {
        starknet::pedersen_hash(a, b)
    }

    /// Check if contract is paused
    fn assert_not_paused(self: @ContractState) {
        assert(!self.paused.read(), "Contract is paused");
    }

    /// Get current Merkle root
    #[view]
    fn get_merkle_root(self: @ContractState) -> felt252 {
        self.merkle_root.read()
    }

    /// Get total deposited amount
    #[view]
    fn get_total_deposited(self: @ContractState) -> u256 {
        self.total_deposited.read()
    }

    /// Get total borrowed amount
    #[view]
    fn get_total_borrowed(self: @ContractState) -> u256 {
        self.total_borrowed.read()
    }

    /// Get commitment count
    #[view]
    fn get_commitment_count(self: @ContractState) -> u64 {
        self.commitment_count.read()
    }

    /// Pause contract operations (admin only)
    #[external(v0)]
    fn pause(ref self: ContractState) {
        self.assert_only_owner();
        self.paused.write(true);
        self.emit(Paused { account: get_caller_address() });
    }

    /// Resume contract operations (admin only)
    #[external(v0)]
    fn resume(ref self: ContractState) {
        self.assert_only_owner();
        self.paused.write(false);
        self.emit(Unpaused { account: get_caller_address() });
    }

    /// Check if caller is owner
    fn assert_only_owner(self: @ContractState) {
        assert(get_caller_address() == self.owner.read(), "Not authorized");
    }

    /// Set minimum health factor (admin only)
    #[external(v0)]
    fn set_min_health_factor(ref self: ContractState, new_min: u256) {
        self.assert_only_owner();
        assert(new_min >= 100, "Health factor must be at least 100 (1.0)");
        self.min_health_factor.write(new_min);
    }

    /// Set buffer percentage (admin only)
    #[external(v0)]
    fn set_buffer_percentage(ref self: ContractState, new_buffer: u256) {
        self.assert_only_owner();
        assert(new_buffer >= 100, "Buffer must be at least 100%");
        self.buffer_percentage.write(new_buffer);
    }

    /// Borrow USDC using a zero-knowledge proof
    /// 
    /// # Arguments
    /// * `proof` - Serialized ZK proof
    /// * `public_inputs` - Public inputs for proof verification
    /// * `recipient` - Address to receive borrowed USDC
    ///
    /// # Returns
    /// * `bool` - True if borrow succeeded
    ///
    /// # Panics
    /// * If proof verification fails
    /// * If nullifier already used
    /// * If aggregate health factor too low
    /// * If contract is paused
    #[external(v0)]
    fn borrow(
        ref self: ContractState,
        proof: Span<felt252>,
        public_inputs: BorrowPublicInputs,
        recipient: ContractAddress
    ) -> bool {
        self.assert_not_paused();
        
        // Verify proof
        let verifier = IVerifierDispatcher { contract_address: self.verifier_address.read() };
        let public_inputs_span = self.serialize_public_inputs(public_inputs);
        let valid = verifier.verify_proof(proof, public_inputs_span);
        assert(valid, "Invalid proof");
        
        // Check merkle root matches current root
        assert(
            public_inputs.merkle_root == self.merkle_root.read(),
            "Stale proof: merkle root mismatch"
        );
        
        // Check nullifier not used
        assert(
            !self.nullifiers.read(public_inputs.nullifier),
            "Nullifier already used"
        );
        
        // Mark nullifier as used
        self.nullifiers.write(public_inputs.nullifier, true);
        
        // Calculate aggregate health factor after borrow
        let (collateral_usd, debt_usd, current_health) = self.get_aggregate_health_factor();
        let new_debt = debt_usd + public_inputs.borrow_amount;
        
        // Calculate new health factor
        assert(new_debt > 0, "Debt cannot be zero");
        let new_health = (collateral_usd * 100) / new_debt;
        
        // Require new health >= (min_health * buffer_percentage / 100)
        let min_required = (self.min_health_factor.read() * self.buffer_percentage.read()) / 100;
        assert(new_health >= min_required, "Health factor too low after borrow");
        
        // Borrow USDC from Vesu pool
        let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool_address.read() };
        vesu_pool.borrow(self.usdc_address.read(), public_inputs.borrow_amount);
        
        // Transfer USDC to recipient
        let usdc = IERC20Dispatcher { contract_address: self.usdc_address.read() };
        usdc.transfer(recipient, public_inputs.borrow_amount);
        
        // Update state
        self.total_borrowed.write(self.total_borrowed.read() + public_inputs.borrow_amount);
        
        // Emit event
        self.emit(Borrow {
            user: get_caller_address(),
            nullifier: public_inputs.nullifier,
            borrow_amount: public_inputs.borrow_amount,
            recipient,
            timestamp: get_block_timestamp()
        });
        
        true
    }

    /// Get aggregate health factor (public view)
    /// Returns (collateral_usd, debt_usd, health_factor)
    /// Health factor is returned as integer (e.g., 150 = 1.50)
    #[view]
    fn get_aggregate_health_factor(
        self: @ContractState
    ) -> (u256, u256, u256) {
        let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool_address.read() };
        
        // Get vault's collateral and debt from Vesu
        let collateral_btc = vesu_pool.get_total_collateral(self.wbtc_address.read());
        let debt_usdc = vesu_pool.get_total_debt(self.usdc_address.read());
        
        // Get prices from oracle
        let oracle = IPragmaOracleDispatcher { contract_address: self.oracle_address.read() };
        
        // Get BTC price (6 decimals)
        let btc_price_response = oracle.get_data_median(0x4254432f555344); // "BTC/USD"
        let btc_price = btc_price_response.price;
        
        // USDC price is 1 (6 decimals)
        let usdc_price = 1000000; // 1 * 10^6
        
        // Calculate USD values
        // collateral_btc has 8 decimals, btc_price has 6 decimals
        // Result should have 6 decimals: (collateral_btc * btc_price) / 10^8
        let collateral_usd = (collateral_btc * btc_price) / 100000000;
        
        // debt_usdc has 6 decimals, usdc_price has 6 decimals
        // Result has 6 decimals: (debt_usdc * usdc_price) / 10^6
        let debt_usd = (debt_usdc * usdc_price) / 1000000;
        
        // Calculate health factor: (collateral_usd / debt_usd) * 100
        // Returns as integer (e.g., 150 = 1.50)
        let health_factor = if debt_usd > 0 {
            (collateral_usd * 100) / debt_usd
        } else {
            0
        };
        
        (collateral_usd, debt_usd, health_factor)
    }

    /// Serialize public inputs for verifier
    fn serialize_public_inputs(
        self: @ContractState,
        inputs: BorrowPublicInputs
    ) -> Span<felt252> {
        let mut serialized = array![
            inputs.merkle_root,
            inputs.borrow_amount.low.into(),
            inputs.btc_price.low.into(),
            inputs.usdc_price.low.into(),
            inputs.min_health_factor.low.into(),
            inputs.nullifier
        ];
        serialized.span()
    }
}

    /// Emergency exit for healthy positions
    /// Allows users with health factor > 150 (1.5x) to exit
    /// Charges 2% exit fee
    #[external(v0)]
    fn emergency_exit(
        ref self: ContractState,
        proof: Span<felt252>,
        public_inputs: ExitPublicInputs
    ) -> bool {
        self.assert_not_paused();
        
        // Verify proof shows health_factor > 150
        let verifier = IVerifierDispatcher { contract_address: self.verifier_address.read() };
        let public_inputs_span = self.serialize_exit_public_inputs(public_inputs);
        let valid = verifier.verify_proof(proof, public_inputs_span);
        assert(valid, "Invalid proof");
        
        // Check merkle root matches
        assert(
            public_inputs.merkle_root == self.merkle_root.read(),
            "Stale proof: merkle root mismatch"
        );
        
        // Verify health factor > 150 (1.5x)
        assert(public_inputs.health_factor > 150, "Health factor must be > 150 for emergency exit");
        
        // Calculate proportional share
        let total_deposited = self.total_deposited.read();
        assert(total_deposited > 0, "No deposits");
        
        // User's share = (user_deposit / total_deposited) * vault_balance
        let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool_address.read() };
        let vault_collateral = vesu_pool.get_total_collateral(self.wbtc_address.read());
        
        let user_share = (public_inputs.user_deposit * vault_collateral) / total_deposited;
        
        // Calculate 2% exit fee
        let exit_fee = (user_share * 2) / 100;
        let withdraw_amount = user_share - exit_fee;
        
        // Withdraw from Vesu
        vesu_pool.withdraw(self.wbtc_address.read(), withdraw_amount);
        
        // Transfer to user
        let wbtc = IERC20Dispatcher { contract_address: self.wbtc_address.read() };
        wbtc.transfer(get_caller_address(), withdraw_amount);
        
        // Update state
        self.total_deposited.write(self.total_deposited.read() - user_share);
        self.commitment_count.write(self.commitment_count.read() - 1);
        
        // Emit event
        self.emit(EmergencyExit {
            user: get_caller_address(),
            commitment: public_inputs.commitment,
            amount: withdraw_amount,
            fee: exit_fee,
            timestamp: get_block_timestamp()
        });
        
        true
    }

    /// Serialize exit public inputs for verifier
    fn serialize_exit_public_inputs(
        self: @ContractState,
        inputs: ExitPublicInputs
    ) -> Span<felt252> {
        let mut serialized = array![
            inputs.merkle_root,
            inputs.commitment,
            inputs.user_deposit.low.into(),
            inputs.health_factor.low.into()
        ];
        serialized.span()
    }
}

/// Public inputs for exit proof
#[derive(Drop, Serde, starknet::Store)]
struct ExitPublicInputs {
    merkle_root: felt252,
    commitment: felt252,
    user_deposit: u256,
    health_factor: u256,
}

/// Public inputs for borrow proof
#[derive(Drop, Serde, starknet::Store)]
struct BorrowPublicInputs {
    merkle_root: felt252,
    borrow_amount: u256,
    btc_price: u256,
    usdc_price: u256,
    min_health_factor: u256,
    nullifier: felt252,
}
