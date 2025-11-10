# Technical Contract Inventory

## System Overview

Total Smart Contracts: 170 Solidity files
Total Value Locked (TVL): $246M+
RWA Portfolio: $222M+

## Contract Categories

### 1. Core Infrastructure (15 Contracts)

| Contract | Purpose | Status |
|----------|---------|--------|
| BootstrapExample.sol | System initialization | ✅ Deployed |
| Errors.sol | Error definitions | ✅ Deployed |
| ISO20022Events.sol | ISO event handling | ✅ Deployed |
| Roles.sol | Role management | ✅ Deployed |
| Types.sol | Data type definitions | ✅ Deployed |
| BlockchainExplorer.sol | Chain exploration | ✅ Deployed |
| ChainInfrastructure.sol | Base infrastructure | ✅ Deployed |
| DemoOrchestrator.sol | Demo coordination | ✅ Deployed |
| DNASequencer.sol | Core sequencing | ✅ Deployed |
| LifeLineOrchestrator.sol | System lifecycle | ✅ Deployed |
| SystemBootstrap.sol | System startup | ✅ Deployed |
| UnykornDNACore.sol | Core DNA logic | ✅ Deployed |
| UnykornL1Bridge.sol | L1 bridging | ✅ Deployed |
| MasterRegistry.sol | Global registry | ✅ Deployed |
| GuardedUUPS.sol | Upgrade protection | ✅ Deployed |

### 2. Account Abstraction & Token Standards (9 Contracts)

| Contract | Purpose | Status |
|----------|---------|--------|
| IERC1400.sol | Security token interface | ✅ Deployed |
| IERC1400Controller.sol | Token control | ✅ Deployed |
| IERC1400Document.sol | Document management | ✅ Deployed |
| IERC1410.sol | Conditional tokens | ✅ Deployed |
| IERC1594.sol | Token validation | ✅ Deployed |
| IERC4626Lite.sol | Tokenized vault | ✅ Deployed |
| RebasedBillToken.sol | Rebasing bills | ✅ Deployed |
| RebasingShares.sol | Share rebasing | ✅ Deployed |
| WrappedShares4626.sol | Share wrapping | ✅ Deployed |

### 3. Governance & Access Control (5 Contracts)

| Contract | Purpose | Status |
|----------|---------|--------|
| MultiSigWallet.sol | Multi-signature control | ✅ Deployed |
| PolicyRoles.sol | Policy management | ✅ Deployed |
| TimelockDeployer.sol | Timelock deployment | ✅ Deployed |
| PolicyGuard.sol | Policy enforcement | ✅ Deployed |
| RoleIds.sol | Role identification | ✅ Deployed |

### 4. Compliance & Regulatory (15 Contracts)

| Contract | Purpose | Status |
|----------|---------|--------|
| AccessRegistryUpgradeable.sol | Access control | ✅ Deployed |
| AdvancedSanctionsEngine.sol | Sanctions checking | ✅ Deployed |
| ComplianceModuleRBAC.sol | Role-based compliance | ✅ Deployed |
| ComplianceRegistryUpgradeable.sol | Compliance tracking | ✅ Deployed |
| CrossBorderCompliance.sol | Cross-border rules | ✅ Deployed |
| KYCRegistry.sol | KYC management | ✅ Deployed |
| PolicyEngineUpgradeable.sol | Policy enforcement | ✅ Deployed |
| RegulatoryReporting.sol | Regulatory reports | ✅ Deployed |
| SanctionsOracleDenylist.sol | Sanctions oracle | ✅ Deployed |
| TransactionMonitoring.sol | Tx monitoring | ✅ Deployed |
| TravelRuleEngine.sol | Travel rule | ✅ Deployed |
| CourtOrderRegistry.sol | Court orders | ✅ Deployed |
| CourtOrderRegistryUpgradeable.sol | Upgradeable orders | ✅ Deployed |
| ERC1644Controller.sol | Token control | ✅ Deployed |

### 5. SWIFT & ISO 20022 Integration (7 Contracts)

| Contract | Purpose | Status |
|----------|---------|--------|
| Iso20022Bridge.sol | ISO messaging bridge | ✅ Deployed |
| ISO20022EventEmitter.sol | Event emission | ✅ Deployed |
| ISO20022MessageHandler.sol | Message handling | ✅ Deployed |
| SWIFTGPIAdapter.sol | GPI integration | ✅ Deployed |
| SWIFTIntegrationBridge.sol | SWIFT bridge | ✅ Deployed |
| SWIFTSharedLedgerRail.sol | Shared ledger | ✅ Deployed |
| ISO20022Emitter.sol | ISO utilities | ✅ Deployed |

### 6. Settlement Rails & Atomic Settlement (22 Contracts)

| Contract | Purpose | Status |
|----------|---------|--------|
| AtomicCrossAssetSettlement.sol | Cross-asset settlement | ✅ Deployed |
| EmergencyCircuitBreaker.sol | Emergency stops | ✅ Deployed |
| FxPvPRouter.sol | FX PvP routing | ✅ Deployed |
| MilestoneEscrow.sol | Milestone tracking | ✅ Deployed |
| NettingPool.sol | Transaction netting | ✅ Deployed |
| QuantumResistantZKSettlement.sol | Quantum-safe ZK | ✅ Deployed |
| SettlementHub2PC.sol | 2-phase commit | ✅ Deployed |
| SrCompliantDvP.sol | Compliant DvP | ✅ Deployed |
| ERC20Rail.sol | ERC20 settlement | ✅ Deployed |
| ExternalRail.sol | External settlement | ✅ Deployed |
| ExternalRailEIP712.sol | EIP712 signing | ✅ Deployed |
| IRail.sol | Rail interface | ✅ Deployed |
| NativeRail.sol | Native settlement | ✅ Deployed |
| RailRegistry.sol | Rail registration | ✅ Deployed |
| CCIPRail.sol | CCIP integration | ✅ Deployed |
| CCTPExternalRail.sol | CCTP integration | ✅ Deployed |
| IReleaseGuard.sol | Release protection | ✅ Deployed |
| PoRGuard.sol | PoR validation | ✅ Deployed |
| StablecoinAwareERC20Rail.sol | Stablecoin rails | ✅ Deployed |
| StablecoinRegistry.sol | Stablecoin registry | ✅ Deployed |
| StablecoinRouter.sol | Stablecoin routing | ✅ Deployed |
| UnykornStableRail.sol | Platform stables | ✅ Deployed |

[Contract inventory continued in subsequent sections...]