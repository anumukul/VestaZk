// Verifier adapter: forwards IVerifier::verify_proof to Garaga Honk verifier.

use core::result::ResultTrait;
use starknet::ContractAddress;
use vestazk_vault::interfaces::IVerifier;
use vestazk_verifier::honk_verifier::IUltraKeccakZKHonkVerifierDispatcher;
use vestazk_verifier::honk_verifier::IUltraKeccakZKHonkVerifierDispatcherTrait;

#[starknet::contract]
mod Verifier {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::{ContractAddress, IVerifier, IUltraKeccakZKHonkVerifierDispatcher, IUltraKeccakZKHonkVerifierDispatcherTrait, ResultTrait};

    #[storage]
    struct Storage {
        honk_verifier_address: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, honk_verifier_address: ContractAddress) {
        self.honk_verifier_address.write(honk_verifier_address);
    }

    #[abi(embed_v0)]
    impl VerifierImpl of IVerifier<ContractState> {
        fn verify_proof(
            self: @ContractState,
            proof: Span<felt252>,
            public_inputs: Span<felt252>
        ) -> bool {
            let honk = IUltraKeccakZKHonkVerifierDispatcher {
                contract_address: self.honk_verifier_address.read()
            };
            let result = honk.verify_ultra_keccak_zk_honk_proof(proof);
            result.is_ok()
        }
    }
}
