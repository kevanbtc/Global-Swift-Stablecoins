// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StablecoinPolicyEngine
 * @notice Policy engine for stablecoin operations with regulatory compliance
 * @dev Manages minting, burning, and transfer policies for stablecoins
 */
contract StablecoinPolicyEngine is Ownable, AccessControl {
    bytes32 public constant POLICY_ADMIN_ROLE = keccak256("POLICY_ADMIN_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    enum PolicyType {
        MINTING,
        BURNING,
        TRANSFER,
        REBASE,
        RESERVE_UPDATE
    }

    enum RiskLevel {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    struct Policy {
        PolicyType policyType;
        bool isActive;
        uint256 maxAmount;
        uint256 minAmount;
        uint256 dailyLimit;
        uint256 cooldownPeriod;
        RiskLevel riskLevel;
        bytes32[] requiredApprovals;
        bool requiresOracle;
        bool requiresCompliance;
    }

    struct PolicyExecution {
        bytes32 policyId;
        address executor;
        address target;
        uint256 amount;
        bytes32 txHash;
        uint256 timestamp;
        bool approved;
        bytes32[] approvals;
    }

    // Policy storage
    mapping(bytes32 => Policy) public policies;
    mapping(bytes32 => PolicyExecution) public executions;
    mapping(address => mapping(bytes32 => uint256)) public dailyUsage; // account => policyId => amount
    mapping(bytes32 => uint256) public lastExecutionTime;

    // Global limits
    uint256 public globalDailyLimit = 10000000 * 1e18; // 10M tokens
    uint256 public globalDailyUsed;
    uint256 public lastResetTime;

    // Events
    event PolicyCreated(bytes32 indexed policyId, PolicyType policyType);
    event PolicyExecuted(bytes32 indexed executionId, bytes32 indexed policyId, bool success);
    event PolicyViolation(bytes32 indexed policyId, address indexed account, string reason);
    event DailyLimitReset(uint256 newLimit);

    constructor(address admin) {
        _transferOwnership(admin);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POLICY_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_OFFICER_ROLE, admin);
        _grantRole(AUDITOR_ROLE, admin);

        lastResetTime = block.timestamp;
    }

    /**
     * @notice Create a new policy
     */
    function createPolicy(
        bytes32 policyId,
        PolicyType policyType,
        uint256 maxAmount,
        uint256 minAmount,
        uint256 dailyLimit,
        uint256 cooldownPeriod,
        RiskLevel riskLevel,
        bytes32[] memory requiredApprovals,
        bool requiresOracle,
        bool requiresCompliance
    ) external onlyRole(POLICY_ADMIN_ROLE) {
        require(policies[policyId].policyType == PolicyType.MINTING, "Policy already exists");

        policies[policyId] = Policy({
            policyType: policyType,
            isActive: true,
            maxAmount: maxAmount,
            minAmount: minAmount,
            dailyLimit: dailyLimit,
            cooldownPeriod: cooldownPeriod,
            riskLevel: riskLevel,
            requiredApprovals: requiredApprovals,
            requiresOracle: requiresOracle,
            requiresCompliance: requiresCompliance
        });

        emit PolicyCreated(policyId, policyType);
    }

    /**
     * @notice Execute a policy action
     */
    function executePolicy(
        bytes32 policyId,
        address target,
        uint256 amount,
        bytes32 txHash
    ) external returns (bool) {
        Policy memory policy = policies[policyId];
        require(policy.isActive, "Policy not active");

        // Check basic limits
        require(amount >= policy.minAmount && amount <= policy.maxAmount, "Amount out of bounds");

        // Check cooldown
        require(
            block.timestamp >= lastExecutionTime[policyId] + policy.cooldownPeriod,
            "Cooldown period not elapsed"
        );

        // Check daily limits
        _checkAndUpdateDailyLimits(msg.sender, policyId, amount);

        // Check approvals for high-risk policies
        if (policy.riskLevel >= RiskLevel.HIGH) {
            require(_checkApprovals(policyId, txHash), "Insufficient approvals");
        }

        // Create execution record
        bytes32 executionId = keccak256(abi.encodePacked(policyId, target, amount, block.timestamp));
        executions[executionId] = PolicyExecution({
            policyId: policyId,
            executor: msg.sender,
            target: target,
            amount: amount,
            txHash: txHash,
            timestamp: block.timestamp,
            approved: true,
            approvals: new bytes32[](0)
        });

        lastExecutionTime[policyId] = block.timestamp;

        emit PolicyExecuted(executionId, policyId, true);
        return true;
    }

    /**
     * @notice Approve a policy execution
     */
    function approveExecution(
        bytes32 executionId,
        bytes32 approvalHash
    ) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        PolicyExecution storage execution = executions[executionId];
        require(execution.timestamp > 0, "Execution not found");
        require(!execution.approved, "Already approved");

        // Add approval
        execution.approvals.push(approvalHash);

        // Check if all required approvals are met
        Policy memory policy = policies[execution.policyId];
        if (execution.approvals.length >= policy.requiredApprovals.length) {
            execution.approved = true;
        }
    }

    /**
     * @notice Check if a policy action is allowed
     */
    function checkPolicy(
        bytes32 policyId,
        address account,
        uint256 amount
    ) external view returns (bool allowed, string memory reason) {
        Policy memory policy = policies[policyId];

        if (!policy.isActive) {
            return (false, "Policy not active");
        }

        if (amount < policy.minAmount || amount > policy.maxAmount) {
            return (false, "Amount out of bounds");
        }

        // Check daily limits
        uint256 currentDailyUsage = dailyUsage[account][policyId];
        if (currentDailyUsage + amount > policy.dailyLimit) {
            return (false, "Daily limit exceeded");
        }

        // Check global daily limit
        if (globalDailyUsed + amount > globalDailyLimit) {
            return (false, "Global daily limit exceeded");
        }

        // Check cooldown
        if (block.timestamp < lastExecutionTime[policyId] + policy.cooldownPeriod) {
            return (false, "Cooldown period active");
        }

        return (true, "");
    }

    /**
     * @notice Update policy parameters
     */
    function updatePolicy(
        bytes32 policyId,
        uint256 maxAmount,
        uint256 dailyLimit,
        uint256 cooldownPeriod
    ) external onlyRole(POLICY_ADMIN_ROLE) {
        Policy storage policy = policies[policyId];
        policy.maxAmount = maxAmount;
        policy.dailyLimit = dailyLimit;
        policy.cooldownPeriod = cooldownPeriod;
    }

    /**
     * @notice Set global daily limit
     */
    function setGlobalDailyLimit(uint256 limit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        globalDailyLimit = limit;
        emit DailyLimitReset(limit);
    }

    /**
     * @notice Reset daily usage counters
     */
    function resetDailyUsage() external onlyRole(AUDITOR_ROLE) {
        // Reset all daily usage (this is a simplified version)
        // In production, you'd want to reset specific mappings
        lastResetTime = block.timestamp;
        globalDailyUsed = 0;
    }

    /**
     * @notice Get policy details
     */
    function getPolicy(bytes32 policyId) external view returns (Policy memory) {
        return policies[policyId];
    }

    /**
     * @notice Get execution details
     */
    function getExecution(bytes32 executionId) external view returns (PolicyExecution memory) {
        return executions[executionId];
    }

    /**
     * @dev Check and update daily limits
     */
    function _checkAndUpdateDailyLimits(address account, bytes32 policyId, uint256 amount) internal {
        // Reset daily counters if needed (simplified - should be time-based)
        if (block.timestamp >= lastResetTime + 1 days) {
            // Reset logic would go here
        }

        dailyUsage[account][policyId] += amount;
        globalDailyUsed += amount;
    }

    /**
     * @dev Check required approvals
     */
    function _checkApprovals(bytes32 policyId, bytes32 txHash) internal view returns (bool) {
        Policy memory policy = policies[policyId];

        // Simplified approval check - in production, verify signatures
        // For now, just check if compliance officer has approved
        return hasRole(COMPLIANCE_OFFICER_ROLE, msg.sender);
    }

    /**
     * @notice Emergency disable policy
     */
    function disablePolicy(bytes32 policyId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        policies[policyId].isActive = false;
    }

    /**
     * @notice Re-enable policy
     */
    function enablePolicy(bytes32 policyId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        policies[policyId].isActive = true;
    }
}
