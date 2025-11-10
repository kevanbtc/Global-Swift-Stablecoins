// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TransactionMonitoring
 * @notice AML transaction monitoring with SAR generation and pattern analysis
 * @dev Real-time transaction surveillance for suspicious activity detection
 */
contract TransactionMonitoring is Ownable, ReentrancyGuard {

    enum AlertSeverity { LOW, MEDIUM, HIGH, CRITICAL }
    enum AlertType {
        LARGE_TRANSACTION,
        FREQUENT_SMALL,
        ROUND_NUMBER,
        UNUSUAL_PATTERN,
        VELOCITY_SPIKE,
        STRUCTURING_ATTEMPT,
        PEER_GROUP_DEVIATION,
        GEOGRAPHIC_ANOMALY
    }

    struct TransactionRecord {
        bytes32 txId;
        address from;
        address to;
        uint256 amount;
        address asset;
        uint256 timestamp;
        string memo;
        bytes32 settlementId;
    }

    struct SuspiciousActivityReport {
        bytes32 sarId;
        address subject;
        AlertType alertType;
        AlertSeverity severity;
        string description;
        TransactionRecord[] relatedTransactions;
        uint256 totalAmount;
        uint256 reportTimestamp;
        bool isFiled;
        string filingReference;
    }

    struct AccountProfile {
        address account;
        uint256 totalVolume30d;
        uint256 transactionCount30d;
        uint256 averageTransactionSize;
        uint256 lastActivityTimestamp;
        uint256 riskScore;
        mapping(uint256 => uint256) hourlyVolume; // hour => volume
        mapping(uint256 => uint256) dailyVolume;   // day => volume
        mapping(address => uint256) counterpartyVolume;
    }

    struct MonitoringRule {
        bytes32 ruleId;
        string name;
        AlertType alertType;
        uint256 threshold;
        bool isActive;
        string description;
    }

    // Storage
    mapping(bytes32 => TransactionRecord) public transactionRecords;
    mapping(bytes32 => SuspiciousActivityReport) public suspiciousReports;
    mapping(address => AccountProfile) public accountProfiles;
    mapping(bytes32 => MonitoringRule) public monitoringRules;

    bytes32[] public activeRules;
    bytes32[] public pendingSARs;

    // Thresholds
    uint256 public constant LARGE_TRANSACTION_THRESHOLD = 10000 * 1e18; // $10k
    uint256 public constant VELOCITY_SPIKE_THRESHOLD = 5000 * 1e18; // $5k/hour
    uint256 public constant STRUCTURING_THRESHOLD = 9000 * 1e18; // $9k (CTRs at $10k)

    // Events
    event TransactionRecorded(bytes32 indexed txId, address indexed from, address indexed to, uint256 amount);
    event SuspiciousActivityDetected(bytes32 indexed sarId, address indexed subject, AlertType alertType, AlertSeverity severity);
    event SARFiled(bytes32 indexed sarId, string filingReference);
    event MonitoringRuleUpdated(bytes32 indexed ruleId, string name, bool isActive);

    constructor() Ownable(msg.sender) {
        _initializeDefaultRules();
    }

    /**
     * @notice Record a transaction for monitoring
     */
    function recordTransaction(
        bytes32 txId,
        address from,
        address to,
        uint256 amount,
        address asset,
        string memory memo,
        bytes32 settlementId
    ) public {
        require(transactionRecords[txId].timestamp == 0, "Transaction already recorded");

        TransactionRecord memory record = TransactionRecord({
            txId: txId,
            from: from,
            to: to,
            amount: amount,
            asset: asset,
            timestamp: block.timestamp,
            memo: memo,
            settlementId: settlementId
        });

        transactionRecords[txId] = record;

        // Update account profiles
        _updateAccountProfile(from, amount, to);
        _updateAccountProfile(to, amount, from);

        // Run monitoring checks
        _runMonitoringChecks(record);

        emit TransactionRecorded(txId, from, to, amount);
    }

    /**
     * @notice Analyze transaction for suspicious patterns
     */
    function _runMonitoringChecks(TransactionRecord memory record) internal {
        // Check all active rules
        for (uint256 i = 0; i < activeRules.length; i++) {
            MonitoringRule memory rule = monitoringRules[activeRules[i]];
            if (!rule.isActive) continue;

            AlertSeverity severity = _evaluateRule(rule, record);
            if (severity != AlertSeverity.LOW) {
                _generateAlert(record, rule.alertType, severity, rule.description);
            }
        }

        // Additional pattern analysis
        _checkStructuring(record);
        _checkVelocitySpike(record);
        _checkRoundNumbers(record);
        _checkUnusualPatterns(record);
    }

    /**
     * @notice Evaluate a monitoring rule against a transaction
     */
    function _evaluateRule(
        MonitoringRule memory rule,
        TransactionRecord memory record
    ) internal view returns (AlertSeverity) {
        AccountProfile storage profile = accountProfiles[record.from];

        if (rule.alertType == AlertType.LARGE_TRANSACTION) {
            if (record.amount >= rule.threshold) {
                return record.amount >= rule.threshold * 2 ? AlertSeverity.HIGH : AlertSeverity.MEDIUM;
            }
        } else if (rule.alertType == AlertType.FREQUENT_SMALL) {
            if (profile.transactionCount30d >= rule.threshold && profile.averageTransactionSize < 1000 * 1e18) {
                return AlertSeverity.MEDIUM;
            }
        }

        return AlertSeverity.LOW;
    }

    /**
     * @notice Check for structuring attempts (smurfing)
     */
    function _checkStructuring(TransactionRecord memory record) internal {
        AccountProfile storage profile = accountProfiles[record.from];

        // Check if multiple transactions just under CTR threshold
        uint256 recentVolume = _getRecentVolume(profile, 1 hours); // Last hour

        if (recentVolume + record.amount >= STRUCTURING_THRESHOLD) {
            // Check if this looks like structuring
            uint256 hourlyTxCount = _getHourlyTransactionCount(profile, block.timestamp / 3600);

            if (hourlyTxCount >= 3) { // Multiple transactions in short time
                _generateAlert(
                    record,
                    AlertType.STRUCTURING_ATTEMPT,
                    AlertSeverity.HIGH,
                    "Potential structuring detected - multiple transactions under CTR threshold"
                );
            }
        }
    }

    /**
     * @notice Check for velocity spikes
     */
    function _checkVelocitySpike(TransactionRecord memory record) internal {
        AccountProfile storage profile = accountProfiles[record.from];

        uint256 hourlyVolume = _getRecentVolume(profile, 1 hours);

        if (hourlyVolume >= VELOCITY_SPIKE_THRESHOLD) {
            _generateAlert(
                record,
                AlertType.VELOCITY_SPIKE,
                AlertSeverity.MEDIUM,
                "Unusual transaction velocity detected"
            );
        }
    }

    /**
     * @notice Check for round number transactions
     */
    function _checkRoundNumbers(TransactionRecord memory record) internal {
        // Check if amount is a round number (potential structuring indicator)
        uint256 amount = record.amount / 1e18; // Convert to whole units

        if (amount >= 1000) { // Only check for amounts >= $1000
            bool isRound = _isRoundNumber(amount);
            if (isRound) {
                _generateAlert(
                    record,
                    AlertType.ROUND_NUMBER,
                    AlertSeverity.LOW,
                    "Round number transaction detected"
                );
            }
        }
    }

    /**
     * @notice Check for unusual transaction patterns
     */
    function _checkUnusualPatterns(TransactionRecord memory record) internal {
        AccountProfile storage profile = accountProfiles[record.from];

        // Check counterparty concentration
        uint256 counterpartyVolume = profile.counterpartyVolume[record.to];
        uint256 totalVolume = profile.totalVolume30d;

        if (totalVolume > 0 && (counterpartyVolume * 100) / totalVolume >= 80) { // 80% to single counterparty
            _generateAlert(
                record,
                AlertType.PEER_GROUP_DEVIATION,
                AlertSeverity.MEDIUM,
                "High concentration with single counterparty"
            );
        }

        // Check geographic anomalies (simplified - would integrate with KYC data)
        if (_isGeographicAnomaly(record.from, record.to)) {
            _generateAlert(
                record,
                AlertType.GEOGRAPHIC_ANOMALY,
                AlertSeverity.MEDIUM,
                "Geographic anomaly detected"
            );
        }
    }

    /**
     * @notice Generate a suspicious activity alert
     */
    function _generateAlert(
        TransactionRecord memory record,
        AlertType alertType,
        AlertSeverity severity,
        string memory description
    ) internal {
        bytes32 sarId = keccak256(abi.encodePacked(record.txId, alertType, block.timestamp));

        TransactionRecord[] memory relatedTxs = new TransactionRecord[](1);
        relatedTxs[0] = record;

        SuspiciousActivityReport memory sar = SuspiciousActivityReport({
            sarId: sarId,
            subject: record.from,
            alertType: alertType,
            severity: severity,
            description: description,
            relatedTransactions: relatedTxs,
            totalAmount: record.amount,
            reportTimestamp: block.timestamp,
            isFiled: false,
            filingReference: ""
        });

        suspiciousReports[sarId] = sar;
        pendingSARs.push(sarId);

        emit SuspiciousActivityDetected(sarId, record.from, alertType, severity);
    }

    /**
     * @notice File a SAR with regulatory authorities
     */
    function fileSAR(bytes32 sarId, string memory filingReference) public onlyOwner {
        require(suspiciousReports[sarId].reportTimestamp > 0, "SAR not found");
        require(!suspiciousReports[sarId].isFiled, "SAR already filed");

        suspiciousReports[sarId].isFiled = true;
        suspiciousReports[sarId].filingReference = filingReference;

        emit SARFiled(sarId, filingReference);
    }

    /**
     * @notice Update monitoring rule
     */
    function updateMonitoringRule(
        bytes32 ruleId,
        string memory name,
        AlertType alertType,
        uint256 threshold,
        bool isActive,
        string memory description
        ) public onlyOwner {
        monitoringRules[ruleId] = MonitoringRule({
            ruleId: ruleId,
            name: name,
            alertType: alertType,
            threshold: threshold,
            isActive: isActive,
            description: description
        });

        // Add to active rules if not already present
        bool exists = false;
        for (uint256 i = 0; i < activeRules.length; i++) {
            if (activeRules[i] == ruleId) {
                exists = true;
                break;
            }
        }

        if (!exists && isActive) {
            activeRules.push(ruleId);
        }

        emit MonitoringRuleUpdated(ruleId, name, isActive);
    }

    /**
     * @notice Get account monitoring profile
     */
    function getAccountProfile(address account) public view returns (
        uint256 totalVolume30d,
        uint256 transactionCount30d,
        uint256 averageTransactionSize,
        uint256 riskScore
    ) {
        AccountProfile storage profile = accountProfiles[account];
        return (
            profile.totalVolume30d,
            profile.transactionCount30d,
            profile.averageTransactionSize,
            profile.riskScore
        );
    }

    /**
     * @notice Get pending SARs
     */
    function getPendingSARs() public view returns (bytes32[] memory) {
        return pendingSARs;
    }

    // Internal helper functions

    function _initializeDefaultRules() internal {
        // Large transaction rule
        bytes32 ruleId1 = keccak256("LARGE_TRANSACTION");
        updateMonitoringRule(
            ruleId1,
            "Large Transaction Monitoring",
            AlertType.LARGE_TRANSACTION,
            LARGE_TRANSACTION_THRESHOLD,
            true,
            "Monitor transactions above threshold"
        );

        // Frequent small transactions
        bytes32 ruleId2 = keccak256("FREQUENT_SMALL");
        updateMonitoringRule(
            ruleId2,
            "Frequent Small Transactions",
            AlertType.FREQUENT_SMALL,
            10, // 10 transactions
            true,
            "Monitor high frequency of small transactions"
        );
    }

    function _updateAccountProfile(address account, uint256 amount, address counterparty) internal {
        AccountProfile storage profile = accountProfiles[account];

        // Update volumes
        profile.totalVolume30d += amount;
        profile.transactionCount30d += 1;
        profile.averageTransactionSize = profile.totalVolume30d / profile.transactionCount30d;
        profile.lastActivityTimestamp = block.timestamp;

        // Update hourly/daily volumes
        uint256 currentHour = block.timestamp / 3600;
        uint256 currentDay = block.timestamp / 86400;

        profile.hourlyVolume[currentHour] += amount;
        profile.dailyVolume[currentDay] += amount;
        profile.counterpartyVolume[counterparty] += amount;

        // Clean old data (simplified - production would use more efficient method)
        _cleanOldVolumeData(profile);
    }

    function _cleanOldVolumeData(AccountProfile storage profile) internal {
        uint256 currentHour = block.timestamp / 3600;
        uint256 currentDay = block.timestamp / 86400;

        // Clean hourly data older than 24 hours
        for (uint256 hour = currentHour - 24; hour < currentHour; hour++) {
            if (profile.hourlyVolume[hour] > 0) {
                profile.hourlyVolume[hour] = 0;
            }
        }

        // Clean daily data older than 30 days
        for (uint256 day = currentDay - 30; day < currentDay; day++) {
            if (profile.dailyVolume[day] > 0) {
                profile.dailyVolume[day] = 0;
            }
        }
    }

    function _getRecentVolume(AccountProfile storage profile, uint256 timeWindow) internal view returns (uint256) {
        uint256 currentHour = block.timestamp / 3600;
        uint256 hoursBack = timeWindow / 3600;
        uint256 totalVolume = 0;

        for (uint256 i = 0; i < hoursBack; i++) {
            totalVolume += profile.hourlyVolume[currentHour - i];
        }

        return totalVolume;
    }

    function _getHourlyTransactionCount(AccountProfile storage profile, uint256 hour) internal view returns (uint256) {
        // Simplified - would track actual transaction counts per hour
        return profile.hourlyVolume[hour] > 0 ? 1 : 0;
    }

    function _isRoundNumber(uint256 amount) internal pure returns (bool) {
        // Check for round numbers like 1000, 5000, 10000, etc.
        if (amount == 0) return false;

        uint256 divisor = 1000;
        while (divisor <= amount) {
            if (amount % divisor == 0 && amount / divisor <= 100) {
                return true;
            }
            divisor *= 10;
        }

        return false;
    }

    function _isGeographicAnomaly(address from, address to) internal view returns (bool) {
        // Simplified - would check KYC jurisdictions
        // In production, integrate with KYC registry
        return false;
    }
}
