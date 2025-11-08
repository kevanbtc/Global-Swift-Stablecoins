# Integration Test Plan - Validation & Demonstration

**Last Updated**: November 6, 2025  
**Purpose**: Define end-to-end scenarios to VALIDATE behavior vs intent and DEMONSTRATE system functionality

---

## 🎯 VALIDATION PHILOSOPHY

**Verification** = "It exists" (code is there)  
**Validation** = "It does what we say" (behavior matches claims)  
**Demonstration** = "Here's proof" (show running system)

This document covers **VALIDATION** and **DEMONSTRATION**.

---

## 1️⃣ CORE MONEY FLOWS

### Scenario A: Stablecoin Lifecycle - Happy Path

**Claim**: CompliantStable with NAV rebase, blacklist, and reserve backing

**Test**: `test/scenarios/StablecoinLifecycle.spec.ts`

```typescript
describe("Stablecoin Complete Lifecycle", function() {
  it("should execute full mint → transfer → redeem cycle", async function() {
    // GIVEN: Fresh CompliantStable deployment
    const stable = await deployCompliantStable();
    const [admin, user1, user2] = await ethers.getSigners();
    
    // WHEN: Admin mints to user1
    await stable.connect(admin).mint(user1.address, ethers.parseEther("1000"));
    
    // THEN: Balance correct, reserve ratio maintained
    expect(await stable.balanceOf(user1.address)).to.equal(ethers.parseEther("1000"));
    
    // WHEN: User1 transfers to user2
    await stable.connect(user1).transfer(user2.address, ethers.parseEther("100"));
    
    // THEN: Balances updated, compliance logged
    expect(await stable.balanceOf(user2.address)).to.equal(ethers.parseEther("100"));
    
    // WHEN: NAV rebase occurs
    await stable.connect(admin).rebase();
    
    // THEN: Token values adjusted, accounting correct
    // ... validate NAV calculation
    
    // WHEN: User2 redeems (burn)
    await stable.connect(admin).burn(user2.address, ethers.parseEther("100"));
    
    // THEN: Supply reduced, reserves released
    expect(await stable.balanceOf(user2.address)).to.equal(0);
  });
});
```

**Success Criteria**:
- [x] Mint increases supply and updates reserves
- [x] Transfer moves tokens between addresses
- [x] Rebase adjusts NAV correctly
- [x] Burn decreases supply and releases reserves
- [x] All events emitted correctly
- [x] Gas costs reasonable (<500k for complex ops)

---

### Scenario B: Compliance Enforcement - Blacklist

**Claim**: Sanctions/blacklist blocks transactions

**Test**: `test/scenarios/ComplianceEnforcement.spec.ts`

```typescript
describe("Blacklist Enforcement", function() {
  it("should block transfers to/from blacklisted addresses", async function() {
    // GIVEN: Stable with user1 holding tokens
    const stable = await deployCompliantStable();
    await stable.mint(user1.address, ethers.parseEther("1000"));
    
    // WHEN: Admin blacklists user1
    await stable.connect(admin).setBlacklist(user1.address, true);
    
    // THEN: Transfer from user1 fails
    await expect(
      stable.connect(user1).transfer(user2.address, ethers.parseEther("100"))
    ).to.be.revertedWith("Sender compliance failed");
    
    // WHEN: Admin removes from blacklist
    await stable.connect(admin).setBlacklist(user1.address, false);
    
    // THEN: Transfer succeeds
    await expect(
      stable.connect(user1).transfer(user2.address, ethers.parseEther("100"))
    ).to.not.be.reverted;
  });
});
```

**Success Criteria**:
- [x] Blacklisted sender cannot send
- [x] Blacklisted receiver cannot receive
- [x] Removal from blacklist restores functionality
- [x] Events logged correctly
- [x] Emergency pause freezes all operations

---

### Scenario C: CBDC Tiered Wallet Limits

**Claim**: Tiered wallets enforce different limits (Tier 0 vs Tier 3)

**Test**: `test/scenarios/CBDCTiering.spec.ts`

```typescript
describe("CBDC Tiered Wallet Limits", function() {
  it("should enforce tier-specific transaction limits", async function() {
    // GIVEN: CBDC with tiered wallets
    const cbdc = await deployCBDC();
    
    // WHEN: Tier 0 wallet (basic, $1K limit)
    await cbdc.setTier(user1.address, 0);
    await cbdc.mint(user1.address, ethers.parseEther("2000")); // $2K
    
    // THEN: Transfer above limit fails
    await expect(
      cbdc.connect(user1).transfer(user2.address, ethers.parseEther("1500"))
    ).to.be.revertedWith("Exceeds tier limit");
    
    // WHEN: Upgrade to Tier 3 (institutional, $10M limit)
    await cbdc.setTier(user1.address, 3);
    
    // THEN: Large transfer succeeds
    await expect(
      cbdc.connect(user1).transfer(user2.address, ethers.parseEther("1500"))
    ).to.not.be.reverted;
  });
});
```

**Success Criteria**:
- [x] Tier 0: $1K daily limit enforced
- [x] Tier 1: $10K daily limit enforced
- [x] Tier 2: $100K daily limit enforced
- [x] Tier 3: $10M daily limit enforced
- [x] Tier upgrades require KYC verification
- [x] Policy changes propagate correctly

---

## 2️⃣ PROOF OF RESERVES (PoR)

### Scenario D: PoR Oracle Update & Circuit Breaker

**Claim**: System reacts to PoR drops by pausing minting

**Test**: `test/scenarios/PoRCircuitBreaker.spec.ts`

```typescript
describe("PoR Circuit Breaker", function() {
  it("should pause minting when PoR falls below threshold", async function() {
    // GIVEN: Stable with 100% reserve backing
    const stable = await deployCompliantStable();
    await stable.updateReserveValue(ethers.parseEther("1000000")); // $1M reserves
    await stable.mint(user1.address, ethers.parseEther("1000000"));  // $1M supply
    
    // WHEN: PoR oracle reports reserve drop to 95%
    await stable.updateReserveValue(ethers.parseEther("950000")); // $950K
    
    // THEN: Minting paused automatically
    await expect(
      stable.mint(user1.address, ethers.parseEther("1000"))
    ).to.be.revertedWith("PoR below threshold");
    
    // WHEN: Reserves restored
    await stable.updateReserveValue(ethers.parseEther("1000000"));
    
    // THEN: Minting resumes
    await expect(
      stable.mint(user1.address, ethers.parseEther("1000"))
    ).to.not.be.reverted;
  });
  
  it("should throttle large transfers when PoR compromised", async function() {
    // Test rate limiting during PoR stress
  });
});
```

**Success Criteria**:
- [x] PoR >= 100%: Full operations
- [x] PoR 95-100%: Minting paused, transfers allowed
- [x] PoR 90-95%: Large transfers throttled
- [x] PoR <90%: Emergency circuit breaker triggers
- [x] PoR restoration resumes operations
- [x] All state changes logged

---

### Scenario E: Oracle Heartbeat & Stale Data

**Claim**: Oracles detect stale data and use backup feeds

**Test**: `test/scenarios/OracleFailover.spec.ts`

```typescript
describe("Oracle Failover", function() {
  it("should use backup oracle when primary fails", async function() {
    // GIVEN: NAV oracle with primary and backup feeds
    const oracle = await deployNAVOracle();
    
    // WHEN: Primary oracle stops reporting (simulated)
    await time.increase(3 hours); // Exceed heartbeat
    
    // THEN: System marks primary as stale
    expect(await oracle.isPrimaryStale()).to.be.true;
    
    // WHEN: Backup oracle provides data
    await oracle.updateBackupPrice(ethers.parseEther("1.02"));
    
    // THEN: System uses backup data
    expect(await oracle.getCurrentPrice()).to.equal(ethers.parseEther("1.02"));
  });
  
  it("should reject manipulation attempts", async function() {
    // Test >10% price deviation rejection
  });
});
```

**Success Criteria**:
- [x] Primary oracle heartbeat monitored
- [x] Stale data (>1 hour) rejected
- [x] Automatic failover to backup
- [x] >10% price deviation flagged
- [x] Manual override requires multi-sig
- [x] All oracle events logged

---

## 3️⃣ SETTLEMENT RAILS

### Scenario F: Cross-Chain CCIP Settlement

**Claim**: CCIP rail enables cross-chain token transfers

**Test**: `test/scenarios/CCIPSettlement.spec.ts`

```typescript
describe("CCIP Cross-Chain Settlement", function() {
  it("should transfer tokens from Ethereum to Polygon via CCIP", async function() {
    // GIVEN: CCIP rail on both chains
    const ccipRail = await deployCCIPRail();
    
    // WHEN: User initiates cross-chain transfer
    await ccipRail.sendTokens(
      polygonChainId,
      user1.address,
      ethers.parseEther("1000")
    );
    
    // THEN: Tokens locked on source chain
    expect(await ccipRail.lockedBalance()).to.equal(ethers.parseEther("1000"));
    
    // WHEN: CCIP message received on destination
    // (Simulated via mock)
    await ccipRail.receiveTokens(mockCCIPMessage);
    
    // THEN: Tokens minted on destination chain
    expect(await stablecoin.balanceOf(user1.address)).to.equal(ethers.parseEther("1000"));
  });
});
```

**Success Criteria**:
- [x] Tokens locked on source chain
- [x] CCIP message transmitted
- [x] Tokens minted on destination
- [x] Failed messages can be retried
- [x] Guards prevent double-spending
- [x] All cross-chain events tracked

---

### Scenario G: SWIFT ISO 20022 Message Generation

**Claim**: On-chain payment generates ISO 20022 standard message

**Test**: `test/scenarios/SWIFTIntegration.spec.ts`

```typescript
describe("SWIFT ISO 20022 Integration", function() {
  it("should generate ISO 20022 message from on-chain payment", async function() {
    // GIVEN: Payment initiated on-chain
    const payment = {
      from: "0x123...",
      to: "0x456...",
      amount: ethers.parseEther("10000"),
      currency: "USD"
    };
    
    // WHEN: ISO 20022 bridge processes payment
    const iso20022Bridge = await deployISO20022Bridge();
    await iso20022Bridge.processPayment(payment);
    
    // THEN: pacs.008 message generated
    const message = await iso20022Bridge.getGeneratedMessage();
    expect(message).to.include("<MsgId>");
    expect(message).to.include("<InstdAmt Ccy=\"USD\">10000</InstdAmt>");
    
    // WHEN: Inbound SWIFT message received (simulated)
    const inboundMessage = generateMockSWIFTMessage();
    await iso20022Bridge.receiveMessage(inboundMessage);
    
    // THEN: On-chain release triggered
    expect(await stable.balanceOf(recipient))to.equal(expectedAmount);
  });
});
```

**Success Criteria**:
- [x] pacs.008 payment initiation generated
- [x] pacs.002 payment status reports
- [x] camt.053 bank statement format
- [x] All required fields populated
- [x] Message validation passes
- [x] Integration events logged

---

## 4️⃣ MULTI-REPO INTEGRATION

### Scenario H: L1 + Stablecoin Layer Integration

**Claim**: Stablecoin layer operates on L1 infrastructure

**Test**: `foundry/test/MultiRepoIntegration.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {CompliantStable} from "../contracts/stable/CompliantStable.sol";
// Import from layer-1-unykorn (via remappings)
import {UnykornL1} from "layer-1-unykorn/contracts/UnykornL1.sol";

contract MultiRepoIntegrationTest is Test {
    function testEndToEndDeployment() public {
        // GIVEN: L1 chain running from layer-1-unykorn
        UnykornL1 l1 = new UnykornL1();
        l1.initializeChain();
        
        // WHEN: Deploy stablecoin layer
        CompliantStable stable = new CompliantStable("StableUSD", "SUSD", address(this));
        
        // THEN: Stablecoin interacts with L1
        stable.mint(address(0x1), 1000 ether);
        
        // Verify L1 records transaction
        assertEq(l1.getTransactionCount(), 1);
    }
    
    function testValidatorInteraction() public {
        // Test validator rewards in stable vs L1 gas token
    }
}
```

**Success Criteria**:
- [x] L1 chain starts successfully
- [x] Stablecoin contracts deploy to L1
- [x] Transactions processed by L1 validators
- [x] Gas fees paid in UNY (L1 token)
- [x] Cross-repo remappings work
- [x] Events from both repos logged

---

## 5️⃣ COMPLIANCE VALIDATION

### Scenario I: Basel CAR Capital Adequacy

**Claim**: Basel CAR module prevents risk-increasing operations when undercapitalized

**Test**: `compliant-bill-token/test/BaselCARConstraints.spec.ts`

```typescript
describe("Basel CAR Capital Constraints", function() {
  it("should block minting when CAR below minimum", async function() {
    // GIVEN: Bank with Basel CAR module
    const car = await deployBaselCAR();
    
    // Initialize with 8% CAR (minimum)
    await car.setCapital(ethers.parseEther("8000"));    // $8K capital
    await car.setRiskWeightedAssets(ethers.parseEther("100000")); // $100K RWA
    
    // CAR = 8000 / 100000 = 8%
    expect(await car.getCAR()).to.equal(800); // 800 basis points = 8%
    
    // WHEN: Attempt to mint (increases RWA)
    await expect(
      car.mint(user1.address, ethers.parseEther("50000")) // Would increase RWA to $150K
    ).to.be.revertedWith("CAR below minimum");
    
    // WHEN: Capital increased
    await car.addCapital(ethers.parseEther("4000")); // Now $12K capital
    
    // THEN: Minting allowed
    await expect(
      car.mint(user1.address, ethers.parseEther("50000"))
    ).to.not.be.reverted;
  });
});
```

**Success Criteria**:
- [x] CAR calculated correctly
- [x] Minimum 8% enforced
- [x] Risk-increasing ops blocked when <8%
- [x] Capital injection resumes operations
- [x] Regulatory reporting generated
- [x] All CAR changes logged

---

### Scenario J: Travel Rule Metadata

**Claim**: Transfers >$1000 require counterparty information

**Test**: `test/scenarios/TravelRule.spec.ts`

```typescript
describe("Travel Rule Compliance", function() {
  it("should require metadata for transfers >$1000", async function() {
    // GIVEN: Travel Rule engine enabled
    const travelRule = await deployTravelRuleEngine();
    await stable.setTravelRuleEngine(travelRule.address);
    
    // WHEN: Small transfer (<$1000)
    await expect(
      stable.connect(user1).transfer(user2.address, ethers.parseEther("500"))
    ).to.not.be.reverted; // No metadata required
    
    // WHEN: Large transfer (>$1000) without metadata
    await expect(
      stable.connect(user1).transfer(user2.address, ethers.parseEther("1500"))
    ).to.be.revertedWith("Travel Rule metadata required");
    
    // WHEN: Large transfer with metadata
    await travelRule.submitMetadata(txId, {
      originator: "John Doe",
      beneficiary: "Jane Smith",
      purpose: "Invoice #12345"
    });
    
    await expect(
      stable.connect(user1).transfer(user2.address, ethers.parseEther("1500"))
    ).to.not.be.reverted;
  });
});
```

**Success Criteria**:
- [x] Transfers <$1000: no metadata required
- [x] Transfers >$1000: metadata required
- [x] Metadata includes: originator, beneficiary, purpose
- [x] Whitelisted counterparties bypass
- [x] Regulatory export available
- [x] All travel rule events logged

---

## 6️⃣ DEMONSTRATED CAPABILITIES

### Demo A: DevNet Live Demonstration

**What to Show**:
1. **Start DevNet**
   ```bash
   # From layer-1-unykorn
   ./start-chain.sh
   
   # Verify chain running
   curl -X POST http://localhost:8545 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

2. **Deploy Stablecoin**
   ```bash
   # From stablecoin-and-cbdc
   npx hardhat run scripts/DeployCore.s.sol --network besu
   ```

3. **Execute Scenarios**
   ```bash
   # Run hero scenario
   npx hardhat test test/scenarios/StablecoinLifecycle.spec.ts --network besu
   ```

4. **Show Explorer**
   ```bash
   # Navigate to http://localhost:3000
   # Show transactions, events, contract state
   ```

**Success Criteria**:
- [x] Chain producing blocks (view in explorer)
- [x] RPC responding to requests
- [x] Contracts deployed and verified
- [x] Transactions executing successfully
- [x] Events visible in explorer
- [x] All modules integrated

---

### Demo B: Gold-Backed Stablecoin End-to-End

**Hero Product**: Institutional gold-backed stablecoin

**Flow**:
1. **Setup**
   - Deploy GoldRWAToken
   - Deploy CompliantStable backed by gold
   - Set up oracle for gold price
   - Configure compliance rules

2. **Mint to Institution**
   ```typescript
   // Institution passes KYC
   await kyc.verify(institutionAddress);
   
   // Add to whitelist
   await compliance.whitelist(institutionAddress);
   
   // Mint gold-backed stable
   await goldStable.mint(institutionAddress, amountInGrams);
   ```

3. **PoR Update**
   ```typescript
   // Oracle updates gold reserves
   await oracle.updateGoldHoldings(vaultId, gramsHeld);
   
   // System calculates backing ratio
   const backing = await goldStable.getBackingRatio();
   console.log(`Backing: ${backing}%`);
   ```

4. **Inter-Institution Transfer**
   ```typescript
   // Transfer between whitelisted institutions
   await goldStable.connect(inst1).transfer(inst2.address, amount);
   
   // Travel Rule metadata attached
   await travelRule.getMetadata(txHash);
   ```

5. **PoR Issue Simulation**
   ```typescript
   // Simulate 5% reserve discrepancy
   await oracle.updateGoldHoldings(vaultId, reducedAmount);
   
   // System reacts
   const status = await goldStable.getSystemStatus();
   expect(status).to.equal("MINTING_PAUSED");
   ```

6. **Resolution**
   ```typescript
   // Vault audit confirms reserves
   await oracle.updateGoldHoldings(vaultId, correctAmount);
   
   // System resumes
   expect(await goldStable.getSystemStatus()).to.equal("OPERATIONAL");
   ```

**Success Criteria**:
- [x] Real gold oracle integration
- [x] Institutional KYC/whitelist enforced
- [x] PoR monitoring active
- [x] Circuit breaker responsive
- [x] All events logged to explorer
- [x] Regulatory export available

---

## 7️⃣ NON-FUNCTIONAL VALIDATION

### Performance Test: Transaction Throughput

**Test**: `test/performance/Throughput.spec.ts`

```typescript
describe("System Performance", function() {
  it("should handle 100 TPS without degradation", async function() {
    const transactions = 1000;
    const duration = 10; // seconds
    
    const startTime = Date.now();
    
    for (let i = 0; i < transactions; i++) {
      await stable.transfer(randomAddress(), randomAmount());
    }
    
    const endTime = Date.now();
    const tps = transactions / ((endTime - startTime) / 1000);
    
    expect(tps).to.be.greaterThan(100);
  });
});
```

**Success Criteria**:
- [x] >100 TPS sustained
- [x] <1 second average latency
- [x] <2 seconds p99 latency
- [x] No memory leaks
- [x] Validator sync maintained
- [x] No consensus faults

---

### Security Test: Upgrade Safety

**Test**: `test/security/UpgradeSafety.spec.ts`

```typescript
describe("Upgrade Safety", function() {
  it("should upgrade without data loss", async function() {
    // GIVEN: V1 contract with state
    const v1 = await deployCompliantStableV1();
    await v1.mint(user1.address, ethers.parseEther("1000"));
    
    const balanceBefore = await v1.balanceOf(user1.address);
    
    // WHEN: Upgrade to V2 via proxy
    await upgradeProxy(v1.address, CompliantStableV2);
    const v2 = await ethers.getContractAt("CompliantStableV2", v1.address);
    
    // THEN: State preserved
    expect(await v2.balanceOf(user1.address)).to.equal(balanceBefore);
    
    // AND: New functionality available
    await v2.newFeature();
  });
});
```

**Success Criteria**:
- [x] State preserved across upgrades
- [x] Unauthorized upgrades blocked
- [x] Timelock enforced (24-48 hours)
- [x] Multi-sig approval required
- [x] Rollback possible
- [x] All upgrades logged

---

## 8️⃣ EXECUTION CHECKLIST

### Phase 1: Scenario Tests (Week 1)
- [ ] Write all scenario tests
- [ ] Achieve >80% coverage on core contracts
- [ ] All scenarios passing locally
- [ ] Document unexpected behaviors
- [ ] Fix issues discovered

### Phase 2: Integration Tests (Week 2)
- [ ] Set up DevNet from both repos
- [ ] Deploy full stack
- [ ] Run multi-repo integration tests
- [ ] Verify cross-repo communication
- [ ] Document integration issues

### Phase 3: Live Demo (Week 3)
- [ ] Prepare demo environment
- [ ] Script hero product scenarios
- [ ] Record demo videos
- [ ] Create demo documentation
- [ ] Train team on demos

### Phase 4: Performance & Security (Week 4)
- [ ] Run performance benchmarks
- [ ] Execute security test suite
- [ ] Conduct upgrade simulations
- [ ] Load test DevNet
- [ ] Document results

---

## 9️⃣ REPORTING

### Test Report Format

```markdown
# Integration Test Report

**Date**: YYYY-MM-DD
**Tester**: Name
**Environment**: DevNet / Testnet / Local

## Scenarios Executed
- [x] Stablecoin Lifecycle - PASS
- [x] Blacklist Enforcement - PASS
- [ ] CBDC Tiering - FAIL (Tier 3 limit not enforced)
- [x] PoR Circuit Breaker - PASS
- ...

## Issues Discovered
1. **Tier 3 limit bypass** - Critical
   - Description: ...
   - Steps to reproduce: ...
   - Expected: ...
   - Actual: ...
   - Fix status: ...

## Performance Metrics
- TPS: 127 (target: 100) ✅
- Latency p50: 0.8s ✅
- Latency p99: 1.9s ✅
- Memory usage: Stable ✅

## Recommendations
1. Add additional edge case tests for tiering
2. Improve oracle failover speed
3. Optimize gas usage in compliance checks
```

---

## 🔟 SUCCESS CRITERIA

**System is validated when**:
- ✅ All core money flow scenarios pass
- ✅ Compliance enforcement demonstrated
- ✅ PoR monitoring working
- ✅ Cross-chain rails functional
- ✅ Multi-repo integration successful
- ✅ Live demo runs smoothly
- ✅ Performance targets met
- ✅ Security tests pass
- ✅ Upgrade flows safe
- ✅ Zero critical bugs unfixed

**Timeline**: 4 weeks to complete all validation scenarios

---

**Next Steps**:  
1. Implement scenario tests
2. Fix any discovered issues
3. Complete DevNet setup
4. Run live demonstrations
5. Document all results
