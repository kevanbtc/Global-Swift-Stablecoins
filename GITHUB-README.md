# Global-Swift-Stablecoins

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange.svg)](https://getfoundry.sh/)

> Complete blockchain infrastructure for global financial systems - Unykorn L1, CBDC, SWIFT integration, and institutional DeFi.

## 🌟 Overview

This repository contains the complete smart contract infrastructure for the **Unykorn Layer 1** blockchain ecosystem, featuring:

- **Unykorn L1**: Besu-based permissioned blockchain (Chain ID: 7777)
- **CBDC Infrastructure**: Central Bank Digital Currency systems
- **SWIFT Integration**: ISO20022 compliant cross-border settlement
- **Stablecoin Rails**: Multi-asset stablecoin infrastructure
- **Institutional DeFi**: Advanced financial protocols
- **Regulatory Compliance**: KYC, AML, and sanctions screening
- **AI Governance**: Quantum-resistant governance systems

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh/) (Solidity development toolkit)
- [Node.js](https://nodejs.org/) >= 18.0.0
- [Git](https://git-scm.com/)

### Installation

```bash
# Clone the repository
git clone https://github.com/kevanbtc/Global-Swift-Stablecoins.git
cd Global-Swift-Stablecoins

# Install dependencies
npm install

# Install Foundry dependencies
forge install
```

### Local Development

```bash
# Start local Unykorn L1 node
./start-chain.sh

# Compile contracts
forge build

# Run tests
forge test

# Deploy to local network
forge script scripts/DeployUnykornChain.s.sol --rpc-url http://localhost:8545 --broadcast
```

## 🏗️ Architecture

### Core Components

#### 🔗 Unykorn Layer 1
- **Chain ID**: 7777
- **Consensus**: IBFT2/QBFT (Besu)
- **Block Time**: ~2 seconds
- **Currency**: Unykorn Ether (UNYETH)
- **RPC**: `http://localhost:8545`

#### 💰 CBDC & Stablecoins
- `CBDCInfrastructure.sol` - Central bank digital currency hub
- `StablecoinRouter.sol` - Multi-asset stablecoin routing
- `UnykornStableRail.sol` - Native stablecoin rail

#### 🌐 SWIFT Integration
- `SWIFTSharedLedgerRail.sol` - SWIFT GPI integration
- `Iso20022Bridge.sol` - ISO20022 message processing
- `SWIFTGPIAdapter.sol` - GPI message adapter

#### 🏛️ Institutional Finance
- `InstitutionalLendingProtocol.sol` - DeFi lending
- `InstitutionalDEX.sol` - Decentralized exchange
- `ReserveManager.sol` - Asset reserve management

#### ⚖️ Compliance & Regulation
- `TravelRuleEngine.sol` - FATF travel rule compliance
- `AdvancedSanctionsEngine.sol` - OFAC sanctions screening
- `KYCRegistry.sol` - Know Your Customer registry

## 📋 Network Configuration

### MetaMask Setup

Add Unykorn L1 to MetaMask:

```json
{
  "chainId": "0x1E61",
  "chainName": "Unykorn L1",
  "nativeCurrency": {
    "name": "Unykorn Ether",
    "symbol": "UNYETH",
    "decimals": 18
  },
  "rpcUrls": ["http://localhost:8545"],
  "blockExplorerUrls": []
}
```

### Foundry Configuration

```toml
# foundry.toml
[profile.unykorn_l1]
eth_rpc_url = "http://localhost:8545"
chain_id = 7777
gas_price = 20000000000
gas_limit = 8000000
```

### Hardhat Configuration

```typescript
// hardhat.config.ts
networks: {
  unykorn_l1: {
    url: "http://localhost:8545",
    chainId: 7777,
    accounts: [process.env.PRIVATE_KEY!],
  },
},
```

## 🎯 Key Features

### 🔐 Security
- Quantum-resistant cryptography
- Multi-signature governance
- Circuit breakers and emergency stops
- Comprehensive audit trails

### 🌍 Interoperability
- Cross-chain bridges (CCIP, Wormhole)
- Legacy system adapters
- API integrations
- Real-time messaging

### 📊 Analytics & Monitoring
- Real-time transaction monitoring
- Fund usage tracking
- Performance analytics
- Regulatory reporting

### 🤖 AI Integration
- AI Agent Swarm for market analysis
- Automated compliance checking
- Predictive risk modeling
- Smart contract optimization

## 📁 Project Structure

```
├── contracts/                 # Smart contracts
│   ├── cbdc/                 # CBDC infrastructure
│   ├── compliance/           # Regulatory compliance
│   ├── core/                 # Core system contracts
│   ├── defi/                 # DeFi protocols
│   ├── governance/           # Governance systems
│   ├── oracle/               # Price oracles
│   ├── risk/                 # Risk management
│   ├── settlement/           # Settlement systems
│   ├── stablecoins/          # Stablecoin contracts
│   └── swift/                # SWIFT integration
├── scripts/                  # Deployment scripts
├── foundry/                  # Foundry tests
├── docs/                     # Documentation
├── cli/                      # Command-line tools
├── subgraph/                 # The Graph subgraphs
└── compliant-bill-token/     # Bill token implementation
```

## 🚀 Deployment

### Local Development

```bash
# Start Besu network
./start-chain.sh

# Deploy core contracts
forge script scripts/DeployUnykornChain.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --chain-id 7777
```

### Production Deployment

```bash
# Deploy to production network
forge script scripts/Deploy_Prod.s.sol \
  --rpc-url $PROD_RPC_URL \
  --broadcast \
  --chain-id 7777 \
  --verify
```

## 🧪 Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path foundry/test/SRIntegration.t.sol

# Run with gas reporting
forge test --gas-report

# Run invariant tests
forge test --match-contract Invariants
```

## 📊 Monitoring

### Local Node
- **RPC**: http://localhost:8545
- **Explorer**: http://localhost:3000 (when running explorer)
- **Metrics**: Prometheus metrics available

### Production
- **RPC**: https://rpc.unykorn.layer1.network (planned)
- **Explorer**: https://explorer.unykorn.layer1.network (planned)
- **API**: https://api.unykorn.layer1.network (planned)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Solidity style guide
- Write comprehensive tests
- Update documentation
- Ensure all tests pass
- Get approval from code reviewers

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [OpenZeppelin](https://openzeppelin.com/) - Secure smart contract libraries
- [Foundry](https://getfoundry.sh/) - Development framework
- [Chainlink](https://chainlinklabs.com/) - Oracle infrastructure
- [Besu](https://besu.hyperledger.org/) - Ethereum client

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/kevanbtc/Global-Swift-Stablecoins/issues)
- **Discussions**: [GitHub Discussions](https://github.com/kevanbtc/Global-Swift-Stablecoins/discussions)
- **Documentation**: [Docs](./docs/)

---

**Built with ❤️ for the future of global finance**
