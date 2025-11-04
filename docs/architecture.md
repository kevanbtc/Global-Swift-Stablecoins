# System Architecture

## Overview

The Global Swift Stablecoins & CBDC infrastructure is built on a modular architecture that emphasizes security, compliance, and interoperability.

## Core Components

### 1. Token Layer

```mermaid
graph TB
    A[Token Core] --> B[Transfer Logic]
    A --> C[Balance Management]
    A --> D[Supply Control]
    B --> E[Compliance Checks]
    B --> F[Settlement Logic]
    C --> G[Account State]
    D --> H[Mint/Burn]
```

#### Key Components:
- StableUSD.sol
- RWASecurityToken.sol
- RebasedBillToken.sol

### 2. Compliance Layer

```mermaid
graph LR
    A[Policy Engine] --> B[KYC Registry]
    A --> C[Sanctions Lists]
    A --> D[Rule Sets]
    B --> E[Identity Verification]
    C --> F[Block Lists]
    D --> G[Transfer Rules]
```

#### Key Components:
- ComplianceRegistryUpgradeable.sol
- PolicyEngineUpgradeable.sol
- SanctionsOracle.sol

### 3. Risk Management Layer

```mermaid
graph TB
    A[Risk Core] --> B[Basel CAR]
    A --> C[Reserve Proofs]
    A --> D[Circuit Breakers]
    B --> E[Capital Ratios]
    C --> F[Asset Verification]
    D --> G[Emergency Controls]
```

#### Key Components:
- BaselCARModule.sol
- ReserveManager.sol
- PolicyCircuitBreaker.sol

### 4. Settlement Layer

```mermaid
graph LR
    A[Settlement Hub] --> B[Cross-Chain]
    A --> C[Internal Settlement]
    B --> D[Bridge Protocols]
    C --> E[Atomic Swaps]
```

#### Key Components:
- SettlementHub2PC.sol
- CCIPAttestationSender.sol
- FxPvPRouter.sol

## Interaction Flow

```mermaid
sequenceDiagram
    participant User
    participant ComplianceCheck
    participant Token
    participant RiskManagement
    participant Settlement
    
    User->>ComplianceCheck: Request Transfer
    ComplianceCheck->>RiskManagement: Verify Limits
    RiskManagement->>Token: Approve Transfer
    Token->>Settlement: Execute Transfer
    Settlement->>User: Confirm Transfer
```

## Security Architecture

### Multi-Layer Security Model

```mermaid
graph TB
    subgraph "Layer 1: Access Control"
        A[RBAC] --> B[Admin Controls]
    end
    
    subgraph "Layer 2: Compliance"
        C[KYC Checks] --> D[Policy Rules]
    end
    
    subgraph "Layer 3: Risk Management"
        E[Limits] --> F[Circuit Breakers]
    end
    
    subgraph "Layer 4: Settlement"
        G[Atomic Operations] --> H[Rollbacks]
    end
```

## Network Architecture

```mermaid
graph TB
    subgraph "Ethereum Mainnet"
        A[Core Contracts]
    end
    
    subgraph "Layer 2s"
        B[Arbitrum]
        C[Optimism]
    end
    
    subgraph "Other Chains"
        D[Polygon]
        E[BSC]
    end
    
    A --> B
    A --> C
    A --> D
    A --> E
```

## Reserve Infrastructure

```mermaid
graph TB
    subgraph "Reserve Assets"
        A[T-Bills]
        B[Cash]
        C[MMF]
    end
    
    subgraph "Proof System"
        D[Attestations]
        E[Verifications]
    end
    
    subgraph "Risk Management"
        F[Basel Rules]
        G[Stress Tests]
    end
    
    A --> D
    B --> D
    C --> D
    D --> F
    E --> G
```

## Integration Points

### External Systems
- Banking APIs
- SWIFT Network
- ISO 20022 Messaging
- Regulatory Reporting

### Cross-Chain
- CCIP (Chainlink)
- Wormhole
- LayerZero
- Axelar

### Oracle Networks
- Chainlink
- Pyth
- API3
- UMA