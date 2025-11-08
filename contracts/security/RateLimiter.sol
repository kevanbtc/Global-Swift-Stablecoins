// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title RateLimiter
 * @notice Rate limiting contract for transaction throughput control
 * @dev Implements configurable rate limiting strategies for CBDC transactions
 */
contract RateLimiter is AccessControl, Pausable {
    bytes32 public constant RATE_ADMIN_ROLE = keccak256("RATE_ADMIN_ROLE");
    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");

    enum LimitType {
        Transaction,    // Limit by transaction count
        Volume,        // Limit by transaction volume
        Both          // Limit by both count and volume
    }

    enum WindowType {
        Rolling,     // Rolling time window
        Fixed       // Fixed time window (e.g., daily reset)
    }

    struct RateLimit {
        uint256 maxTransactions;     // Maximum transactions per window
        uint256 maxVolume;          // Maximum volume per window
        uint256 windowSize;         // Time window size in seconds
        LimitType limitType;        // Type of limit to enforce
        WindowType windowType;      // Type of time window
        bool active;               // Whether limit is active
    }

    struct UsageData {
        uint256 transactionCount;   // Number of transactions in current window
        uint256 volume;            // Total volume in current window
        uint256 windowStart;       // Start time of current window
        uint256 lastUpdate;        // Last update timestamp
    }

    // State variables
    mapping(bytes32 => RateLimit) public limits;
    mapping(bytes32 => mapping(address => UsageData)) public usage;
    mapping(bytes32 => uint256) public globalUsage;
    
    // Events
    event RateLimitCreated(
        bytes32 indexed limitId,
        uint256 maxTransactions,
        uint256 maxVolume,
        uint256 windowSize,
        LimitType limitType,
        WindowType windowType
    );

    event RateLimitUpdated(
        bytes32 indexed limitId,
        uint256 maxTransactions,
        uint256 maxVolume
    );

    event TransactionChecked(
        bytes32 indexed limitId,
        address indexed account,
        uint256 amount,
        bool allowed
    );

    event WindowReset(
        bytes32 indexed limitId,
        address indexed account,
        uint256 timestamp
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RATE_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Create a new rate limit
     * @param limitId Unique identifier for the rate limit
     * @param maxTransactions Maximum transactions per window
     * @param maxVolume Maximum volume per window
     * @param windowSize Time window size in seconds
     * @param limitType Type of limit to enforce
     * @param windowType Type of time window
     */
    function createRateLimit(
        bytes32 limitId,
        uint256 maxTransactions,
        uint256 maxVolume,
        uint256 windowSize,
        LimitType limitType,
        WindowType windowType
    ) public onlyRole(RATE_ADMIN_ROLE)
    {
        require(limits[limitId].windowSize == 0, "Limit exists");
        require(windowSize > 0, "Invalid window");
        require(
            maxTransactions > 0 || maxVolume > 0,
            "Invalid limits"
        );
        
        limits[limitId] = RateLimit({
            maxTransactions: maxTransactions,
            maxVolume: maxVolume,
            windowSize: windowSize,
            limitType: limitType,
            windowType: windowType,
            active: true
        });
        
        emit RateLimitCreated(
            limitId,
            maxTransactions,
            maxVolume,
            windowSize,
            limitType,
            windowType
        );
    }

    /**
     * @notice Update an existing rate limit
     * @param limitId Rate limit identifier
     * @param maxTransactions New maximum transactions
     * @param maxVolume New maximum volume
     */
    function updateRateLimit(
        bytes32 limitId,
        uint256 maxTransactions,
        uint256 maxVolume
    ) public onlyRole(RATE_ADMIN_ROLE)
    {
        RateLimit storage limit = limits[limitId];
        require(limit.windowSize > 0, "Limit not found");
        
        limit.maxTransactions = maxTransactions;
        limit.maxVolume = maxVolume;
        
        emit RateLimitUpdated(limitId, maxTransactions, maxVolume);
    }

    /**
     * @notice Check if a transaction would exceed rate limits
     * @param limitId Rate limit identifier
     * @param account Account to check
     * @param amount Transaction amount
     * @return allowed Whether the transaction is allowed
     */
    function checkLimit(
        bytes32 limitId,
        address account,
        uint256 amount
    ) public whenNotPaused
        returns (bool allowed)
    {
        RateLimit storage limit = limits[limitId];
        require(limit.active, "Limit not active");
        
        _updateWindow(limitId, account);
        
        UsageData storage data = usage[limitId][account];
        allowed = true;
        
        if (limit.limitType == LimitType.Transaction ||
            limit.limitType == LimitType.Both) {
            if (data.transactionCount >= limit.maxTransactions) {
                allowed = false;
            }
        }
        
        if (allowed && (limit.limitType == LimitType.Volume ||
            limit.limitType == LimitType.Both)) {
            if (data.volume + amount > limit.maxVolume) {
                allowed = false;
            }
        }
        
        if (allowed) {
            data.transactionCount = data.transactionCount + 1;
            data.volume = data.volume + amount;
            data.lastUpdate = block.timestamp;
            globalUsage[limitId] = globalUsage[limitId] + amount;
        }
        
        emit TransactionChecked(limitId, account, amount, allowed);
        
        return allowed;
    }

    /**
     * @notice Update the time window for rate limiting
     * @param limitId Rate limit identifier
     * @param account Account to update
     */
    function _updateWindow(bytes32 limitId, address account) internal {
        RateLimit storage limit = limits[limitId];
        UsageData storage data = usage[limitId][account];
        
        if (data.windowStart == 0) {
            data.windowStart = block.timestamp;
            return;
        }
        
        uint256 windowEnd = limit.windowType == WindowType.Fixed
            ? data.windowStart + limit.windowSize
            : block.timestamp;
            
        if (block.timestamp >= windowEnd) {
            data.transactionCount = 0;
            data.volume = 0;
            data.windowStart = limit.windowType == WindowType.Fixed
                ? windowEnd
                : block.timestamp;
                
            emit WindowReset(limitId, account, block.timestamp);
        }
    }

    /**
     * @notice Get current usage data for an account
     * @param limitId Rate limit identifier
     * @param account Account to query
     */
    function getUsage(bytes32 limitId, address account) public view
        returns (
            uint256 transactionCount,
            uint256 volume,
            uint256 windowStart,
            uint256 lastUpdate
        )
    {
        UsageData storage data = usage[limitId][account];
        return (
            data.transactionCount,
            data.volume,
            data.windowStart,
            data.lastUpdate
        );
    }

    /**
     * @notice Get global usage for a rate limit
     * @param limitId Rate limit identifier
     */
    function getGlobalUsage(bytes32 limitId) public view
        returns (uint256)
    {
        return globalUsage[limitId];
    }

    /**
     * @notice Activate or deactivate a rate limit
     * @param limitId Rate limit identifier
     * @param active New active status
     */
    function setLimitActive(bytes32 limitId, bool active) public onlyRole(RATE_ADMIN_ROLE)
    {
        RateLimit storage limit = limits[limitId];
        require(limit.windowSize > 0, "Limit not found");
        limit.active = active;
    }

    // Admin functions
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}