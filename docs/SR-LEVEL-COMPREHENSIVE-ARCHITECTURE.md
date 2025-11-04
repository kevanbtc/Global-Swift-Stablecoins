# SR-Level Comprehensive Architecture: SWIFT, Agorá, RLN, Fnality + Gold RWA & Natural Resource Assets

## Executive Summary

This document outlines the SR (Settlement Rails) level architecture for a comprehensive institutional-grade settlement system integrating:

1. **SWIFT GPI & Shared Ledger** - Traditional banking rails
2. **BIS Project Agorá** - Tokenized deposits + CBDC on programmable ledger
3. **RLN (Regulated Liability Network)** - Multi-CBDC settlement network
4. **Fnality** - Wholesale settlement using tokenized central bank money
5. **Gold RWA** - Tokenized in-ground gold reserves
6. **Natural Resource Assets** - Water rights, mineral rights, patented deeds
7. **Self-Instant Settlement** - Atomic cross-asset settlement contracts

---

## 1. SWIFT Integration Layer

### 1.1 SWIFT GPI Adapter (Existing + Enhanced)
**File**: `contracts/swift/SWIFTGPIAdapter.sol`

**Purpose**: Connects to SWIFT GPI for real-time payment tracking and status updates.

**Key Components**:
```solidity
// Enhanced SWIFT GPI tracking with Agorá integration
struct SWIFTGPIPayment {
    string uetr;                    // Unique End-to-End Transaction Reference
    bytes32 settlementId;           // Internal settlement ID
    Types.SWIFTStatus status;       // PENDING, COMPLETED, FAILED
    address initiator;              // Payment initiator
    uint256 amount;                 // Payment amount
    string currency;                // ISO currency code
    uint256 timestamp;              // Initiation timestamp
    bytes32 agoraLedgerHash;       // Link to Agorá ledger entry
    bool isAgoraSettled;           // Settled via Agorá
}

// Integration with Agorá tokenized deposits
function initiateAgoraGPIPayment(
    string memory uetr,
    bytes32 settlementId,
    address tokenizedDeposit,      // Agorá tokenized deposit contract
    uint256 amount
) external;

// Fnality integration for wholesale settlement
function initiateFnalityGPIPayment(
    string memory uetr,
    bytes32 settlementId,
    address fnalityToken,          // Fnality USC/GBPf token
    uint256 amount
) external;
```

### 1.2 SWIFT Shared Ledger Rail
**File**: `contracts/swift/SWIFTSharedLedgerRail.sol`

**Purpose**: Integrates with SWIFT's blockchain-based shared ledger (announced Sep 2025).

**Key Features**:
- Smart contract validation on SWIFT ledger
- Instant cross-border settlement
- Interoperability with Agorá and RLN

---

## 2. BIS Project Agorá Integration

### 2.1 Agorá Tokenized Deposit Adapter
**New File**: `contracts/agora/AgoraTokenizedDepositAdapter.sol`

**Purpose**: Interfaces with BIS Agorá's tokenized commercial bank deposits and CBDC.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AgoraTokenizedDepositAdapter
 * @notice Adapter for BIS Project Agorá tokenized deposits + CBDC
 * @dev Integrates with programmable ledger for unified liquidity
 */
contract AgoraTokenizedDepositAdapter is Ownable {
    
    struct TokenizedDeposit {
        address depositToken;           // Tokenized deposit contract
        address issuerBank;             // Issuing commercial bank
        string currency;                // ISO currency code
        bool isCBDC;                    // True if central bank money
        uint256 totalSupply;            // Total tokenized amount
        bytes32 agoraLedgerRef;        // Reference to Agorá ledger
    }
    
    struct AgoraSettlement {
        bytes32 settlementId;
        address[] depositTokens;        // Multiple tokenized deposits
        uint256[] amounts;              // Amounts per token
        address beneficiary;
        bool isAtomic;                  // Atomic multi-currency settlement
        uint256 timestamp;
        bytes32 swiftUETR;             // Link to SWIFT payment
    }
    
    mapping(address => TokenizedDeposit) public deposits;
    mapping(bytes32 => AgoraSettlement) public settlements;
    
    event DepositRegistered(address indexed token, address indexed bank, string currency);
    event AgoraSettlementInitiated(bytes32 indexed settlementId, address indexed beneficiary);
    event AgoraSettlementCompleted(bytes32 indexed settlementId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Register a tokenized deposit from Agorá
     */
    function registerTokenizedDeposit(
        address depositToken,
        address issuerBank,
        string memory currency,
        bool isCBDC,
        bytes32 agoraLedgerRef
    ) external onlyOwner {
        deposits[depositToken] = TokenizedDeposit({
            depositToken: depositToken,
            issuerBank: issuerBank,
            currency: currency,
            isCBDC: isCBDC,
            totalSupply: IERC20(depositToken).totalSupply(),
            agoraLedgerRef: agoraLedgerRef
        });
        
        emit DepositRegistered(depositToken, issuerBank, currency);
    }
    
    /**
     * @notice Initiate atomic multi-currency settlement via Agorá
     */
    function initiateAgoraSettlement(
        bytes32 settlementId,
        address[] memory depositTokens,
        uint256[] memory amounts,
        address beneficiary,
        bytes32 swiftUETR
    ) external returns (bool) {
        require(depositTokens.length == amounts.length, "Length mismatch");
        
        settlements[settlementId] = AgoraSettlement({
            settlementId: settlementId,
            depositTokens: depositTokens,
            amounts: amounts,
            beneficiary: beneficiary,
            isAtomic: true,
            timestamp: block.timestamp,
            swiftUETR: swiftUETR
        });
        
        emit AgoraSettlementInitiated(settlementId, beneficiary);
        return true;
    }
    
    /**
     * @notice Complete Agorá settlement (called by oracle/executor)
     */
    function completeAgoraSettlement(bytes32 settlementId) external onlyOwner {
        AgoraSettlement storage settlement = settlements[settlementId];
        require(settlement.timestamp > 0, "Settlement not found");
        
        // Transfer all tokenized deposits atomically
        for (uint i = 0; i < settlement.depositTokens.length; i++) {
            IERC20(settlement.depositTokens[i]).transfer(
                settlement.beneficiary,
                settlement.amounts[i]
            );
        }
        
        emit AgoraSettlementCompleted(settlementId);
    }
}
```

---

## 3. RLN (Regulated Liability Network) Integration

### 3.1 RLN Multi-CBDC Adapter
**New File**: `contracts/rln/RLNMultiCBDCAdapter.sol`

**Purpose**: Connects to RLN for multi-CBDC settlement across jurisdictions.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RLNMultiCBDCAdapter
 * @notice Adapter for Regulated Liability Network (RLN) multi-CBDC settlement
 * @dev Enables atomic FX settlement across multiple CBDCs
 */
contract RLNMultiCBDCAdapter is Ownable {
    
    struct CBDCToken {
        address tokenAddress;
        string jurisdiction;            // US, EU, UK, SG, etc.
        string currencyCode;            // USD, EUR, GBP, SGD
        address centralBank;            // Issuing central bank
        bool isActive;
    }
    
    struct RLNSettlement {
        bytes32 settlementId;
        address[] cbdcTokens;           // Multiple CBDCs
        uint256[] amounts;              // Amounts per CBDC
        address[] participants;         // Settlement participants
        uint256 fxRate;                 // Agreed FX rate (scaled)
        bool isCompleted;
        uint256 timestamp;
    }
    
    mapping(address => CBDCToken) public cbdcs;
    mapping(bytes32 => RLNSettlement) public settlements;
    
    event CBDCRegistered(address indexed token, string jurisdiction, string currency);
    event RLNSettlementInitiated(bytes32 indexed settlementId);
    event RLNSettlementCompleted(bytes32 indexed settlementId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Register a CBDC token in RLN
     */
    function registerCBDC(
        address tokenAddress,
        string memory jurisdiction,
        string memory currencyCode,
        address centralBank
    ) external onlyOwner {
        cbdcs[tokenAddress] = CBDCToken({
            tokenAddress: tokenAddress,
            jurisdiction: jurisdiction,
            currencyCode: currencyCode,
            centralBank: centralBank,
            isActive: true
        });
        
        emit CBDCRegistered(tokenAddress, jurisdiction, currencyCode);
    }
    
    /**
     * @notice Initiate atomic multi-CBDC FX settlement
     */
    function initiateRLNSettlement(
        bytes32 settlementId,
        address[] memory cbdcTokens,
        uint256[] memory amounts,
        address[] memory participants,
        uint256 fxRate
    ) external returns (bool) {
        require(cbdcTokens.length == amounts.length, "Length mismatch");
        require(cbdcTokens.length >= 2, "Need at least 2 CBDCs");
        
        settlements[settlementId] = RLNSettlement({
            settlementId: settlementId,
            cbdcTokens: cbdcTokens,
            amounts: amounts,
            participants: participants,
            fxRate: fxRate,
            isCompleted: false,
            timestamp: block.timestamp
        });
        
        emit RLNSettlementInitiated(settlementId);
        return true;
    }
}
```

---

## 4. Fnality Integration

### 4.1 Fnality Wholesale Settlement Adapter
**New File**: `contracts/fnality/FnalitySettlementAdapter.sol`

**Purpose**: Integrates with Fnality's tokenized central bank money (USC, GBPf, EURf).

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FnalitySettlementAdapter
 * @notice Adapter for Fnality wholesale settlement using tokenized CB money
 * @dev Supports USC (Utility Settlement Coin), GBPf, EURf, etc.
 */
contract FnalitySettlementAdapter is Ownable {
    
    struct FnalityToken {
        address tokenAddress;
        string currency;                // USD, GBP, EUR, etc.
        address centralBank;
        bool isActive;
    }
    
    struct FnalityPvP {
        bytes32 settlementId;
        address tokenA;                 // First Fnality token
        address tokenB;                 // Second Fnality token
        uint256 amountA;
        uint256 amountB;
        address partyA;
        address partyB;
        bool isAtomic;                  // Atomic PvP settlement
        bool isCompleted;
        uint256 timestamp;
    }
    
    mapping(address => FnalityToken) public fnalityTokens;
    mapping(bytes32 => FnalityPvP) public pvpSettlements;
    
    event FnalityTokenRegistered(address indexed token, string currency);
    event FnalityPvPInitiated(bytes32 indexed settlementId);
    event FnalityPvPCompleted(bytes32 indexed settlementId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Register a Fnality token (USC, GBPf, etc.)
     */
    function registerFnalityToken(
        address tokenAddress,
        string memory currency,
        address centralBank
    ) external onlyOwner {
        fnalityTokens[tokenAddress] = FnalityToken({
            tokenAddress: tokenAddress,
            currency: currency,
            centralBank: centralBank,
            isActive: true
        });
        
        emit FnalityTokenRegistered(tokenAddress, currency);
    }
    
    /**
     * @notice Initiate atomic PvP settlement via Fnality
     */
    function initiateFnalityPvP(
        bytes32 settlementId,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address partyA,
        address partyB
    ) external returns (bool) {
        require(fnalityTokens[tokenA].isActive, "Token A not active");
        require(fnalityTokens[tokenB].isActive, "Token B not active");
        
        pvpSettlements[settlementId] = FnalityPvP({
            settlementId: settlementId,
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            partyA: partyA,
            partyB: partyB,
            isAtomic: true,
            isCompleted: false,
            timestamp: block.timestamp
        });
        
        emit FnalityPvPInitiated(settlementId);
        return true;
    }
}
```

---

## 5. Gold RWA & Natural Resource Assets

### 5.1 Gold RWA Token (In-Ground Reserves)
**New File**: `contracts/rwa/GoldRWAToken.sol`

**Purpose**: Tokenizes in-ground gold reserves with geological surveys and mining rights.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title GoldRWAToken
 * @notice Tokenized in-ground gold reserves
 * @dev Each token represents 1 troy ounce of proven/probable gold reserves
 */
contract GoldRWAToken is ERC20, AccessControl {
    
    bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
    
    struct GoldReserve {
        string mineLocation;            // GPS coordinates or jurisdiction
        uint256 provenReserves;         // Troy ounces (proven)
        uint256 probableReserves;       // Troy ounces (probable)
        bytes32 geologicalSurveyHash;   // IPFS hash of survey
        bytes32 miningRightsHash;       // IPFS hash of rights deed
        address miningCompany;
        uint256 lastAuditTimestamp;
        bool isActive;
    }
    
    struct GoldAudit {
        bytes32 reserveId;
        uint256 auditedAmount;          // Troy ounces verified
        address auditor;
        bytes32 reportHash;             // IPFS hash of audit report
        uint256 timestamp;
    }
    
    mapping(bytes32 => GoldReserve) public reserves;
    mapping(bytes32 => GoldAudit[]) public audits;
    
    event ReserveRegistered(bytes32 indexed reserveId, string location, uint256 amount);
    event ReserveAudited(bytes32 indexed reserveId, uint256 amount, address auditor);
    event GoldMinted(address indexed to, uint256 amount, bytes32 reserveId);
    
    constructor() ERC20("Gold RWA Token", "GRWA") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @notice Register new in-ground gold reserve
     */
    function registerReserve(
        bytes32 reserveId,
        string memory mineLocation,
        uint256 provenReserves,
        uint256 probableReserves,
        bytes32 geologicalSurveyHash,
        bytes32 miningRightsHash,
        address miningCompany
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        reserves[reserveId] = GoldReserve({
            mineLocation: mineLocation,
            provenReserves: provenReserves,
            probableReserves: probableReserves,
            geologicalSurveyHash: geologicalSurveyHash,
            miningRightsHash: miningRightsHash,
            miningCompany: miningCompany,
            lastAuditTimestamp: block.timestamp,
            isActive: true
        });
        
        emit ReserveRegistered(reserveId, mineLocation, provenReserves);
    }
    
    /**
     * @notice Audit gold reserve (by certified auditor)
     */
    function auditReserve(
        bytes32 reserveId,
        uint256 auditedAmount,
        bytes32 reportHash
    ) external onlyRole(AUDITOR_ROLE) {
        require(reserves[reserveId].isActive, "Reserve not active");
        
        audits[reserveId].push(GoldAudit({
            reserveId: reserveId,
            auditedAmount: auditedAmount,
            auditor: msg.sender,
            reportHash: reportHash,
            timestamp: block.timestamp
        }));
        
        reserves[reserveId].lastAuditTimestamp = block.timestamp;
        
        emit ReserveAudited(reserveId, auditedAmount, msg.sender);
    }
    
    /**
     * @notice Mint tokens against audited reserves
     */
    function mintAgainstReserve(
        address to,
        uint256 amount,
        bytes32 reserveId
    ) external onlyRole(MINER_ROLE) {
        require(reserves[reserveId].isActive, "Reserve not active");
        require(
            reserves[reserveId].provenReserves >= totalSupply() + amount,
            "Exceeds proven reserves"
        );
        
        _mint(to, amount);
        emit GoldMinted(to, amount, reserveId);
    }
}
```

### 5.2 Natural Resource Rights Token
**New File**: `contracts/rwa/NaturalResourceRightsToken.sol`

**Purpose**: Tokenizes water rights, mineral rights, and patented deeds.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title NaturalResourceRightsToken
 * @notice NFT representing natural resource rights (water, minerals, land)
 * @dev Each NFT is a unique deed/right with legal enforceability
 */
contract NaturalResourceRightsToken is ERC721, AccessControl {
    
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    
    enum ResourceType { WATER, MINERAL, LAND, TIMBER, OIL_GAS }
    
    struct ResourceRight {
        uint256 tokenId;
        ResourceType resourceType;
        string jurisdiction;            // Legal jurisdiction
        string legalDescription;        // Metes and bounds description
        bytes32 deedHash;              // IPFS hash of legal deed
        bytes32 surveyHash;            // IPFS hash of survey
        uint256 acreage;               // Size in acres
        uint256 annualYield;           // Estimated annual yield (units vary)
        address registeredOwner;
        uint256 registrationDate;
        bool isEncumbered;             // Has liens/mortgages
    }
    
    struct WaterRight {
        uint256 tokenId;
        uint256 annualAllocation;      // Acre-feet per year
        string waterSource;            // River, aquifer, etc.
        uint256 priority;              // Priority date (earlier = senior)
        bool isSenior;                 // Senior vs junior right
    }
    
    struct MineralRight {
        uint256 tokenId;
        string[] minerals;             // Gold, silver, copper, etc.
        uint256 royaltyRate;           // Percentage (scaled by 100)
        bool includesSubsurface;       // Full subsurface rights
    }
    
    mapping(uint256 => ResourceRight) public resourceRights;
    mapping(uint256 => WaterRight) public waterRights;
    mapping(uint256 => MineralRight) public mineralRights;
    
    uint256 private _nextTokenId;
    
    event ResourceRightRegistered(uint256 indexed tokenId, ResourceType resourceType, string jurisdiction);
    event WaterRightAllocated(uint256 indexed tokenId, uint256 allocation);
    event MineralRightGranted(uint256 indexed tokenId, string[] minerals);
    
    constructor() ERC721("Natural Resource Rights", "NRR") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @notice Register a new natural resource right
     */
    function registerResourceRight(
        ResourceType resourceType,
        string memory jurisdiction,
        string memory legalDescription,
        bytes32 deedHash,
        bytes32 surveyHash,
        uint256 acreage,
        address owner
    ) external onlyRole(REGISTRAR_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        
        resourceRights[tokenId] = ResourceRight({
            tokenId: tokenId,
            resourceType: resourceType,
            jurisdiction: jurisdiction,
            legalDescription: legalDescription,
            deedHash: deedHash,
            surveyHash: surveyHash,
            acreage: acreage,
            annualYield: 0,
            registeredOwner: owner,
            registrationDate: block.timestamp,
            isEncumbered: false
        });
        
        _safeMint(owner, tokenId);
        
        emit ResourceRightRegistered(tokenId, resourceType, jurisdiction);
        return tokenId;
    }
    
    /**
     * @notice Allocate water rights to a token
     */
    function allocateWaterRight(
        uint256 tokenId,
        uint256 annualAllocation,
        string memory waterSource,
        uint256 priority,
        bool isSenior
    ) external onlyRole(REGISTRAR_ROLE) {
        require(resourceRights[tokenId].resourceType == ResourceType.WATER, "Not a water right");
        
        waterRights[tokenId] = WaterRight({
            tokenId: tokenId,
            annualAllocation: annualAllocation,
            waterSource: waterSource,
            priority: priority,
            isSenior: isSenior
        });
        
        emit WaterRightAllocated(tokenId, annualAllocation);
    }
    
    /**
     * @notice Grant mineral rights to a token
     */
    function grantMineralRight(
        uint256 tokenId,
        string[] memory minerals,
        uint256 royaltyRate,
        bool includesSubsurface
    ) external onlyRole(REGISTRAR_ROLE) {
        require(resourceRights[tokenId].resourceType == ResourceType.MINERAL, "Not a mineral right");
        
        mineralRights[tokenId] = MineralRight({
            tokenId: tokenId,
            minerals: minerals,
            royaltyRate: royaltyRate,
            includesSubsurface: includesSubsurface
        });
        
        emit MineralRightGranted(tokenId, minerals);
    }
}
```

---

## 6. Self-Instant Settlement Contracts

### 6.1 Atomic Cross-Asset Settlement Engine
**New File**: `contracts/settlement/AtomicCrossAssetSettlement.sol`

**Purpose**: Enables instant atomic settlement across all asset types (stablecoins, RWA, CBDC, gold, resources).

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AtomicCrossAssetSettlement
 * @notice Instant atomic settlement across multiple asset classes
 * @dev Supports ERC20 (stablecoins, CBDC), ERC721 (RWA), and external rails
 */
contract AtomicCrossAssetSettlement is ReentrancyGuard, Ownable {
    
    enum AssetType { ERC20, ERC721, EXTERNAL_RAIL, AGORA, RLN, FNALITY }
    
    struct Asset {
        AssetType assetType;
        address assetAddress;           // Token contract or rail address
        uint256 amountOrTokenId;        // Amount for ERC20, tokenId for ERC721
        address owner;
        bytes32 externalRef;            // For external rails (SWIFT UETR, etc.)
    }
    
    struct AtomicSettlement {
        bytes32 settlementId;
        Asset[] assetsIn;               // Assets being exchanged
        Asset[] assetsOut;              // Assets being received
        address[] participants;
        bool isCompleted;
        bool isCancelled;
        uint256 timestamp;
        uint256 expiryTime;
    }
    
    mapping(bytes32 => AtomicSettlement) public settlements;
    
    event SettlementInitiated(bytes32 indexed settlementId, address[] participants);
    event SettlementCompleted(bytes32 indexed settlementId);
    event SettlementCancelled(bytes32 indexed settlementId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Initiate atomic cross-asset settlement
     */
    function initiateAtomicSettlement(
        bytes32 settlementId,
        Asset[] memory assetsIn,
        Asset[] memory assetsOut,
        address[] memory participants,
        uint256 expiryTime
    ) external nonReentrant returns (bool) {
        require(assetsIn.length > 0 && assetsOut.length > 0, "Empty assets");
        require(participants.length >= 2, "Need at least 2 participants");
        require(expiryTime > block.timestamp, "Invalid expiry");
        
        // Store settlement
        AtomicSettlement storage settlement = settlements[settlementId];
        settlement.settlementId = settlementId;
        settlement.timestamp = block.timestamp;
        settlement.expiryTime = expiryTime;
        settlement.participants = participants;
        
        // Copy assets
        for (uint i = 0; i < assetsIn.length; i++) {
            settlement.assetsIn.push(assetsIn[i]);
        }
        for (uint i = 0; i < assetsOut.length; i++) {
            settlement.assetsOut.push(assetsOut[i]);
        }
        
        emit SettlementInitiated(settlementId, participants);
        return true;
    }
    
    /**
     * @notice Execute atomic settlement (all-or-nothing)
     */
    function executeAtomicSettlement(bytes32 settlementId) external nonReentrant onlyOwner {
        AtomicSettlement storage settlement = settlements[settlementId];
        require(!settlement.isCompleted, "Already completed");
        require(!settlement.isCancelled, "Cancelled");
        require(block.timestamp <= settlement.expiryTime, "Expired");
        
        // Execute all asset transfers atomically
        for (uint i = 0; i < settlement.assetsIn.length; i++) {
            _transferAsset(settlement.assetsIn[i], address(this));
        }
        
        for (uint i = 0; i < settlement.assetsOut.length; i++) {
            _transferAsset(settlement.assetsOut[i], settlement.assetsOut[i].owner);
        }
        
        settlement.isCompleted = true;
        emit SettlementCompleted(settlementId);
    }
    
    /**
     * @dev Internal function to transfer assets based on type
     */
    function _transferAsset(Asset memory asset, address to) internal {
        if (asset.assetType == AssetType.ERC20) {
            IERC20(asset.assetAddress).transferFrom(asset.owner, to, asset.amountOrTokenId);
        } else if (asset.assetType == AssetType.ERC721) {
            IERC721(asset.assetAddress).transferFrom(asset.owner, to, asset.amountOrTokenId);
        }
        // External rails handled off-chain with receipts
    }
}
```

---

## 7. Compliance & Regulatory Framework

### 7.1 Comprehensive Compliance Module
**Enhanced File**: `contracts/compliance/ComprehensiveComplianceModule.sol`

**Key Regulations Covered**:
1. **FATF Travel Rule** - For all cross-border transfers
2. **Basel III** - Capital adequacy for tokenized deposits
3. **MiCA** - EU Markets in Crypto-Assets regulation
4. **Dodd-Frank** - US derivatives and commodities
5. **Mining Rights Laws** - Jurisdiction-specific mineral/water rights
6. **Environmental Compliance** - For natural resource extraction

```solidity
// Compliance checks for all asset types
function checkComprehensiveCompliance(
    address participant,
    AssetType assetType,
    uint256 amount,
    string memory jurisdiction
) external view returns (bool);
```

---

## 8. System Integration Architecture

### 8.1 Master Settlement Orchestrator
**New File**: `contracts/settlement/MasterSettlementOrchestrator.sol`

**Purpose**: Coordinates all settlement rails (SWIFT, Agorá, RLN, Fnality, RWA).

```solidity
/**
 * @title MasterSettlementOrchestrator
 * @notice Coordinates multi-rail, multi-asset atomic settlements
 * @dev Integrates SWIFT, Agorá, RLN, Fnality, and RWA rails
 */
contract MasterSettlementOrchestrator {
    
    // References to all adapters
    SWIFTGPIAdapter public swiftAdapter;
    AgoraTokenizedDepositAdapter public agoraAdapter;
    RLNMultiCBDCAdapter public rlnAdapter;
    FnalitySettlementAdapter public fnalityAdapter;
    AtomicCrossAssetSettlement public atomicSett
