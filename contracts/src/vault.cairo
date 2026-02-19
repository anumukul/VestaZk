use starknet::ContractAddress;
use starknet::get_caller_address;
use starknet::get_contract_address;
use starknet::get_block_timestamp;

use vestazk_vault::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, IVesuPoolDispatcher, IVesuPoolDispatcherTrait, IVerifierDispatcher, IVerifierDispatcherTrait, IPragmaOracleDispatcher, IPragmaOracleDispatcherTrait};

const TREE_DEPTH: u32 = 20;

/// Public inputs for borrow proof.
#[derive(Drop, Serde, starknet::Store)]
pub struct BorrowPublicInputs {
    pub merkle_root: felt252,
    pub borrow_amount: u256,
    pub btc_price: u256,
    pub usdc_price: u256,
    pub min_health_factor: u256,
    pub nullifier: felt252,
}

/// Public inputs for exit proof.
#[derive(Drop, Serde, starknet::Store)]
pub struct ExitPublicInputs {
    pub merkle_root: felt252,
    pub commitment: felt252,
    pub user_deposit: u256,
    pub health_factor: u256,
}

/// Main Vault contract for privacy-preserving lending
#[starknet::contract]
mod Vault {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    use vestazk_vault::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, IVesuPoolDispatcher, IVesuPoolDispatcherTrait, IVerifierDispatcher, IVerifierDispatcherTrait, IPragmaOracleDispatcher, IPragmaOracleDispatcherTrait};
    use super::{BorrowPublicInputs, ExitPublicInputs};

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
        reentrancy_lock: bool,
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
        leaf_index: u64,
        salt: felt252,
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
        self.reentrancy_lock.write(false);
    }

    fn reentrancy_guard_start(ref self: ContractState) {
        assert(!self.reentrancy_lock.read(), 'ReentrancyGuard: reentrant call');
        self.reentrancy_lock.write(true);
    }

    fn reentrancy_guard_end(ref self: ContractState) {
        self.reentrancy_lock.write(false);
    }

    #[starknet::interface]
    trait IVault<TContractState> {
        fn deposit(ref self: TContractState, amount: u256) -> (felt252, u64, felt252);
        fn get_merkle_root(self: @TContractState) -> felt252;
        fn get_merkle_proof(self: @TContractState, leaf_index: u64) -> (Array<felt252>, Array<u64>);
        fn get_merkle_next_index(self: @TContractState) -> u64;
        fn get_total_deposited(self: @TContractState) -> u256;
        fn get_total_borrowed(self: @TContractState) -> u256;
        fn get_commitment_count(self: @TContractState) -> u64;
        fn pause(ref self: TContractState);
        fn resume(ref self: TContractState);
        fn set_min_health_factor(ref self: TContractState, new_min: u256);
        fn set_buffer_percentage(ref self: TContractState, new_buffer: u256);
        fn borrow(
            ref self: TContractState,
            proof: Span<felt252>,
            public_inputs: BorrowPublicInputs,
            recipient: ContractAddress
        ) -> bool;
        fn get_aggregate_health_factor(self: @TContractState) -> (u256, u256, u256);
        fn emergency_exit(
            ref self: TContractState,
            proof: Span<felt252>,
            public_inputs: ExitPublicInputs
        ) -> bool;
    }

    #[abi(embed_v0)]
    impl VaultImpl of IVault<ContractState> {
        /// Deposit WBTC and receive a privacy-preserving commitment
        fn deposit(ref self: ContractState, amount: u256) -> (felt252, u64, felt252) {
        self.assert_not_paused();
        assert(amount > 0, 'Amount must be positive');

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
        let salt = generate_salt(caller);
        let commitment = generate_commitment(caller, amount, salt);

        // Insert commitment into Merkle tree; get new root and leaf index
        let (new_root, leaf_index) = self.merkle_insert(commitment);
        self.merkle_root.write(new_root);

        // Update state
        self.total_deposited.write(self.total_deposited.read() + amount);
        self.commitment_count.write(self.commitment_count.read() + 1);

        // Emit event
        self.emit(Deposit {
            user: caller,
            commitment,
            leaf_index,
            salt,
            amount,
            timestamp: get_block_timestamp()
        });

        self.reentrancy_guard_end();
        (commitment, leaf_index, salt)
        }

        fn get_merkle_root(self: @ContractState) -> felt252 {
            self.merkle_root.read()
        }

        fn get_merkle_proof(self: @ContractState, leaf_index: u64) -> (Array<felt252>, Array<u64>) {
            let mut path = ArrayTrait::new();
            let mut indices = ArrayTrait::new();
            let mut current_index = leaf_index;
            for level in 0..TREE_DEPTH {
                let sibling_index = if current_index % 2 == 0 { current_index + 1 } else { current_index - 1 };
                let sibling = self.merkle_levels.read((level, sibling_index));
                let zero_val = self.merkle_zero_values.read(level);
                let sibling_hash = if sibling == 0 { zero_val } else { sibling };
                path.append(sibling_hash);
                indices.append(current_index % 2);
                current_index = current_index / 2;
            }
            (path, indices)
        }

        fn get_merkle_next_index(self: @ContractState) -> u64 {
            self.merkle_next_index.read()
        }

        fn get_total_deposited(self: @ContractState) -> u256 {
            self.total_deposited.read()
        }

        fn get_total_borrowed(self: @ContractState) -> u256 {
            self.total_borrowed.read()
        }

        fn get_commitment_count(self: @ContractState) -> u64 {
            self.commitment_count.read()
        }

        fn pause(ref self: ContractState) {
            self.assert_only_owner();
            self.paused.write(true);
            self.emit(Paused { account: get_caller_address() });
        }

        fn resume(ref self: ContractState) {
            self.assert_only_owner();
            self.paused.write(false);
            self.emit(Unpaused { account: get_caller_address() });
        }

        fn set_min_health_factor(ref self: ContractState, new_min: u256) {
            self.assert_only_owner();
            assert(new_min >= 100, 'Health factor must be at least 100');
            self.min_health_factor.write(new_min);
        }

        fn set_buffer_percentage(ref self: ContractState, new_buffer: u256) {
            self.assert_only_owner();
            assert(new_buffer >= 100, 'Buffer must be at least 100');
            self.buffer_percentage.write(new_buffer);
        }

        fn borrow(
            ref self: ContractState,
            proof: Span<felt252>,
            public_inputs: BorrowPublicInputs,
            recipient: ContractAddress
        ) -> bool {
            self.reentrancy_guard_start();
            self.assert_not_paused();
            let verifier = IVerifierDispatcher { contract_address: self.verifier_address.read() };
            let public_inputs_span = self.serialize_public_inputs(public_inputs);
            let valid = verifier.verify_proof(proof, public_inputs_span);
            assert(valid, 'Invalid proof');
            assert(public_inputs.merkle_root == self.merkle_root.read(), 'Stale proof: merkle root mismatch');
            assert(!self.nullifiers.read(public_inputs.nullifier), 'Nullifier already used');
            self.nullifiers.write(public_inputs.nullifier, true);
            let (collateral_usd, debt_usd, _) = self.get_aggregate_health_factor();
            let new_debt = debt_usd + public_inputs.borrow_amount;
            assert(new_debt > 0, 'Debt cannot be zero');
            let new_health = (collateral_usd * 100) / new_debt;
            let min_required = (self.min_health_factor.read() * self.buffer_percentage.read()) / 100;
            assert(new_health >= min_required, 'Health factor too low after borrow');
            let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool_address.read() };
            vesu_pool.borrow(self.usdc_address.read(), public_inputs.borrow_amount);
            let usdc = IERC20Dispatcher { contract_address: self.usdc_address.read() };
            usdc.transfer(recipient, public_inputs.borrow_amount);
            self.total_borrowed.write(self.total_borrowed.read() + public_inputs.borrow_amount);
            self.emit(Borrow {
                user: get_caller_address(),
                nullifier: public_inputs.nullifier,
                borrow_amount: public_inputs.borrow_amount,
                recipient,
                timestamp: get_block_timestamp()
            });
            self.reentrancy_guard_end();
            true
        }

        fn get_aggregate_health_factor(self: @ContractState) -> (u256, u256, u256) {
            let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool_address.read() };
            let collateral_btc = vesu_pool.get_total_collateral(self.wbtc_address.read());
            let debt_usdc = vesu_pool.get_total_debt(self.usdc_address.read());
            let oracle = IPragmaOracleDispatcher { contract_address: self.oracle_address.read() };
            let btc_price_response = oracle.get_data_median(0x4254432f555344);
            let btc_price = btc_price_response.price;
            let usdc_price = 1000000_u256;
            let collateral_usd = (collateral_btc * btc_price) / 100000000;
            let debt_usd = (debt_usdc * usdc_price) / 1000000;
            let health_factor = if debt_usd > 0 { (collateral_usd * 100) / debt_usd } else { 0 };
            (collateral_usd, debt_usd, health_factor)
        }

        fn emergency_exit(
            ref self: ContractState,
            proof: Span<felt252>,
            public_inputs: ExitPublicInputs
        ) -> bool {
            self.reentrancy_guard_start();
            self.assert_not_paused();
            let verifier = IVerifierDispatcher { contract_address: self.verifier_address.read() };
            let public_inputs_span = self.serialize_exit_public_inputs(public_inputs);
            let valid = verifier.verify_proof(proof, public_inputs_span);
            assert(valid, 'Invalid proof');
            assert(public_inputs.merkle_root == self.merkle_root.read(), 'Stale proof: merkle root mismatch');
            assert(public_inputs.health_factor > 150, 'Health factor must be > 150 for emergency exit');
            let total_deposited = self.total_deposited.read();
            assert(total_deposited > 0, 'No deposits');
            let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool_address.read() };
            let vault_collateral = vesu_pool.get_total_collateral(self.wbtc_address.read());
            let user_share = (public_inputs.user_deposit * vault_collateral) / total_deposited;
            let exit_fee = (user_share * 2) / 100;
            let withdraw_amount = user_share - exit_fee;
            vesu_pool.withdraw(self.wbtc_address.read(), withdraw_amount);
            let wbtc = IERC20Dispatcher { contract_address: self.wbtc_address.read() };
            wbtc.transfer(get_caller_address(), withdraw_amount);
            self.total_deposited.write(self.total_deposited.read() - user_share);
            self.commitment_count.write(self.commitment_count.read() - 1);
            self.emit(EmergencyExit {
                user: get_caller_address(),
                commitment: public_inputs.commitment,
                amount: withdraw_amount,
                fee: exit_fee,
                timestamp: get_block_timestamp()
            });
            self.reentrancy_guard_end();
            true
        }
    }

    /// Insert a leaf into the Merkle tree and return (new root, leaf index).
    fn merkle_insert(ref self: ContractState, leaf: felt252) -> (felt252, u64) {
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
        (current_hash, index)
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
        assert(!self.paused.read(), 'Contract is paused');
    }

    /// Check if caller is owner
    fn assert_only_owner(self: @ContractState) {
        assert(get_caller_address() == self.owner.read(), 'Not authorized');
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
