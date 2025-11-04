# 🌐 Unykorn Layer 1 Infrastructure

<div align="center">

![Unykorn Logo](docs/assets/logo.png)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.19-363636)
![TypeScript](https://img.shields.io/badge/TypeScript-5.0-3178C6)
![TVL](https://img.shields.io/badge/TVL-$246M+-success)
![RWA](https://img.shields.io/badge/RWA-$222M+-blue)

*Institutional-grade blockchain infrastructure for global financial markets*

</div>

## 📚 Table of Contents

- [Overview](#-overview)
- [Key Metrics](#-key-metrics)
- [Core Infrastructure](#-core-infrastructure)
- [System Architecture](#-system-architecture)
- [Contract Documentation](#-contract-documentation)
- [Quick Start](#-quick-start)
- [Development](#-development)
- [Testing](#-testing)
- [Deployment](#-deployment)
- [Security](#-security)
- [Contributing](#-contributing)
- [License](#-license)

## 🌟 Overview

Unykorn Layer 1 is a comprehensive Besu-based permissioned EVM blockchain (Chain ID 7777) designed for institutional finance. It integrates:

- 🏦 SWIFT/ISO 20022 compliance
- 💱 Multi-rail settlement systems
- 💎 RWA tokenization
- 🔐 Quantum-resistant security
- 🤖 AI-enhanced monitoring
- ⚖️ Full regulatory compliance

Our infrastructure supports:
- Basel III/IV capital adequacy requirements
- ISO 20022 payment messages and attestations
- MiCA/SEC/MAS/DFSA regulatory frameworks
- FATF Travel Rule compliance
- Proof of Reserves (PoR) and solvency checks

## 📊 Key Metrics

| Metric | Value | Status |
|--------|-------|--------|
| Chain ID | 7777 | ✅ Active |
| Smart Contracts | 170+ | ✅ Deployed |
| TVL | $246M+ | 📈 Growing |
| RWA Portfolio | $222M+ | 🏢 8 Assets |
| Validators | 21 | 🔄 Expandable to 100 |
| TPS | 500-1,000 | ⚡ Peak 5,000+ |

## 🏗 Core Components

### Stablecoin Infrastructure

A compliant, upgradeable token ecosystem with:

- KYC-gated transfers
- Capital adequacy checks
- ISO 20022 event emission
- Proof of Reserves validation
- Travel Rule hooks
- Rebase functionality for yield distribution

### Compliance Framework

Manages jurisdictional policies and investor profiles:

- KYC/AML status tracking
- Professional investor flags
- Geographic restrictions (US/EU/SG/etc.)
- MiCA EMT/ART classifications
- Reg D/Reg S flags

### Capital Requirements

Enforces Basel-style capital requirements:

- Risk-weighted assets (RWA) calculation
- Capital Adequacy Ratio (CAR) floors
- Eligible reserve tracking
- Liability monitoring

### Settlement Infrastructure

Multi-rail settlement system:

- SWIFT GPI integration
- BIS Agorá compatibility
- RLN Multi-CBDC support
- Fnality settlement integration

## 🚀 Quick Start

### Prerequisites

- Node.js ≥ 16
- Hardhat
- Foundry
- Besu Client

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/unykorn-l1.git
cd unykorn-l1

# Install dependencies
npm install

# Copy environment file
cp .env.example .env
```

### Initial Setup

1. Configure your environment:
```bash
# Start local node
npm run node

# Deploy contracts
npm run deploy:local
```

2. Set up compliance policy:
```typescript
await registry.setPolicy(policyId, {
    allowUS: true,
    allowEU: true,
    regD506c: true,
    micaART: true,
    proOnly: true,
    travelRuleRequired: true
});
```

3. Configure KYC profiles:
```typescript
await registry.setProfile(user, {
    kyc: true,
    accredited: true,
    kycAsOf: timestamp,
    kycExpiry: expiryTime,
    isoCountry: "US",
    frozen: false
});
```

## 📋 Operational Checklist

### ISO 20022 Integration

- [ ] Set up document generation for pacs.009/camt.053
- [ ] Configure IPFS/S3 storage for payloads
- [ ] Set up hash + URI emission

### Compliance Pipeline

- [ ] Regular KYC reverification (90d/365d)
- [ ] Professional investor validation
- [ ] Jurisdiction updates
- [ ] Sanctions screening (OFAC/EU/UN)

### Risk Management

- [ ] Daily PoR attestations
- [ ] Asset eligibility checks
- [ ] RWA calculations
- [ ] NAV/liability reconciliation

### Regulatory Reporting

- [ ] TRP message generation
- [ ] Off-chain permit validation
- [ ] On-chain attestation posting
- [ ] Regulatory reporting automation

## 🛡 Security Features

- UUPS proxy pattern for upgradeability
- Role-based access control (RBAC)
- Circuit breakers and pause functionality
- Freshness checks for oracles
- Solvency guards on mint/rebase
- Quantum-resistant cryptography
- AI-enhanced monitoring

## 🔧 Development Tools

### Core Dependencies

- Solidity ^0.8.19
- OpenZeppelin 4.9.0
- Hardhat/Foundry
- TypeScript 5.0
- Besu Client

### Testing Framework

```bash
# Run unit tests
npm run test

# Run integration tests
npm run test:integration

# Generate coverage report
npm run coverage
```

### Deployment

```bash
# Deploy to testnet
npm run deploy:testnet

# Deploy to mainnet
npm run deploy:mainnet
```

## 📚 Documentation

- [System Architecture](docs/SYSTEM_ARCHITECTURE.md)
- [Contract Inventory](docs/CONTRACT_INVENTORY.md)
- [Deployment Guide](docs/DEPLOYMENT_STATUS.md)
- [Security Overview](docs/security.md)
- [API Reference](docs/api-reference.md)
- [Integration Guide](docs/integration.md)

## 🤝 Contributing

Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a pull request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
