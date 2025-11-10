# Midnight.js Integration Guide

## Overview

This guide explains how to integrate Midnight blockchain capabilities into the Unykorn stablecoin and CBDC infrastructure using the Midnight.js framework.

## What is Midnight?

Midnight is a privacy-focused blockchain that enables:
- **Private Transactions**: Zero-knowledge proof-based privacy preservation
- **Selective Disclosure**: Controlled data sharing for compliance
- **Private State Management**: Off-chain private state with on-chain verification
- **Smart Contracts with Privacy**: Compact language for privacy-preserving contracts

## Midnight.js Framework

Midnight.js (v2.0.2) is similar to Web3.js for Ethereum or polkadot.js for Polkadot, providing:

### Core Packages

1. **types** - Common types and interfaces
2. **contracts** - Smart contract interaction utilities
3. **indexer-public-data-provider** - Indexer client for blockchain queries
4. **node-zk-config-provider** - Node.js zero-knowledge artifact retrieval
5. **fetch-zk-config-provider** - Cross-environment ZK artifact fetching
6. **network-id** - Network identification utilities
7. **http-client-proof-provider** - Proof server client
8. **level-private-state-provider** - Persistent private state storage

### Unique Capabilities

Unlike traditional blockchain frameworks, Midnight.js includes:
- Local smart contract execution
- Private state incorporation into contract execution
- Private state querying and updating
- Zero-knowledge proof creation and verification

## Integration Opportunities

### 1. Midnight Network Bridge Adapter

**Purpose**: Connect Midnight blockchain to your settlement rail infrastructure

**Benefits**:
- Private cross-chain settlements
- Selective disclosure for regulatory compliance
- Enhanced privacy for institutional transactions

**Location**: `contracts/midnight/MidnightSettlementAdapter.sol`

**Interfaces With**:
- `contracts/settlement/stable/StablecoinRouter.sol`
- `contracts/settlement/rails/RailRegistry.sol`
- `contracts/cbdc/CBDCIntegrationHub.sol`

### 2. Enhanced Privacy Layer

**Purpose**: Replace placeholder ZK verification with real Midnight.js proof verification

**Current**: `contracts/security/PrivacyLayer.sol` uses placeholder verification
**Enhancement**: Use Midnight.js proof server for actual ZK-SNARK verification

**Benefits**:
- Production-grade privacy transactions
- Real zero-knowledge proofs
- Compliance-friendly selective disclosure

### 3. Private State Management for Reserves

**Purpose**: Keep reserve asset details private while proving adequacy publicly

**Use Case**: Proof of Reserves without revealing:
- Specific asset locations
- Custody arrangements
- Real-time balances
- Trading strategies

**Integration Point**: `contracts/reserves/ReserveManager.sol`

### 4. Private Settlement Client

**Purpose**: TypeScript client for private institutional settlements

**Features**:
- Private transaction creation
- Zero-knowledge proof generation
- Wallet integration
- Private state synchronization

**Location**: `apps/midnight-settlement-client/`

### 5. CBDC Privacy Extension

**Purpose**: Add privacy features to CBDC implementation

**Benefits**:
- Private balance viewing (with audit capability)
- Anonymous small transactions (below threshold)
- Regulatory compliance with Travel Rule
- Suspicious activity monitoring without compromising privacy

**Integration**: `contracts/cbdc/CBDCPrivacyModule.sol`

### 6. Private Oracle Data

**Purpose**: Submit oracle data privately (prices, NAV, reserves)

**Benefits**:
- Prevent front-running
- Protect proprietary pricing models
- Enable gradual revelation
- Support time-locked data release

**Integration**: `contracts/oracle/MidnightOracleAdapter.sol`

## Implementation Architecture

### On-Chain Components (Solidity)

```
contracts/midnight/
├── MidnightBridge.sol              # Main bridge contract
├── MidnightSettlementRail.sol      # Settlement rail implementation
├── MidnightPrivacyModule.sol       # Privacy functionality
├── MidnightProofVerifier.sol       # ZK proof verification
└── interfaces/
    ├── IMidnightBridge.sol
    └── IMidnightProofVerifier.sol
```

### Off-Chain Components (TypeScript)

```
cli/midnight/
├── private-state-manager.ts        # Private state operations
├── proof-generator.ts              # ZK proof generation
├── midnight-client.ts              # Blockchain interaction
└── wallet-connector.ts             # Wallet integration

apps/midnight-client/
├── src/
│   ├── contracts/                  # Contract interaction
│   ├── private-state/              # State management
│   ├── proofs/                     # Proof handling
│   └── api/                        # Client API
└── package.json
```

## Integration Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [ ] Install Midnight.js dependencies
- [ ] Set up development environment
- [ ] Create basic bridge contract
- [ ] Implement proof verifier stub
- [ ] Write integration tests

### Phase 2: Bridge Implementation (Weeks 3-4)
- [ ] Implement MidnightSettlementRail
- [ ] Add to RailRegistry
- [ ] Create cross-chain message handling
- [ ] Test with StablecoinRouter
- [ ] Add emergency controls

### Phase 3: Privacy Features (Weeks 5-6)
- [ ] Enhance PrivacyLayer with real ZK proofs
- [ ] Implement private state storage
- [ ] Add selective disclosure APIs
- [ ] Create compliance hooks
- [ ] Audit privacy guarantees

### Phase 4: Client Development (Weeks 7-8)
- [ ] Build TypeScript client library
- [ ] Implement wallet integration
- [ ] Create proof generation pipeline
- [ ] Add private state synchronization
- [ ] Write comprehensive documentation

### Phase 5: Testing & Audit (Weeks 9-10)
- [ ] Security audit of privacy features
- [ ] Stress testing
- [ ] Compliance validation
- [ ] Performance optimization
- [ ] Documentation finalization

## Technical Specifications

### ZK Proof Format

Midnight uses ZK-SNARKs for privacy. Proof structure:
```typescript
interface MidnightProof {
  a: [bigint, bigint];        // G1 point
  b: [[bigint, bigint], [bigint, bigint]]; // G2 point
  c: [bigint, bigint];        // G1 point
  publicInputs: bigint[];     // Public parameters
}
```

### Private State Schema

```typescript
interface PrivateTransactionState {
  transactionId: string;
  commitments: Commitment[];
  nullifiers: Nullifier[];
  encryptedAmount: EncryptedValue;
  encryptedRecipient: EncryptedValue;
  proof: MidnightProof;
}
```

### Settlement Flow with Privacy

1. **Initiator**: Creates private transaction with ZK proof
2. **Proof Server**: Generates zero-knowledge proof
3. **Private State**: Updates local state database
4. **Bridge Contract**: Verifies proof on-chain
5. **Settlement**: Executes if proof valid
6. **Compliance**: Selective disclosure to regulators if needed

## Compliance Considerations

### Selective Disclosure

Midnight enables:
- **Public**: Transaction occurred, amount range validated
- **Regulator**: Full details upon request with authorization
- **Counterparty**: Transaction details
- **Public**: Nothing (zero-knowledge)

### Travel Rule Compliance

Integration with `contracts/compliance/TravelRuleEngine.sol`:
- Private transaction amounts over threshold trigger disclosure
- Automatic reporting to regulatory systems
- Encrypted PII transmission to counterparty
- Audit trail without compromising privacy

### Sanctions Screening

Works with `contracts/compliance/SanctionsOracleDenylist.sol`:
- Private address screening before settlement
- Zero-knowledge proof of non-sanctioned status
- Regulatory reporting without revealing all transactions

## Security Model

### Threat Mitigation

1. **Front-Running**: Private transaction details prevent MEV extraction
2. **Data Leakage**: Zero-knowledge proofs reveal nothing unnecessary
3. **Compliance Risk**: Selective disclosure satisfies regulators
4. **Key Management**: Midnight.js level-based private state storage

### Audit Recommendations

- [ ] Third-party ZK circuit audit
- [ ] Proof verifier security review
- [ ] Private state storage penetration testing
- [ ] Compliance workflow validation
- [ ] Side-channel attack analysis

## Development Environment Setup

### Installation

```bash
# Install Midnight.js packages
npm install @midnight-ntwrk/midnight-js-types
npm install @midnight-ntwrk/midnight-js-contracts
npm install @midnight-ntwrk/midnight-js-indexer-public-data-provider
npm install @midnight-ntwrk/midnight-js-node-zk-config-provider
npm install @midnight-ntwrk/midnight-js-fetch-zk-config-provider
npm install @midnight-ntwrk/midnight-js-network-id
npm install @midnight-ntwrk/midnight-js-http-client-proof-provider
npm install @midnight-ntwrk/midnight-js-level-private-state-provider
```

### Configuration

Create `midnight.config.json`:
```json
{
  "network": "testnet",
  "proofServerUrl": "https://proof-server.midnight.network",
  "indexerUrl": "https://indexer.midnight.network",
  "privateStateDir": "./data/private-state",
  "zkArtifactsPath": "./zk-artifacts"
}
```

## Example Use Cases

### Use Case 1: Private Reserve Audit

```typescript
// Generate proof of adequate reserves without revealing amounts
const reserveProof = await generateReserveProof({
  reserveAssets: privateReserveData,
  liabilities: publicStablecoinSupply,
  minimumRatio: 1.05
});

// Submit to contract
await reserveManager.submitPrivateProof(reserveProof);
// Public can verify reserves are adequate
// Details remain private
```

### Use Case 2: Anonymous Small Transactions

```typescript
// Sub-threshold CBDC transfer
const privateTx = await cbdcPrivacy.createPrivateTransfer({
  recipient: recipientPublicKey,
  amount: 50, // Below $1000 threshold
  proof: anonymityProof
});

// No identity revealed for small amounts
// Compliance triggers automatically if threshold exceeded
```

### Use Case 3: Private Settlement with Disclosure

```typescript
// Private institutional settlement
const settlement = await midnightRail.initiateSettlement({
  counterparty: institutionPublicKey,
  amount: encryptedAmount,
  asset: "USDC",
  proof: settlementProof
});

// Regulator requests details
const disclosure = await midnightRail.selectiveDisclose({
  settlementId: settlement.id,
  requester: regulatorAddress,
  authorization: regulatorCredential
});
```

## Resources

### Documentation
- [Midnight Network Docs](https://docs.midnight.network)
- [Midnight.js API Reference](https://docs.midnight.network/develop/reference/midnight-api/midnight-js)
- [Compact Language Guide](https://docs.midnight.network/develop/compact)

### Support
- GitHub: [Midnight Network](https://github.com/midnightntwrk)
- Discord: Midnight Developer Community
- Email: developers@midnight.network

### Related Contracts
- `contracts/security/PrivacyLayer.sol` - Current privacy implementation
- `contracts/settlement/QuantumResistantZKSettlement.sol` - ZK settlement
- `contracts/settlement/rails/` - Settlement rail infrastructure
- `contracts/compliance/TravelRuleEngine.sol` - Compliance engine

## Next Steps

1. **Review**: Evaluate Midnight integration benefits for your use cases
2. **Prototype**: Build proof-of-concept for highest-value integration
3. **Test**: Validate privacy guarantees and performance
4. **Audit**: Security review before production deployment
5. **Deploy**: Phase roll-out starting with non-critical features

---

**Status**: Documentation Complete - Ready for Implementation Planning
**Version**: 1.0.0
**Last Updated**: 2025-01-06
**Maintainer**: Unykorn Development Team
