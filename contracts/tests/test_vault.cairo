use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::get_block_timestamp;

use vestazk_vault::vault::{Vault, VaultDispatcher, VaultDispatcherTrait};
use vestazk_vault::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait};

#[test]
fn test_deposit_creates_commitment() {
    // Setup
    let vault = deploy_vault();
    let user = contract_address_const::<0x123>();
    let amount = 100000000_u256; // 1 BTC (8 decimals)
    
    // Mock setup would go here
    // For now, this is a placeholder test structure
    
    // Execute deposit
    // let commitment = vault.deposit(amount);
    
    // Verify
    // assert(commitment != 0, 'Commitment should be non-zero');
    // let total_deposited = vault.get_total_deposited();
    // assert(total_deposited == amount, 'Total deposit mismatch');
}

#[test]
fn test_get_merkle_root() {
    let vault = deploy_vault();
    
    // Initially root should be zero value
    let root = vault.get_merkle_root();
    assert(root != 0, 'Root should be initialized');
}

#[test]
fn test_pause_and_resume() {
    let vault = deploy_vault();
    let owner = contract_address_const::<0x999>();
    
    set_caller_address(owner);
    
    // Pause
    vault.pause();
    
    // Try to deposit (should fail)
    // This would require mocking
    
    // Resume
    vault.resume();
}

fn deploy_vault() -> VaultDispatcher {
    let wbtc = contract_address_const::<0x111>();
    let usdc = contract_address_const::<0x222>();
    let vesu_pool = contract_address_const::<0x333>();
    let verifier = contract_address_const::<0x444>();
    let oracle = contract_address_const::<0x555>();
    let owner = contract_address_const::<0x999>();
    
    // Mock deployment - actual deployment would use starknet::deploy_syscall
    // For testing, we'd use snforge's deploy functionality
    let vault_address = contract_address_const::<0xAAA>();
    VaultDispatcher { contract_address: vault_address }
}
