# VestaZK Roadmap

A privacy-preserving lending vault on Starknet - preventing liquidation hunting via ZK proofs.

## Project Overview

**Timeline**: Hackathon (Feb 1-28, 2026)  
**Track**: Starknet Re{define}  
**Goal**: Build a lending vault that protects users from liquidation hunting while maintaining privacy

---

## Phase 1: Foundation ✅ (COMPLETED)

### Tasks Completed
- [x] Fork starknet-privacy-toolkit
- [x] Clean commit history  
- [x] Update project metadata (package.json, README)
- [x] Create documentation (SETUP.md, ARCHITECTURE.md)

---

## Phase 2: Vesu Integration ✅ (COMPLETED)

### Tasks Completed
- [x] Create VesuVault contract structure
- [x] Implement deposit with Poseidon commitments
- [x] Integrate with Vesu pool (supply/borrow)
- [x] Implement Merkle tree for commitments
- [x] Contract compiles successfully

---

## Phase 3: ZK Circuit ✅ (COMPLETED)

### Tasks Completed
- [x] Create lending_proof Noir circuit
- [x] Implement health factor verification
- [x] Add Merkle proof verification
- [x] Implement nullifier system
- [x] Circuit tests passing (2/2)
- [x] Add generate-verifier.sh script

---

## Phase 4: Contract Integration ✅ (COMPLETED)

### Tasks Completed
- [x] Add borrow_with_proof function with ZK verification
- [x] Implement nullifier system
- [x] Add emergency_exit function (2% fee)
- [x] Integrate with Garaga verifier
- [x] Deploy to Sepolia testnet

### Deployed Contracts
| Contract | Address | Network |
|----------|---------|---------|
| VesuVault | `0x04997bb4f992a6c9918030b34947fcc2bc73ce0068e9077a6b07c0abce40baaf` | Sepolia |

---

## Phase 5: Frontend Services ✅ (COMPLETED)

### Tasks Completed
- [x] Create vestazk-service.ts (contract interactions)
- [x] Create pragma-service.ts (price oracle)
- [x] Build complete frontend UI

---

## Phase 6: Finalization ✅ (COMPLETED)

### Tasks Completed
- [x] Build complete frontend UI (vestazk.html)
- [x] Add commitment storage (localStorage)
- [x] Integrate wallet connection
- [x] Update documentation

---

## Project Summary

| Component | Status | Location |
|-----------|--------|----------|
| VesuVault Contract | ✅ Deployed | `contracts/src/vesu_vault.cairo` |
| Lending Proof Circuit | ✅ Ready | `zk-badges/lending_proof/` |
| Frontend Services | ✅ Complete | `src/vestazk-service.ts`, `src/pragma-service.ts` |
| Frontend UI | ✅ Complete | `src/web/vestazk.html` |

---

## Next Steps (Post-Hackathon)

1. **Deploy Verifier**: Run `./scripts/generate-verifier.sh` in Codespace
2. **Configure Vault**: Set WBTC, USDC, VesuPool addresses
3. **Add Real Proof Generation**: Integrate client-side Noir + Barretenberg
4. **Mainnet Deployment**: Audit contracts before mainnet

---

## Resources

- **GitHub**: https://github.com/anumukul/vestazk
- **Live Demo**: https://starknet-privacy-toolkit.vercel.app/
- **Documentation**: See docs/ folder

---

**Built with ❤️ on Starknet**  
VestaZK - Privacy-Preserving Lending Vault
