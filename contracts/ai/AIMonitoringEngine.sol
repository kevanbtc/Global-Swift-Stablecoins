// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title AIMonitoringEngine
 * @notice AI-powered monitoring and analytics engine for system health
 * @dev Advanced monitoring with predictive analytics and anomaly detection
 */
contract AIMonitoringEngine is OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    enum AlertSeverity {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    enum MetricType {
        PERFORMANCE,
        SECURITY,
        COMPLIANCE,
        FINANCIAL,
        OPERATIONAL,
        SYSTEM_HEALTH
    }

    enum AnomalyType {
        SPIKE,
        DROP,
        TREND_CHANGE,
        OUTLIER,
        CORRELATION_BREAK,
        PREDICTION_DEVIATION
    }

    struct MetricData {
        bytes32 metricId;
        string name;
        string description;
        MetricType metricType;
        uint256 currentValue;
        uint256 previousValue;
        uint256 baselineValue;
        uint256 thresholdHigh;
        uint256 thresholdLow;
        uint256 lastUpdate;
        uint256 updateFrequency; // seconds
        bool isActive;
        bytes32[] dependencies;
    }

    struct Alert {
        bytes32 alertId;
        bytes32 metricId;
        AlertSeverity severity;
        string message;
        uint256 timestamp;
        uint256 value;
        uint256 threshold;
        bool isActive;
        bool isAcknowledged;
        address acknowledgedBy;
        uint256 acknowledgedAt;
    }

    struct Prediction {
        bytes32 predictionId;
        bytes32 metricId;
        uint256 predictedValue;
        uint256 confidence; // BPS
        uint256 predictionHorizon; // seconds
        uint256 timestamp;
        bool realized;
        uint256 actualValue;
    }

    struct AnomalyDetection {
        bytes32 anomalyId;
        bytes32 metricId;
        AnomalyType anomalyType;
        uint256 detectedValue;
        uint256 expectedValue;
        uint256 confidence; // BPS
        uint256 timestamp;
        string description;
        bool isResolved;
    }

    struct SystemHealthScore {
        uint256 overallScore; // 0-100
        uint256 performanceScore;
        uint256 securityScore;
        uint256 complianceScore;
        uint256 financialScore;
        uint256 operationalScore;
        uint256 lastUpdate;
        string riskLevel; // LOW, MEDIUM, HIGH, CRITICAL
    }

    // Storage
    mapping(bytes32 => MetricData) public metrics;
    mapping(bytes32 => Alert) public alerts;
    mapping(bytes32 => Prediction) public predictions;
    mapping(bytes32 => AnomalyDetection) public anomalies;
    mapping(address => bool) public authorizedReporters;
    mapping(MetricType => bytes32[]) public metricsByType;
    mapping(AlertSeverity => bytes32[]) public alertsBySeverity;

    bytes32[] public allMetrics;
    bytes32[] public activeAlerts;
    bytes32[] public recentPredictions;
    bytes32[] public detectedAnomalies;

    SystemHealthScore public systemHealth;

    // Configuration
    uint256 public alertCooldown = 1 hours; // Minimum time between similar alerts
    uint256 public predictionHorizon = 24 hours; // Default prediction window
    uint256 public anomalyThreshold = 9500; // 95% confidence for anomaly detection
    uint256 public healthUpdateFrequency = 1 hours;
    uint256 public maxPredictions = 1000; // Maximum stored predictions
    uint256 public maxAnomalies = 500; // Maximum stored anomalies

    // Events
    event MetricUpdated(bytes32 indexed metricId, uint256 value, uint256 timestamp);
    event AlertTriggered(bytes32 indexed alertId, bytes32 indexed metricId, AlertSeverity severity);
    event AlertAcknowledged(bytes32 indexed alertId, address acknowledgedBy);
    event PredictionMade(bytes32 indexed predictionId, bytes32 indexed metricId, uint256 predictedValue);
    event AnomalyDetected(bytes32 indexed anomalyId, bytes32 indexed metricId, AnomalyType anomalyType);
    event SystemHealthUpdated(uint256 overallScore, string riskLevel);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        authorizedReporters[initialOwner] = true;
        systemHealth.lastUpdate = block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Register a new metric for monitoring
     */
    function registerMetric(
        string memory _name,
        string memory _description,
        MetricType _metricType,
        uint256 _thresholdHigh,
        uint256 _thresholdLow,
        uint256 _updateFrequency,
        bytes32[] memory _dependencies
    ) external onlyOwner returns (bytes32) {
        bytes32 metricId = keccak256(abi.encodePacked(_name, _metricType, block.timestamp));

        MetricData storage metric = metrics[metricId];
        metric.metricId = metricId;
        metric.name = _name;
        metric.description = _description;
        metric.metricType = _metricType;
        metric.thresholdHigh = _thresholdHigh;
        metric.thresholdLow = _thresholdLow;
        metric.updateFrequency = _updateFrequency;
        metric.isActive = true;
        metric.dependencies = _dependencies;
        metric.lastUpdate = block.timestamp;

        metricsByType[_metricType].push(metricId);
        allMetrics.push(metricId);

        return metricId;
    }

    /**
     * @notice Update metric value (authorized reporters only)
     */
    function updateMetric(bytes32 _metricId, uint256 _value) external {
        require(authorizedReporters[msg.sender] || owner() == msg.sender, "Not authorized");
        require(metrics[_metricId].isActive, "Metric not active");

        MetricData storage metric = metrics[_metricId];
        metric.previousValue = metric.currentValue;
        metric.currentValue = _value;
        metric.lastUpdate = block.timestamp;

        // Check thresholds and trigger alerts
        _checkThresholds(_metricId);

        // Update system health
        _updateSystemHealth();

        emit MetricUpdated(_metricId, _value, block.timestamp);
    }

    /**
     * @notice Create a prediction for a metric
     */
    function createPrediction(
        bytes32 _metricId,
        uint256 _predictedValue,
        uint256 _confidence,
        uint256 _predictionHorizon
    ) external onlyOwner returns (bytes32) {
        require(metrics[_metricId].isActive, "Metric not active");
        require(_confidence <= 10000, "Invalid confidence");

        bytes32 predictionId = keccak256(abi.encodePacked(
            _metricId,
            _predictedValue,
            block.timestamp
        ));

        Prediction storage prediction = predictions[predictionId];
        prediction.predictionId = predictionId;
        prediction.metricId = _metricId;
        prediction.predictedValue = _predictedValue;
        prediction.confidence = _confidence;
        prediction.predictionHorizon = _predictionHorizon;
        prediction.timestamp = block.timestamp;

        recentPredictions.push(predictionId);
        if (recentPredictions.length > maxPredictions) {
            // Remove oldest prediction
            for (uint i = 0; i < recentPredictions.length - 1; i++) {
                recentPredictions[i] = recentPredictions[i + 1];
            }
            recentPredictions.pop();
        }

        emit PredictionMade(predictionId, _metricId, _predictedValue);
        return predictionId;
    }

    /**
     * @notice Report anomaly detection
     */
    function reportAnomaly(
        bytes32 _metricId,
        AnomalyType _anomalyType,
        uint256 _detectedValue,
        uint256 _expectedValue,
        uint256 _confidence,
        string memory _description
    ) external onlyOwner returns (bytes32) {
        require(metrics[_metricId].isActive, "Metric not active");
        require(_confidence >= anomalyThreshold, "Confidence too low");

        bytes32 anomalyId = keccak256(abi.encodePacked(
            _metricId,
            _anomalyType,
            _detectedValue,
            block.timestamp
        ));

        AnomalyDetection storage anomaly = anomalies[anomalyId];
        anomaly.anomalyId = anomalyId;
        anomaly.metricId = _metricId;
        anomaly.anomalyType = _anomalyType;
        anomaly.detectedValue = _detectedValue;
        anomaly.expectedValue = _expectedValue;
        anomaly.confidence = _confidence;
        anomaly.timestamp = block.timestamp;
        anomaly.description = _description;

        detectedAnomalies.push(anomalyId);
        if (detectedAnomalies.length > maxAnomalies) {
            // Remove oldest anomaly
            for (uint i = 0; i < detectedAnomalies.length - 1; i++) {
                detectedAnomalies[i] = detectedAnomalies[i + 1];
            }
            detectedAnomalies.pop();
        }

        emit AnomalyDetected(anomalyId, _metricId, _anomalyType);
        return anomalyId;
    }

    /**
     * @notice Acknowledge an alert
     */
    function acknowledgeAlert(bytes32 _alertId) external onlyOwner {
        Alert storage alert = alerts[_alertId];
        require(alert.isActive, "Alert not active");
        require(!alert.isAcknowledged, "Alert already acknowledged");

        alert.isAcknowledged = true;
        alert.acknowledgedBy = msg.sender;
        alert.acknowledgedAt = block.timestamp;

        // Remove from active alerts
        _removeFromActiveAlerts(_alertId);

        emit AlertAcknowledged(_alertId, msg.sender);
    }

    /**
     * @notice Authorize a reporter
     */
    function authorizeReporter(address _reporter, bool _authorized) external onlyOwner {
        authorizedReporters[_reporter] = _authorized;
    }

    /**
     * @notice Get metric details
     */
    function getMetric(bytes32 _metricId)
        external
        view
        returns (
            string memory name,
            MetricType metricType,
            uint256 currentValue,
            uint256 thresholdHigh,
            uint256 thresholdLow,
            bool isActive
        )
    {
        MetricData memory metric = metrics[_metricId];
        return (
            metric.name,
            metric.metricType,
            metric.currentValue,
            metric.thresholdHigh,
            metric.thresholdLow,
            metric.isActive
        );
    }

    /**
     * @notice Get alert details
     */
    function getAlert(bytes32 _alertId)
        external
        view
        returns (
            bytes32 metricId,
            AlertSeverity severity,
            string memory message,
            uint256 timestamp,
            bool isActive,
            bool isAcknowledged
        )
    {
        Alert memory alert = alerts[_alertId];
        return (
            alert.metricId,
            alert.severity,
            alert.message,
            alert.timestamp,
            alert.isActive,
            alert.isAcknowledged
        );
    }

    /**
     * @notice Get active alerts
     */
    function getActiveAlerts() external view returns (bytes32[] memory) {
        return activeAlerts;
    }

    /**
     * @notice Get alerts by severity
     */
    function getAlertsBySeverity(AlertSeverity _severity)
        external
        view
        returns (bytes32[] memory)
    {
        return alertsBySeverity[_severity];
    }

    /**
     * @notice Get metrics by type
     */
    function getMetricsByType(MetricType _type)
        external
        view
        returns (bytes32[] memory)
    {
        return metricsByType[_type];
    }

    /**
     * @notice Get system health score
     */
    function getSystemHealth()
        external
        view
        returns (
            uint256 overallScore,
            uint256 performanceScore,
            uint256 securityScore,
            uint256 complianceScore,
            uint256 financialScore,
            uint256 operationalScore,
            string memory riskLevel
        )
    {
        return (
            systemHealth.overallScore,
            systemHealth.performanceScore,
            systemHealth.securityScore,
            systemHealth.complianceScore,
            systemHealth.financialScore,
            systemHealth.operationalScore,
            systemHealth.riskLevel
        );
    }

    /**
     * @notice Update monitoring parameters
     */
    function updateParameters(
        uint256 _alertCooldown,
        uint256 _predictionHorizon,
        uint256 _anomalyThreshold,
        uint256 _healthUpdateFrequency,
        uint256 _maxPredictions,
        uint256 _maxAnomalies
    ) external onlyOwner {
        alertCooldown = _alertCooldown;
        predictionHorizon = _predictionHorizon;
        anomalyThreshold = _anomalyThreshold;
        healthUpdateFrequency = _healthUpdateFrequency;
        maxPredictions = _maxPredictions;
        maxAnomalies = _maxAnomalies;
    }

    /**
     * @notice Internal function to check thresholds and trigger alerts
     */
    function _checkThresholds(bytes32 _metricId) internal {
        MetricData memory metric = metrics[_metricId];

        // Check if we should trigger an alert (avoid spam)
        bool shouldAlert = true;
        for (uint i = 0; i < activeAlerts.length; i++) {
            Alert memory existingAlert = alerts[activeAlerts[i]];
            if (existingAlert.metricId == _metricId &&
                block.timestamp - existingAlert.timestamp < alertCooldown) {
                shouldAlert = false;
                break;
            }
        }

        if (!shouldAlert) return;

        AlertSeverity severity;
        string memory message;

        if (metric.currentValue >= metric.thresholdHigh) {
            severity = AlertSeverity.HIGH;
            message = string(abi.encodePacked("High threshold exceeded for ", metric.name));
        } else if (metric.currentValue <= metric.thresholdLow) {
            severity = AlertSeverity.MEDIUM;
            message = string(abi.encodePacked("Low threshold exceeded for ", metric.name));
        } else {
            return; // No alert needed
        }

        bytes32 alertId = keccak256(abi.encodePacked(
            _metricId,
            severity,
            metric.currentValue,
            block.timestamp
        ));

        Alert storage alert = alerts[alertId];
        alert.alertId = alertId;
        alert.metricId = _metricId;
        alert.severity = severity;
        alert.message = message;
        alert.timestamp = block.timestamp;
        alert.value = metric.currentValue;
        alert.threshold = metric.currentValue >= metric.thresholdHigh ? metric.thresholdHigh : metric.thresholdLow;
        alert.isActive = true;

        activeAlerts.push(alertId);
        alertsBySeverity[severity].push(alertId);

        emit AlertTriggered(alertId, _metricId, severity);
    }

    /**
     * @notice Internal function to update system health
     */
    function _updateSystemHealth() internal {
        // Calculate scores for each category
        uint256 performanceScore = _calculateCategoryScore(MetricType.PERFORMANCE);
        uint256 securityScore = _calculateCategoryScore(MetricType.SECURITY);
        uint256 complianceScore = _calculateCategoryScore(MetricType.COMPLIANCE);
        uint256 financialScore = _calculateCategoryScore(MetricType.FINANCIAL);
        uint256 operationalScore = _calculateCategoryScore(MetricType.OPERATIONAL);

        // Weighted overall score
        uint256 overallScore = (
            performanceScore * 2000 +    // 20%
            securityScore * 2500 +       // 25%
            complianceScore * 2000 +     // 20%
            financialScore * 2000 +      // 20%
            operationalScore * 1500      // 15%
        ) / 10000;

        // Determine risk level
        string memory riskLevel;
        if (overallScore >= 90) {
            riskLevel = "LOW";
        } else if (overallScore >= 75) {
            riskLevel = "MEDIUM";
        } else if (overallScore >= 60) {
            riskLevel = "HIGH";
        } else {
            riskLevel = "CRITICAL";
        }

        systemHealth.overallScore = overallScore;
        systemHealth.performanceScore = performanceScore;
        systemHealth.securityScore = securityScore;
        systemHealth.complianceScore = complianceScore;
        systemHealth.financialScore = financialScore;
        systemHealth.operationalScore = operationalScore;
        systemHealth.riskLevel = riskLevel;
        systemHealth.lastUpdate = block.timestamp;

        emit SystemHealthUpdated(overallScore, riskLevel);
    }

    /**
     * @notice Calculate score for a metric category
     */
    function _calculateCategoryScore(MetricType _type) internal view returns (uint256) {
        bytes32[] memory categoryMetrics = metricsByType[_type];
        if (categoryMetrics.length == 0) return 100; // Default healthy score

        uint256 totalScore = 0;
        uint256 activeMetrics = 0;

        for (uint i = 0; i < categoryMetrics.length; i++) {
            MetricData memory metric = metrics[categoryMetrics[i]];
            if (!metric.isActive) continue;

            uint256 metricScore = 100; // Default healthy

            // Calculate health based on thresholds
            if (metric.currentValue >= metric.thresholdHigh) {
                metricScore = 50; // Critical
            } else if (metric.currentValue <= metric.thresholdLow) {
                metricScore = 75; // Warning
            }

            // Factor in recency of updates
            uint256 timeSinceUpdate = block.timestamp - metric.lastUpdate;
            if (timeSinceUpdate > metric.updateFrequency * 2) {
                metricScore = metricScore * 80 / 100; // Penalty for stale data
            }

            totalScore += metricScore;
            activeMetrics++;
        }

        return activeMetrics > 0 ? totalScore / activeMetrics : 100;
    }

    /**
     * @notice Remove alert from active alerts array
     */
    function _removeFromActiveAlerts(bytes32 _alertId) internal {
        for (uint i = 0; i < activeAlerts.length; i++) {
            if (activeAlerts[i] == _alertId) {
                activeAlerts[i] = activeAlerts[activeAlerts.length - 1];
                activeAlerts.pop();
                break;
            }
        }
    }

    /**
     * @notice Get all metrics
     */
    function getAllMetrics() external view returns (bytes32[] memory) {
        return allMetrics;
    }

    /**
     * @notice Get recent predictions
     */
    function getRecentPredictions() external view returns (bytes32[] memory) {
        return recentPredictions;
    }

    /**
     * @notice Get detected anomalies
     */
    function getDetectedAnomalies() external view returns (bytes32[] memory) {
        return detectedAnomalies;
    }
}
