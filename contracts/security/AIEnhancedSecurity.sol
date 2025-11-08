// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AIEnhancedSecurity
 * @notice AI-powered security monitoring and threat detection
 * @dev Uses on-chain AI models for anomaly detection and fraud prevention
 */
contract AIEnhancedSecurity is Ownable, ReentrancyGuard, Pausable {

    enum ThreatLevel {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    enum AnomalyType {
        TRANSACTION_PATTERN,
        VOLUME_SPIKE,
        GEOGRAPHIC_ANOMALY,
        TIME_PATTERN,
        WALLET_BEHAVIOR,
        NETWORK_ANOMALY
    }

    struct AIModel {
        bytes32 modelId;
        string modelName;
        string modelType;      // "anomaly_detection", "fraud_prevention", "risk_scoring"
        uint256 version;
        uint256 accuracy;      // BPS (0-10000)
        uint256 lastUpdated;
        bool isActive;
        address maintainer;
    }

    struct SecurityEvent {
        bytes32 eventId;
        address targetAddress;
        AnomalyType anomalyType;
        ThreatLevel threatLevel;
        uint256 confidence;    // BPS (0-10000)
        uint256 timestamp;
        bytes32 modelId;
        string description;
        bool isResolved;
        uint256 resolutionTime;
    }

    struct RiskProfile {
        address account;
        uint256 riskScore;     // 0-1000 (higher = riskier)
        ThreatLevel threatLevel;
        uint256 lastAssessment;
        uint256 flags;         // Bitfield of risk flags
        bytes32[] recentEvents;
        bool isBlacklisted;
        uint256 quarantineUntil;
    }

    struct BehavioralPattern {
        address account;
        uint256 transactionCount;
        uint256 totalVolume;
        uint256 averageTransactionSize;
        uint256 lastActivity;
        uint256 uniqueCounterparties;
        mapping(uint256 => uint256) hourlyActivity;  // hour => transaction count
        mapping(uint256 => uint256) dailyVolume;     // day => volume
        mapping(address => uint256) counterpartyVolume;
    }

    // Storage
    mapping(bytes32 => AIModel) public aiModels;
    mapping(bytes32 => SecurityEvent) public securityEvents;
    mapping(address => RiskProfile) public riskProfiles;
    mapping(address => BehavioralPattern) public behavioralPatterns;

    // Global parameters
    uint256 public anomalyThreshold = 7500;     // 75% confidence threshold
    uint256 public riskThreshold = 700;         // Risk score threshold (0-1000)
    uint256 public quarantinePeriod = 24 hours; // Default quarantine time
    uint256 public assessmentInterval = 1 hours; // Risk reassessment interval

    uint256 public totalModels;
    uint256 public totalEvents;
    uint256 public totalQuarantines;

    // Risk flags (bitfield positions)
    uint256 public constant FLAG_SUSPICIOUS_PATTERN = 1 << 0;
    uint256 public constant FLAG_HIGH_FREQUENCY = 1 << 1;
    uint256 public constant FLAG_LARGE_VOLUME = 1 << 2;
    uint256 public constant FLAG_GEOGRAPHIC_RISK = 1 << 3;
    uint256 public constant FLAG_NEW_ACCOUNT = 1 << 4;
    uint256 public constant FLAG_MIXED_ASSETS = 1 << 5;

    // Events
    event AIModelRegistered(bytes32 indexed modelId, string modelName, string modelType);
    event SecurityEventDetected(bytes32 indexed eventId, address indexed target, AnomalyType anomalyType, ThreatLevel level);
    event RiskProfileUpdated(address indexed account, uint256 riskScore, ThreatLevel level);
    event AccountQuarantined(address indexed account, uint256 until, string reason);
    event AccountUnquarantined(address indexed account);
    event AnomalyThresholdUpdated(uint256 newThreshold);

    modifier notQuarantined(address account) {
        require(block.timestamp >= riskProfiles[account].quarantineUntil, "Account is quarantined");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new AI model for security monitoring
     */
    function registerAIModel(
        string memory _modelName,
        string memory _modelType,
        uint256 _accuracy
    ) public onlyOwner returns (bytes32) {
        require(_accuracy <= 10000, "Invalid accuracy");

        bytes32 modelId = keccak256(abi.encodePacked(
            _modelName,
            _modelType,
            block.timestamp,
            totalModels++
        ));

        aiModels[modelId] = AIModel({
            modelId: modelId,
            modelName: _modelName,
            modelType: _modelType,
            version: 1,
            accuracy: _accuracy,
            lastUpdated: block.timestamp,
            isActive: true,
            maintainer: msg.sender
        });

        emit AIModelRegistered(modelId, _modelName, _modelType);
        return modelId;
    }

    /**
     * @notice Update AI model accuracy and version
     */
    function updateAIModel(
        bytes32 _modelId,
        uint256 _newAccuracy,
        uint256 _newVersion
    ) public {
        AIModel storage model = aiModels[_modelId];
        require(model.maintainer == msg.sender || owner() == msg.sender, "Not authorized");
        require(_newAccuracy <= 10000, "Invalid accuracy");
        require(_newVersion > model.version, "Version must increase");

        model.accuracy = _newAccuracy;
        model.version = _newVersion;
        model.lastUpdated = block.timestamp;

        // Update anomaly threshold based on model accuracy
        if (_newAccuracy > 8000) { // 80%+ accuracy
            anomalyThreshold = 7000; // Lower threshold for high-confidence models
        }
    }

    /**
     * @notice Analyze transaction for security anomalies
     */
    function analyzeTransaction(
        address _from,
        address _to,
        uint256 _amount,
        address _token,
        bytes32 _modelId
    ) public whenNotPaused returns (bool isAnomalous, ThreatLevel threatLevel) {
        require(aiModels[_modelId].isActive, "Model not active");

        // Update behavioral patterns
        _updateBehavioralPattern(_from, _amount, _to);

        // Run AI analysis (simplified simulation)
        (isAnomalous, threatLevel) = _runAIAnalysis(_from, _to, _amount, _token);

        if (isAnomalous) {
            _createSecurityEvent(_from, AnomalyType.TRANSACTION_PATTERN, threatLevel, _modelId);

            // Update risk profile
            _updateRiskProfile(_from, threatLevel);

            // Auto-quarantine for critical threats
            if (threatLevel == ThreatLevel.CRITICAL) {
                _quarantineAccount(_from, "Critical threat detected");
            }
        }

        return (isAnomalous, threatLevel);
    }

    /**
     * @notice Assess account risk profile
     */
    function assessRiskProfile(address _account) public returns (uint256 riskScore, ThreatLevel level) {
        RiskProfile storage profile = riskProfiles[_account];

        // Only reassess if enough time has passed
        if (block.timestamp < profile.lastAssessment + assessmentInterval) {
            return (profile.riskScore, profile.threatLevel);
        }

        // Run comprehensive risk assessment
        riskScore = _calculateRiskScore(_account);
        level = _determineThreatLevel(riskScore);

        profile.riskScore = riskScore;
        profile.threatLevel = level;
        profile.lastAssessment = block.timestamp;

        emit RiskProfileUpdated(_account, riskScore, level);

        return (riskScore, level);
    }

    /**
     * @notice Manually quarantine an account
     */
    function quarantineAccount(
        address _account,
        uint256 _duration,
        string memory _reason
    ) public onlyOwner {
        _quarantineAccount(_account, _reason);

        // Override default quarantine period
        if (_duration > 0) {
            riskProfiles[_account].quarantineUntil = block.timestamp + _duration;
        }
    }

    /**
     * @notice Unquarantine an account
     */
    function unquarantineAccount(address _account) public onlyOwner {
        require(riskProfiles[_account].quarantineUntil > 0, "Account not quarantined");

        riskProfiles[_account].quarantineUntil = 0;
        riskProfiles[_account].isBlacklisted = false;

        emit AccountUnquarantined(_account);
    }

    /**
     * @notice Get security event details
     */
    function getSecurityEvent(bytes32 _eventId) public view
        returns (
            address targetAddress,
            AnomalyType anomalyType,
            ThreatLevel threatLevel,
            uint256 confidence,
            uint256 timestamp,
            bool isResolved
        )
    {
        SecurityEvent memory event_ = securityEvents[_eventId];
        return (
            event_.targetAddress,
            event_.anomalyType,
            event_.threatLevel,
            event_.confidence,
            event_.timestamp,
            event_.isResolved
        );
    }

    /**
     * @notice Get risk profile
     */
    function getRiskProfile(address _account) public view
        returns (
            uint256 riskScore,
            ThreatLevel threatLevel,
            uint256 flags,
            bool isBlacklisted,
            uint256 quarantineUntil
        )
    {
        RiskProfile memory profile = riskProfiles[_account];
        return (
            profile.riskScore,
            profile.threatLevel,
            profile.flags,
            profile.isBlacklisted,
            profile.quarantineUntil
        );
    }

    /**
     * @notice Get behavioral pattern
     */
    function getBehavioralPattern(address _account) public view
        returns (
            uint256 transactionCount,
            uint256 totalVolume,
            uint256 averageTransactionSize,
            uint256 uniqueCounterparties
        )
    {
        BehavioralPattern storage pattern = behavioralPatterns[_account];
        return (
            pattern.transactionCount,
            pattern.totalVolume,
            pattern.averageTransactionSize,
            pattern.uniqueCounterparties
        );
    }

    /**
     * @notice Update security parameters
     */
    function updateParameters(
        uint256 _anomalyThreshold,
        uint256 _riskThreshold,
        uint256 _quarantinePeriod,
        uint256 _assessmentInterval
    ) public onlyOwner {
        require(_anomalyThreshold <= 10000, "Invalid anomaly threshold");
        require(_riskThreshold <= 1000, "Invalid risk threshold");

        anomalyThreshold = _anomalyThreshold;
        riskThreshold = _riskThreshold;
        quarantinePeriod = _quarantinePeriod;
        assessmentInterval = _assessmentInterval;

        emit AnomalyThresholdUpdated(_anomalyThreshold);
    }

    /**
     * @notice Emergency pause
     */
    function emergencyPause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause
     */
    function emergencyUnpause() public onlyOwner {
        _unpause();
    }

    // Internal functions

    function _runAIAnalysis(
        address _from,
        address _to,
        uint256 _amount,
        address _token
    ) internal view returns (bool isAnomalous, ThreatLevel threatLevel) {
        BehavioralPattern storage pattern = behavioralPatterns[_from];

        // Simple anomaly detection rules (in production would use ML models)
        uint256 anomalyScore = 0;

        // Check transaction size vs average
        if (pattern.transactionCount > 5) {
            uint256 sizeRatio = (_amount * 10000) / pattern.averageTransactionSize;
            if (sizeRatio > 50000 || sizeRatio < 100) { // 5x larger or 100x smaller
                anomalyScore += 3000;
            }
        }

        // Check hourly activity spike
        uint256 currentHour = block.timestamp / 3600;
        uint256 hourlyTx = pattern.hourlyActivity[currentHour];
        if (hourlyTx > 10) { // More than 10 tx/hour
            anomalyScore += 2000;
        }

        // Check new counterparty
        if (pattern.counterpartyVolume[_to] == 0 && pattern.transactionCount > 3) {
            anomalyScore += 1500;
        }

        // Check volume concentration
        if (pattern.counterpartyVolume[_to] > pattern.totalVolume / 2) {
            anomalyScore += 1000;
        }

        isAnomalous = anomalyScore >= anomalyThreshold;

        if (anomalyScore >= 9000) {
            threatLevel = ThreatLevel.CRITICAL;
        } else if (anomalyScore >= 7000) {
            threatLevel = ThreatLevel.HIGH;
        } else if (anomalyScore >= 5000) {
            threatLevel = ThreatLevel.MEDIUM;
        } else {
            threatLevel = ThreatLevel.LOW;
        }

        return (isAnomalous, threatLevel);
    }

    function _calculateRiskScore(address _account) internal view returns (uint256) {
        RiskProfile storage profile = riskProfiles[_account];
        BehavioralPattern storage pattern = behavioralPatterns[_account];

        uint256 score = 0;

        // Base score from behavioral patterns
        if (pattern.transactionCount < 5) score += 200; // New account risk
        if (pattern.uniqueCounterparties < 3) score += 150; // Limited diversification

        // Volume-based risk
        if (pattern.totalVolume > 1000000 * 1e18) score += 100; // High volume account

        // Time-based patterns
        uint256 daysSinceLastActivity = (block.timestamp - pattern.lastActivity) / 86400;
        if (daysSinceLastActivity > 90) score += 100; // Dormant account

        // Security flags
        if (profile.flags & FLAG_SUSPICIOUS_PATTERN != 0) score += 300;
        if (profile.flags & FLAG_HIGH_FREQUENCY != 0) score += 200;
        if (profile.flags & FLAG_LARGE_VOLUME != 0) score += 150;
        if (profile.flags & FLAG_GEOGRAPHIC_RISK != 0) score += 250;
        if (profile.flags & FLAG_NEW_ACCOUNT != 0) score += 100;

        // Recent security events
        uint256 recentEvents = 0;
        for (uint256 i = 0; i < profile.recentEvents.length; i++) {
            SecurityEvent memory event_ = securityEvents[profile.recentEvents[i]];
            if (block.timestamp - event_.timestamp < 30 days) {
                recentEvents++;
                if (event_.threatLevel == ThreatLevel.HIGH) score += 100;
                if (event_.threatLevel == ThreatLevel.CRITICAL) score += 200;
            }
        }

        if (recentEvents > 3) score += 150; // Multiple recent events

        return score > 1000 ? 1000 : score;
    }

    function _determineThreatLevel(uint256 _riskScore) internal pure returns (ThreatLevel) {
        if (_riskScore >= 800) return ThreatLevel.CRITICAL;
        if (_riskScore >= 600) return ThreatLevel.HIGH;
        if (_riskScore >= 400) return ThreatLevel.MEDIUM;
        return ThreatLevel.LOW;
    }

    function _updateBehavioralPattern(address _account, uint256 _amount, address _counterparty) internal {
        BehavioralPattern storage pattern = behavioralPatterns[_account];

        pattern.transactionCount++;
        pattern.totalVolume += _amount;
        pattern.averageTransactionSize = pattern.totalVolume / pattern.transactionCount;
        pattern.lastActivity = block.timestamp;

        // Update counterparty tracking
        if (pattern.counterpartyVolume[_counterparty] == 0) {
            pattern.uniqueCounterparties++;
        }
        pattern.counterpartyVolume[_counterparty] += _amount;

        // Update time-based patterns
        uint256 currentHour = block.timestamp / 3600;
        uint256 currentDay = block.timestamp / 86400;

        pattern.hourlyActivity[currentHour]++;
        pattern.dailyVolume[currentDay] += _amount;
    }

    function _createSecurityEvent(
        address _target,
        AnomalyType _type,
        ThreatLevel _level,
        bytes32 _modelId
    ) internal returns (bytes32) {
        bytes32 eventId = keccak256(abi.encodePacked(
            _target,
            _type,
            _level,
            block.timestamp,
            totalEvents++
        ));

        securityEvents[eventId] = SecurityEvent({
            eventId: eventId,
            targetAddress: _target,
            anomalyType: _type,
            threatLevel: _level,
            confidence: anomalyThreshold + 1000, // Mock confidence
            timestamp: block.timestamp,
            modelId: _modelId,
            description: _getAnomalyDescription(_type),
            isResolved: false,
            resolutionTime: 0
        });

        // Add to risk profile
        riskProfiles[_target].recentEvents.push(eventId);

        emit SecurityEventDetected(eventId, _target, _type, _level);

        return eventId;
    }

    function _updateRiskProfile(address _account, ThreatLevel _level) internal {
        RiskProfile storage profile = riskProfiles[_account];

        // Update flags based on threat level
        if (_level == ThreatLevel.HIGH || _level == ThreatLevel.CRITICAL) {
            profile.flags |= FLAG_SUSPICIOUS_PATTERN;
        }

        // Increase risk score
        uint256 increase = _level == ThreatLevel.CRITICAL ? 200 :
                          _level == ThreatLevel.HIGH ? 150 :
                          _level == ThreatLevel.MEDIUM ? 100 : 50;

        profile.riskScore = profile.riskScore + increase > 1000 ?
                           1000 : profile.riskScore + increase;

        profile.threatLevel = _determineThreatLevel(profile.riskScore);
    }

    function _quarantineAccount(address _account, string memory _reason) internal {
        RiskProfile storage profile = riskProfiles[_account];

        profile.isBlacklisted = true;
        profile.quarantineUntil = block.timestamp + quarantinePeriod;
        totalQuarantines++;

        emit AccountQuarantined(_account, profile.quarantineUntil, _reason);
    }

    function _getAnomalyDescription(AnomalyType _type) internal pure returns (string memory) {
        if (_type == AnomalyType.TRANSACTION_PATTERN) return "Unusual transaction pattern detected";
        if (_type == AnomalyType.VOLUME_SPIKE) return "Sudden volume spike detected";
        if (_type == AnomalyType.GEOGRAPHIC_ANOMALY) return "Geographic anomaly detected";
        if (_type == AnomalyType.TIME_PATTERN) return "Unusual timing pattern detected";
        if (_type == AnomalyType.WALLET_BEHAVIOR) return "Suspicious wallet behavior detected";
        if (_type == AnomalyType.NETWORK_ANOMALY) return "Network anomaly detected";
        return "Unknown anomaly type";
    }
}
