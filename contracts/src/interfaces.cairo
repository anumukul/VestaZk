use starknet::ContractAddress;

/// ERC20 token interface
#[starknet::interface]
trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(
        self: @TContractState,
        owner: ContractAddress,
        spender: ContractAddress
    ) -> u256;
}

/// Vesu pool interface for lending operations
#[starknet::interface]
trait IVesuPool<TContractState> {
    fn supply(
        ref self: TContractState,
        asset: ContractAddress,
        amount: u256
    );
    fn borrow(
        ref self: TContractState,
        asset: ContractAddress,
        amount: u256
    );
    fn withdraw(
        ref self: TContractState,
        asset: ContractAddress,
        amount: u256
    );
    fn repay(
        ref self: TContractState,
        asset: ContractAddress,
        amount: u256
    );
    fn get_user_collateral(
        self: @TContractState,
        user: ContractAddress,
        asset: ContractAddress
    ) -> u256;
    fn get_user_debt(
        self: @TContractState,
        user: ContractAddress,
        asset: ContractAddress
    ) -> u256;
    fn get_total_collateral(
        self: @TContractState,
        asset: ContractAddress
    ) -> u256;
    fn get_total_debt(
        self: @TContractState,
        asset: ContractAddress
    ) -> u256;
}

/// Pragma oracle interface for price feeds
#[starknet::interface]
trait IPragmaOracle<TContractState> {
    fn get_data_median(
        self: @TContractState,
        data_type: felt252
    ) -> PragmaPricesResponse;
}

#[derive(Drop, Serde, starknet::Store)]
struct PragmaPricesResponse {
    price: u256,
    decimals: u8,
    last_updated_timestamp: u64,
}

/// Verifier interface for ZK proof verification
#[starknet::interface]
trait IVerifier<TContractState> {
    fn verify_proof(
        self: @TContractState,
        proof: Span<felt252>,
        public_inputs: Span<felt252>
    ) -> bool;
}

/// Merkle tree interface
#[starknet::interface]
trait IMerkleTree<TContractState> {
    fn insert(ref self: TContractState, leaf: felt252) -> felt252;
    fn get_root(self: @TContractState) -> felt252;
    fn get_proof(self: @TContractState, index: u64) -> Array<felt252>;
    fn verify_proof(
        self: @TContractState,
        leaf: felt252,
        proof: Span<felt252>,
        indices: Span<u64>,
        root: felt252
    ) -> bool;
    fn get_next_index(self: @TContractState) -> u64;
}
