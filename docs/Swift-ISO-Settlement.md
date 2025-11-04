# Swift/ISO 20022-aligned settlement modules

This directory maps the on-chain primitives we added to the “new digital Swift” architecture and shows how they fit into your institutional stack.

## Modules and roles

- Compliance
  - `contracts/compliance/KYCRegistry.sol`: on-chain registry of approved parties with jurisdiction/risk tier metadata.
  - `contracts/compliance/SanctionsOracleDenylist.sol`: simple denylist; swap for a TRM/Chainalysis adapter later.
  - `contracts/compliance/ComplianceModuleRBAC.sol`: pluggable compliance gate (KYC + sanctions + asset allowlist) implementable behind any workflow.

- ISO 20022 binding
  - `contracts/iso20022/Iso20022Bridge.sol`: binds an on-chain `id` to ISO 20022 envelope hashes and emits canonical events for indexers/audit. Use `uetr` and `payloadHash` to link to your off-chain golden copy.

- Rails (value movement abstraction)
  - `contracts/settlement/rails/IRail.sol`: common interface (ERC20, native, external rails) with two‑phase prepare/release.
  - `contracts/settlement/rails/ERC20Rail.sol`: escrow + release ERC‑20 tokens.
  - `contracts/settlement/rails/NativeRail.sol`: escrow + release native coin with msg.value.
  - `contracts/settlement/rails/ExternalRail.sol`: stub for RTGS/Swift/shared‑ledger legs; a trusted `executor` posts receipts via `markReleased/markRefunded`.
  - `contracts/settlement/rails/RailRegistry.sol`: registry keyed by `keccak256("RAIL_*")` for rails discovery.

- Orchestration
  - `contracts/settlement/SettlementHub2PC.sol`: two‑phase commit hub across two rails (on→on, on→off). `open → prepareA/B → finalize` or `cancel/expire`.
  - `contracts/settlement/FxPvPRouter.sol`: price‑checked PvP using `contracts/oracle/IPriceOracle.sol` to cap slippage before preparing both legs.
  - `contracts/settlement/SrCompliantDvP.sol`: upgradeable DvP/PvP router with KYC/sanctions hooks and ISO‑friendly events; use when both legs are on‑chain.
  - `contracts/settlement/NettingPool.sol`: simple bilateral executor for ERC‑20 netting batches.
  - `contracts/settlement/MilestoneEscrow.sol`: multi‑milestone ERC‑20 escrow with dual approvals and refund path.

## How it lines up with “digital Swift”

- Transaction Manager / golden copy
  - Keep your ISO envelope off‑chain (UETR/endToEndId). Hash it and bind via `Iso20022Bridge.bind(...)`; correlate events from `SrCompliantDvP` or `SettlementHub2PC` by `id`/`uetr`.

- Shared ledger / external rails
  - For fiat or permissioned shared‑ledger legs, use `ExternalRail` and have an off‑chain service call `markReleased/markRefunded` once a receipt is verified.

- Instant / domestic handoff
  - For on‑chain ↔ on‑chain, use `ERC20Rail`/`NativeRail` + `SettlementHub2PC`. For on‑chain ↔ bank rail, pair `ERC20Rail` with `ExternalRail`.

- Controls (CSP, sanctions, screening)
  - Gate operations with `ComplianceModuleRBAC` + `SanctionsOracleDenylist`. Replace the denylist with a production sanctions oracle as needed.

## Quick start

- Foundry deploy script: `script/DeploySettlement.s.sol` deploys KYC, sanctions, compliance module, ISO bridge, rails/registry, and the 2PC hub.
- Smoke test: `foundry/test/SettlementSmoke.t.sol` covers a minimal ERC‑20 rail prepare→release flow.

## Design notes

- Solidity `0.8.24`, via‑IR enabled; OpenZeppelin upgradeable libs are imported from `lib/openzeppelin-contracts-upgradeable` for Hardhat/Foundry compatibility.
- Interfaces are minimal and local to avoid dependency sprawl; swap implementations behind those interfaces per environment.
- Events are ISO‑friendly (UETR/endToEndId hashes) to make audit/trace straightforward.
