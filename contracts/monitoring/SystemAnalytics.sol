// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title SystemAnalytics
 * @notice Analytics and insights for transaction patterns and system performance
 * @dev Implements advanced analytics for system optimization
 */
contract SystemAnalytics is AccessControl, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant ANALYTICS_ROLE = keccak256("ANALYTICS_ROLE");
    bytes32 public constant VIEWER_ROLE = keccak256("VIEWER_ROLE");

    struct TransactionPattern {
        bytes32 patternId;
        string patternType;
        uint256 occurrences;
        uint256 avgGasUsed;
        uint256 avgValue;
        uint256 firstSeen;
        uint256 lastSeen;
    }

    struct UserAnalytics {
        address userAddress;
        uint256 totalTransactions;
        uint256 totalGasUsed;
        uint256 totalValue;
        uint256 avgResponseTime;
        uint256[] patternIds;
        uint256 firstActivity;
        uint256 lastActivity;
    }

    struct SystemUsage {
        uint256 timestamp;
        uint256 activeUsers;
        uint256 newUsers;
        uint256 transactionCount;
        uint256 avgGasPrice;
        uint256 totalValue;
        mapping(string => uint256) categoryMetrics;
    }

    // State variables
    mapping(bytes32 => TransactionPattern) public patterns;
    mapping(address => UserAnalytics) public userAnalytics;
    mapping(uint256 => SystemUsage) public hourlyUsage;
    mapping(uint256 => SystemUsage) public dailyUsage;
    
    EnumerableSet.AddressSet private activeUsers;
    EnumerableSet.Bytes32Set private knownPatterns;
    
    // Tracking variables
    uint256 public totalPatterns;
    uint256 public totalUsers;
    uint256 public currentHour;
    uint256 public currentDay;

    // Events
    event PatternDetected(
        bytes32 indexed patternId,
        string patternType,
        uint256 occurrences
    );

    event UserActivityUpdated(
        address indexed user,
        uint256 transactions,
        uint256 gasUsed
    );

    event SystemUsageUpdated(
        uint256 indexed timestamp,
        bool isHourly,
        uint256 activeUsers,
        uint256 transactionCount
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ANALYTICS_ROLE, msg.sender);
        _grantRole(VIEWER_ROLE, msg.sender);
        
        currentHour = block.timestamp / 1 hours;
        currentDay = block.timestamp / 1 days;
    }

    /**
     * @notice Record transaction pattern
     * @param patternType Type of pattern detected
     * @param gasUsed Gas consumed
     * @param value Transaction value
     */
    function recordPattern(
        string memory patternType,
        uint256 gasUsed,
        uint256 value
    ) public onlyRole(ANALYTICS_ROLE)
        whenNotPaused
        returns (bytes32)
    {
        bytes32 patternId = keccak256(abi.encodePacked(patternType));
        
        TransactionPattern storage pattern = patterns[patternId];
        if (pattern.firstSeen == 0) {
            pattern.patternId = patternId;
            pattern.patternType = patternType;
            pattern.firstSeen = block.timestamp;
            knownPatterns.add(patternId);
            totalPatterns++;
        }
        
        pattern.occurrences++;
        pattern.avgGasUsed = ((pattern.avgGasUsed * (pattern.occurrences - 1)) + gasUsed) / pattern.occurrences;
        pattern.avgValue = ((pattern.avgValue * (pattern.occurrences - 1)) + value) / pattern.occurrences;
        pattern.lastSeen = block.timestamp;
        
        emit PatternDetected(patternId, patternType, pattern.occurrences);
        
        return patternId;
    }

    /**
     * @notice Update user analytics
     * @param user User address
     * @param gasUsed Gas consumed
     * @param value Transaction value
     * @param responseTime Response time
     * @param patternId Associated pattern
     */
    function updateUserAnalytics(
        address user,
        uint256 gasUsed,
        uint256 value,
        uint256 responseTime,
        bytes32 patternId
    ) public onlyRole(ANALYTICS_ROLE)
        whenNotPaused
    {
        UserAnalytics storage analytics = userAnalytics[user];
        
        if (analytics.firstActivity == 0) {
            analytics.firstActivity = block.timestamp;
            analytics.userAddress = user;
            totalUsers++;
        }
        
        analytics.totalTransactions++;
        analytics.totalGasUsed += gasUsed;
        analytics.totalValue += value;
        analytics.avgResponseTime = ((analytics.avgResponseTime * (analytics.totalTransactions - 1)) + responseTime) / analytics.totalTransactions;
        analytics.lastActivity = block.timestamp;
        
        if (patternId != bytes32(0)) {
            bool patternExists = false;
            for (uint256 i = 0; i < analytics.patternIds.length; i++) {
                if (analytics.patternIds[i] == uint256(patternId)) {
                    patternExists = true;
                    break;
                }
            }
            if (!patternExists) {
                analytics.patternIds.push(uint256(patternId));
            }
        }
        
        activeUsers.add(user);
        
        emit UserActivityUpdated(user, analytics.totalTransactions, analytics.totalGasUsed);
        
        updateSystemUsage(gasUsed, value);
    }

    /**
     * @notice Update system usage metrics
     * @param gasUsed Gas consumed
     * @param value Transaction value
     */
    function updateSystemUsage(uint256 gasUsed, uint256 value) internal {
        uint256 hourId = block.timestamp / 1 hours;
        uint256 dayId = block.timestamp / 1 days;
        
        // Update hourly usage
        if (hourId > currentHour) {
            currentHour = hourId;
        }
        
        SystemUsage storage hourly = hourlyUsage[hourId];
        if (hourly.timestamp == 0) {
            hourly.timestamp = hourId * 1 hours;
            hourly.newUsers = 0;
        }
        
        updateUsageMetrics(hourly, gasUsed, value);
        
        // Update daily usage
        if (dayId > currentDay) {
            currentDay = dayId;
        }
        
        SystemUsage storage daily = dailyUsage[dayId];
        if (daily.timestamp == 0) {
            daily.timestamp = dayId * 1 days;
            daily.newUsers = 0;
        }
        
        updateUsageMetrics(daily, gasUsed, value);
    }

    /**
     * @notice Update usage metrics for a time window
     * @param usage Usage struct to update
     * @param gasUsed Gas consumed
     * @param value Transaction value
     */
    function updateUsageMetrics(
        SystemUsage storage usage,
        uint256 gasUsed,
        uint256 value
    )
        internal
    {
        usage.activeUsers = activeUsers.length();
        usage.transactionCount++;
        usage.avgGasPrice = ((usage.avgGasPrice * (usage.transactionCount - 1)) + gasUsed) / usage.transactionCount;
        usage.totalValue += value;
    }

    /**
     * @notice Get pattern details
     * @param patternId Pattern identifier
     */
    function getPattern(bytes32 patternId) public view
        returns (TransactionPattern memory)
    {
        return patterns[patternId];
    }

    /**
     * @notice Get all known patterns
     */
    function getAllPatterns() public view
        returns (TransactionPattern[] memory)
    {
        bytes32[] memory patternIds = new bytes32[](knownPatterns.length());
        TransactionPattern[] memory result = new TransactionPattern[](knownPatterns.length());
        
        for (uint256 i = 0; i < knownPatterns.length(); i++) {
            patternIds[i] = knownPatterns.at(i);
            result[i] = patterns[patternIds[i]];
        }
        
        return result;
    }

    /**
     * @notice Get user analytics
     * @param user User address
     */
    function getUserAnalytics(address user) public view
        returns (UserAnalytics memory)
    {
        return userAnalytics[user];
    }

    /**
     * @notice Get hourly system usage
     * @param hour Hour timestamp
     */
    function getHourlyUsage(uint256 hour) public view
        returns (
            uint256 timestamp,
            uint256 activeUsers,
            uint256 newUsers,
            uint256 transactionCount,
            uint256 avgGasPrice,
            uint256 totalValue
        )
    {
        SystemUsage storage usage = hourlyUsage[hour];
        return (
            usage.timestamp,
            usage.activeUsers,
            usage.newUsers,
            usage.transactionCount,
            usage.avgGasPrice,
            usage.totalValue
        );
    }

    /**
     * @notice Get daily system usage
     * @param day Day timestamp
     */
    function getDailyUsage(uint256 day) public view
        returns (
            uint256 timestamp,
            uint256 activeUsers,
            uint256 newUsers,
            uint256 transactionCount,
            uint256 avgGasPrice,
            uint256 totalValue
        )
    {
        SystemUsage storage usage = dailyUsage[day];
        return (
            usage.timestamp,
            usage.activeUsers,
            usage.newUsers,
            usage.transactionCount,
            usage.avgGasPrice,
            usage.totalValue
        );
    }

    /**
     * @notice Get system overview
     */
    function getSystemOverview() public view
        returns (
            uint256 _totalUsers,
            uint256 _activeUsers,
            uint256 _totalPatterns,
            uint256 currentHourlyTx,
            uint256 currentDailyTx
        )
    {
        return (
            totalUsers,
            activeUsers.length(),
            totalPatterns,
            hourlyUsage[currentHour].transactionCount,
            dailyUsage[currentDay].transactionCount
        );
    }

    // Admin functions
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}