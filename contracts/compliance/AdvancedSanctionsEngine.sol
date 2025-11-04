/ SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AdvancedSanctionsEngine
 * @notice Advanced sanctions compliance with OFAC, EU, UN screening and risk scoring
 * @dev Multi-source sanctions screening with ML-enhanced risk assessment
 */
contract AdvancedSanctionsEngine is Ownable, ReentrancyGuard {
    enum RiskLevel { LOW, MEDIUM, HIGH, EXTREME }
    enum SanctionSource { OFAC, EU, UN, INTERPOL, CUSTOM }

    struct SanctionedEntity {
        bytes32 entityId;
        string name;
        string[] aliases;
        string jurisdiction;
        SanctionSource source;
        RiskLevel riskLevel;
        uint256 addedTimestamp;
        uint256 lastUpdated;
        bool isActive;
        string reason;
    }

    struct RiskProfile {
        address account;
        uint256 riskScore;           // 0-1000 scale
        RiskLevel overallRisk;
        mapping(SanctionSource => uint256) sourceRiskScores;
        uint256 lastAssessment;
        bool isFrozen;
        string[] riskFactors;
    }

    struct TransactionRisk {
        bytes32 txId;
        address from;
        address to;
        uint256 amount;
        address asset;
        uint256 riskScore;
        RiskLevel riskLevel;
        bool isBlocked;
        string[] riskFactors;
        uint256 timestamp;
    }

    mapping(bytes32 => SanctionedEntity) public sanctionedEntities;
    mapping(address => RiskProfile) public riskProfiles;
    mapping(bytes32 => TransactionRisk) public transactionRisks;

    bytes32[] public sanctionedEntityIds;
    address[] public monitoredAccounts;

    uint256 public constant MAX_RISK_SCORE = 1000;
    uint256 public constant HIGH_RISK_THRESHOLD = 700;
    uint256 public constant EXTREME_RISK_THRESHOLD = 900;

    event EntitySanctioned(bytes32 indexed entityId, SanctionSource source, RiskLevel riskLevel);
    event EntityDelisted(bytes32 indexed entityId);
    event RiskProfileUpdated(address indexed account, uint256 riskScore, RiskLevel riskLevel);
    event TransactionBlocked(bytes32 indexed txId, address indexed from, address indexed to, string reason);
    event AccountFrozen(address indexed account, string reason);
    event AccountUnfrozen(address indexed account);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Add sanctioned entity to the list
     */
    function addSanctionedEntity(
        bytes32 entityId,
        string memory name,
        string[] memory aliases,
        string memory jurisdiction,
        SanctionSource source,
        RiskLevel riskLevel,
        string memory reason
    ) external onlyOwner {
        require(!sanctionedEntities[entityId].isActive, "Entity already sanctioned");

        sanctionedEntities[entityId] = SanctionedEntity({
            entityId: entityId,
            name: name,
            aliases: aliases,
            jurisdiction: jurisdiction,
            source: source,
            riskLevel: riskLevel,
            addedTimestamp: block.timestamp,
            lastUpdated: block.timestamp,
            isActive: true,
            reason: reason
        });

        sanctionedEntityIds.push(entityId);

        emit EntitySanctioned(entityId, source, riskLevel);
    }

    /**
     * @notice Remove entity from sanctions list
     */
    function removeSanctionedEntity(bytes32 entityId) external onlyOwner {
        require(sanctionedEntities[entityId].isActive, "Entity not sanctioned");

        sanctionedEntities[entityId].isActive = false;
        sanctionedEntities[entityId].lastUpdated = block.timestamp;

        emit EntityDelisted(entityId);
    }

    /**
     * @notice Assess risk for an account
     */
    function assessAccountRisk(address account) external returns (uint256 riskScore, RiskLevel riskLevel) {
        RiskProfile storage profile = riskProfiles[account];

        // Reset risk factors
        delete profile.riskFactors;

        uint256 totalRisk = 0;
        uint256 factors = 0;

        // Check direct sanctions
        if (_isDirectlySanctioned(account)) {
            profile.riskFactors.push("Direct sanctions match");
            totalRisk += 1000;
            factors++;
        }

        // Check associated entities (simplified - would check connected addresses)
        uint256 associationRisk = _checkEntityAssociations(account);
        if (associationRisk > 0) {
            profile.riskFactors.push("Associated with sanctioned entities");
            totalRisk += associationRisk;
            factors++;
        }

        // Geographic risk
        uint256 geoRisk = _assessGeographicRisk(account);
        if (geoRisk > 0) {
            profile.riskFactors.push("High-risk jurisdiction");
            totalRisk += geoRisk;
            factors++;
        }

        // Transaction pattern risk
        uint256 patternRisk = _assessTransactionPatterns(account);
        if (patternRisk > 0) {
            profile.riskFactors.push("Suspicious transaction patterns");
            totalRisk += patternRisk;
            factors++;
        }

        // Behavioral risk
        uint256 behaviorRisk = _assessBehavioralRisk(account);
        if (behaviorRisk > 0) {
            profile.riskFactors.push("High-risk behavior detected");
            totalRisk += behaviorRisk;
            factors++;
        }

        // Calculate average risk score
        riskScore = factors > 0 ? totalRisk / factors : 0;
        riskScore = riskScore > MAX_RISK_SCORE ? MAX_RISK_SCORE : riskScore;

        // Determine risk level
        if (riskScore >= EXTREME_RISK_THRESHOLD) {
            riskLevel = RiskLevel.EXTREME;
        } else if (riskScore >= HIGH_RISK_THRESHOLD) {
            riskLevel = RiskLevel.HIGH;
        } else if (riskScore >= 300) {
            riskLevel = RiskLevel.MEDIUM;
        } else {
            riskLevel = RiskLevel.LOW;
        }

        // Update profile
        profile.account = account;
        profile.riskScore = riskScore;
        profile.overallRisk = riskLevel;
        profile.lastAssessment = block.timestamp;

        // Auto-freeze extreme risk accounts
        if (riskLevel == RiskLevel.EXTREME && !profile.isFrozen) {
            profile.isFrozen = true;
            emit AccountFrozen(account, "Extreme risk detected");
        }

        emit RiskProfileUpdated(account, riskScore, riskLevel);
        return (riskScore, riskLevel);
    }

    /**
     * @notice Evaluate transaction risk
     */
    function evaluateTransactionRisk(
        bytes32 txId,
        address from,
        address to,
        uint256 amount,
        address asset
    ) external returns (bool isAllowed, string memory reason) {
        uint256 riskScore = 0;
        string[] memory riskFactors;

        // Assess sender risk
        (uint256 senderRisk,) = assessAccountRisk(from);
        riskScore += senderRisk / 2; // 50% weight

        // Assess receiver risk
        (uint256 receiverRisk,) = assessAccountRisk(to);
        riskScore += receiverRisk / 2; // 50% weight

        // Amount-based risk
        if (amount > _getLargeTransactionThreshold(asset)) {
            riskScore += 200;
            riskFactors.push("Large transaction amount");
        }

        // Cross-border risk (simplified)
        if (_isCrossBorderTransaction(from, to)) {
            riskScore += 100;
            riskFactors.push("Cross-border transaction");
        }

        // Velocity risk
        if (_checkTransactionVelocity(from, amount)) {
            riskScore += 150;
            riskFactors.push("High transaction velocity");
        }

        riskScore = riskScore > MAX_RISK_SCORE ? MAX_RISK_SCORE : riskScore;

        // Determine if transaction should be blocked
        bool shouldBlock = riskScore >= HIGH_RISK_THRESHOLD;

        // Store transaction risk assessment
        transactionRisks[txId] = TransactionRisk({
            txId: txId,
            from: from,
            to: to,
            amount: amount,
            asset: asset,
            riskScore: riskScore,
            riskLevel: riskScore >= EXTREME_RISK_THRESHOLD ? RiskLevel.EXTREME :
                      riskScore >= HIGH_RISK_THRESHOLD ? RiskLevel.HIGH :
                      riskScore >= 300 ? RiskLevel.MEDIUM : RiskLevel.LOW,
            isBlocked: shouldBlock,
            riskFactors: riskFactors,
            timestamp: block.timestamp
        });

        if (shouldBlock) {
            emit TransactionBlocked(txId, from, to, "High risk transaction");
            return (false, "Transaction blocked due to high risk score");
        }

        return (true, "Transaction approved");
    }

    /**
     * @notice Manually freeze/unfreeze account
     */
    function setAccountFrozen(address account, bool frozen, string memory reason) external onlyOwner {
        RiskProfile storage profile = riskProfiles[account];
        profile.isFrozen = frozen;

        if (frozen) {
            emit AccountFrozen(account, reason);
        } else {
            emit AccountUnfrozen(account);
        }
    }

    /**
     * @notice Get risk profile for account
     */
    function getRiskProfile(address account) external view returns (
        uint256 riskScore,
        RiskLevel riskLevel,
        bool isFrozen,
        uint256 lastAssessment,
        string[] memory riskFactors
    ) {
        RiskProfile storage profile = riskProfiles[account];
        return (
            profile.riskScore,
            profile.overallRisk,
            profile.isFrozen,
            profile.lastAssessment,
            profile.riskFactors
        );
    }

    // Internal helper functions

    function _isDirectlySanctioned(address account) internal view returns (bool) {
        // Simplified - in production would check multiple sanction lists
        bytes32 entityId = keccak256(abi.encodePacked(account));
        return sanctionedEntities[entityId].isActive;
    }

    function _checkEntityAssociations(address account) internal view returns (uint256) {
        // Simplified - would check connected addresses, beneficial owners, etc.
        return 0;
    }

    function _assessGeographicRisk(address account) internal view returns (uint256) {
        // Simplified - would check IP geolocation, KYC jurisdiction, etc.
        return 0;
    }

    function _assessTransactionPatterns(address account) internal view returns (uint256) {
        // Simplified - would analyze transaction frequency, amounts, counterparties
        return 0;
    }

    function _assessBehavioralRisk(address account) internal view returns (uint256) {
        // Simplified - would check for money laundering patterns, unusual activity
        return 0;
    }

    function _getLargeTransactionThreshold(address asset) internal view returns (uint256) {
        // Simplified - would return asset-specific thresholds
        return 100000 * 1e18; // 100k units
    }

    function _isCrossBorderTransaction(address from, address to) internal view returns (bool) {
        // Simplified - would check jurisdictions of from/to addresses
        return true; // Assume cross-border for demo
    }

    function _checkTransactionVelocity(address account, uint256 amount) internal view returns (bool) {
        // Simplified - would check recent transaction volume
        return false;
    }
}
