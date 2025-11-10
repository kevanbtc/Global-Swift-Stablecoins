// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title NAVRebaseController
 * @notice Controls NAV-based rebase operations for stablecoins
 * @dev Manages rebase timing, calculations, and execution with safety checks
 */
contract NAVRebaseController is Ownable, AccessControl {
    bytes32 public constant REBASE_ADMIN_ROLE = keccak256("REBASE_ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    struct RebaseConfig {
        address stablecoin;           // Target stablecoin contract
        uint256 targetPrice;          // Target price (18 decimals, e.g., 1e18 = $1.00)
        uint256 rebaseThreshold;      // Minimum deviation to trigger rebase (basis points)
        uint256 maxRebasePercent;     // Maximum rebase percentage (basis points)
        uint256 rebaseCooldown;       // Minimum time between rebases
        bool isActive;                // Whether rebase is enabled
        uint256 lastRebaseTime;       // Timestamp of last rebase
    }

    struct RebaseExecution {
        bytes32 executionId;
        address stablecoin;
        uint256 oldNav;
        uint256 newNav;
        uint256 rebasePercent;
        uint256 totalSupply;
        uint256 timestamp;
        bool success;
        string reason;
    }

    // Rebase configurations
    mapping(address => RebaseConfig) public rebaseConfigs;
    mapping(bytes32 => RebaseExecution) public rebaseExecutions;

    // Global settings
    uint256 public globalRebaseCooldown = 6 hours;
    uint256 public globalMaxRebasePercent = 100; // 1%
    uint256 public lastGlobalRebaseTime;

    // Circuit breaker
    bool public emergencyPause;
    uint256 public emergencyPauseTime;

    // Events
    event RebaseConfigured(address indexed stablecoin, uint256 targetPrice);
    event RebaseExecuted(bytes32 indexed executionId, address indexed stablecoin, uint256 rebasePercent);
    event RebaseSkipped(address indexed stablecoin, string reason);
    event EmergencyPauseActivated(address indexed activator);
    event EmergencyPauseDeactivated(address indexed deactivator);

    constructor(address admin) Ownable(admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REBASE_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
        _grantRole(EMERGENCY_ROLE, admin);
    }

    /**
     * @notice Configure rebase parameters for a stablecoin
     */
    function configureRebase(
        address stablecoin,
        uint256 targetPrice,
        uint256 rebaseThreshold,
        uint256 maxRebasePercent,
        uint256 rebaseCooldown
    ) public onlyRole(REBASE_ADMIN_ROLE) {
        require(stablecoin != address(0), "Invalid stablecoin address");
        require(targetPrice > 0, "Invalid target price");
        require(rebaseThreshold > 0 && rebaseThreshold <= 10000, "Invalid threshold"); // Max 100%
        require(maxRebasePercent > 0 && maxRebasePercent <= 1000, "Invalid max rebase"); // Max 10%

        rebaseConfigs[stablecoin] = RebaseConfig({
            stablecoin: stablecoin,
            targetPrice: targetPrice,
            rebaseThreshold: rebaseThreshold,
            maxRebasePercent: maxRebasePercent,
            rebaseCooldown: rebaseCooldown,
            isActive: true,
            lastRebaseTime: 0
        });

        emit RebaseConfigured(stablecoin, targetPrice);
    }

    /**
     * @notice Execute rebase for a stablecoin
     */
    function executeRebase(
        address stablecoin,
        uint256 currentNav
    ) public onlyRole(ORACLE_ROLE) returns (bool) {
        require(!emergencyPause, "Emergency pause active");

        RebaseConfig storage config = rebaseConfigs[stablecoin];
        require(config.isActive, "Rebase not configured");
        require(config.stablecoin == stablecoin, "Stablecoin mismatch");

        // Check cooldown periods
        require(
            block.timestamp >= config.lastRebaseTime + config.rebaseCooldown,
            "Rebase cooldown active"
        );
        require(
            block.timestamp >= lastGlobalRebaseTime + globalRebaseCooldown,
            "Global rebase cooldown active"
        );

        // Calculate deviation from target
        uint256 deviation;
        bool isAboveTarget;

        if (currentNav > config.targetPrice) {
            deviation = ((currentNav - config.targetPrice) * 10000) / config.targetPrice;
            isAboveTarget = true;
        } else {
            deviation = ((config.targetPrice - currentNav) * 10000) / config.targetPrice;
            isAboveTarget = false;
        }

        // Check if deviation exceeds threshold
        if (deviation < config.rebaseThreshold) {
            emit RebaseSkipped(stablecoin, "Deviation below threshold");
            return false;
        }

        // Calculate rebase percentage (capped)
        uint256 rebasePercent = deviation > config.maxRebasePercent ?
            config.maxRebasePercent : deviation;

        // Cap at global max
        if (rebasePercent > globalMaxRebasePercent) {
            rebasePercent = globalMaxRebasePercent;
        }

        // Execute rebase (this would call the stablecoin contract)
        // For now, just record the execution
        bytes32 executionId = keccak256(abi.encodePacked(
            stablecoin, currentNav, rebasePercent, block.timestamp
        ));

        rebaseExecutions[executionId] = RebaseExecution({
            executionId: executionId,
            stablecoin: stablecoin,
            oldNav: config.targetPrice, // Simplified
            newNav: currentNav,
            rebasePercent: rebasePercent,
            totalSupply: 0, // Would get from stablecoin
            timestamp: block.timestamp,
            success: true,
            reason: ""
        });

        // Update timestamps
        config.lastRebaseTime = block.timestamp;
        lastGlobalRebaseTime = block.timestamp;

        emit RebaseExecuted(executionId, stablecoin, rebasePercent);
        return true;
    }

    /**
     * @notice Check if rebase is needed for a stablecoin
     */
    function shouldRebase(
        address stablecoin,
        uint256 currentNav
    ) public view returns (bool needed, uint256 deviation, bool isAboveTarget) {
        RebaseConfig memory config = rebaseConfigs[stablecoin];
        if (!config.isActive) return (false, 0, false);

        // Check cooldowns
        if (block.timestamp < config.lastRebaseTime + config.rebaseCooldown) {
            return (false, 0, false);
        }
        if (block.timestamp < lastGlobalRebaseTime + globalRebaseCooldown) {
            return (false, 0, false);
        }

        // Calculate deviation
        uint256 dev;
        bool above;

        if (currentNav > config.targetPrice) {
            dev = ((currentNav - config.targetPrice) * 10000) / config.targetPrice;
            above = true;
        } else {
            dev = ((config.targetPrice - currentNav) * 10000) / config.targetPrice;
            above = false;
        }

        bool needsRebase = dev >= config.rebaseThreshold;
        return (needsRebase, dev, above);
    }

    /**
     * @notice Get rebase configuration
     */
    function getRebaseConfig(address stablecoin) public view returns (RebaseConfig memory) {
        return rebaseConfigs[stablecoin];
    }

    /**
     * @notice Get rebase execution details
     */
    function getRebaseExecution(bytes32 executionId) public view returns (RebaseExecution memory) {
        return rebaseExecutions[executionId];
    }

    /**
     * @notice Update global rebase settings
     */
    function updateGlobalSettings(
        uint256 cooldown,
        uint256 maxRebasePercent
    ) public onlyRole(REBASE_ADMIN_ROLE) {
        globalRebaseCooldown = cooldown;
        globalMaxRebasePercent = maxRebasePercent;
    }

    /**
     * @notice Update rebase config for specific stablecoin
     */
    function updateRebaseConfig(
        address stablecoin,
        uint256 targetPrice,
        uint256 rebaseThreshold,
        uint256 maxRebasePercent
    ) public onlyRole(REBASE_ADMIN_ROLE) {
        RebaseConfig storage config = rebaseConfigs[stablecoin];
        require(config.isActive, "Rebase not configured");

        config.targetPrice = targetPrice;
        config.rebaseThreshold = rebaseThreshold;
        config.maxRebasePercent = maxRebasePercent;
    }

    /**
     * @notice Enable/disable rebase for stablecoin
     */
    function setRebaseActive(address stablecoin, bool active) public onlyRole(REBASE_ADMIN_ROLE) {
        rebaseConfigs[stablecoin].isActive = active;
    }

    /**
     * @notice Emergency pause all rebases
     */
    function activateEmergencyPause() public onlyRole(EMERGENCY_ROLE) {
        emergencyPause = true;
        emergencyPauseTime = block.timestamp;
        emit EmergencyPauseActivated(msg.sender);
    }

    /**
     * @notice Deactivate emergency pause
     */
    function deactivateEmergencyPause() public onlyRole(EMERGENCY_ROLE) {
        emergencyPause = false;
        emit EmergencyPauseDeactivated(msg.sender);
    }

    /**
     * @notice Get emergency status
     */
    function getEmergencyStatus() public view returns (bool paused, uint256 pauseTime) {
        return (emergencyPause, emergencyPauseTime);
    }

    /**
     * @notice Get time until next allowed rebase
     */
    function getTimeUntilNextRebase(address stablecoin) public view returns (uint256) {
        RebaseConfig memory config = rebaseConfigs[stablecoin];
        if (!config.isActive) return type(uint256).max;

        uint256 configCooldownEnd = config.lastRebaseTime + config.rebaseCooldown;
        uint256 globalCooldownEnd = lastGlobalRebaseTime + globalRebaseCooldown;

        uint256 latestCooldownEnd = configCooldownEnd > globalCooldownEnd ?
            configCooldownEnd : globalCooldownEnd;

        if (block.timestamp >= latestCooldownEnd) return 0;
        return latestCooldownEnd - block.timestamp;
    }
}
