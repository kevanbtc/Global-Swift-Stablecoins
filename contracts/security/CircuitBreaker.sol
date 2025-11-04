// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title CircuitBreaker
 * @notice Emergency circuit breaker for CBDC system protection
 * @dev Implements multi-level circuit breakers with automated and manual triggers
 */
contract CircuitBreaker is AccessControl, ReentrancyGuard {

    bytes32 public constant BREAKER_ADMIN_ROLE = keccak256("BREAKER_ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    enum CircuitState {
        Active,         // Normal operation
        Warning,        // Warning threshold reached
        Restricted,     // Some functions restricted
        Emergency,      // Emergency shutdown
        Recovering     // Recovering from emergency
    }

    enum TriggerType {
        Manual,        // Manual trigger by admin
        Automatic,     // Automatic trigger by metrics
        Consensus,     // Trigger by validator consensus
        External       // External oracle trigger
    }

    struct Circuit {
        bytes32 circuitId;
        string name;
        CircuitState state;
        uint256 warningThreshold;
        uint256 restrictedThreshold;
        uint256 emergencyThreshold;
        uint256 cooldownPeriod;
        uint256 lastStateChange;
        address[] validators;
        uint256 requiredConsensus;
        bool automated;
        mapping(address => bool) validatorVotes;
        uint256 voteCount;
    }

    struct Trigger {
        bytes32 triggerId;
        bytes32 circuitId;
        TriggerType triggerType;
        CircuitState targetState;
        uint256 timestamp;
        address initiator;
        string reason;
    }

    // State variables
    mapping(bytes32 => Circuit) public circuits;
    mapping(bytes32 => Trigger) public triggers;
    mapping(bytes32 => mapping(bytes32 => bool)) public functionRestrictions;
    mapping(bytes32 => uint256) public metricValues;
    
    // Events
    event CircuitCreated(
        bytes32 indexed circuitId,
        string name,
        uint256 warningThreshold,
        uint256 restrictedThreshold,
        uint256 emergencyThreshold
    );

    event CircuitStateChanged(
        bytes32 indexed circuitId,
        CircuitState oldState,
        CircuitState newState,
        TriggerType triggerType
    );

    event TriggerActivated(
        bytes32 indexed triggerId,
        bytes32 indexed circuitId,
        TriggerType triggerType,
        address initiator
    );

    event MetricUpdated(
        bytes32 indexed circuitId,
        uint256 oldValue,
        uint256 newValue
    );

    event ValidatorVoteSubmitted(
        bytes32 indexed circuitId,
        address indexed validator,
        CircuitState proposedState
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BREAKER_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Create a new circuit breaker
     * @param name Circuit name
     * @param warningThreshold Warning level threshold
     * @param restrictedThreshold Restricted level threshold
     * @param emergencyThreshold Emergency level threshold
     * @param cooldownPeriod Cooldown period between state changes
     * @param validators Array of validator addresses
     * @param requiredConsensus Number of validators required for consensus
     * @param automated Whether circuit is automated
     */
    function createCircuit(
        string calldata name,
        uint256 warningThreshold,
        uint256 restrictedThreshold,
        uint256 emergencyThreshold,
        uint256 cooldownPeriod,
        address[] calldata validators,
        uint256 requiredConsensus,
        bool automated
    )
        external
        onlyRole(BREAKER_ADMIN_ROLE)
        returns (bytes32)
    {
        require(bytes(name).length > 0, "Invalid name");
        require(
            warningThreshold < restrictedThreshold &&
            restrictedThreshold < emergencyThreshold,
            "Invalid thresholds"
        );
        require(cooldownPeriod > 0, "Invalid cooldown");
        require(
            validators.length >= requiredConsensus,
            "Invalid consensus config"
        );
        
        bytes32 circuitId = keccak256(abi.encodePacked(
            name,
            block.timestamp
        ));
        
        Circuit storage circuit = circuits[circuitId];
        circuit.circuitId = circuitId;
        circuit.name = name;
        circuit.state = CircuitState.Active;
        circuit.warningThreshold = warningThreshold;
        circuit.restrictedThreshold = restrictedThreshold;
        circuit.emergencyThreshold = emergencyThreshold;
        circuit.cooldownPeriod = cooldownPeriod;
        circuit.validators = validators;
        circuit.requiredConsensus = requiredConsensus;
        circuit.automated = automated;
        
        for (uint256 i = 0; i < validators.length; i++) {
            _grantRole(VALIDATOR_ROLE, validators[i]);
        }
        
        emit CircuitCreated(
            circuitId,
            name,
            warningThreshold,
            restrictedThreshold,
            emergencyThreshold
        );
        
        return circuitId;
    }

    /**
     * @notice Update metric value and check thresholds
     * @param circuitId Circuit identifier
     * @param value New metric value
     */
    function updateMetric(bytes32 circuitId, uint256 value)
        external
        onlyRole(ORACLE_ROLE)
        nonReentrant
    {
        Circuit storage circuit = circuits[circuitId];
        require(circuit.automated, "Not automated");
        
        uint256 oldValue = metricValues[circuitId];
        metricValues[circuitId] = value;
        
        emit MetricUpdated(circuitId, oldValue, value);
        
        if (value >= circuit.emergencyThreshold) {
            _changeState(
                circuitId,
                CircuitState.Emergency,
                TriggerType.Automatic
            );
        } else if (value >= circuit.restrictedThreshold) {
            _changeState(
                circuitId,
                CircuitState.Restricted,
                TriggerType.Automatic
            );
        } else if (value >= circuit.warningThreshold) {
            _changeState(
                circuitId,
                CircuitState.Warning,
                TriggerType.Automatic
            );
        }
    }

    /**
     * @notice Submit validator vote for state change
     * @param circuitId Circuit identifier
     * @param proposedState Proposed new state
     */
    function submitValidatorVote(
        bytes32 circuitId,
        CircuitState proposedState
    )
        external
        onlyRole(VALIDATOR_ROLE)
    {
        Circuit storage circuit = circuits[circuitId];
        require(!circuit.validatorVotes[msg.sender], "Already voted");
        
        circuit.validatorVotes[msg.sender] = true;
        circuit.voteCount = circuit.voteCount.add(1);
        
        emit ValidatorVoteSubmitted(
            circuitId,
            msg.sender,
            proposedState
        );
        
        if (circuit.voteCount >= circuit.requiredConsensus) {
            _changeState(
                circuitId,
                proposedState,
                TriggerType.Consensus
            );
            _resetVotes(circuitId);
        }
    }

    /**
     * @notice Manually trigger circuit breaker
     * @param circuitId Circuit identifier
     * @param targetState Target state
     * @param reason Reason for trigger
     */
    function manualTrigger(
        bytes32 circuitId,
        CircuitState targetState,
        string calldata reason
    )
        external
        onlyRole(BREAKER_ADMIN_ROLE)
    {
        bytes32 triggerId = _createTrigger(
            circuitId,
            TriggerType.Manual,
            targetState,
            reason
        );
        
        _changeState(circuitId, targetState, TriggerType.Manual);
        
        emit TriggerActivated(
            triggerId,
            circuitId,
            TriggerType.Manual,
            msg.sender
        );
    }

    /**
     * @notice Create a trigger record
     * @param circuitId Circuit identifier
     * @param triggerType Type of trigger
     * @param targetState Target state
     * @param reason Reason for trigger
     */
    function _createTrigger(
        bytes32 circuitId,
        TriggerType triggerType,
        CircuitState targetState,
        string calldata reason
    )
        internal
        returns (bytes32)
    {
        bytes32 triggerId = keccak256(abi.encodePacked(
            circuitId,
            triggerType,
            targetState,
            block.timestamp
        ));
        
        triggers[triggerId] = Trigger({
            triggerId: triggerId,
            circuitId: circuitId,
            triggerType: triggerType,
            targetState: targetState,
            timestamp: block.timestamp,
            initiator: msg.sender,
            reason: reason
        });
        
        return triggerId;
    }

    /**
     * @notice Change circuit state
     * @param circuitId Circuit identifier
     * @param newState New state
     * @param triggerType Type of trigger
     */
    function _changeState(
        bytes32 circuitId,
        CircuitState newState,
        TriggerType triggerType
    )
        internal
    {
        Circuit storage circuit = circuits[circuitId];
        require(
            block.timestamp >= circuit.lastStateChange.add(circuit.cooldownPeriod),
            "Cooldown active"
        );
        
        CircuitState oldState = circuit.state;
        circuit.state = newState;
        circuit.lastStateChange = block.timestamp;
        
        emit CircuitStateChanged(
            circuitId,
            oldState,
            newState,
            triggerType
        );
    }

    /**
     * @notice Reset validator votes
     * @param circuitId Circuit identifier
     */
    function _resetVotes(bytes32 circuitId) internal {
        Circuit storage circuit = circuits[circuitId];
        circuit.voteCount = 0;
        
        for (uint256 i = 0; i < circuit.validators.length; i++) {
            circuit.validatorVotes[circuit.validators[i]] = false;
        }
    }

    /**
     * @notice Check if a function is restricted
     * @param circuitId Circuit identifier
     * @param functionId Function identifier
     */
    function isFunctionRestricted(bytes32 circuitId, bytes32 functionId)
        external
        view
        returns (bool)
    {
        Circuit storage circuit = circuits[circuitId];
        
        if (circuit.state == CircuitState.Emergency) {
            return true;
        }
        
        if (circuit.state == CircuitState.Restricted) {
            return functionRestrictions[circuitId][functionId];
        }
        
        return false;
    }

    /**
     * @notice Configure function restrictions
     * @param circuitId Circuit identifier
     * @param functionId Function identifier
     * @param restricted Whether function is restricted
     */
    function setFunctionRestriction(
        bytes32 circuitId,
        bytes32 functionId,
        bool restricted
    )
        external
        onlyRole(BREAKER_ADMIN_ROLE)
    {
        functionRestrictions[circuitId][functionId] = restricted;
    }

    /**
     * @notice Get circuit details
     * @param circuitId Circuit identifier
     */
    function getCircuit(bytes32 circuitId)
        external
        view
        returns (
            string memory name,
            CircuitState state,
            uint256 warningThreshold,
            uint256 restrictedThreshold,
            uint256 emergencyThreshold,
            uint256 cooldownPeriod,
            uint256 lastStateChange,
            bool automated
        )
    {
        Circuit storage circuit = circuits[circuitId];
        return (
            circuit.name,
            circuit.state,
            circuit.warningThreshold,
            circuit.restrictedThreshold,
            circuit.emergencyThreshold,
            circuit.cooldownPeriod,
            circuit.lastStateChange,
            circuit.automated
        );
    }
}
