# Project Index

A curated, repo-ready index of the codebase, grouped by domains with deep links to actual files. Planned modules that aren’t yet present are called out separately at the end.

## On-chain smart contracts

- Core types and roles
  - `contracts/common/Errors.sol`
  - `contracts/common/ISO20022Events.sol`
  - `contracts/common/Roles.sol`
  - `contracts/common/Types.sol`

- Compliance & policy
  - `contracts/compliance/ComplianceRegistryUpgradeable.sol`
  - `contracts/compliance/PolicyEngineUpgradeable.sol`
  - `contracts/policy/PolicyGuard.sol`
  - `contracts/ops/PolicyCircuitBreaker.sol`

- Tokenization
  - `contracts/token/RWASecurityToken.sol`
  - `contracts/token/RWASecurityTokenSnapshot.sol`
  - `contracts/token/InstitutionalEMTUpgradeable.sol`
  - ERC-1400 interfaces: `contracts/erc1400/interfaces/IERC1400.sol`, `IERC1410.sol`, `IERC1594.sol`, `IERC1400Document.sol`, `IERC1400Controller.sol`

- Stablecoin & reserves
  - `contracts/stable/StableUSD.sol`
  - `contracts/mica/ReserveManager.sol`
  - `contracts/mica/ReserveManagerUpgradeable.sol`
  - `contracts/reserves/ReserveVault.sol`
  - `contracts/reserves/adapters/TBillInventoryAdapter.sol`

- RWA & custody
  - `contracts/rwa/RWAVaultNFT.sol`
  - `contracts/reporting/CustodianNavReporter.sol`

- Oracles
  - `contracts/oracle/AttestationOracle.sol`
  - `contracts/oracle/NAVEventOracle.sol`
  - `contracts/oracle/NAVEventOracleUpgradeable.sol`
  - `contracts/oracle/OracleCommittee.sol`
  - `contracts/oracle/ShareMaturityOracleCatalog.sol`
  - Quote adapters: `contracts/oracle/adapters/ChainlinkQuoteAdapter.sol`, `HybridQuoteAdapter.sol`, `PythQuoteAdapter.sol`
  - Interfaces: `contracts/interfaces/IPriceOracle.sol`, `IShareMaturityOracle.sol`, `IAttestationOracle.sol`

- Distribution
  - `contracts/distribution/MerkleCouponDistributor.sol`
  - `contracts/distribution/MerkleStreamDistributor.sol`
  - `contracts/distribution/MerkleStreamDistributorUpgradeable.sol`

- Escrow & control
  - `contracts/escrow/MultiAssetEscrow.sol`
  - `contracts/controller/ERC1644Controller.sol`
  - `contracts/controller/CourtOrderRegistry.sol`

- Interop / ISO 20022
  - `contracts/iso20022/ISO20022EventEmitter.sol`
  - Utilities: `contracts/utils/ISO20022Emitter.sol`

- Bridge & attestations
  - `contracts/attest/AttestationRegistry.sol`
  - `contracts/bridge/CCIPAttestationSender.sol`

- Misc
  - `contracts/ReserveProofRegistry.sol`
  - `contracts/BootstrapExample.sol`
  - Governance: `contracts/governance/PolicyRoles.sol`
  - Insurance: `contracts/insurance/InsurancePolicyNFT.sol`
  - Risk: `contracts/risk/BaselCARModule.sol`

## Off-chain services & adapters (planned stubs)

- IBKR Adapter (Flask + ib-insync) — planned
- Attestation harvester — planned
- ISO 20022 bus — planned

## APIs & data (planned stubs)

- Treasury Catalog API — planned
- Trade API — planned
- DCX APIs — planned
- LiveDataService — planned
- News/Signals — planned

## AI Swarm (planned stubs)

- Coordinator and agents — planned

## Database & schema (planned stubs)

- Prisma models for stablecoins, RWAs, positions, compliance — planned

## Frontend calculators & ops UI (planned stubs)

- Pricing/yield calculator, ladder builder, shock analysis, ops panels — planned

## Security, compliance, & policy

- Gates and controls are enforced via:
  - `ComplianceRegistryUpgradeable` + `PolicyEngineUpgradeable`
  - `PolicyGuard` and `PolicyCircuitBreaker`
  - ERC-1400 interfaces for transfer restrictions (see `contracts/erc1400/interfaces/*`)

## DevOps & scripts

- Foundry config: `foundry.toml`
- Hardhat config: `hardhat.config.js`, `hardhat.config.ts`
- Scripts: `script/`, `scripts/`
- Tasks: `tasks/`

## Tests

- Foundry tests:
  - `test/Invariants.t.sol`
  - `test/ReserveProofRegistry.t.sol`
  - New invariant stubs under `test/invariants/` (see below)
- Hardhat tests:
  - `test/distribution/MerkleCouponDistributor.test.js`
  - `test/RegulatoryCompliantToken.test.js`

## How to run (Foundry)

Optional quick commands if you have Foundry installed:

```bash
forge build
forge test -q
```

If `forge` isn’t available, install via Foundryup (see <https://book.getfoundry.sh/getting-started/installation>).

## Planned modules not yet in repo

The following items from the product map are planned but not present as files yet. Their typical locations are shown for future implementation:

- ERC1400PartitionedSecurityToken (UUPS) — `contracts/security/ERC1400PartitionedSecurityToken.sol`
- ReserveVault4626Adapter (UUPS) — `contracts/vaults/ReserveVault4626Adapter.sol`
- PerformanceBondEscrowV2 — `contracts/credit/PerformanceBondEscrowV2.sol`
- RWARegistry — `contracts/rwa/RWARegistry.sol`
- AppraisalOracle — `contracts/oracle/AppraisalOracle.sol`
- NAVOracleRouter — `contracts/oracle/NAVOracleRouter.sol`
- USDOStablecoin (UUPS) — `contracts/stablecoin/USDOStablecoin.sol`
- CollateralReserve — `contracts/stablecoin/CollateralReserve.sol`
- TransferGate (policy lib) — `contracts/compliance/TransferGate.sol`
- ISO20022Codec/IsoEmitter — `contracts/interop/*`
- FeeManager/Waterfall — `contracts/fees/FeeManager.sol`
- GuardianControl/PauseGuardian — `contracts/control/GuardianControl.sol`

—

Last updated: 2025-11-01
