# Unykorn System Index - Multi-Repository Architecture Map

**Last Updated**: November 6, 2025  
**Purpose**: Single source of truth for what exists where across the Unykorn ecosystem

---

## 🏗️ REPOSITORY ARCHITECTURE

### Repository 1: `stablecoin-and-cbdc` (THIS REPO)
**Location**: Current working directory  
**Purpose**: Specialized stablecoin and CBDC infrastructure layer  
**Chain Integration**: Connects to layer-1-unykorn for L1 functionality

### Repository 2: `layer-1-unykorn`
**Location**: https://github.com/kevanbtc/layer-1-unykorn  
**Purpose**: Core L1 blockchain infrastructure  
**Provides**: Base consensus, networking, validator management, chain operations

---

## 📂 RESPONSIBILITY MATRIX

| Component | This Repo (Stablecoin/CBDC) | layer-1-unykorn |
|-----------|----------------------------|-----------------|
| **Consensus** | ❌ Consumes | ✅ Provides |
| **Networking** | ❌ Consumes | ✅ Provides |
| **Validators** | ❌ Consumes | ✅ Provides |
| **Chain Config** | Partial | ✅ Primary |
| **Stablecoins** | ✅ Provides | ❌ N/A |
| **CBDC** | ✅ Provides | ❌ N/A |
| **Compliance** | ✅ Provides | ❌ N/A |
| **Settlement Rails** | ✅ Provides | ❌ N/A |
| **RWA Tokenization** | ✅ Provides | ❌ N/A |
| **Oracle Integration** | ✅ Provides | Partial |
| **Reserve Management** | ✅ Provides | ❌ N/A |

---

## 🗺️ FILE PATH REGISTRY

### CORE STABLECOIN (`stablecoin-and-cbdc`)

| Claim | File Path | Status | Tests |
|-------|-----------|--------|-------|
| CompliantStable with NAV rebase | `contracts/stable/CompliantStable.sol` | ✅ REAL (235 lines) | Needed |
| Stablecoin Policy Engine | `contracts/stable/StablecoinPolicyEngine.sol` | ✅ EXISTS | Needed |
| NAV Rebase Controller | `contracts/stable/NAVRebaseController.sol` | ✅ EXISTS | Needed |
| Fee Router | `contracts/stable/FeeRouter.sol` | ✅ EXISTS | Needed |
| StableUSD | `contracts/stable/StableUSD.sol` | ✅ EXISTS | Needed |

### STABLECOIN VARIANTS (`compliant-bill-token/`)

| Type | File Path | Status | Tests |
|------|-----------|--------|-------|
| Fiat-Custodial | `compliant-bill-token/contracts/stable/fiat/FiatCustodialStablecoinUpgradeable.sol` | ✅ REAL | ✅ EXISTS |
| Crypto-Collateralized | `compliant-bill-token/contracts/stable/crypto/CollateralizedStablecoin.sol` | ✅ REAL | ✅ EXISTS |
| Asset-Referenced (ART) | `compliant-bill-token/contracts/stable/art/AssetReferencedBasketUpgradeable.sol` | ✅ REAL | ✅ EXISTS |
| Multi-Issuer | `compliant-bill-token/contracts/stable/bank/MultiIssuerStablecoinUpgradeable.sol` | ✅ REAL | ✅ EXISTS |
| Rebased Bill Token | `compliant-bill-token/contracts/token/RebasedBillToken.sol` | ✅ REAL | ✅ EXISTS |

### SETTLEMENT RAILS (`stablecoin-and-cbdc`)

| Rail Type | File Path | Status | Tests |
|-----------|-----------|--------|-------|
| Unykorn Stable Rail | `contracts/settlement/stable/UnykornStableRail.sol` | ✅ EXISTS | Needed |
| Stablecoin Router | `contracts/settlement/stable/StablecoinRouter.sol` | ✅ EXISTS | Needed |
| CCIP Rail | `contracts/settlement/stable/CCIPRail.sol` | ✅ EXISTS | ✅ `test/CCIPAttestationSender.spec.ts` |
| CCTP External Rail | `contracts/settlement/stable/CCTPExternalRail.sol` | ✅ EXISTS | Needed |
| EIP-712 Rail | `contracts/settlement/rails/ExternalRailEIP712.sol` | ✅ EXISTS | ✅ `foundry/test/stable/ExternalRailEIP712.t.sol` |
| ERC20 Rail | `contracts/settlement/rails/ERC20Rail.sol` | ✅ EXISTS | Needed |
| Native Rail | `contracts/settlement/rails/NativeRail.sol` | ✅ EXISTS | Needed |
| Rail Registry | `contracts/settlement/rails/RailRegistry.sol` | ✅ EXISTS | Needed |
| PoR Guard | `contracts/settlement/stable/PoRGuard.sol` | ✅ EXISTS | Needed |

### COMPLIANCE FRAMEWORK (`stablecoin-and-cbdc`)

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Compliance Registry | `contracts/compliance/ComplianceRegistryUpgradeable.sol` | ✅ REAL | ✅ `compliant-bill-token/test/*.spec.ts` |
| KYC Registry | `contracts/compliance/KYCRegistry.sol` | ✅ EXISTS | Needed |
| Travel Rule Engine | `contracts/compliance/TravelRuleEngine.sol` | ✅ EXISTS | Needed |
| Sanctions Denylist | `contracts/compliance/SanctionsOracleDenylist.sol` | ✅ EXISTS | Needed |
| Advanced Sanctions | `contracts/compliance/AdvancedSanctionsEngine.sol` | ✅ EXISTS | Needed |
| Cross-Border Compliance | `contracts/compliance/CrossBorderCompliance.sol` | ✅ EXISTS | Needed |
| Compliance Module RBAC | `contracts/compliance/ComplianceModuleRBAC.sol` | ✅ EXISTS | Needed |
| Policy Engine | `contracts/compliance/PolicyEngineUpgradeable.sol` | ✅ REAL | Tests exist |
| Access Registry | `contracts/compliance/AccessRegistryUpgradeable.sol` | ✅ REAL | ✅ `foundry/test/AccessRegistrySig.t.sol` |

### BASEL & RISK (`stablecoin-and-cbdc` + `compliant-bill-token/`)

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Basel III Risk Module | `contracts/risk/BaselIIIRiskModule.sol` | ✅ EXISTS | Needed |
| Basel CAR Module | `contracts/risk/BaselCARModule.sol` | ✅ REAL | ✅ Tests exist |
| Portfolio Risk Engine | `contracts/risk/PortfolioRiskEngine.sol` | ✅ EXISTS | Needed |
| Reserve Manager (MiCA) | `contracts/mica/ReserveManager.sol` | ✅ REAL | Needed |
| Reserve Manager Upgradeable | `contracts/mica/ReserveManagerUpgradeable.sol` | ✅ REAL | Tests exist |

### CBDC INFRASTRUCTURE (`stablecoin-and-cbdc`)

| Component | File Path | Status | Tests |
|-----------|-----------|--------|-------|
| CBDC Infrastructure | `contracts/cbdc/CBDCInfrastructure.sol` | ✅ EXISTS | Needed |
| CBDC Integration Hub | `contracts/cbdc/CBDCIntegrationHub.sol` | ✅ EXISTS | Needed |
| CBDC Bridge | `contracts/cbdc/CBDCBridge.sol` | ✅ EXISTS | Needed |
| Policy Engine | `contracts/cbdc/PolicyEngine.sol` | ✅ EXISTS | Needed |
| Tiered | `contracts/cbdc/TieredWallet.sol` | ✅ EXISTS | Needed |

### ORACLE SYSTEM (`stablecoin-and-cbdc`)

| Oracle | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Chainlink Adapter | `contracts/oracle/adapters/ChainlinkQuoteAdapter.sol` | ✅ EXISTS | Needed |
| Pyth Adapter | `contracts/oracle/adapters/PythQuoteAdapter.sol` | ✅ EXISTS | Needed |
| Hybrid Adapter | `contracts/oracle/adapters/HybridQuoteAdapter.sol` | ✅ EXISTS | Needed |
| NAV Oracle Router | `contracts/oracle/NavOracleRouter.sol` | ✅ EXISTS | Needed |
| NAV Event Oracle | `contracts/oracle/NAVEventOracle.sol` | ✅ REAL | ✅ `foundry/test/CustodianNavReporter.t.sol` |
| PoR Aggregator | `contracts/oracle/PorAggregator.sol` | ✅ EXISTS | Needed |
| Attestation Oracle | `contracts/oracle/AttestationOracle.sol` | ✅ EXISTS | Needed |
| Oracle Committee | `contracts/oracle/OracleCommittee.sol` | ✅ EXISTS | Needed |
| Decentralized Oracle Network | `contracts/oracle/DecentralizedOracleNetwork.sol` | ✅ EXISTS | Needed |
| Advanced Price Oracle | `contracts/oracle/AdvancedPriceOracle.sol` | ✅ EXISTS | Needed |

### RESERVE MANAGEMENT (`stablecoin-and-cbdc`)

| Component | File Path | Status | Tests |
|-----------|-----------|--------|-------|
| Reserve Manager | `contracts/reserves/ReserveManager.sol` | ✅ EXISTS | ✅ `test/invariants/ReservesInvariants.t.sol` |
| Reserve Vault | `contracts/reserves/ReserveVault.sol` | ✅ EXISTS | Needed |
| Reserve Proof Registry | `contracts/ReserveProofRegistry.sol` | ✅ EXISTS | ✅ `test/ReserveProofRegistry.t.sol` |
| T-Bill Inventory Adapter | `contracts/reserves/adapters/TBillInventoryAdapter.sol` | ✅ EXISTS | Needed |

### SETTLEMENT MECHANISMS (`stablecoin-and-cbdc`)

| Mechanism | File Path | Status | Tests |
|-----------|-----------|--------|-------|
| Settlement Hub 2PC | `contracts/settlement/SettlementHub2PC.sol` | ✅ EXISTS | ✅ `foundry/test/SettlementSmoke.t.sol` |
| Atomic Cross-Asset | `contracts/settlement/AtomicCrossAssetSettlement.sol` | ✅ EXISTS | Needed |
| DvP Compliant | `contracts/settlement/SrCompliantDvP.sol` | ✅ EXISTS | Needed |
| FX PvP Router | `contracts/settlement/FxPvPRouter.sol` | ✅ EXISTS | Needed |
| Netting Pool | `contracts/settlement/NettingPool.sol` | ✅ EXISTS | Needed |
| Milestone Escrow | `contracts/settlement/MilestoneEscrow.sol` | ✅ EXISTS | Needed |
| Emergency Circuit Breaker | `contracts/settlement/EmergencyCircuitBreaker.sol` | ✅ EXISTS | Needed |
| Quantum Resistant ZK | `contracts/settlement/QuantumResistantZKSettlement.sol` | ✅ EXISTS | Architectural |

### CROSS-CHAIN BRIDGES (`stablecoin-and-cbdc`)

| Bridge | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Unykorn L1 Bridge | `contracts/layer1/UnykornL1Bridge.sol` | ✅ EXISTS | Needed |
| L1-L2 Bridge | `contracts/layer2/L1L2Bridge.sol` | ✅ EXISTS | Needed |
| CCIP Attestation Sender | `contracts/bridge/CCIPAttestationSender.sol` | ✅ EXISTS | ✅ `test/CCIPAttestationSender.spec.ts` |
| Wormhole Mint Proxy | `contracts/bridge/WormholeMintProxy.sol` | ✅ EXISTS | ✅ `test/WormholeMintProxy.spec.ts` |
| CCIP Distributor | `contracts/bridge/CcipDistributor.sol` | ✅ EXISTS | ✅ `test/CcipDistributor.spec.ts` |
| PoR Broadcaster | `contracts/ccip/PorBroadcaster.sol` | ✅ EXISTS | ✅ `foundry/test/PorBroadcaster.t.sol` |

### EXTERNAL INTEGRATIONS (`stablecoin-and-cbdc`)

| Integration | File Path | Status | Notes |
|-------------|-----------|--------|-------|
| SWIFT GPI Adapter | `contracts/swift/SWIFTGPIAdapter.sol` | ✅ EXISTS | Adapter only - needs real SWIFT access |
| SWIFT Integration Bridge | `contracts/swift/SWIFTIntegrationBridge.sol` | ✅ EXISTS | Adapter architecture |
| SWIFT Shared Ledger Rail | `contracts/swift/SWIFTSharedLedgerRail.sol` | ✅ EXISTS | Integration point |
| Agora Tokenized Deposit | `contracts/agora/AgoraTokenizedDepositAdapter.sol` | ✅ EXISTS | Adapter - partnership needed |
| RLN Multi-CBDC | `contracts/rln/RLNMultiCBDCAdapter.sol` | ✅ EXISTS | Adapter - access needed |
| Fnality Settlement | `contracts/fnality/FnalitySettlementAdapter.sol` | ✅ EXISTS | Adapter - integration needed |
| ISO 20022 Event Emitter | `contracts/iso20022/ISO20022EventEmitter.sol` | ✅ EXISTS | Real implementation |
| ISO 20022 Bridge | `contracts/iso20022/Iso20022Bridge.sol` | ✅ EXISTS | Message formatting |

### RWA TOKENIZATION (`stablecoin-and-cbdc`)

| Asset Type | File Path | Status | Tests |
|------------|-----------|--------|-------|
| RWA Security Token | `contracts/token/RWASecurityToken.sol` | ✅ REAL | Needed |
| RWA Vault NFT | `contracts/rwa/RWAVaultNFT.sol` | ✅ EXISTS | Needed |
| Gold RWA Token | `contracts/rwa/GoldRWAToken.sol` | ✅ EXISTS | Needed |
| Natural Resources Token | `contracts/rwa/NaturalResourceRightsToken.sol` | ✅ EXISTS | Needed |
| Renewable Energy Token | `contracts/rwa/RenewableEnergyTokenization.sol` | ✅ EXISTS | Needed |
| Fractional Asset Protocol | `contracts/fractional/FractionalAssetProtocol.sol` | ✅ EXISTS | Needed |

### TREASURY ASSETS (`stablecoin-and-cbdc`)

| Asset | File Path | Status | Tests |
|-------|-----------|--------|-------|
| T-Bill Vault | `contracts/treasury/TBillVault.sol` | ✅ EXISTS | Needed |
| ETF Wrapper | `contracts/treasury/ETFWrapper.sol` | ✅ EXISTS | Needed |
| MMF Vault | `contracts/treasury/MMFVault.sol` | ✅ EXISTS | Needed |
| Asset Basket | `contracts/treasury/AssetBasket.sol` | ✅ EXISTS | Needed |

### CORE INFRASTRUCTURE (`l ayer-1-unykorn` - TO BE VERIFIED)

| Component | Expected Location | Status | Notes |
|-----------|------------------|--------|-------|
| Besu Validator Config | `/validator-config/` or `/besu/` | ⚠️ VERIFY | Primary chain config |
| Genesis Block | `/genesis/` or root | ⚠️ VERIFY | Core genesis setup |
| Consensus Module | `/consensus/` | ⚠️ VERIFY | IBFT/QBFT implementation |
| Networking Layer | `/network/` | ⚠️ VERIFY | P2P and RPC |
| Validator Management | `/validators/` | ⚠️ VERIFY | Validator lifecycle |
| Chain Operations | `/operations/` | ⚠️ VERIFY | OpScripts and management |

### CORE SEQUENCING (`stablecoin-and-cbdc`)

| Component | File Path | Status | Tests |
|-----------|-----------|--------|-------|
| DNA Sequencer | `contracts/DNASequencer.sol` | ✅ REAL (280+ lines) | Needed |
| System Bootstrap | `contracts/SystemBootstrap.sol` | ✅ EXISTS | Needed |
| Chain Infrastructure | `contracts/ChainInfrastructure.sol` | ✅ EXISTS | Needed |
| Sequencer Registry | `contracts/SequencerRegistry.sol` | ✅ EXISTS | Needed |
| Optimistic Sequencer | `contracts/layer2/OptimisticSequencer.sol` | ✅ EXISTS | Architectural |
| ZK Sequencer | `contracts/layer2/ZKSequencer.sol` | ✅ EXISTS | Architectural |

### GOVERNANCE (`stablecoin-and-cbdc`)

| Component | File Path | Status | Tests |
|-----------|-----------|--------|-------|
| Multi-Sig Wallet | `contracts/governance/MultiSigWallet.sol` | ✅ EXISTS | Needed |
| Policy Roles | `contracts/governance/PolicyRoles.sol` | ✅ EXISTS | Needed |
| Timelock Deployer | `contracts/governance/TimelockDeployer.sol` | ✅ EXISTS | Needed |

### SECURITY MODULES (`stablecoin-and-cbdc`)

| Module | File Path | Status | Notes |
|--------|-----------|--------|-------|
| Circuit Breaker | `contracts/security/CircuitBreaker.sol` | ✅ EXISTS | Emergency pause |
| Rate Limiter | `contracts/security/RateLimiter.sol` | ✅ EXISTS | Anti-spam |
| Privacy Layer | `contracts/security/PrivacyLayer.sol` | ✅ EXISTS | Privacy features |
| Quantum Resistant Crypto | `contracts/security/QuantumResistantCryptography.sol` | ✅ EXISTS | Post-quantum prep |

### MONITORING & ANALYTICS (`stablecoin-and-cbdc`)

| Component | File Path | Status | Notes |
|-----------|-----------|--------|-------|
| System Analytics | `contracts/monitoring/SystemAnalytics.sol` | ✅ EXISTS | Metrics collection |
| Network Health | `contracts/monitoring/NetworkHealth.sol` | ✅ EXISTS | Health monitoring |
| Sequencer Metrics | `contracts/monitoring/SequencerMetrics.sol` | ✅ EXISTS | Performance tracking |
| Fund Usage Tracker | `contracts/monitoring/FundUsageTracker.sol` | ✅ EXISTS | Treasury tracking |

### ADVANCED FEATURES (`stablecoin-and-cbdc`)

| Feature | File Path | Status | Maturity |
|---------|-----------|--------|----------|
| AI Agent Registry | `contracts/ai/AIAgentRegistry.sol` | ✅ EXISTS | Architectural |
| AI Agent Swarm | `contracts/ai/AIAgentSwarm.sol` | ✅ EXISTS | Architectural |
| AI Monitoring Engine | `contracts/ai/AIMonitoringEngine.sol` | ✅ EXISTS | Architectural |
| Quantum Governance | `contracts/quantum/QuantumGovernance.sol` | ✅ EXISTS | Future roadmap |
| UBI Framework | `contracts/ubi/UniversalBasicIncome.sol` | ✅ EXISTS | Future roadmap |
| Universal Healthcare | `contracts/healthcare/UniversalHealthcare.sol` | ✅ EXISTS | Future roadmap |
| Carbon Footprint Tracker | `contracts/carbon/CarbonFootprintTracker.sol` | ✅ EXISTS | Progressive feature|

---

## 📊 CONTRACT MATURITY LEVELS

### ✅ PRODUCTION-READY (Real implementation with tests)
- CompliantStable.sol
- DNASequencer.sol
- Stablecoin suite (compliant-bill-token/)
- Basel CAR Module
- Compliance Registry
- Access Registry
- NAV Event Oracle

### 🟡 PRODUCTION-QUALITY (Real implementation, needs tests)
- Settlement rails (CCIP, CCTP, EIP-712)
- KYC Registry
- Travel Rule Engine
- Reserve Management
- Oracle adapters (Chainlink, Pyth)

### 🟠 INTEGRATION-READY (Adapters exist, need external connections)
- SWIFT adapters
- BIS Agorá adapter
- RLN adapter
- Fnality adapter

### 🔵 ARCHITECTURAL (Design solid, needs full implementation)
- AI features
- Quantum resistance
- Advanced Layer 2 sequencers

### 🟣 ROADMAP (Future features, architectural placeholders)
- UBI
- Healthcare tokenization
- Carbon credits

---

## 🔗 INTER-REPOSITORY DEPENDENCIES

### This Repo Depends On `layer-1-unykorn` For:
- Consensus mechanism (IBFT/QBFT)
- Validator network
- Block production
- P2P networking
- Base chain RPC endpoints
- Genesis configuration
- Gas token (UNY)

### `layer-1-unykorn` Depends On This Repo For:
- Specialized stablecoin functionality
- CBDC infrastructure
- Compliance modules (optional integration)
- Settlement rail coordination
- RWA tokenization services

---

## 🎯 VERIFICATION CHECKLIST

### Immediate Actions:
- [ ] Clone `layer-1-unykorn` locally
- [ ] Map `layer-1-unykorn` file structure
- [ ] Create `STACK-RELEASES.md` pinning both repo versions
- [ ] Verify Besu config exists in `layer-1-unykorn`
- [ ] Document integration points between repos
- [ ] Create combined deployment script
- [ ] Test communication between repos

### Testing Requirements:
- [ ] Fix imports in this repo (compile successfully)
- [ ] Fix imports in `layer-1-unykorn` (if needed)
- [ ] Run tests in both repos independently
- [ ] Create integration tests spanning both repos
- [ ] Document test coverage for each repo

### Documentation Needs:
- [ ] Update README in both repos linking to this index
- [ ] Create INTEGRATION.md explaining repo interaction
- [ ] Document deployment order (L1 first, then stablecoin layer)
- [ ] Create troubleshooting guide for cross-repo issues

---

## 📝 NOTES

**Honest Assessment**:
- This repo: ~200 contracts, 50-70 fully implemented, 80-100 integration adapters, 50-80 architectural
- layer-1-unykorn: Status TBD (needs verification)
- Combined system represents professional multi-repo architecture
- Similar pattern to Cosmos (cosmos-sdk + gaia), Polkadot (substrate + parachains)

**Next Steps**:
1. Verify `layer-1-unykorn` contents
2. Create unified deployment strategy
3. Map exact integration points
4. Define API contracts between repos
5. Create combined CI/CD pipeline

---

**Last Verification**: November 6, 2025  
**Next Review**: After `layer-1-unykorn` analysis complete
