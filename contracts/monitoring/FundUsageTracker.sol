// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title FundUsageTracker
 * @notice Comprehensive monitoring and tracking of UBI and healthcare fund usage
 * @dev AI-powered monitoring with real-time analytics and fraud detection
 */
contract FundUsageTracker is Ownable, ReentrancyGuard {

    enum FundType {
        UBI_DISTRIBUTION,
        HEALTHCARE_COVERAGE,
        CARBON_OFFSETS,
        SOCIAL_SERVICES,
        EDUCATION_FUNDING,
        INFRASTRUCTURE_DEVELOPMENT
    }

    enum TransactionCategory {
        ESSENTIAL_FOOD,
        HOUSING_UTILITIES,
        HEALTHCARE_SERVICES,
        EDUCATION_EXPENSES,
        TRANSPORTATION,
        CLOTHING_PERSONAL,
        ENTERTAINMENT_LEISURE,
        INVESTMENT_SAVINGS,
        CHARITABLE_DONATIONS,
        BUSINESS_EXPENSES,
        OTHER
    }

    enum RiskLevel {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    struct FundAllocation {
        bytes32 allocationId;
        bytes32 citizenId;
        FundType fundType;
        uint256 amount;
        uint256 allocationDate;
        uint256 expiryDate;
        bool isActive;
        bytes32 purposeHash;
        address approvedBy;
    }

    struct TransactionRecord {
        bytes32 transactionId;
        bytes32 citizenId;
        bytes32 allocationId;
        uint256 amount;
        uint256 transactionDate;
        TransactionCategory category;
        address merchant;
        bytes32 receiptHash;
        bytes32 locationHash;
        bool isVerified;
        RiskLevel riskScore;
        bytes32 aiAnalysisHash;
    }

    struct SpendingPattern {
        bytes32 citizenId;
        uint256 totalSpent;
        uint256 transactionCount;
        uint256 averageTransactionSize;
        uint256 lastTransactionDate;
        mapping(TransactionCategory => uint256) categorySpending;
        mapping(TransactionCategory => uint256) categoryCount;
        bytes32 behaviorProfileHash;
        RiskLevel overallRisk;
        uint256 fraudProbability; // 0-10000 (basis points)
    }

    struct MerchantProfile {
        address merchantAddress;
        string merchantName;
        string businessType;
        uint256 registrationDate;
        uint256 totalTransactions;
        uint256 totalVolume;
        uint256 averageTransactionSize;
        uint256 reputationScore; // 0-1000
        bool isVerified;
        bool isBlacklisted;
        bytes32 licenseHash;
    }

    struct MonitoringAlert {
        bytes32 alertId;
        bytes32 citizenId;
        string alertType;
        string description;
        RiskLevel severity;
        uint256 alertDate;
        bool isResolved;
        bytes32 resolutionHash;
        address investigator;
    }

    // Storage
    mapping(bytes32 => FundAllocation) public fundAllocations;
    mapping(bytes32 => TransactionRecord) public transactionRecords;
    mapping(bytes32 => SpendingPattern) public spendingPatterns;
    mapping(address => MerchantProfile) public merchantProfiles;
    mapping(bytes32 => MonitoringAlert) public monitoringAlerts;
    mapping(bytes32 => bytes32[]) public allocationsByCitizen;
    mapping(bytes32 => bytes32[]) public transactionsByCitizen;
    mapping(bytes32 => bytes32[]) public alertsByCitizen;

    // Global statistics
    uint256 public totalAllocations;
    uint256 public totalTransactions;
    uint256 public totalMonitoringAlerts;
    uint256 public totalFraudDetected;
    uint256 public totalFundsTracked;

    // Protocol parameters
    uint256 public maxTransactionAmount = 1000 * 1e18; // $1000 max per transaction
    uint256 public dailySpendingLimit = 5000 * 1e18;   // $5000 daily limit
    uint256 public monthlySpendingLimit = 50000 * 1e18; // $50,000 monthly limit
    uint256 public fraudThreshold = 7500; // 75% fraud probability threshold
    uint256 public highRiskThreshold = 5000; // 50% risk threshold

    // Events
    event FundAllocated(bytes32 indexed allocationId, bytes32 indexed citizenId, uint256 amount, FundType fundType);
    event TransactionRecorded(bytes32 indexed transactionId, bytes32 indexed citizenId, uint256 amount, TransactionCategory category);
    event RiskAlert(bytes32 indexed alertId, bytes32 indexed citizenId, RiskLevel severity, string alertType);
    event FraudDetected(bytes32 indexed citizenId, uint256 fraudProbability, bytes32 evidenceHash);
    event MerchantVerified(address indexed merchant, uint256 reputationScore);

    modifier validAllocation(bytes32 _allocationId) {
        require(fundAllocations[_allocationId].citizenId != bytes32(0), "Allocation not found");
        _;
    }

    modifier validCitizen(bytes32 _citizenId) {
        require(allocationsByCitizen[_citizenId].length > 0, "Citizen not found");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Allocate funds to a citizen
     */
    function allocateFunds(
        bytes32 _citizenId,
        FundType _fundType,
        uint256 _amount,
        uint256 _expiryDate,
        bytes32 _purposeHash
    ) external onlyOwner returns (bytes32) {
        bytes32 allocationId = keccak256(abi.encodePacked(
            _citizenId,
            _fundType,
            _amount,
            block.timestamp
        ));

        FundAllocation storage allocation = fundAllocations[allocationId];
        allocation.allocationId = allocationId;
        allocation.citizenId = _citizenId;
        allocation.fundType = _fundType;
        allocation.amount = _amount;
        allocation.allocationDate = block.timestamp;
        allocation.expiryDate = _expiryDate;
        allocation.isActive = true;
        allocation.purposeHash = _purposeHash;
        allocation.approvedBy = msg.sender;

        allocationsByCitizen[_citizenId].push(allocationId);
        totalAllocations++;
        totalFundsTracked += _amount;

        emit FundAllocated(allocationId, _citizenId, _amount, _fundType);
        return allocationId;
    }

    /**
     * @notice Record a transaction
     */
    function recordTransaction(
        bytes32 _citizenId,
        bytes32 _allocationId,
        uint256 _amount,
        TransactionCategory _category,
        address _merchant,
        bytes32 _receiptHash,
        bytes32 _locationHash
    ) external validCitizen(_citizenId) validAllocation(_allocationId) returns (bytes32) {
        FundAllocation memory allocation = fundAllocations[_allocationId];
        require(allocation.citizenId == _citizenId, "Allocation not for citizen");
        require(allocation.isActive, "Allocation not active");
        require(block.timestamp <= allocation.expiryDate, "Allocation expired");
        require(_amount <= maxTransactionAmount, "Transaction amount too high");

        // Check spending limits
        SpendingPattern storage pattern = spendingPatterns[_citizenId];
        require(pattern.totalSpent + _amount <= monthlySpendingLimit, "Monthly limit exceeded");

        // Check daily spending
        uint256 todayStart = block.timestamp - (block.timestamp % 86400);
        uint256 dailySpent = _calculateDailySpending(_citizenId, todayStart);
        require(dailySpent + _amount <= dailySpendingLimit, "Daily limit exceeded");

        bytes32 transactionId = keccak256(abi.encodePacked(
            _citizenId,
            _allocationId,
            _amount,
            block.timestamp
        ));

        TransactionRecord storage transaction = transactionRecords[transactionId];
        transaction.transactionId = transactionId;
        transaction.citizenId = _citizenId;
        transaction.allocationId = _allocationId;
        transaction.amount = _amount;
        transaction.transactionDate = block.timestamp;
        transaction.category = _category;
        transaction.merchant = _merchant;
        transaction.receiptHash = _receiptHash;
        transaction.locationHash = _locationHash;

        // AI-powered risk analysis
        (RiskLevel riskScore, uint256 fraudProbability, bytes32 aiAnalysisHash) = _analyzeTransactionRisk(transactionId);
        transaction.riskScore = riskScore;
        transaction.fraudProbability = fraudProbability;
        transaction.aiAnalysisHash = aiAnalysisHash;

        // Update spending patterns
        _updateSpendingPattern(_citizenId, _amount, _category);

        transactionsByCitizen[_citizenId].push(transactionId);
        totalTransactions++;

        // Check for fraud
        if (fraudProbability >= fraudThreshold) {
            _createFraudAlert(_citizenId, fraudProbability, transactionId);
        }

        // Check for high risk
        if (uint256(riskScore) >= uint256(RiskLevel.HIGH)) {
            _createRiskAlert(_citizenId, riskScore, "High risk transaction detected", transactionId);
        }

        emit TransactionRecorded(transactionId, _citizenId, _amount, _category);
        return transactionId;
    }

    /**
     * @notice Register a merchant
     */
    function registerMerchant(
        address _merchantAddress,
        string memory _merchantName,
        string memory _businessType,
        bytes32 _licenseHash
    ) external onlyOwner {
        MerchantProfile storage merchant = merchantProfiles[_merchantAddress];
        merchant.merchantAddress = _merchantAddress;
        merchant.merchantName = _merchantName;
        merchant.businessType = _businessType;
        merchant.registrationDate = block.timestamp;
        merchant.licenseHash = _licenseHash;
        merchant.reputationScore = 500; // Base score
        merchant.isVerified = true;

        emit MerchantVerified(_merchantAddress, merchant.reputationScore);
    }

    /**
     * @notice Update merchant reputation
     */
    function updateMerchantReputation(address _merchant, int256 _scoreChange) external onlyOwner {
        MerchantProfile storage merchant = merchantProfiles[_merchant];
        require(merchant.registrationDate > 0, "Merchant not registered");

        if (_scoreChange > 0) {
            merchant.reputationScore = merchant.reputationScore + uint256(_scoreChange) > 1000 ?
                1000 : merchant.reputationScore + uint256(_scoreChange);
        } else {
            merchant.reputationScore = uint256(int256(merchant.reputationScore) + _scoreChange) < 0 ?
                0 : merchant.reputationScore + uint256(_scoreChange);
        }

        // Check for blacklisting
        if (merchant.reputationScore < 200) {
            merchant.isBlacklisted = true;
        }
    }

    /**
     * @notice Resolve a monitoring alert
     */
    function resolveAlert(bytes32 _alertId, bytes32 _resolutionHash) external onlyOwner {
        MonitoringAlert storage alert = monitoringAlerts[_alertId];
        require(!alert.isResolved, "Alert already resolved");

        alert.isResolved = true;
        alert.resolutionHash = _resolutionHash;
        alert.investigator = msg.sender;
    }

    /**
     * @notice Get citizen spending pattern
     */
    function getSpendingPattern(bytes32 _citizenId)
        external
        view
        returns (
            uint256 totalSpent,
            uint256 transactionCount,
            uint256 averageTransactionSize,
            RiskLevel overallRisk,
            uint256 fraudProbability
        )
    {
        SpendingPattern memory pattern = spendingPatterns[_citizenId];
        return (
            pattern.totalSpent,
            pattern.transactionCount,
            pattern.averageTransactionSize,
            pattern.overallRisk,
            pattern.fraudProbability
        );
    }

    /**
     * @notice Get category spending for a citizen
     */
    function getCategorySpending(bytes32 _citizenId, TransactionCategory _category)
        external
        view
        returns (uint256 amount, uint256 count)
    {
        SpendingPattern memory pattern = spendingPatterns[_citizenId];
        return (pattern.categorySpending[_category], pattern.categoryCount[_category]);
    }

    /**
     * @notice Get transaction details
     */
    function getTransaction(bytes32 _transactionId)
        external
        view
        returns (
            bytes32 citizenId,
            uint256 amount,
            TransactionCategory category,
            address merchant,
            RiskLevel riskScore,
            uint256 fraudProbability,
            bool isVerified
        )
    {
        TransactionRecord memory transaction = transactionRecords[_transactionId];
        return (
            transaction.citizenId,
            transaction.amount,
            transaction.category,
            transaction.merchant,
            transaction.riskScore,
            transaction.fraudProbability,
            transaction.isVerified
        );
    }

    /**
     * @notice Get merchant profile
     */
    function getMerchantProfile(address _merchant)
        external
        view
        returns (
            string memory merchantName,
            uint256 reputationScore,
            bool isVerified,
            bool isBlacklisted,
            uint256 totalTransactions
        )
    {
        MerchantProfile memory merchant = merchantProfiles[_merchant];
        return (
            merchant.merchantName,
            merchant.reputationScore,
            merchant.isVerified,
            merchant.isBlacklisted,
            merchant.totalTransactions
        );
    }

    /**
     * @notice Get monitoring alert
     */
    function getMonitoringAlert(bytes32 _alertId)
        external
        view
        returns (
            bytes32 citizenId,
            string memory alertType,
            RiskLevel severity,
            bool isResolved,
            uint256 alertDate
        )
    {
        MonitoringAlert memory alert = monitoringAlerts[_alertId];
        return (
            alert.citizenId,
            alert.alertType,
            alert.severity,
            alert.isResolved,
            alert.alertDate
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _maxTransactionAmount,
        uint256 _dailySpendingLimit,
        uint256 _monthlySpendingLimit,
        uint256 _fraudThreshold
    ) external onlyOwner {
        maxTransactionAmount = _maxTransactionAmount;
        dailySpendingLimit = _dailySpendingLimit;
        monthlySpendingLimit = _monthlySpendingLimit;
        fraudThreshold = _fraudThreshold;
    }

    /**
     * @notice Get global monitoring statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalAllocations,
            uint256 _totalTransactions,
            uint256 _totalMonitoringAlerts,
            uint256 _totalFraudDetected,
            uint256 _totalFundsTracked
        )
    {
        return (totalAllocations, totalTransactions, totalMonitoringAlerts, totalFraudDetected, totalFundsTracked);
    }

    // Internal functions
    function _analyzeTransactionRisk(bytes32 _transactionId)
        internal
        view
        returns (RiskLevel risk, uint256 fraudProbability, bytes32 aiAnalysisHash)
    {
        TransactionRecord memory transaction = transactionRecords[_transactionId];
        MerchantProfile memory merchant = merchantProfiles[transaction.merchant];
        SpendingPattern memory pattern = spendingPatterns[transaction.citizenId];

        uint256 riskScore = 0;

        // Merchant reputation check
        if (!merchant.isVerified || merchant.isBlacklisted) {
            riskScore += 300;
        } else if (merchant.reputationScore < 400) {
            riskScore += 200;
        }

        // Amount-based risk
        if (transaction.amount > pattern.averageTransactionSize * 3) {
            riskScore += 200;
        }

        // Category risk (unusual spending patterns)
        uint256 categoryPercentage = (pattern.categorySpending[transaction.category] * 10000) / (pattern.totalSpent + 1);
        if (categoryPercentage < 500) { // Less than 5% of spending in this category
            riskScore += 150;
        }

        // Time-based risk (unusual hours)
        uint256 hour = (block.timestamp / 3600) % 24;
        if (hour < 6 || hour > 22) { // Unusual transaction time
            riskScore += 100;
        }

        // Location consistency (simplified)
        // In production, would check against known locations

        // Determine risk level
        if (riskScore >= 500) {
            risk = RiskLevel.CRITICAL;
        } else if (riskScore >= 300) {
            risk = RiskLevel.HIGH;
        } else if (riskScore >= 150) {
            risk = RiskLevel.MEDIUM;
        } else {
            risk = RiskLevel.LOW;
        }

        // Fraud probability (simplified AI model)
        fraudProbability = riskScore * 10; // 0-1000 scale to 0-10000
        if (fraudProbability > 10000) fraudProbability = 10000;

        aiAnalysisHash = keccak256(abi.encodePacked(
            transaction.transactionId,
            riskScore,
            fraudProbability,
            block.timestamp
        ));

        return (risk, fraudProbability, aiAnalysisHash);
    }

    function _updateSpendingPattern(bytes32 _citizenId, uint256 _amount, TransactionCategory _category) internal {
        SpendingPattern storage pattern = spendingPatterns[_citizenId];

        pattern.totalSpent += _amount;
        pattern.transactionCount++;
        pattern.averageTransactionSize = pattern.totalSpent / pattern.transactionCount;
        pattern.lastTransactionDate = block.timestamp;
        pattern.categorySpending[_category] += _amount;
        pattern.categoryCount[_category]++;

        // Update overall risk based on patterns
        _updateOverallRisk(_citizenId);
    }

    function _updateOverallRisk(bytes32 _citizenId) internal {
        SpendingPattern storage pattern = spendingPatterns[_citizenId];

        uint256 riskScore = 0;

        // High fraud probability
        if (pattern.fraudProbability > highRiskThreshold) {
            riskScore += 300;
        }

        // Unusual spending patterns
        if (pattern.transactionCount > 0) {
            uint256 avgTransaction = pattern.averageTransactionSize;
            if (avgTransaction > 2000 * 1e18) { // High average transaction
                riskScore += 200;
            }
        }

        // Determine overall risk
        if (riskScore >= 400) {
            pattern.overallRisk = RiskLevel.CRITICAL;
        } else if (riskScore >= 250) {
            pattern.overallRisk = RiskLevel.HIGH;
        } else if (riskScore >= 150) {
            pattern.overallRisk = RiskLevel.MEDIUM;
        } else {
            pattern.overallRisk = RiskLevel.LOW;
        }
    }

    function _calculateDailySpending(bytes32 _citizenId, uint256 _dayStart) internal view returns (uint256) {
        bytes32[] memory citizenTransactions = transactionsByCitizen[_citizenId];
        uint256 dailyTotal = 0;

        for (uint256 i = 0; i < citizenTransactions.length; i++) {
            TransactionRecord memory transaction = transactionRecords[citizenTransactions[i]];
            if (transaction.transactionDate >= _dayStart && transaction.transactionDate < _dayStart + 86400) {
                dailyTotal += transaction.amount;
            }
        }

        return dailyTotal;
    }

    function _createFraudAlert(bytes32 _citizenId, uint256 _fraudProbability, bytes32 _transactionId) internal {
        bytes32 alertId = keccak256(abi.encodePacked(
            "FRAUD",
            _citizenId,
            _fraudProbability,
            block.timestamp
        ));

        MonitoringAlert storage alert = monitoringAlerts[alertId];
        alert.alertId = alertId;
        alert.citizenId = _citizenId;
        alert.alertType = "FRAUD_DETECTED";
        alert.description = "High probability of fraudulent transaction";
        alert.severity = RiskLevel.CRITICAL;
        alert.alertDate = block.timestamp;
        alert.isResolved = false;

        alertsByCitizen[_citizenId].push(alertId);
        totalMonitoringAlerts++;
        totalFraudDetected++;

        emit FraudDetected(_citizenId, _fraudProbability, alertId);
        emit RiskAlert(alertId, _citizenId, RiskLevel.CRITICAL, "FRAUD_DETECTED");
    }

    function _createRiskAlert(bytes32 _citizenId, RiskLevel _severity, string memory _description, bytes32 _transactionId) internal {
        bytes32 alertId = keccak256(abi.encodePacked(
            "RISK",
            _citizenId,
            _severity,
            block.timestamp
        ));

        MonitoringAlert storage alert = monitoringAlerts[alertId];
        alert.alertId = alertId;
        alert.citizenId = _citizenId;
        alert.alertType = "HIGH_RISK_TRANSACTION";
        alert.description = _description;
        alert.severity = _severity;
        alert.alertDate = block.timestamp;
        alert.isResolved = false;

        alertsByCitizen[_citizenId].push(alertId);
        totalMonitoringAlerts++;

        emit RiskAlert(alertId, _citizenId, _severity, "HIGH_RISK_TRANSACTION");
    }
}
