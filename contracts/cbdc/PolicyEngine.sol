// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title PolicyEngine
 * @notice Programmable money policy engine for CBDC
 * @dev Implements rules and conditions for programmable money features
 */
contract PolicyEngine is AccessControl, Pausable {
    bytes32 public constant POLICY_ADMIN_ROLE = keccak256("POLICY_ADMIN_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    enum PolicyType {
        Timelock,       // Time-based restrictions
        Geographic,     // Geographic restrictions
        Purpose,        // Purpose-based restrictions
        Flow,          // Flow control restrictions
        Conditional,    // Conditional execution
        Composite      // Combination of policies
    }

    enum ConditionOperator {
        Equals,
        NotEquals,
        GreaterThan,
        LessThan,
        Contains,
        NotContains
    }

    struct Policy {
        bytes32 policyId;
        PolicyType policyType;
        bytes32[] conditions;
        bytes32[] actions;
        bool active;
        uint256 startTime;
        uint256 endTime;
        address creator;
    }

    struct Condition {
        bytes32 conditionId;
        string parameter;
        ConditionOperator operator;
        bytes value;
        bool negate;
    }

    struct Action {
        bytes32 actionId;
        string actionType;
        bytes parameters;
        bool executed;
        bool success;
    }

    struct PolicyExecution {
        bytes32 executionId;
        bytes32 policyId;
        address initiator;
        uint256 timestamp;
        bool completed;
        bool success;
        string result;
    }

    // State variables
    mapping(bytes32 => Policy) public policies;
    mapping(bytes32 => Condition) public conditions;
    mapping(bytes32 => Action) public actions;
    mapping(bytes32 => PolicyExecution) public executions;
    mapping(address => bytes32[]) public addressPolicies;
    
    // Events
    event PolicyCreated(
        bytes32 indexed policyId,
        PolicyType policyType,
        address indexed creator
    );

    event PolicyUpdated(
        bytes32 indexed policyId,
        bool active
    );

    event ConditionCreated(
        bytes32 indexed conditionId,
        string parameter,
        ConditionOperator operator
    );

    event ActionCreated(
        bytes32 indexed actionId,
        string actionType
    );

    event PolicyExecuted(
        bytes32 indexed executionId,
        bytes32 indexed policyId,
        bool success
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POLICY_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
    }

    /**
     * @notice Create a new policy
     * @param policyType Type of policy
     * @param conditions Array of condition IDs
     * @param actions Array of action IDs
     * @param startTime Policy start time
     * @param endTime Policy end time
     */
    function createPolicy(
        PolicyType policyType,
        bytes32[] calldata conditions,
        bytes32[] calldata actions,
        uint256 startTime,
        uint256 endTime
    )
        external
        onlyRole(POLICY_ADMIN_ROLE)
        whenNotPaused
        returns (bytes32)
    {
        require(conditions.length > 0, "No conditions");
        require(actions.length > 0, "No actions");
        require(endTime > startTime, "Invalid time range");
        
        bytes32 policyId = keccak256(abi.encodePacked(
            policyType,
            conditions,
            actions,
            startTime,
            endTime,
            msg.sender,
            block.timestamp
        ));
        
        policies[policyId] = Policy({
            policyId: policyId,
            policyType: policyType,
            conditions: conditions,
            actions: actions,
            active: true,
            startTime: startTime,
            endTime: endTime,
            creator: msg.sender
        });
        
        addressPolicies[msg.sender].push(policyId);
        
        emit PolicyCreated(policyId, policyType, msg.sender);
        
        return policyId;
    }

    /**
     * @notice Create a new condition
     * @param parameter Condition parameter
     * @param operator Condition operator
     * @param value Condition value
     * @param negate Whether to negate the condition
     */
    function createCondition(
        string calldata parameter,
        ConditionOperator operator,
        bytes calldata value,
        bool negate
    )
        external
        onlyRole(POLICY_ADMIN_ROLE)
        whenNotPaused
        returns (bytes32)
    {
        bytes32 conditionId = keccak256(abi.encodePacked(
            parameter,
            operator,
            value,
            negate,
            block.timestamp
        ));
        
        conditions[conditionId] = Condition({
            conditionId: conditionId,
            parameter: parameter,
            operator: operator,
            value: value,
            negate: negate
        });
        
        emit ConditionCreated(conditionId, parameter, operator);
        
        return conditionId;
    }

    /**
     * @notice Create a new action
     * @param actionType Type of action
     * @param parameters Action parameters
     */
    function createAction(
        string calldata actionType,
        bytes calldata parameters
    )
        external
        onlyRole(POLICY_ADMIN_ROLE)
        whenNotPaused
        returns (bytes32)
    {
        bytes32 actionId = keccak256(abi.encodePacked(
            actionType,
            parameters,
            block.timestamp
        ));
        
        actions[actionId] = Action({
            actionId: actionId,
            actionType: actionType,
            parameters: parameters,
            executed: false,
            success: false
        });
        
        emit ActionCreated(actionId, actionType);
        
        return actionId;
    }

    /**
     * @notice Execute a policy
     * @param policyId Policy identifier
     * @param context Execution context
     */
    function executePolicy(bytes32 policyId, bytes calldata context)
        external
        onlyRole(EXECUTOR_ROLE)
        whenNotPaused
        returns (bytes32)
    {
        Policy storage policy = policies[policyId];
        require(policy.active, "Policy not active");
        require(
            block.timestamp >= policy.startTime &&
            block.timestamp <= policy.endTime,
            "Policy not in effect"
        );
        
        bytes32 executionId = keccak256(abi.encodePacked(
            policyId,
            msg.sender,
            block.timestamp,
            context
        ));
        
        PolicyExecution storage execution = executions[executionId];
        execution.executionId = executionId;
        execution.policyId = policyId;
        execution.initiator = msg.sender;
        execution.timestamp = block.timestamp;
        
        bool success = evaluateConditions(policy.conditions, context);
        
        if (success) {
            success = executeActions(policy.actions, context);
        }
        
        execution.completed = true;
        execution.success = success;
        execution.result = success ? "Success" : "Failed";
        
        emit PolicyExecuted(executionId, policyId, success);
        
        return executionId;
    }

    /**
     * @notice Evaluate policy conditions
     * @param conditionIds Condition identifiers
     * @param context Execution context
     */
    function evaluateConditions(bytes32[] storage conditionIds, bytes calldata context)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < conditionIds.length; i++) {
            Condition storage condition = conditions[conditionIds[i]];
            
            bool result = evaluateCondition(
                condition.parameter,
                condition.operator,
                condition.value,
                context
            );
            
            if (condition.negate) {
                result = !result;
            }
            
            if (!result) {
                return false;
            }
        }
        
        return true;
    }

    /**
     * @notice Evaluate a single condition
     * @param parameter Condition parameter
     * @param operator Condition operator
     * @param value Condition value
     * @param context Execution context
     */
    function evaluateCondition(
        string memory parameter,
        ConditionOperator operator,
        bytes memory value,
        bytes calldata context
    )
        internal
        pure
        returns (bool)
    {
        // This is a simplified implementation
        // In practice, this would handle different parameter types
        // and complex condition evaluation
        bytes32 paramValue = keccak256(abi.encodePacked(parameter, context));
        bytes32 compareValue = keccak256(value);
        
        if (operator == ConditionOperator.Equals) {
            return paramValue == compareValue;
        } else if (operator == ConditionOperator.NotEquals) {
            return paramValue != compareValue;
        } else if (operator == ConditionOperator.GreaterThan) {
            return uint256(paramValue) > uint256(compareValue);
        } else if (operator == ConditionOperator.LessThan) {
            return uint256(paramValue) < uint256(compareValue);
        }
        
        return false;
    }

    /**
     * @notice Execute policy actions
     * @param actionIds Action identifiers
     * @param context Execution context
     */
    function executeActions(bytes32[] storage actionIds, bytes calldata context)
        internal
        returns (bool)
    {
        bool success = true;
        
        for (uint256 i = 0; i < actionIds.length; i++) {
            Action storage action = actions[actionIds[i]];
            
            (bool actionSuccess,) = executeAction(
                action.actionType,
                action.parameters,
                context
            );
            
            action.executed = true;
            action.success = actionSuccess;
            
            if (!actionSuccess) {
                success = false;
            }
        }
        
        return success;
    }

    /**
     * @notice Execute a single action
     * @param actionType Type of action
     * @param parameters Action parameters
     * @param context Execution context
     */
    function executeAction(
        string memory actionType,
        bytes memory parameters,
        bytes calldata context
    )
        internal
        returns (bool, bytes memory)
    {
        // This is a simplified implementation
        // In practice, this would handle different action types
        // and complex action execution
        
        // Example action execution:
        if (keccak256(bytes(actionType)) == keccak256(bytes("transfer"))) {
            // Handle transfer action
            return (true, "");
        } else if (keccak256(bytes(actionType)) == keccak256(bytes("freeze"))) {
            // Handle freeze action
            return (true, "");
        }
        
        return (false, "Unknown action type");
    }

    /**
     * @notice Update policy status
     * @param policyId Policy identifier
     * @param active New active status
     */
    function updatePolicy(bytes32 policyId, bool active)
        external
        onlyRole(POLICY_ADMIN_ROLE)
    {
        Policy storage policy = policies[policyId];
        require(policy.creator == msg.sender, "Not policy creator");
        
        policy.active = active;
        
        emit PolicyUpdated(policyId, active);
    }

    /**
     * @notice Get policy details
     * @param policyId Policy identifier
     */
    function getPolicy(bytes32 policyId)
        external
        view
        returns (
            PolicyType policyType,
            bytes32[] memory conditionIds,
            bytes32[] memory actionIds,
            bool active,
            uint256 startTime,
            uint256 endTime,
            address creator
        )
    {
        Policy storage policy = policies[policyId];
        require(policy.creator != address(0), "Policy not found");
        
        return (
            policy.policyType,
            policy.conditions,
            policy.actions,
            policy.active,
            policy.startTime,
            policy.endTime,
            policy.creator
        );
    }

    /**
     * @notice Get execution details
     * @param executionId Execution identifier
     */
    function getExecution(bytes32 executionId)
        external
        view
        returns (PolicyExecution memory)
    {
        PolicyExecution storage execution = executions[executionId];
        require(execution.timestamp > 0, "Execution not found");
        return execution;
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}