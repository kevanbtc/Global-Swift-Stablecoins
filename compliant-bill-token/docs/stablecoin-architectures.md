# Stablecoin Architectures — Senior-Level Overview

This suite provides reference implementations for the major stablecoin infrastructures without copying any proprietary code. Use these as production-grade starting points and wire your custody/oracles/policies via the adapter seams.

## Archetypes

1) Fiat Custodial (e-money / EMT)
- Contract: `FiatCustodialStablecoinUpgradeable`
- Infra: Off-chain custodial fiat/reserves; on-chain mint/burn via cashier; KYC/AML gating via `ComplianceRegistryUpgradeable`; Reserve ratio guard via NAV oracle; ISO 20022 events for audit.
- Key modules: UUPS proxy, role-based ops, pause, reserve ratio guard, policy gates.

2) RWA Bill/Rebasing Token (asset-referenced / ART)
- Contract: `RebasedBillToken`
- Infra: NAV-driven rebasing index with reserve and CAR guards; jurisdiction/policy gates; travel rule optional; ISO events.
- Key modules: Shares/index supply model, `BaselCARModule`, `ComplianceRegistryUpgradeable`, `IReserveOracle`.

3) Crypto-Collateralized (CDP/Vault engine)
- Contract: `CollateralizedStablecoin`
- Infra: Per-asset collateral types, price oracle, debt ceilings; vaults per user/asset; mint/burn with safety checks; liquidation entrypoint for keepers.
- Key modules: `IPriceOracle`, safety math, keeper liquidation.

## Integration Seams

- Compliance: `ComplianceRegistryUpgradeable` accepts attestor-set profiles and policy IDs. Replace with your TBAC stack or integrate EIP-712 attestations.
- Oracles: `IReserveOracle` (fiat/RWA) and `IPriceOracle` (crypto) are small interfaces; plug in Chainlink, CCIP pull, or your aggregator.
- Capital Adequacy: `BaselCARModule` tracks liabilities and eligible reserves; extend adapters to your reserve catalogs and risk weights.
- Audit Trail: `ISO20022Emitter` emits pacs.009 and camt.053 style events with doc hashes and URIs.

## Operations

- UUPS Upgrades: All upgradeable contracts restrict `_authorizeUpgrade` to `DEFAULT_ADMIN_ROLE`. Pair with a timelock in production.
- Roles: `ADMIN_ROLE` for parameters and pause; `CASHIER_ROLE` for mint/burn (fiat), `REBASE_ROLE` for index changes (rebasing), `KEEPER_ROLE` for liquidations (crypto).
- Risk Controls: Min reserve ratio; CAR floor; per-asset debt ceilings; liquidation ratios; penalties.

## Testing

- Unit tests cover:
  - Fiat EMT: KYC gating + reserve guard mint/burn
  - RWA Bill: mint + rebase + guards
  - Crypto CDP: collateral listing, safe mint, unsafe prevented

Extend with fuzz/property tests, oracle staleness checks, and pause/role boundary tests.

## Deployment Notes

- Configure compiler 0.8.24 and OZ v5 upgradeable.
- Verify implementations on Etherscan and store proxy admin ownership in a safe/DAO with timelocks.
- For multi-chain, standardize interfaces and use CCIP or a canonical bridge only for attestations (never mint cross-chain without strong controls).
