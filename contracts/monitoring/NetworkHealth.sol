// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title NetworkHealth
 * @notice Monitors and manages the health of the sequencer network
 * @dev Implements health checks, alerts, and network status tracking
 */
contract NetworkHealth is AccessControl, Pausable {
    bytes32 public constant HEALTH_REPORTER_ROLE = keccak256("HEALTH_REPORTER_ROLE");
    bytes32 public constant ALERT_MANAGER_ROLE = keccak256("ALERT_MANAGER_ROLE");

    // Health status enum
    enum HealthStatus {
        Healthy,
        Degraded,
        Critical,
        Offline
    }

    // Alert severity levels
    enum AlertSeverity {
        Info,
        Warning,
        Error,
        Critical
    }

    struct NodeHealth {
        address nodeAddress;
        HealthStatus status;
        uint256 lastHeartbeat;
        uint256 missedHeartbeats;
        uint256 responseTime;
        uint256 errorCount;
        string lastError;
        bool isActive;
    }

    struct NetworkStatus {
        uint256 activeNodes;
        uint256 totalNodes;
        uint256 healthyNodes;
        HealthStatus overallStatus;
        uint256 avgResponseTime;
        uint256 lastUpdateTime;
    }

    struct Alert {
        uint256 alertId;
        address nodeAddress;
        AlertSeverity severity;
        string message;
        uint256 timestamp;
        bool isActive;
        bool acknowledged;
    }

    // Constants
    uint256 public constant HEARTBEAT_INTERVAL = 5 minutes;
    uint256 public constant MAX_MISSED_HEARTBEATS = 3;
    uint256 public constant RESPONSE_TIME_THRESHOLD = 2 seconds;
    uint256 public constant ERROR_THRESHOLD = 5;

    // State variables
    mapping(address => NodeHealth) public nodeHealth;
    mapping(uint256 => Alert) public alerts;
    NetworkStatus public networkStatus;
    
    address[] public registeredNodes;
    uint256 public alertCount;
    uint256 public activeAlertCount;

    // Events
    event HealthStatusUpdated(
        address indexed node,
        HealthStatus status,
        uint256 timestamp
    );

    event AlertRaised(
        uint256 indexed alertId,
        address indexed node,
        AlertSeverity severity,
        string message
    );

    event AlertResolved(
        uint256 indexed alertId,
        address indexed node,
        uint256 timestamp
    );

    event NetworkStatusChanged(
        HealthStatus status,
        uint256 activeNodes,
        uint256 timestamp
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(HEALTH_REPORTER_ROLE, msg.sender);
        _grantRole(ALERT_MANAGER_ROLE, msg.sender);
        
        networkStatus.lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Register a new node for health monitoring
     * @param node Node address to register
     */
    function registerNode(address node)
        external
        onlyRole(HEALTH_REPORTER_ROLE)
        whenNotPaused
    {
        require(nodeHealth[node].lastHeartbeat == 0, "Node already registered");
        
        nodeHealth[node] = NodeHealth({
            nodeAddress: node,
            status: HealthStatus.Healthy,
            lastHeartbeat: block.timestamp,
            missedHeartbeats: 0,
            responseTime: 0,
            errorCount: 0,
            lastError: "",
            isActive: true
        });
        
        registeredNodes.push(node);
        networkStatus.totalNodes++;
        networkStatus.activeNodes++;
        networkStatus.healthyNodes++;
        
        emit HealthStatusUpdated(node, HealthStatus.Healthy, block.timestamp);
    }

    /**
     * @notice Update node health status
     * @param node Node address
     * @param status Health status
     * @param responseTime Node response time
     */
    function updateNodeHealth(
        address node,
        HealthStatus status,
        uint256 responseTime
    )
        external
        onlyRole(HEALTH_REPORTER_ROLE)
        whenNotPaused
    {
        NodeHealth storage health = nodeHealth[node];
        require(health.lastHeartbeat > 0, "Node not registered");
        
        health.status = status;
        health.lastHeartbeat = block.timestamp;
        health.responseTime = responseTime;
        
        if (status != HealthStatus.Healthy && health.errorCount < type(uint256).max) {
            health.errorCount++;
        }
        
        updateNetworkStatus();
        
        emit HealthStatusUpdated(node, status, block.timestamp);
    }

    /**
     * @notice Report an error for a node
     * @param node Node address
     * @param errorMessage Error description
     * @param severity Alert severity
     */
    function reportError(
        address node,
        string memory errorMessage,
        AlertSeverity severity
    )
        external
        onlyRole(HEALTH_REPORTER_ROLE)
        whenNotPaused
    {
        NodeHealth storage health = nodeHealth[node];
        require(health.lastHeartbeat > 0, "Node not registered");
        
        health.lastError = errorMessage;
        health.errorCount++;
        
        if (health.errorCount >= ERROR_THRESHOLD) {
            health.status = HealthStatus.Degraded;
        }
        
        uint256 alertId = ++alertCount;
        alerts[alertId] = Alert({
            alertId: alertId,
            nodeAddress: node,
            severity: severity,
            message: errorMessage,
            timestamp: block.timestamp,
            isActive: true,
            acknowledged: false
        });
        
        activeAlertCount++;
        updateNetworkStatus();
        
        emit AlertRaised(alertId, node, severity, errorMessage);
    }

    /**
     * @notice Acknowledge an alert
     * @param alertId Alert identifier
     */
    function acknowledgeAlert(uint256 alertId)
        external
        onlyRole(ALERT_MANAGER_ROLE)
        whenNotPaused
    {
        Alert storage alert = alerts[alertId];
        require(alert.timestamp > 0, "Alert not found");
        require(!alert.acknowledged, "Already acknowledged");
        
        alert.acknowledged = true;
        
        if (alert.isActive) {
            alert.isActive = false;
            activeAlertCount--;
        }
        
        emit AlertResolved(alertId, alert.nodeAddress, block.timestamp);
    }

    /**
     * @notice Update the overall network status
     */
    function updateNetworkStatus() internal {
        uint256 totalResponseTime = 0;
        uint256 healthyCount = 0;
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < registeredNodes.length; i++) {
            address node = registeredNodes[i];
            NodeHealth storage health = nodeHealth[node];
            
            if (health.isActive) {
                activeCount++;
                totalResponseTime += health.responseTime;
                
                if (health.status == HealthStatus.Healthy) {
                    healthyCount++;
                }
            }
        }
        
        networkStatus.activeNodes = activeCount;
        networkStatus.healthyNodes = healthyCount;
        networkStatus.avgResponseTime = activeCount > 0 ? totalResponseTime / activeCount : 0;
        networkStatus.lastUpdateTime = block.timestamp;
        
        // Determine overall network health
        if (healthyCount == activeCount) {
            networkStatus.overallStatus = HealthStatus.Healthy;
        } else if (healthyCount >= activeCount * 2 / 3) {
            networkStatus.overallStatus = HealthStatus.Degraded;
        } else if (healthyCount >= activeCount / 3) {
            networkStatus.overallStatus = HealthStatus.Critical;
        } else {
            networkStatus.overallStatus = HealthStatus.Offline;
        }
        
        emit NetworkStatusChanged(
            networkStatus.overallStatus,
            activeCount,
            block.timestamp
        );
    }

    /**
     * @notice Get detailed node health information
     * @param node Node address
     */
    function getNodeHealth(address node)
        external
        view
        returns (NodeHealth memory)
    {
        require(nodeHealth[node].lastHeartbeat > 0, "Node not registered");
        return nodeHealth[node];
    }

    /**
     * @notice Get all active alerts
     */
    function getActiveAlerts()
        external
        view
        returns (Alert[] memory)
    {
        Alert[] memory activeAlerts = new Alert[](activeAlertCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= alertCount; i++) {
            if (alerts[i].isActive) {
                activeAlerts[index] = alerts[i];
                index++;
            }
        }
        
        return activeAlerts;
    }

    /**
     * @notice Get network health summary
     */
    function getNetworkHealthSummary()
        external
        view
        returns (
            HealthStatus status,
            uint256 activeNodes,
            uint256 healthyNodes,
            uint256 avgResponseTime,
            uint256 activeAlerts
        )
    {
        return (
            networkStatus.overallStatus,
            networkStatus.activeNodes,
            networkStatus.healthyNodes,
            networkStatus.avgResponseTime,
            activeAlertCount
        );
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}