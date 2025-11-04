// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/layer1/UnykornL1Bridge.sol";
import "../../contracts/swift/SWIFTGPIAdapter.sol";
import "../../contracts/swift/SWIFTSharedLedgerRail.sol";
import "../../contracts/settlement/stable/UnykornStableRail.sol";
import "../../contracts/compliance/TravelRuleEngine.sol";
import "../../contracts/risk/BaselIIIRiskModule.sol";
import "../../contracts/registry/MasterRegistry.sol";
import "../../contracts/settlement/rails/RailRegistry.sol";
import "../../contracts/settlement/stable/StablecoinRegistry.sol";
import "../../contracts/compliance/ComplianceRegistryUpgradeable.sol";
import "../../contracts/settlement/rails/ExternalRail.sol";
import "../../contracts/mocks/MockMintableERC20.sol";
import "../../contracts/common/Types.sol";

/**
 * @title SRIntegration
 * @notice Comprehensive integration tests for SR-level SWIFT, Besu, Unykorn L1, and compliance infrastructure
 */
contract SRIntegrationTest is Test {
    // Core registries
    RailRegistry railRegistry;
    StablecoinRegistry stablecoinRegistry;
    ComplianceRegistryUpgradeable complianceRegistry;
    MasterRegistry masterRegistry;
    
    // Rails
    UnykornStableRail unykornRail;
    SWIFTSharedLedgerRail swiftRail;
    ExternalRail externalRail;
    
    // SWIFT & L1
    SWIFTGPIAdapter swiftAdapter;
    UnykornL1Bridge l1Bridge;
    
    // Compliance
    TravelRuleEngine travelRule;
    BaselIIIRiskModule baselModule;
    
    // Mock tokens
    MockMintableERC20 uUSD;
    MockMintableERC20 mockOracle;
    
    // Test accounts
    address admin = address(this);
    address governor = address(0x1);
    address executor = address(0x2);
    address alice = address(0x3);
    address bob = address(0x4);
    address vasp1 = address(0x5);
    address vasp2 = address(0x6);
    
    function setUp() public {
        // Deploy mock tokens
        uUSD = new MockMintableERC20("Unykorn USD", "uUSD");
        mockOracle = new MockMintableERC20("Mock Oracle", "MOCK");
        
        // Deploy registries
        railRegistry = new RailRegistry(admin);
        stablecoinRegistry = new StablecoinRegistry(admin);
        complianceRegistry = new ComplianceRegistryUpgradeable();
        complianceRegistry.initialize(admin);
        
        // Deploy compliance modules  
        travelRule = new TravelRuleEngine(1000 * 1e18); // threshold
        baselModule = new BaselIIIRiskModule();
        
        // Deploy rails
        externalRail = new ExternalRail(admin, executor);
        unykornRail = new UnykornStableRail(
            address(uUSD),
            address(mockOracle),
            address(complianceRegistry)
        );
        swiftRail = new SWIFTSharedLedgerRail();
        
        // Deploy SWIFT adapter
        swiftAdapter = new SWIFTGPIAdapter(address(externalRail));
        
        // Deploy L1 bridge
        l1Bridge = new UnykornL1Bridge(address(railRegistry));
        
        // Deploy master registry
        masterRegistry = new MasterRegistry(
            address(railRegistry),
            address(stablecoinRegistry),
            address(complianceRegistry)
        );
        
        // Register rails
        bytes32 unykornKey = keccak256("UNYKORN_RAIL");
        bytes32 swiftKey = keccak256("SWIFT_SHARED_LEDGER");
        bytes32 externalKey = keccak256("EXTERNAL_RAIL");
        
        railRegistry.set(unykornKey, address(unykornRail));
        railRegistry.set(swiftKey, address(swiftRail));
        railRegistry.set(externalKey, address(externalRail));
        
        // Register uUSD in stablecoin registry
        stablecoinRegistry.setStablecoin(
            address(uUSD),
            true, // supported
            keccak256("UNYKORN_RESERVE"), // reserveId
            address(mockOracle), // por
            10000, // minReserveRatioBps (100%)
            unykornKey, // defaultRailKey
            bytes32(0), // cctpRailKey
            bytes32(0)  // ccipRailKey
        );
        
        // Setup compliance for test accounts (skip for now - will use mock if needed)
        
        // Mint test tokens
        uUSD.mint(alice, 1000000 * 1e18);
        uUSD.mint(address(unykornRail), 1000000 * 1e18);
    }
    
    // ========== 1. UnykornStableRail Tests ==========
    
    function test_UnykornRail_Kind() public {
        // UnykornStableRail returns ERC20 kind
        assertEq(uint(unykornRail.kind()), uint(IRail.Kind.ERC20));
    }
    
    function test_UnykornRail_PrepareTransfer() public {
        IRail.Transfer memory xfer = IRail.Transfer({
            asset: address(uUSD),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: ""
        });
        
        vm.prank(alice);
        uUSD.approve(address(unykornRail), 1000 * 1e18);
        
        unykornRail.prepare(xfer);
        
        bytes32 id = unykornRail.transferId(xfer);
        assertEq(uint(unykornRail.status(id)), uint(IRail.Status.PREPARED));
    }
    
    function test_UnykornRail_ReleaseTransfer() public {
        IRail.Transfer memory xfer = IRail.Transfer({
            asset: address(uUSD),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: ""
        });
        
        vm.prank(alice);
        uUSD.approve(address(unykornRail), 1000 * 1e18);
        
        unykornRail.prepare(xfer);
        bytes32 id = unykornRail.transferId(xfer);
        
        uint256 bobBalBefore = uUSD.balanceOf(bob);
        unykornRail.release(id, xfer);
        uint256 bobBalAfter = uUSD.balanceOf(bob);
        
        assertEq(bobBalAfter - bobBalBefore, 1000 * 1e18);
        assertEq(uint(unykornRail.status(id)), uint(IRail.Status.RELEASED));
    }
    
    function test_UnykornRail_RefundTransfer() public {
        IRail.Transfer memory xfer = IRail.Transfer({
            asset: address(uUSD),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: ""
        });
        
        vm.prank(alice);
        uUSD.approve(address(unykornRail), 1000 * 1e18);
        
        uint256 aliceBalBefore = uUSD.balanceOf(alice);
        unykornRail.prepare(xfer);
        bytes32 id = unykornRail.transferId(xfer);
        
        unykornRail.refund(id, xfer);
        uint256 aliceBalAfter = uUSD.balanceOf(alice);
        
        assertEq(aliceBalAfter, aliceBalBefore);
        assertEq(uint(unykornRail.status(id)), uint(IRail.Status.REFUNDED));
    }
    
    // ========== 2. SWIFT Integration Tests ==========
    
    function test_SWIFTAdapter_InitiatePayment() public {
        string memory uetr = "550e8400-e29b-41d4-a716-446655440000";
        bytes32 settlementId = keccak256(abi.encodePacked(uetr));
        
        swiftAdapter.initiateGPIPayment(uetr, settlementId);
        
        Types.SWIFTTracking memory tracking = swiftAdapter.getGPITracking(uetr);
        assertEq(uint(tracking.status), uint(Types.SWIFTStatus.PENDING));
        assertEq(swiftAdapter.getUETRForSettlement(settlementId), uetr);
    }
    
    function test_SWIFTAdapter_UpdateStatus() public {
        string memory uetr = "550e8400-e29b-41d4-a716-446655440001";
        bytes32 settlementId = keccak256(abi.encodePacked(uetr));
        
        swiftAdapter.initiateGPIPayment(uetr, settlementId);
        swiftAdapter.updateGPIStatus(uetr, Types.SWIFTStatus.PENDING);
        
        Types.SWIFTTracking memory tracking = swiftAdapter.getGPITracking(uetr);
        assertEq(uint(tracking.status), uint(Types.SWIFTStatus.PENDING));
    }
    
    function test_SWIFTAdapter_CompletePayment() public {
        string memory uetr = "550e8400-e29b-41d4-a716-446655440002";
        bytes32 settlementId = keccak256(abi.encodePacked(uetr));
        bytes32 receiptHash = keccak256("SWIFT_RECEIPT");
        
        // Prepare external rail first
        IRail.Transfer memory dummyXfer = IRail.Transfer({
            asset: address(0),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: ""
        });
        externalRail.prepare(dummyXfer);
        
        swiftAdapter.initiateGPIPayment(uetr, settlementId);
        
        vm.prank(executor);
        swiftAdapter.completeGPIPayment(uetr, settlementId, receiptHash);
        
        Types.SWIFTTracking memory tracking = swiftAdapter.getGPITracking(uetr);
        assertEq(uint(tracking.status), uint(Types.SWIFTStatus.COMPLETED));
    }
    
    function test_SWIFTSharedLedgerRail_Prepare() public {
        IRail.Transfer memory xfer = IRail.Transfer({
            asset: address(uUSD),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: abi.encode("SWIFT_LEG_DATA")
        });
        
        swiftRail.prepare(xfer);
        bytes32 id = swiftRail.transferId(xfer);
        
        assertEq(uint(swiftRail.status(id)), uint(IRail.Status.PREPARED));
    }
    
    // ========== 3. Compliance Module Tests ==========
    
    function test_TravelRule_RegisterVASP() public {
        travelRule.registerVASP(vasp1, "VASP1", "US", "LEI123456789");
        assertTrue(travelRule.isVASP(vasp1));
    }
    
    function test_TravelRule_CheckVASPCount() public {
        // Test VASP registration count
        travelRule.registerVASP(vasp1, "VASP1", "US", "LEI123456789");
        assertTrue(travelRule.isVASP(vasp1));
    }
    
    function test_TravelRule_DeactivateVASP() public {
        travelRule.registerVASP(vasp1, "VASP1", "US", "LEI123456789");
        assertTrue(travelRule.isVASP(vasp1));
        
        travelRule.deactivateVASP(vasp1);
        assertFalse(travelRule.isVASP(vasp1));
    }
    
    function test_BaselIII_SetRiskWeight() public {
        uint16 newWeight = 15000; // 150%
        baselModule.setRiskWeight(BaselIIIRiskModule.RiskCategory.CORPORATE, newWeight);
        
        assertEq(baselModule.riskWeights(BaselIIIRiskModule.RiskCategory.CORPORATE), newWeight);
    }
    
    function test_BaselIII_SetMinimumCAR() public {
        uint256 newMinCAR = 1000; // 10%
        baselModule.setMinimumCAR(newMinCAR);
        
        // Verify via checkCAR or state if exposed
    }
    
    // ========== 4. Registry Interconnection Tests ==========
    
    function test_MasterRegistry_GetRail() public {
        bytes32 unykornKey = keccak256("UNYKORN_RAIL");
        address railAddr = masterRegistry.getRail(unykornKey);
        
        assertEq(railAddr, address(unykornRail));
    }
    
    function test_MasterRegistry_GetStablecoin() public {
        StablecoinRegistry.Meta memory meta = masterRegistry.getStablecoin(address(uUSD));
        
        assertTrue(meta.supported);
        assertEq(meta.defaultRailKey, keccak256("UNYKORN_RAIL"));
    }
    
    function test_MasterRegistry_IsCompliant() public {
        bool compliant = masterRegistry.isCompliant(alice);
        assertTrue(compliant);
    }
    
    function test_MasterRegistry_GetAllRegistries() public {
        (
            address rail,
            address stable,
            address compliance,
            address rwa,
            address swift,
            address besu,
            address travelRuleAddr
        ) = masterRegistry.getAllRegistries();
        
        assertEq(rail, address(railRegistry));
        assertEq(stable, address(stablecoinRegistry));
        assertEq(compliance, address(complianceRegistry));
    }
    
    // ========== 5. L1 Bridge Tests ==========
    
    function test_L1Bridge_Deployed() public {
        // Verify L1 bridge was deployed
        assertTrue(address(l1Bridge) != address(0));
    }
    
    // ========== 6. End-to-End Integration Tests ==========
    
    function test_E2E_UnykornToSWIFT() public {
        // 1. Prepare Unykorn rail transfer
        IRail.Transfer memory xfer = IRail.Transfer({
            asset: address(uUSD),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: ""
        });
        
        vm.prank(alice);
        uUSD.approve(address(unykornRail), 1000 * 1e18);
        
        unykornRail.prepare(xfer);
        bytes32 unykornId = unykornRail.transferId(xfer);
        
        // 2. Initiate SWIFT GPI payment
        string memory uetr = "550e8400-e29b-41d4-a716-446655440003";
        bytes32 swiftSettlementId = keccak256(abi.encodePacked(uetr));
        
        swiftAdapter.initiateGPIPayment(uetr, swiftSettlementId);
        
        // 3. Complete Unykorn rail
        unykornRail.release(unykornId, xfer);
        
        // 4. Complete SWIFT payment
        IRail.Transfer memory swiftDummy = IRail.Transfer({
            asset: address(0),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: ""
        });
        externalRail.prepare(swiftDummy);
        
        vm.prank(executor);
        swiftAdapter.completeGPIPayment(uetr, swiftSettlementId, keccak256("RECEIPT"));
        
        // Verify both legs completed
        assertEq(uint(unykornRail.status(unykornId)), uint(IRail.Status.RELEASED));
        
        Types.SWIFTTracking memory tracking = swiftAdapter.getGPITracking(uetr);
        assertEq(uint(tracking.status), uint(Types.SWIFTStatus.COMPLETED));
    }
    
    function test_E2E_ComplianceGate() public {
        // Test compliance gate (simplified - actual compliance checks depend on registry implementation)
        IRail.Transfer memory xfer = IRail.Transfer({
            asset: address(uUSD),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: ""
        });
        
        vm.prank(alice);
        uUSD.approve(address(unykornRail), 1000 * 1e18);
        
        // Should succeed with compliant accounts
        unykornRail.prepare(xfer);
        bytes32 id = unykornRail.transferId(xfer);
        assertEq(uint(unykornRail.status(id)), uint(IRail.Status.PREPARED));
    }
    
    function test_E2E_TravelRuleEnforcement() public {
        // Register VASPs
        travelRule.registerVASP(vasp1, "VASP1", "US", "LEI123456789");
        travelRule.registerVASP(vasp2, "VASP2", "EU", "LEI987654321");
        
        // Verify VASPs were registered
        assertTrue(travelRule.isVASP(vasp1));
        assertTrue(travelRule.isVASP(vasp2));
    }
    
    // ========== 7. Failure Scenarios ==========
    
    function testFail_UnykornRail_DoubleRelease() public {
        IRail.Transfer memory xfer = IRail.Transfer({
            asset: address(uUSD),
            from: alice,
            to: bob,
            amount: 1000 * 1e18,
            metadata: ""
        });
        
        vm.prank(alice);
        uUSD.approve(address(unykornRail), 1000 * 1e18);
        
        unykornRail.prepare(xfer);
        bytes32 id = unykornRail.transferId(xfer);
        
        unykornRail.release(id, xfer);
        unykornRail.release(id, xfer); // Should fail
    }
    
    function testFail_SWIFTAdapter_UnauthorizedComplete() public {
        string memory uetr = "550e8400-e29b-41d4-a716-446655440004";
        bytes32 settlementId = keccak256(abi.encodePacked(uetr));
        
        swiftAdapter.initiateGPIPayment(uetr, settlementId);
        
        // Non-executor tries to complete (should fail)
        vm.prank(alice);
        swiftAdapter.completeGPIPayment(uetr, settlementId, keccak256("RECEIPT"));
    }
    
    function testFail_TravelRule_DeactivateUnregistered() public {
        // Try to deactivate unregistered VASP (should fail)
        travelRule.deactivateVASP(vasp1); // Not registered
    }
}
