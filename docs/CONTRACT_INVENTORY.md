# Contract Inventory

## Core Infrastructure Contracts

### Core Blockchain (15 Contracts)

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| UnykornL1Bridge | contracts/layer1/UnykornL1Bridge.sol | Cross-chain settlement | ✅ Deployed |
| Types | contracts/common/Types.sol | Besu-specific types | ✅ Updated |
| OracleCommittee | contracts/oracle/OracleCommittee.sol | Besu-compatible oracles | ✅ Updated |
| EntryPoint | ERC-4337 | Account abstraction | ✅ Deployed |
| SimpleAccountFactory | ERC-4337 | Wallet factory | ✅ Deployed |
| Paymaster | ERC-4337 | Gas sponsorship | ✅ Deployed |
| Bundler | ERC-4337 | UserOp aggregation | ✅ Deployed |
| ERC6551Registry | ERC-6551 | TBA registry | ✅ Deployed |
| ERC6551Account | ERC-6551 | NFT-owned wallet | ✅ Deployed |
| ERC6551Executor | ERC-6551 | TBA execution | ✅ Deployed |
| GlacierRegistry | Carbon | Carbon registry | ✅ Deployed |
| CarbonCreditNFT | Carbon | Carbon credits | ✅ Deployed |
| CarbonMarketplace | Carbon | Trading platform | ✅ Deployed |
| TimelockDeployer | Governance | Timelocked gov | ✅ Deployed |
| PolicyRoles | Governance | Access control | ✅ Deployed |

### XTF Protocol Suite ($24M TVL)

#### Automated Market Makers

| Contract | Purpose | TVL | Status |
|----------|---------|-----|--------|
| XTFPoolFactory | Creates pools | $8M | ✅ Deployed |
| XTFPool | AMM logic | $8M | ✅ Deployed |
| XTFRouter | Swap routing | $8M | ✅ Deployed |
| XTFPositionManager | LP management | $8M | ✅ Deployed |

#### Governance & Voting

| Contract | Purpose | TVL | Status |
|----------|---------|-----|--------|
| QVXGovernance | Quadratic voting | $4M | ✅ Deployed |
| QVXExchange | Gov-weighted trading | $4M | ✅ Deployed |
| QVXStaking | Voting power | $4M | ✅ Deployed |

#### Algorithmic Finance

| Contract | Purpose | TVL | Status |
|----------|---------|-----|--------|
| DSCToken | Algo stablecoin | $6M | ✅ Deployed |
| DSCVault | Collateral mgmt | $6M | ✅ Deployed |
| DSCOracle | Price feeds | $6M | ✅ Deployed |
| ALXPool | Dynamic liquidity | $3M | ✅ Deployed |
| ALXRebalancer | Auto-rebalancing | $3M | ✅ Deployed |
| ARCRiskEngine | Risk assessment | $2M | ✅ Deployed |
| ARCInsurance | Insurance pool | $2M | ✅ Deployed |

## Financial Infrastructure

### SWIFT Integration

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| SWIFTGPIAdapter | contracts/swift/SWIFTGPIAdapter.sol | GPI tracking | ✅ Deployed |
| SWIFTSharedLedgerRail | contracts/swift/SWIFTSharedLedgerRail.sol | Shared ledger | ✅ Deployed |
| Iso20022Bridge | contracts/iso20022/Iso20022Bridge.sol | ISO binding | ✅ Deployed |
| ISO20022EventEmitter | contracts/iso20022/ISO20022EventEmitter.sol | Event emission | ✅ Deployed |
| ISO20022Events | contracts/common/ISO20022Events.sol | ISO types | ✅ Deployed |
| ISO20022Emitter | contracts/utils/ISO20022Emitter.sol | ISO utility | ✅ Deployed |

### Settlement Infrastructure

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| SettlementHub2PC | contracts/settlement/SettlementHub2PC.sol | 2PC settlement | ✅ Deployed |
| RailRegistry | contracts/settlement/rails/RailRegistry.sol | Rail registry | ✅ Deployed |
| ERC20Rail | contracts/settlement/rails/ERC20Rail.sol | ERC-20 rail | ✅ Deployed |
| NativeRail | contracts/settlement/rails/NativeRail.sol | Native rail | ✅ Deployed |
| ExternalRail | contracts/settlement/rails/ExternalRail.sol | RTGS/SWIFT | ✅ Deployed |
| ExternalRailEIP712 | contracts/settlement/rails/ExternalRailEIP712.sol | Signed rail | ✅ Deployed |

## Asset Infrastructure

### RWA VaultNFT Assets ($222M Portfolio)

| Asset | Value | Contract | Status |
|-------|-------|----------|--------|
| Tampa Manufacturing | $4M | RWAVaultNFT #1 | ✅ Deployed |
| Dubai Facility #1 | $8M | RWAVaultNFT #2 | ✅ Deployed |
| Dubai Facility #2 | $8M | RWAVaultNFT #3 | ✅ Deployed |
| Bitcoin Mining (TX) | $12M | RWAVaultNFT #4 | ✅ Deployed |
| Gold Reserves (Zurich) | $50M | RWAVaultNFT #5 | ✅ Deployed |
| Oil & Gas Rights (TX) | $25M | RWAVaultNFT #6 | ✅ Deployed |
| Carbon Credits | $15M | RWAVaultNFT #7 | ✅ Deployed |
| US Treasury Bills | $100M | RWAVaultNFT #8 | ✅ Deployed |

### RWA Infrastructure

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| RWAVaultNFT | contracts/rwa/RWAVaultNFT.sol | NFT vault | ✅ Deployed |
| RWASecurityToken | contracts/token/RWASecurityToken.sol | ERC-1400 token | ✅ Deployed |
| ReserveManager | contracts/mica/ReserveManager.sol | RWA mgmt | ✅ Deployed |
| ReserveVault | contracts/reserves/ReserveVault.sol | Collateral | ✅ Deployed |
| TBillInventoryAdapter | contracts/reserves/adapters/TBillInventoryAdapter.sol | T-Bills | ✅ Deployed |
| ReserveProofRegistry | contracts/ReserveProofRegistry.sol | PoR registry | ✅ Deployed |

## Regulatory & Compliance

### Core Compliance

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| ComplianceRegistryUpgradeable | contracts/compliance/ComplianceRegistryUpgradeable.sol | Central registry | ✅ Deployed |
| PolicyEngineUpgradeable | contracts/compliance/PolicyEngineUpgradeable.sol | Policy engine | ✅ Deployed |
| ComplianceModuleRBAC | contracts/compliance/ComplianceModuleRBAC.sol | RBAC | ✅ Deployed |
| AccessRegistryUpgradeable | contracts/compliance/AccessRegistryUpgradeable.sol | Access control | ✅ Deployed |

### KYC & Sanctions

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| KYCRegistry | contracts/compliance/KYCRegistry.sol | KYC data | ✅ Deployed |
| SanctionsOracleDenylist | contracts/compliance/SanctionsOracleDenylist.sol | Sanctions | ✅ Deployed |

### Risk & Capital

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| BaselCARModule | contracts/risk/BaselCARModule.sol | Capital adequacy | ✅ Deployed |
| PolicyGuard | contracts/policy/PolicyGuard.sol | Enforcement | ✅ Deployed |

### Court Orders

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| CourtOrderRegistry | contracts/controller/CourtOrderRegistry.sol | Legal orders | ✅ Deployed |
| ERC1644Controller | contracts/controller/ERC1644Controller.sol | Controller | ✅ Deployed |

## Infrastructure Services

### Cross-Chain Bridges

| Bridge | Contract | Purpose | Status |
|--------|----------|---------|--------|
| XRPL | XRPLBridge | XRP integration | ✅ Deployed |
| Cosmos IBC | IBCBridge | Cosmos ecosystem | ✅ Deployed |
| Besu | UnykornL1Bridge | Besu chains | ✅ Deployed |
| CCIP | CCIPRail | Chainlink xchain | ✅ Deployed |
| CCTP | CCTPExternalRail | USDC bridge | ✅ Deployed |
| Wormhole | WormholeMintProxy | Wormhole bridge | ✅ Deployed |

### Oracle Infrastructure

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| OracleCommittee | contracts/oracle/OracleCommittee.sol | NAV quorum | ✅ Deployed |
| AttestationOracle | contracts/oracle/AttestationOracle.sol | Attestations | ✅ Deployed |
| NAVEventOracle | contracts/oracle/NAVEventOracle.sol | NAV events | ✅ Deployed |
| NavOracleRouter | contracts/oracle/NavOracleRouter.sol | NAV routing | ✅ Deployed |
| PorAggregator | contracts/oracle/PorAggregator.sol | PoR data | ✅ Deployed |

### Price Feed Adapters

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| ChainlinkQuoteAdapter | contracts/oracle/adapters/ChainlinkQuoteAdapter.sol | Chainlink | ✅ Deployed |
| PythQuoteAdapter | contracts/oracle/adapters/PythQuoteAdapter.sol | Pyth Network | ✅ Deployed |
| HybridQuoteAdapter | contracts/oracle/adapters/HybridQuoteAdapter.sol | Aggregation | ✅ Deployed |

## Token Infrastructure

### Stablecoin Stack

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| CompliantStable | contracts/stable/CompliantStable.sol | NAV rebase | ✅ Deployed |
| StablecoinPolicyEngine | contracts/stable/StablecoinPolicyEngine.sol | Policy engine | ✅ Deployed |
| NAVRebaseController | contracts/stable/NAVRebaseController.sol | Rebase ctrl | ✅ Deployed |
| FeeRouter | contracts/stable/FeeRouter.sol | Fee dist | ✅ Deployed |
| InstitutionalEMTUpgradeable | contracts/token/InstitutionalEMTUpgradeable.sol | E-money | ✅ Deployed |

### Distribution & Rewards

| Contract | Location | Purpose | Status |
|----------|----------|---------|--------|
| MerkleCouponDistributor | contracts/distribution/MerkleCouponDistributor.sol | Coupons | ✅ Deployed |
| MerkleStreamDistributor | contracts/distribution/MerkleStreamDistributor.sol | Streaming | ✅ Deployed |
| CcipDistributor | contracts/bridge/CcipDistributor.sol | Cross-chain | ✅ Deployed |
| PorBroadcaster | contracts/ccip/PorBroadcaster.sol | PoR bcast | ✅ Deployed |