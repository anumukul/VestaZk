use core::array::{ArrayTrait, Span};
use core::integer::u256;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IVesuPool<TContractState> {
    fn supply(ref self: TContractState, asset: ContractAddress, amount: u256) -> bool;
    fn borrow(ref self: TContractState, asset: ContractAddress, amount: u256) -> bool;
    fn withdraw(ref self: TContractState, asset: ContractAddress, amount: u256) -> bool;
    fn repay(ref self: TContractState, asset: ContractAddress, amount: u256) -> bool;
    fn get_user_collateral(self: @TContractState, user: ContractAddress, asset: ContractAddress) -> u256;
    fn get_user_debt(self: @TContractState, user: ContractAddress, asset: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, to: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, from: ContractAddress, to: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IVesuVault<TContractState> {
    fn deposit(ref self: TContractState, amount: u256) -> felt252;
    fn withdraw(ref self: TContractState, commitment: felt252, amount: u256) -> bool;
    fn borrow(ref self: TContractState, amount: u256, recipient: ContractAddress) -> bool;
    fn repay(ref self: TContractState, amount: u256) -> bool;
    fn get_merkle_root(self: @TContractState) -> felt252;
    fn get_commitment_count(self: @TContractState) -> u64;
    fn is_commitment_used(self: @TContractState, commitment: felt252) -> bool;
    fn get_total_deposited(self: @TContractState) -> u256;
    fn get_total_borrowed(self: @TContractState) -> u256;
    fn get_aggregate_health_factor(self: @TContractState) -> (u256, u256, u256);
}

#[starknet::contract]
pub mod VesuVault {
    use super::{
        ArrayTrait, ContractAddress, IERC20Dispatcher, IERC20DispatcherTrait, IVesuPoolDispatcher,
        IVesuPoolDispatcherTrait, IVesuVault, Span, u256,
    };
    use core::poseidon::poseidon_hash_span;
    use starknet::get_caller_address;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    const MERKLE_TREE_DEPTH: u32 = 20;

    #[storage]
    struct Storage {
        merkle_root: felt252,
        total_deposited: u256,
        total_borrowed: u256,
        commitment_count: u64,
        commitments: Map<felt252, (u256, felt252)>,
        nullifiers: Map<felt252, bool>,
        wbtc_token: ContractAddress,
        usdc_token: ContractAddress,
        vesu_pool: ContractAddress,
        min_health_factor: u256,
        buffer_percentage: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        Borrowed: Borrowed,
        Repaid: Repaid,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Deposited {
        #[key]
        user: ContractAddress,
        amount: u256,
        commitment: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdrawn {
        #[key]
        user: ContractAddress,
        amount: u256,
        commitment: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Borrowed {
        #[key]
        user: ContractAddress,
        amount: u256,
        nullifier: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Repaid {
        #[key]
        user: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        wbtc_token: ContractAddress,
        usdc_token: ContractAddress,
        vesu_pool: ContractAddress,
    ) {
        self.wbtc_token.write(wbtc_token);
        self.usdc_token.write(usdc_token);
        self.vesu_pool.write(vesu_pool);
        self.min_health_factor.write(u256 { low: 110, high: 0 });
        self.buffer_percentage.write(u256 { low: 120, high: 0 });
        self.merkle_root.write(0);
        self.commitment_count.write(0);
        self.total_deposited.write(u256 { low: 0, high: 0 });
        self.total_borrowed.write(u256 { low: 0, high: 0 });
    }

    #[abi(embed_v0)]
    impl VesuVaultImpl of IVesuVault<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) -> felt252 {
            let caller = get_caller_address();
            
            let wbtc = IERC20Dispatcher { contract_address: self.wbtc_token.read() };
            let vault_address = starknet::get_contract_address();
            
            let transferred = wbtc.transfer_from(caller, vault_address, amount);
            assert(transferred, 'WBTC transfer failed');

            let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            let supplied = vesu_pool.supply(self.wbtc_token.read(), amount);
            assert(supplied, 'Vesu supply failed');

            let salt = self.generate_salt(caller, amount);
            let commitment = self.compute_commitment(caller, amount, salt);

            let current_count = self.commitment_count.read();
            self.commitments.write(commitment, (amount, salt));
            self.commitment_count.write(current_count + 1);
            self.total_deposited.write(self.total_deposited.read() + amount);

            let new_root = self.update_merkle_root(commitment, current_count);
            self.merkle_root.write(new_root);

            self.emit(Event::Deposited(Deposited {
                user: caller,
                amount,
                commitment,
            }));

            commitment
        }

        fn withdraw(ref self: ContractState, commitment: felt252, amount: u256) -> bool {
            let caller = get_caller_address();
            assert(!self.is_commitment_used(commitment), 'Commitment already used');

            let (stored_amount, _) = self.commitments.read(commitment);
            assert(stored_amount == amount, 'Amount mismatch');

            let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            let withdrawn = vesu_pool.withdraw(self.wbtc_token.read(), amount);
            assert(withdrawn, 'Vesu withdraw failed');

            let wbtc = IERC20Dispatcher { contract_address: self.wbtc_token.read() };
            wbtc.transfer(caller, amount);

            self.nullifiers.write(commitment, true);
            self.total_deposited.write(self.total_deposited.read() - amount);

            self.emit(Event::Withdrawn(Withdrawn {
                user: caller,
                amount,
                commitment,
            }));

            true
        }

        fn borrow(ref self: ContractState, amount: u256, recipient: ContractAddress) -> bool {
            let caller = get_caller_address();
            
            let new_total_borrowed = self.total_borrowed.read() + amount;
            self.total_borrowed.write(new_total_borrowed);

            let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            let borrowed = vesu_pool.borrow(self.usdc_token.read(), amount);
            assert(borrowed, 'Vesu borrow failed');

            let usdc = IERC20Dispatcher { contract_address: self.usdc_token.read() };
            usdc.transfer(recipient, amount);

            let nullifier = self.compute_nullifier(caller, amount);
            self.nullifiers.write(nullifier, true);

            self.emit(Event::Borrowed(Borrowed {
                user: caller,
                amount,
                nullifier,
            }));

            true
        }

        fn repay(ref self: ContractState, amount: u256) -> bool {
            let caller = get_caller_address();
            
            let usdc = IERC20Dispatcher { contract_address: self.usdc_token.read() };
            let vault_address = starknet::get_contract_address();
            
            let transferred = usdc.transfer_from(caller, vault_address, amount);
            assert(transferred == true, 'USDC transfer failed');

            let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            let repaid = vesu_pool.repay(self.usdc_token.read(), amount);
            assert(repaid, 'Vesu repay failed');

            self.total_borrowed.write(self.total_borrowed.read() - amount);

            self.emit(Event::Repaid(Repaid {
                user: caller,
                amount,
            }));

            true
        }

        fn get_merkle_root(self: @ContractState) -> felt252 {
            self.merkle_root.read()
        }

        fn get_commitment_count(self: @ContractState) -> u64 {
            self.commitment_count.read()
        }

        fn is_commitment_used(self: @ContractState, commitment: felt252) -> bool {
            self.nullifiers.read(commitment)
        }

        fn get_total_deposited(self: @ContractState) -> u256 {
            self.total_deposited.read()
        }

        fn get_total_borrowed(self: @ContractState) -> u256 {
            self.total_borrowed.read()
        }

        fn get_aggregate_health_factor(self: @ContractState) -> (u256, u256, u256) {
            let vesu_pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            let vault_address = starknet::get_contract_address();
            
            let collateral = vesu_pool.get_user_collateral(vault_address, self.wbtc_token.read());
            let debt = vesu_pool.get_user_debt(vault_address, self.usdc_token.read());

            let collateral_usd = collateral;
            let debt_usd = debt;

            let health = if debt_usd.low == 0 && debt_usd.high == 0 {
                u256 { low: 0, high: 0 }
            } else {
                let mut health_val: u256 = u256 { low: 0, high: 0 };
                if collateral_usd.high == 0 && debt_usd.high == 0 {
                    health_val = u256 {
                        low: (collateral_usd.low * 100) / debt_usd.low,
                        high: 0
                    };
                }
                health_val
            };

            (collateral_usd, debt_usd, health)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn compute_commitment(
            self: @ContractState,
            owner: ContractAddress,
            amount: u256,
            salt: felt252,
        ) -> felt252 {
            let mut inputs: Array<felt252> = ArrayTrait::new();
            inputs.append(owner.into());
            inputs.append(amount.low.into());
            inputs.append(amount.high.into());
            inputs.append(salt);
            poseidon_hash_span(inputs.span())
        }

        fn compute_nullifier(self: @ContractState, owner: ContractAddress, amount: u256) -> felt252 {
            let mut inputs: Array<felt252> = ArrayTrait::new();
            inputs.append(owner.into());
            inputs.append(amount.low.into());
            inputs.append(amount.high.into());
            poseidon_hash_span(inputs.span())
        }

        fn generate_salt(self: @ContractState, owner: ContractAddress, amount: u256) -> felt252 {
            let count = self.commitment_count.read();
            let mut inputs: Array<felt252> = ArrayTrait::new();
            inputs.append(owner.into());
            inputs.append(amount.low.into());
            inputs.append(amount.high.into());
            inputs.append(count.into());
            poseidon_hash_span(inputs.span())
        }

        fn update_merkle_root(
            self: @ContractState,
            commitment: felt252,
            index: u64,
        ) -> felt252 {
            let current_root = self.merkle_root.read();
            if current_root == 0 {
                return commitment;
            }
            let mut inputs: Array<felt252> = ArrayTrait::new();
            inputs.append(current_root);
            inputs.append(commitment);
            poseidon_hash_span(inputs.span())
        }
    }
}
