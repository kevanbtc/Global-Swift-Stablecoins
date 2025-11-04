# Regulatory-Compliant Stablecoin Templates

This repository contains smart contract templates for building regulatory-compliant stablecoins and CBDCs that support:

- Basel III/IV capital adequacy requirements
- ISO 20022 payment messages and attestations
- MiCA/SEC/MAS/DFSA regulatory frameworks
- FATF Travel Rule compliance
- Proof of Reserves (PoR) and solvency checks

## Core Components

### 1. RebasedBillToken

A compliant, upgradeable token with:

- KYC-gated transfers
- Capital adequacy checks
- ISO 20022 event emission
- Proof of Reserves validation
- Travel Rule hooks
- Rebase functionality for yield distribution

### 2. ComplianceRegistry

Manages jurisdictional policies and investor profiles:

- KYC/AML status tracking
- Professional investor flags
- Geographic restrictions (US/EU/SG/etc.)
- MiCA EMT/ART classifications
- Reg D/Reg S flags

### 3. BaselCARModule

Enforces Basel-style capital requirements:

- Risk-weighted assets (RWA) calculation
- Capital Adequacy Ratio (CAR) floors
- Eligible reserve tracking
- Liability monitoring

### 4. ISO20022Emitter

Standardized financial messaging:

- pacs.009 for fund transfers
- camt.053 for statements
- URI + hash linking for full payloads

## Installation

\`\`\`bash
npm install
\`\`\`

## Quick Start

1. Deploy contracts:
\`\`\`bash
npx hardhat run scripts/deploy.js
\`\`\`

2. Configure your compliance policy:
\`\`\`solidity
registry.setPolicy(policyId, {
    allowUS: true,
    allowEU: true,
    regD506c: true,
    micaART: true,
    proOnly: true,
    travelRuleRequired: true
});
\`\`\`

3. Set up KYC profiles:
\`\`\`solidity
registry.setProfile(user, {
    kyc: true,
    accredited: true,
    kycAsOf: timestamp,
    kycExpiry: expiryTime,
    isoCountry: "US",
    frozen: false
});
\`\`\`

## Operational Checklist

1. ISO 20022 Pipeline:
   - Set up document generation for pacs.009/camt.053
   - Configure IPFS/S3 storage for payloads
   - Set up hash + URI emission

2. KYC/Profiles:
   - Regular KYC reverification (90d/365d)
   - Professional investor validation
   - Jurisdiction updates
   - Sanctions screening (OFAC/EU/UN)

3. Basel/Reserves:
   - Daily PoR attestations
   - Asset eligibility checks
   - RWA calculations
   - NAV/liability reconciliation

4. Travel Rule:
   - TRP message generation
   - Off-chain permit validation
   - On-chain attestation posting

## Security & Upgradeability

- UUPS proxy pattern for upgradeability
- Role-based access control
- Circuit breakers and pause functionality
- Freshness checks for oracles
- Solvency guards on mint/rebase

## Dependencies

- OpenZeppelin Contracts Upgradeable v5.0.0
- Hardhat development environment
- TypeScript support
