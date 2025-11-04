# RWA contracts inventory (now) — mapped to this repo

This document maps the current product inventory to actual Solidity files (or marks items as planned if not present), to keep engineering, product, and DevOps in sync.

Last updated: 2025-11-01

## 1) Core Money & Treasury Layer

A. Asset-Backed Stablecoin Stack
- CompliantStable.sol — Planned (spec complete)
- StablecoinPolicyEngine.sol — Planned
- ReserveManager.sol — Present → `contracts/mica/ReserveManager.sol` and `contracts/reserves/ReserveVault.sol`
- NAVRebaseController.sol — Planned
- FeeRouter.sol — Planned

B. T-Bills / Notes / ETFs Access (Vaults & Wrappers)
- TreasuryBillVault4626.sol — Planned (4626 present for OZ in libs; no local implementation yet)
- EtfShareVault4626.sol — Planned
- AuctionReceiptNFT.sol — Planned
- ProofOfReserveRegistry.sol — Present → `contracts/ReserveProofRegistry.sol`

## 2) Securities / Compliance (Institutional)

A. Security Tokens & Tranches
- ERC1400_CompliantSecurity.sol — Baseline present via interfaces → `contracts/erc1400/interfaces/*`; concrete token examples:
  - `contracts/token/RWASecurityToken.sol`
  - `contracts/token/InstitutionalEMTUpgradeable.sol`
- ERC3525_TrancheNote.sol — Planned
- TransferGate.sol — Planned (policy present via `contracts/policy/PolicyGuard.sol` and `contracts/compliance/*`)
- ComplianceRegistryUpgradeable.sol — Present → `contracts/compliance/ComplianceRegistryUpgradeable.sol`

B. Attestations & Disclosures
- AttestationRegistry.sol — Present → `contracts/attest/AttestationRegistry.sol`
- DisclosureHub.sol — Planned

## 3) RWA Title, Vaults & Escrows

A. Title & Vault
- VaultProofNFT.sol — Present → `contracts/rwa/RWAVaultNFT.sol`
- TokenBoundVault6551.sol — Planned
- RwaRegistry.sol — Planned

B. Atomic Settlement
- DvPEscrow.sol — Present (multi-asset escrow) → `contracts/escrow/MultiAssetEscrow.sol`
- PvPEscrow.sol — Planned
- LienManager.sol — Planned

## 4) Insurance / Surety / SBLC
- InsurancePolicyNFT.sol — Present → `contracts/insurance/InsurancePolicyNFT.sol`
- SuretyBond1400.sol — Planned (baseline ERC-1400 interfaces present)
- SBLCInstrument.sol — Planned
- ClaimEscrow.sol — Planned

## 5) Commodities & Precious Metals
- GoldBarNFT.sol — Planned (vault/title NFT present as `RWAVaultNFT.sol`)
- XAUVault4626.sol — Planned
- CommodityBasket1400.sol — Planned

## 6) Carbon / Water / Real Estate / Mining
- CarbonCredit1155.sol — Planned
- WaterRightsNFT.sol — Planned
- RealPropertyDeed721.sol — Planned
- MineralRoyalty1400.sol — Planned

## 7) Oracles, Risk & Governance
- OracleHub.sol — Present across modules:
  - `contracts/oracle/AttestationOracle.sol`
  - `contracts/oracle/NAVEventOracle.sol`
  - `contracts/oracle/NAVEventOracleUpgradeable.sol`
  - `contracts/oracle/OracleCommittee.sol`
  - `contracts/oracle/adapters/*` (Chainlink/Pyth/Hybrid)
- PriceSanityLib.sol — Planned (bounded moves present implicitly in circuit breakers policy)
- ShockLimiter.sol — Planned (see `contracts/ops/PolicyCircuitBreaker.sol` for circuit-breaks)
- PauseGuardian.sol — Planned (policy breaker exists)
- AccessManager.sol — Planned (roles via AccessControl used across contracts)

## 8) Cross-Chain & Settlement Rails
- CCIPBridgeAdapter.sol — Related present → `contracts/bridge/CCIPAttestationSender.sol`
- LayerZeroOFTAdapter.sol — Planned
- RLNAdapter.sol — Planned
- FnalityAdapter.sol — Planned

## Additional modules present in repo
- ISO 20022 events → `contracts/iso20022/ISO20022EventEmitter.sol`, `contracts/utils/ISO20022Emitter.sol`
- Governance roles → `contracts/governance/PolicyRoles.sol`
- Compliance policy engine (upgradeable) → `contracts/compliance/PolicyEngineUpgradeable.sol`
- Reporting → `contracts/reporting/CustodianNavReporter.sol`
- Reserves adapters → `contracts/reserves/adapters/TBillInventoryAdapter.sol`

## Notes
- ERC-1400 interfaces are present; full-featured partitioned implementations are planned.
- Stablecoin upgradeable (InstitutionalEMTUpgradeable) present; policy engine wired.
- Some OZ v5 path shifts require either (a) project-wide import updates, or (b) small compatibility shims (which we added) to compile on Windows with Foundry.
