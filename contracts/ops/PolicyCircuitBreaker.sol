// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Policy-Driven Circuit Breaker
/// @notice Implements configurable circuit breakers based on predefined policies
contract PolicyCircuitBreaker is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant POLICY_ADMIN_ROLE = keccak256("POLICY_ADMIN_ROLE");

    enum TriggerType {
        VOLUME,         // Trading volume threshold
        PRICE,         // Price movement threshold
        VELOCITY,      // Transaction velocity
        CONCENTRATION, // Holder concentration
        CUSTOM        // Custom policy check
    }

    struct CircuitBreaker {
        string name;
        TriggerType triggerType;
        uint256 threshold;
        uint256 cooldownPeriod;
        bool isActive;
        uint256 lastTriggered;
        address policyChecker;   // Contract implementing the check logic
    }

    struct ActivityLog {
        uint256 timestamp;
        bytes32 breakerId;
        string reason;
        address triggeredBy;
    }

    // Circuit breaker ID => Circuit breaker config
    mapping(bytes32 => CircuitBreaker) public circuitBreakers;
    
    // Circuit breaker ID => Activity logs
    mapping(bytes32 => ActivityLog[]) public activityLogs;

    // Events
    event CircuitBreakerCreated(bytes32 indexed id, string name, TriggerType triggerType);
    event CircuitBreakerTriggered(bytes32 indexed id, string reason, address triggeredBy);
    event CircuitBreakerReset(bytes32 indexed id, address resetBy);
    event CircuitBreakerUpdated(bytes32 indexed id, uint256 threshold, uint256 cooldownPeriod);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POLICY_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /// @notice Creates a new circuit breaker
    function createCircuitBreaker(
        string calldata name,
        TriggerType triggerType,
        uint256 threshold,
        uint256 cooldownPeriod,
        address policyChecker
    ) 
        external 
        onlyRole(POLICY_ADMIN_ROLE) 
        returns (bytes32)
    {
        require(bytes(name).length > 0, "Invalid name");
        require(cooldownPeriod > 0, "Invalid cooldown");
        if (triggerType == TriggerType.CUSTOM) {
            require(policyChecker != address(0), "Invalid policy checker");
        }

        bytes32 id = keccak256(abi.encodePacked(name, block.timestamp));
        
        require(circuitBreakers[id].threshold == 0, "Circuit breaker exists");

        circuitBreakers[id] = CircuitBreaker({
            name: name,
            triggerType: triggerType,
            threshold: threshold,
            cooldownPeriod: cooldownPeriod,
            isActive: true,
            lastTriggered: 0,
            policyChecker: policyChecker
        });

        emit CircuitBreakerCreated(id, name, triggerType);
        return id;
    }

    /// @notice Triggers a circuit breaker
    function triggerCircuitBreaker(bytes32 id, string calldata reason) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
    {
        CircuitBreaker storage breaker = circuitBreakers[id];
        require(breaker.isActive, "Circuit breaker not active");
        require(
            block.timestamp >= breaker.lastTriggered + breaker.cooldownPeriod,
            "Cooldown period active"
        );

        breaker.lastTriggered = block.timestamp;
        
        activityLogs[id].push(ActivityLog({
            timestamp: block.timestamp,
            breakerId: id,
            reason: reason,
            triggeredBy: msg.sender
        }));

        _pause();
        
        emit CircuitBreakerTriggered(id, reason, msg.sender);
    }

    /// @notice Resets a triggered circuit breaker
    function resetCircuitBreaker(bytes32 id) 
        external 
        onlyRole(POLICY_ADMIN_ROLE) 
        whenPaused 
    {
        CircuitBreaker storage breaker = circuitBreakers[id];
        require(breaker.isActive, "Circuit breaker not active");
        
        // Only reset if cooldown period has passed
        require(
            block.timestamp >= breaker.lastTriggered + breaker.cooldownPeriod,
            "Cooldown period active"
        );

        _unpause();
        
        emit CircuitBreakerReset(id, msg.sender);
    }

    /// @notice Updates circuit breaker parameters
    function updateCircuitBreaker(
        bytes32 id,
        uint256 newThreshold,
        uint256 newCooldownPeriod
    ) 
        external 
        onlyRole(POLICY_ADMIN_ROLE) 
    {
        CircuitBreaker storage breaker = circuitBreakers[id];
        require(breaker.isActive, "Circuit breaker not active");
        require(newCooldownPeriod > 0, "Invalid cooldown");

        breaker.threshold = newThreshold;
        breaker.cooldownPeriod = newCooldownPeriod;

        emit CircuitBreakerUpdated(id, newThreshold, newCooldownPeriod);
    }

    /// @notice Gets circuit breaker configuration
    function getCircuitBreaker(bytes32 id) 
        external 
        view 
        returns (
            string memory name,
            TriggerType triggerType,
            uint256 threshold,
            uint256 cooldownPeriod,
            bool isActive,
            uint256 lastTriggered,
            address policyChecker
        )
    {
        CircuitBreaker storage breaker = circuitBreakers[id];
        return (
            breaker.name,
            breaker.triggerType,
            breaker.threshold,
            breaker.cooldownPeriod,
            breaker.isActive,
            breaker.lastTriggered,
            breaker.policyChecker
        );
    }

    /// @notice Gets activity logs for a circuit breaker
    function getActivityLogs(bytes32 id) 
        external 
        view 
        returns (ActivityLog[] memory) 
    {
        return activityLogs[id];
    }
}
