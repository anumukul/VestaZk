use starknet::testing::{set_caller_address, set_contract_address};
use starknet::ContractAddress;
use starknet::contract_address_const;

use vestazk_vault::vault::{VaultDispatcher, VaultDispatcherTrait};
use vestazk_vault::interfaces::IERC20DispatcherTrait;

#[test]
fn test_get_merkle_root_initialized() {
    let vault = create_vault_dispatcher();
    let root = vault.get_merkle_root();
    assert(root != 0, 'Root should be initialized');
}

#[test]
fn test_get_merkle_next_index_starts_at_zero() {
    let vault = create_vault_dispatcher();
    let next = vault.get_merkle_next_index();
    assert(next == 0, 'Next index should start at 0');
}

#[test]
fn test_get_total_deposited_initialized() {
    let vault = create_vault_dispatcher();
    let total = vault.get_total_deposited();
    assert(total == 0, 'Total deposited should start at 0');
}

#[test]
fn test_get_total_borrowed_initialized() {
    let vault = create_vault_dispatcher();
    let total = vault.get_total_borrowed();
    assert(total == 0, 'Total borrowed should start at 0');
}

#[test]
fn test_get_commitment_count_initialized() {
    let vault = create_vault_dispatcher();
    let count = vault.get_commitment_count();
    assert(count == 0, 'Commitment count should start at 0');
}

#[test]
fn test_pause_and_resume() {
    let vault = create_vault_dispatcher();
    let owner = contract_address_const::<0x999>();
    set_caller_address(owner);

    vault.pause();
    vault.resume();
}

#[test]
fn test_get_merkle_proof_empty_tree() {
    let vault = create_vault_dispatcher();
    let (path, indices) = vault.get_merkle_proof(0);
    assert(path.len() == 20, 'Path should have TREE_DEPTH elements');
    assert(indices.len() == 20, 'Indices should have TREE_DEPTH elements');
}

fn create_vault_dispatcher() -> VaultDispatcher {
    let wbtc = contract_address_const::<0x111>();
    let usdc = contract_address_const::<0x222>();
    let vesu_pool = contract_address_const::<0x333>();
    let verifier = contract_address_const::<0x444>();
    let oracle = contract_address_const::<0x555>();
    let owner = contract_address_const::<0x999>();
    let vault_address = contract_address_const::<0xAAA>();
    VaultDispatcher { contract_address: vault_address }
}
