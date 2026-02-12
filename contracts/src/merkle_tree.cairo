use starknet::get_block_timestamp;
use starknet::ContractAddress;

const TREE_DEPTH: u32 = 20;

/// Incremental Merkle tree for storing commitments
/// Only stores the root hash on-chain, full tree maintained off-chain
#[starknet::contract]
mod MerkleTree {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::get_block_timestamp;

    #[storage]
    struct Storage {
        levels: Map<(u32, u64), felt252>,
        next_index: u64,
        zero_values: Map<u32, felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        LeafInserted: LeafInserted,
    }

    #[derive(Drop, starknet::Event)]
    struct LeafInserted {
        index: u64,
        leaf: felt252,
        root: felt252,
    }

    /// Initialize Merkle tree with zero values
    fn constructor(ref self: ContractState) {
        self.zero_values.write(0, 0);
        let mut current = 0;
        for i in 1..=TREE_DEPTH {
            current = poseidon_hash_2(current, current);
            self.zero_values.write(i, current);
        }
    }

    /// Insert a new leaf into the Merkle tree
    /// Returns the new root hash
    fn insert(ref self: ContractState, leaf: felt252) -> felt252 {
        let index = self.next_index.read();
        
        // Store leaf at level 0
        self.levels.write((0, index), leaf);
        
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
            
            let sibling = self.levels.read((level, sibling_index));
            let zero_val = self.zero_values.read(level);
            let sibling_hash = if sibling == 0 { zero_val } else { sibling };
            
            // Compute parent hash
            current_hash = if is_right {
                poseidon_hash_2(sibling_hash, current_hash)
            } else {
                poseidon_hash_2(current_hash, sibling_hash)
            };
            
            // Move to parent level
            current_index = current_index / 2;
            self.levels.write((level + 1, current_index), current_hash);
        }
        
        self.next_index.write(index + 1);
        
        let root = current_hash;
        self.emit(LeafInserted { index, leaf, root });
        root
    }

    /// Get the current root hash of the Merkle tree
    fn get_root(self: @ContractState) -> felt252 {
        if self.next_index.read() == 0 {
            self.zero_values.read(TREE_DEPTH)
        } else {
            self.levels.read((TREE_DEPTH, 0))
        }
    }

    /// Get Merkle proof for a given leaf index
    /// Returns array of sibling hashes along the path to root
    fn get_proof(self: @ContractState, index: u64) -> Array<felt252> {
        let mut proof = ArrayTrait::new();
        let mut current_index = index;
        
        for level in 0..TREE_DEPTH {
            let sibling_index = if current_index % 2 == 0 {
                current_index + 1
            } else {
                current_index - 1
            };
            
            let sibling = self.levels.read((level, sibling_index));
            let zero_val = self.zero_values.read(level);
            let sibling_hash = if sibling == 0 { zero_val } else { sibling };
            
            proof.append(sibling_hash);
            current_index = current_index / 2;
        }
        
        proof
    }

    /// Verify a Merkle proof
    /// Returns true if the proof is valid
    fn verify_proof(
        self: @ContractState,
        leaf: felt252,
        proof: Span<felt252>,
        indices: Span<u64>,
        root: felt252
    ) -> bool {
        let mut current = leaf;
        
        let proof_len = proof.len();
        assert(proof_len == TREE_DEPTH, "Invalid proof length");
        
        for i in 0..TREE_DEPTH {
            let sibling = *proof.at(i);
            let is_right = *indices.at(i) == 1;
            
            current = if is_right {
                poseidon_hash_2(sibling, current)
            } else {
                poseidon_hash_2(current, sibling)
            };
        }
        
        current == root
    }

    /// Get the next available leaf index
    fn get_next_index(self: @ContractState) -> u64 {
        self.next_index.read()
    }

    /// Poseidon hash function for two inputs
    /// Uses Pedersen hash as Poseidon equivalent for Starknet
    fn poseidon_hash_2(a: felt252, b: felt252) -> felt252 {
        starknet::pedersen_hash(a, b)
    }
}

/// Library for Merkle tree operations
/// Can be used by other contracts
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
