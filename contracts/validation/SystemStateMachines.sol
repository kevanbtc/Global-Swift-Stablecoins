// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SystemStateMachines
 * @notice State machine validation for system accuracy and integrity
 * @dev Implements finite state machines for validating system operations
 */
contract SystemStateMachines is Ownable, ReentrancyGuard {

    enum StateMachineType {
        FINANCIAL_TRANSACTION,
        COMPLIANCE_CHECK,
        SETTLEMENT_PROCESS,
        GOVERNANCE_VOTE,
        CROSS_CHAIN_TRANSFER,
        IDENTITY_VERIFICATION,
        RISK_ASSESSMENT,
        AUDIT_TRAIL
    }

    enum State {
        INITIALIZED,
        VALIDATING,
        PROCESSING,
        VERIFIED,
        EXECUTED,
        FAILED,
        ROLLED_BACK,
        ARCHIVED
    }

    enum TransitionResult {
        SUCCESS,
        FAILURE,
        PENDING,
        BLOCKED,
        REQUIRES_APPROVAL
    }

    struct StateMachine {
        bytes32 machineId;
        StateMachineType machineType;
        State currentState;
        address initiator;
        uint256 createdAt;
        uint256 updatedAt;
        uint256 timeoutAt;
        bytes32[] stateHistory;
        mapping(bytes32 => bytes32) stateData; // key => value hash
        mapping(State => bytes32[]) allowedTransitions;
        bool isActive;
    }

    struct ValidationRule {
        bytes32 ruleId;
        StateMachineType machineType;
        State fromState;
        State toState;
        bytes32[] preconditions;
        bytes32[] postconditions;
        address validator;
        bool isActive;
    }

    struct StateTransition {
        bytes32 transitionId;
        bytes32 machineId;
        State fromState;
        State toState;
        address executor;
        uint256 timestamp;
        bytes32 evidenceHash;
        TransitionResult result;
        string failureReason;
    }

    // Storage
    mapping(bytes32 => StateMachine) public stateMachines;
    mapping(bytes32 => ValidationRule) public validationRules;
    mapping(bytes32 => StateTransition) public stateTransitions;
    mapping(StateMachineType => bytes32[]) public rulesByType;
    mapping(address => bytes32[]) public machinesByInitiator;

    // Global statistics
    uint256 public totalMachines;
    uint256 public totalRules;
    uint256 public totalTransitions;
    uint256 public successRate; // in basis points

    // Protocol parameters
    uint256 public defaultTimeout = 1 hours;
    uint256 public maxStateHistory = 50;
    uint256 public validationFee = 0.001 ether;

    // Events
    event StateMachineCreated(bytes32 indexed machineId, StateMachineType machineType, address initiator);
    event StateTransitionExecuted(bytes32 indexed machineId, State fromState, State toState, TransitionResult result);
    event ValidationRuleAdded(bytes32 indexed ruleId, StateMachineType machineType);
    event StateMachineTimeout(bytes32 indexed machineId);

    modifier validMachine(bytes32 _machineId) {
        require(stateMachines[_machineId].initiator != address(0), "Machine not found");
        _;
    }

    modifier activeMachine(bytes32 _machineId) {
        require(stateMachines[_machineId].isActive, "Machine not active");
        _;
    }

    modifier validRule(bytes32 _ruleId) {
        require(validationRules[_ruleId].isActive, "Rule not found or inactive");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new state machine
     */
    function createStateMachine(
        StateMachineType _machineType,
        bytes32[] memory _initialDataKeys,
        bytes32[] memory _initialDataValues
    ) external returns (bytes32) {
        require(_initialDataKeys.length == _initialDataValues.length, "Data array length mismatch");

        bytes32 machineId = keccak256(abi.encodePacked(
            _machineType,
            msg.sender,
            block.timestamp
        ));

        StateMachine storage machine = stateMachines[machineId];
        machine.machineId = machineId;
        machine.machineType = _machineType;
        machine.currentState = State.INITIALIZED;
        machine.initiator = msg.sender;
        machine.createdAt = block.timestamp;
        machine.updatedAt = block.timestamp;
        machine.timeoutAt = block.timestamp + defaultTimeout;
        machine.isActive = true;

        // Store initial data
        for (uint256 i = 0; i < _initialDataKeys.length; i++) {
            machine.stateData[_initialDataKeys[i]] = _initialDataValues[i];
        }

        // Initialize state history
        machine.stateHistory.push(bytes32(uint256(State.INITIALIZED)));

        machinesByInitiator[msg.sender].push(machineId);
        totalMachines++;

        emit StateMachineCreated(machineId, _machineType, msg.sender);
        return machineId;
    }

    /**
     * @notice Add a validation rule
     */
    function addValidationRule(
        StateMachineType _machineType,
        State _fromState,
        State _toState,
        bytes32[] memory _preconditions,
        bytes32[] memory _postconditions
    ) external onlyOwner returns (bytes32) {
        bytes32 ruleId = keccak256(abi.encodePacked(
            _machineType,
            _fromState,
            _toState,
            block.timestamp
        ));

        ValidationRule storage rule = validationRules[ruleId];
        rule.ruleId = ruleId;
        rule.machineType = _machineType;
        rule.fromState = _fromState;
        rule.toState = _toState;
        rule.preconditions = _preconditions;
        rule.postconditions = _postconditions;
        rule.validator = msg.sender;
        rule.isActive = true;

        rulesByType[_machineType].push(ruleId);
        totalRules++;

        emit ValidationRuleAdded(ruleId, _machineType);
        return ruleId;
    }

    /**
     * @notice Execute state transition
     */
    function executeTransition(
        bytes32 _machineId,
        State _toState,
        bytes32 _evidenceHash
    ) external payable validMachine(_machineId) activeMachine(_machineId) returns (TransitionResult) {
        StateMachine storage machine = stateMachines[_machineId];
        State fromState = machine.currentState;

        // Check timeout
        if (block.timestamp > machine.timeoutAt) {
            machine.isActive = false;
            emit StateMachineTimeout(_machineId);
            return TransitionResult.FAILURE;
        }

        // Check validation fee
        if (msg.value < validationFee) {
            return TransitionResult.BLOCKED;
        }

        // Validate transition
        TransitionResult result = _validateTransition(machine, _toState);

        bytes32 transitionId = keccak256(abi.encodePacked(
            _machineId,
            fromState,
            _toState,
            block.timestamp
        ));

        StateTransition storage transition = stateTransitions[transitionId];
        transition.transitionId = transitionId;
        transition.machineId = _machineId;
        transition.fromState = fromState;
        transition.toState = _toState;
        transition.executor = msg.sender;
        transition.timestamp = block.timestamp;
        transition.evidenceHash = _evidenceHash;
        transition.result = result;

        if (result == TransitionResult.SUCCESS) {
            machine.currentState = _toState;
            machine.updatedAt = block.timestamp;
            machine.timeoutAt = block.timestamp + defaultTimeout;

            // Update state history
            if (machine.stateHistory.length < maxStateHistory) {
                machine.stateHistory.push(bytes32(uint256(_toState)));
            }

            // Check if machine is complete
            if (_toState == State.EXECUTED || _toState == State.ARCHIVED) {
                machine.isActive = false;
            }

            totalTransitions++;
            _updateSuccessRate();
        } else {
            transition.failureReason = "Validation failed";
        }

        emit StateTransitionExecuted(_machineId, fromState, _toState, result);
        return result;
    }

    /**
     * @notice Force rollback state machine
     */
    function forceRollback(bytes32 _machineId, string memory _reason)
        external
        onlyOwner
        validMachine(_machineId)
        activeMachine(_machineId)
    {
        StateMachine storage machine = stateMachines[_machineId];
        machine.currentState = State.ROLLED_BACK;
        machine.isActive = false;

        emit StateTransitionExecuted(_machineId, machine.currentState, State.ROLLED_BACK, TransitionResult.FAILURE);
    }

    /**
     * @notice Update state machine data
     */
    function updateMachineData(bytes32 _machineId, bytes32 _key, bytes32 _value)
        external
        validMachine(_machineId)
        activeMachine(_machineId)
    {
        StateMachine storage machine = stateMachines[_machineId];
        require(machine.initiator == msg.sender || msg.sender == owner(), "Not authorized");

        machine.stateData[_key] = _value;
        machine.updatedAt = block.timestamp;
    }

    /**
     * @notice Get machine state history
     */
    function getMachineStateHistory(bytes32 _machineId)
        external
        view
        returns (bytes32[] memory)
    {
        return stateMachines[_machineId].stateHistory;
    }

    /**
     * @notice Get machine data
     */
    function getMachineData(bytes32 _machineId, bytes32 _key)
        external
        view
        returns (bytes32)
    {
        return stateMachines[_machineId].stateData[_key];
    }

    /**
     * @notice Get validation rules for machine type
     */
    function getValidationRules(StateMachineType _machineType)
        external
        view
        returns (bytes32[] memory)
    {
        return rulesByType[_machineType];
    }

    /**
     * @notice Get machine details
     */
    function getMachineDetails(bytes32 _machineId)
        external
        view
        returns (
            StateMachineType machineType,
            State currentState,
            address initiator,
            uint256 createdAt,
            uint256 updatedAt,
            bool isActive
        )
    {
        StateMachine memory machine = stateMachines[_machineId];
        return (
            machine.machineType,
            machine.currentState,
            machine.initiator,
            machine.createdAt,
            machine.updatedAt,
            machine.isActive
        );
    }

    /**
     * @notice Get transition details
     */
    function getTransitionDetails(bytes32 _transitionId)
        external
        view
        returns (
            bytes32 machineId,
            State fromState,
            State toState,
            address executor,
            uint256 timestamp,
            TransitionResult result
        )
    {
        StateTransition memory transition = stateTransitions[_transitionId];
        return (
            transition.machineId,
            transition.fromState,
            transition.toState,
            transition.executor,
            transition.timestamp,
            transition.result
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _defaultTimeout,
        uint256 _maxStateHistory,
        uint256 _validationFee
    ) external onlyOwner {
        defaultTimeout = _defaultTimeout;
        maxStateHistory = _maxStateHistory;
        validationFee = _validationFee;
    }

    /**
     * @notice Get global state machine statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalMachines,
            uint256 _totalRules,
            uint256 _totalTransitions,
            uint256 _successRate
        )
    {
        return (totalMachines, totalRules, totalTransitions, successRate);
    }

    // Internal functions
    function _validateTransition(StateMachine storage _machine, State _toState)
        internal
        view
        returns (TransitionResult)
    {
        // Get applicable rules
        bytes32[] memory rules = rulesByType[_machine.machineType];

        for (uint256 i = 0; i < rules.length; i++) {
            ValidationRule memory rule = validationRules[rules[i]];

            if (rule.fromState == _machine.currentState && rule.toState == _toState) {
                // Check preconditions (simplified - in production would validate each precondition)
                if (rule.preconditions.length > 0) {
                    // Validate preconditions
                    bool preconditionsMet = _checkPreconditions(_machine, rule.preconditions);
                    if (!preconditionsMet) {
                        return TransitionResult.BLOCKED;
                    }
                }

                return TransitionResult.SUCCESS;
            }
        }

        return TransitionResult.FAILURE;
    }

    function _checkPreconditions(StateMachine storage _machine, bytes32[] memory _preconditions)
        internal
        view
        returns (bool)
    {
        // Simplified precondition checking
        // In production, this would validate each precondition against machine state
        for (uint256 i = 0; i < _preconditions.length; i++) {
            bytes32 precondition = _preconditions[i];
            // Check if precondition data exists and is valid
            if (_machine.stateData[precondition] == bytes32(0)) {
                return false;
            }
        }
        return true;
    }

    function _updateSuccessRate() internal {
        if (totalTransitions > 0) {
            uint256 successfulTransitions = 0;
            // Simplified success rate calculation
            // In production, would track successful transitions properly
            successRate = 9500; // 95% success rate (placeholder)
        }
    }
}
