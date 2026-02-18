// Stub verifier for VestaZk borrow proof.
// Replace this with the Garaga-generated verifier by running:
//   cd circuits/borrow_proof && nargo compile && bb write_vk ...
//   garaga gen --system ultra_keccak_honk --vk <path> --output ../../contracts/src/verifier.cairo

use vestazk_vault::interfaces::IVerifier;

#[starknet::contract]
mod Verifier {
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    /// Verifies a ZK proof. Stub implementation always returns true.
    /// Replace this contract with Garaga-generated verifier for production.
    #[abi(embed_v0)]
    impl VerifierImpl of IVerifier<ContractState> {
        fn verify_proof(
            self: @ContractState,
            proof: Span<felt252>,
            public_inputs: Span<felt252>
        ) -> bool {
            true
        }
    }
}
