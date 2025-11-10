# Compilation Fixes and Repairs for Unykorn Contracts

## Current Status
- Compilation failing with syntax errors in LifeLineOrchestrator.sol and UniversalDeployer.sol
- OpenZeppelin dependencies partially installed but remappings may need adjustment
- Multiple contracts need fixes for imports, implementations, and syntax

## Plan

### 1. Fix Syntax Errors in Core Contracts
- [ ] Fix LifeLineOrchestrator.sol: Remove invalid "memory" keyword from mapping declaration
- [ ] Fix UniversalDeployer.sol: Correct invalid "type(bytes).memory" usage

### 2. Install Missing Dependencies
- [ ] Properly install OpenZeppelin contracts (resolve existing directory conflict)
- [ ] Ensure Chainlink contracts are accessible via remappings

### 3. Fix Import and Implementation Issues
- [ ] Add missing imports for Types.sol, Roles.sol, Errors.sol in affected contracts
- [ ] Implement missing IRail interfaces in settlement contracts
- [ ] Fix Ownable constructor issues
- [ ] Resolve parameter conflicts in oracle contracts

### 4. Test Compilation
- [ ] Run forge build to verify all fixes
- [ ] Address any remaining errors iteratively

### 5. Deployment Preparation
- [ ] Ensure all contracts can be compiled successfully
- [ ] Verify contract interactions and dependencies
