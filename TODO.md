# Unykorn L1 Testnet Deployment Plan

## Phase 1: Chain Infrastructure Setup
- [x] Verify Besu configuration (besu-config.toml, genesis.json)
- [x] Start Besu QBFT chain with 2 validators
- [x] Verify chain is running (RPC, WebSocket, metrics)
- [x] Confirm QBFT consensus is operational

## Phase 2: Core Infrastructure Deployment
- [ ] Deploy compliance framework (KYC, Sanctions, ComplianceModule)
- [ ] Deploy ISO20022 bridge
- [ ] Deploy settlement rails (ERC20, Native, External)
- [ ] Deploy settlement hub (SettlementHub2PC)
- [ ] Deploy rail registry

## Phase 3: Stablecoin Infrastructure Deployment
- [ ] Deploy stablecoin rails (CCIP, CCTP, PoR Guard)
- [ ] Deploy stablecoin registry and router
- [ ] Deploy stablecoin-aware ERC20 rail
- [ ] Configure rail routing

## Phase 4: Production Core Deployment
- [ ] Deploy compliance registry (upgradeable)
- [ ] Deploy court order registry
- [ ] Deploy policy engine
- [ ] Deploy institutional EMT token
- [ ] Deploy reserve manager
- [ ] Deploy NAV event oracle
- [ ] Deploy Merkle stream distributor

## Phase 5: Verification and Testing
- [ ] Verify all contracts deployed successfully
- [ ] Test basic RPC functionality
- [ ] Test WebSocket connections
- [ ] Validate contract interactions
- [ ] Test settlement rails
- [ ] Verify compliance framework
- [ ] Test stablecoin infrastructure

## Phase 6: Advanced Features Testing
- [ ] Test cross-chain capabilities
- [ ] Validate ISO20022 compliance
- [ ] Test oracle functionality
- [ ] Verify governance mechanisms
- [ ] Test emergency procedures
- [ ] Validate security features

## Phase 7: Final Validation
- [ ] Confirm all major features operational
- [ ] Document deployed contract addresses
- [ ] Update deployment status documentation
- [ ] Prepare for mainnet deployment
