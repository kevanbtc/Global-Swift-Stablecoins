// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title OperationalProtocols
 * @notice Operational protocols and procedures for system operation
 * @dev Defines operational standards, protocols, and procedures for daily operations
 */
contract OperationalProtocols is Ownable, ReentrancyGuard {

    enum ProtocolType {
        SECURITY_PROTOCOL,
        COMPLIANCE_PROTOCOL,
        MAINTENANCE_PROTOCOL,
        EMERGENCY_PROTOCOL,
        UPGRADE_PROTOCOL,
        AUDIT_PROTOCOL,
        MONITORING_PROTOCOL,
        RECOVERY_PROTOCOL,
        GOVERNANCE_PROTOCOL,
        REPORTING_PROTOCOL
    }

    enum ProtocolStatus {
        DRAFT,
        UNDER_REVIEW,
        APPROVED,
        ACTIVE,
        SUSPENDED,
        DEPRECATED,
        ARCHIVED
    }

    enum SeverityLevel {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL,
        EMERGENCY
    }

    enum ProtocolExecutionStatus {
        NOT_STARTED,
        INITIALIZING,
        EXECUTING,
        MONITORING,
        COMPLETED,
        FAILED,
        ROLLED_BACK,
        CANCELLED
    }

    struct OperationalProtocol {
        bytes32 protocolId;
        ProtocolType protocolType;
        string name;
        string description;
        string version;
        ProtocolStatus status;
        SeverityLevel severityLevel;
        address author;
        uint256 createdAt;
        uint256 lastUpdated;
        uint256 executionCount;
        uint256 successRate; // in basis points
        bytes32[] requiredProcedures;
        mapping(bytes32 => ProtocolStep) steps;
        bytes32[] stepSequence;
        mapping(SeverityLevel => bytes32[]) escalationPaths;
        uint256 maxExecutionTime; // seconds
        bool requiresApproval;
        uint256 minApprovals;
    }

    struct ProtocolStep {
        bytes32 stepId;
        string name;
        string description;
        string instructions;
        address responsibleRole;
        uint256 estimatedDuration; // seconds
        uint256 timeout; // seconds
        bool isCritical;
        bytes32[] dependencies;
        bytes32[] inputs;
        bytes32[] outputs;
        string verificationCriteria;
        ProtocolExecutionStatus status;
        uint256 startedAt;
        uint256 completedAt;
        bytes32 evidenceHash;
        string executionNotes;
    }

    struct ProtocolExecution {
        bytes32 executionId;
        bytes32 protocolId;
        address initiator;
        SeverityLevel triggerSeverity;
        uint256 startedAt;
        uint256 completedAt;
        ProtocolExecutionStatus status;
        bytes32[] completedSteps;
        mapping(bytes32 => bytes32) stepEvidence;
        mapping(address => bool) approvals;
        uint256 approvalCount;
        string executionSummary;
        uint256 totalDuration;
        bool incidentReported;
        bytes32 incidentReportId;
    }

    struct EscalationRule {
        bytes32 ruleId;
        SeverityLevel triggerLevel;
        uint256 timeoutThreshold; // seconds
        address[] escalationContacts;
        string escalationMessage;
        bool autoEscalate;
        uint256 escalationDelay; // seconds
    }

    // Storage
    mapping(bytes32 => OperationalProtocol) public protocols;
    mapping(bytes32 => ProtocolExecution) public executions;
    mapping(ProtocolType => bytes32[]) public protocolsByType;
    mapping(address => bytes32[]) public protocolsByAuthor;
    mapping(SeverityLevel => EscalationRule) public escalationRules;

    // Global statistics
    uint256 public totalProtocols;
    uint256 public totalExecutions;
    uint256 public overallSuccessRate; // in basis points
    uint256 public averageExecutionTime; // seconds

    // Protocol parameters
    uint256 public defaultMaxExecutionTime = 3600; // 1 hour
    uint256 public defaultMinApprovals = 2;
    uint256 public escalationCheckInterval = 300; // 5 minutes

    // Events
    event ProtocolCreated(bytes32 indexed protocolId, ProtocolType protocolType, string name);
    event ProtocolExecuted(bytes32 indexed executionId, bytes32 indexed protocolId, SeverityLevel severity);
    event StepCompleted(bytes32 indexed executionId, bytes32 indexed stepId, address completedBy);
    event ProtocolEscalated(bytes32 indexed executionId, SeverityLevel newSeverity);
    event IncidentReported(bytes32 indexed executionId, bytes32 indexed incidentId);

    modifier validProtocol(bytes32 _protocolId) {
        require(protocols[_protocolId].author != address(0), "Protocol not found");
        _;
    }

    modifier activeProtocol(bytes32 _protocolId) {
        require(protocols[_protocolId].status == ProtocolStatus.ACTIVE, "Protocol not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new operational protocol
     */
    function createProtocol(
        ProtocolType _protocolType,
        string memory _name,
        string memory _description,
        string memory _version,
        SeverityLevel _severityLevel,
        bytes32[] memory _stepIds,
        string[] memory _stepNames,
        string[] memory _stepDescriptions,
        address[] memory _responsibleRoles,
        uint256[] memory _estimatedDurations,
        bool[] memory _isCritical
    ) public returns (bytes32) {
        require(_stepIds.length == _stepNames.length, "Array length mismatch");
        require(_stepNames.length == _stepDescriptions.length, "Array length mismatch");
        require(_stepDescriptions.length == _responsibleRoles.length, "Array length mismatch");
        require(_responsibleRoles.length == _estimatedDurations.length, "Array length mismatch");
        require(_estimatedDurations.length == _isCritical.length, "Array length mismatch");

        bytes32 protocolId = keccak256(abi.encodePacked(
            _protocolType,
            _name,
            _version,
            msg.sender,
            block.timestamp
        ));

        OperationalProtocol storage protocol = protocols[protocolId];
        protocol.protocolId = protocolId;
        protocol.protocolType = _protocolType;
        protocol.name = _name;
        protocol.description = _description;
        protocol.version = _version;
        protocol.status = ProtocolStatus.DRAFT;
        protocol.severityLevel = _severityLevel;
        protocol.author = msg.sender;
        protocol.createdAt = block.timestamp;
        protocol.lastUpdated = block.timestamp;
        protocol.maxExecutionTime = defaultMaxExecutionTime;
        protocol.requiresApproval = _severityLevel >= SeverityLevel.HIGH;
        protocol.minApprovals = defaultMinApprovals;

        // Create protocol steps
        for (uint256 i = 0; i < _stepIds.length; i++) {
            bytes32 stepId = _stepIds[i];
            protocol.stepSequence.push(stepId);

            ProtocolStep storage step = protocol.steps[stepId];
            step.stepId = stepId;
            step.name = _stepNames[i];
            step.description = _stepDescriptions[i];
            step.responsibleRole = _responsibleRoles[i];
            step.estimatedDuration = _estimatedDurations[i];
            step.timeout = _estimatedDurations[i] * 2; // 2x estimated time
            step.isCritical = _isCritical[i];
            step.status = ProtocolExecutionStatus.NOT_STARTED;
        }

        protocolsByType[_protocolType].push(protocolId);
        protocolsByAuthor[msg.sender].push(protocolId);
        totalProtocols++;

        emit ProtocolCreated(protocolId, _protocolType, _name);
        return protocolId;
    }

    /**
     * @notice Update protocol status
     */
    function updateProtocolStatus(bytes32 _protocolId, ProtocolStatus _status) public validProtocol(_protocolId)
    {
        OperationalProtocol storage protocol = protocols[_protocolId];
        require(protocol.author == msg.sender || msg.sender == owner(), "Not authorized");

        protocol.status = _status;
        protocol.lastUpdated = block.timestamp;
    }

    /**
     * @notice Execute operational protocol
     */
    function executeProtocol(
        bytes32 _protocolId,
        SeverityLevel _triggerSeverity,
        string memory _executionReason
    ) public validProtocol(_protocolId) activeProtocol(_protocolId) returns (bytes32) {
        bytes32 executionId = keccak256(abi.encodePacked(
            _protocolId,
            msg.sender,
            _triggerSeverity,
            block.timestamp
        ));

        ProtocolExecution storage execution = executions[executionId];
        execution.executionId = executionId;
        execution.protocolId = _protocolId;
        execution.initiator = msg.sender;
        execution.triggerSeverity = _triggerSeverity;
        execution.startedAt = block.timestamp;
        execution.status = ProtocolExecutionStatus.INITIALIZING;
        execution.executionSummary = _executionReason;

        totalExecutions++;

        emit ProtocolExecuted(executionId, _protocolId, _triggerSeverity);
        return executionId;
    }

    /**
     * @notice Execute protocol step
     */
    function executeStep(
        bytes32 _executionId,
        bytes32 _stepId,
        bytes32 _evidenceHash,
        string memory _executionNotes
    ) public {
        ProtocolExecution storage execution = executions[_executionId];
        require(execution.initiator == msg.sender, "Not execution initiator");
        require(execution.status != ProtocolExecutionStatus.COMPLETED, "Execution completed");

        OperationalProtocol storage protocol = protocols[execution.protocolId];
        ProtocolStep storage step = protocol.steps[_stepId];
        require(step.status == ProtocolExecutionStatus.NOT_STARTED ||
                step.status == ProtocolExecutionStatus.INITIALIZING, "Step not executable");

        step.status = ProtocolExecutionStatus.EXECUTING;
        step.startedAt = block.timestamp;
        step.evidenceHash = _evidenceHash;
        step.executionNotes = _executionNotes;

        execution.stepEvidence[_stepId] = _evidenceHash;
    }

    /**
     * @notice Complete protocol step
     */
    function completeStep(bytes32 _executionId, bytes32 _stepId) public {
        ProtocolExecution storage execution = executions[_executionId];
        OperationalProtocol storage protocol = protocols[execution.protocolId];
        ProtocolStep storage step = protocol.steps[_stepId];

        require(step.status == ProtocolExecutionStatus.EXECUTING, "Step not executing");

        step.status = ProtocolExecutionStatus.COMPLETED;
        step.completedAt = block.timestamp;

        execution.completedSteps.push(_stepId);

        // Check if all steps completed
        if (execution.completedSteps.length == protocol.stepSequence.length) {
            execution.status = ProtocolExecutionStatus.COMPLETED;
            execution.completedAt = block.timestamp;
            execution.totalDuration = execution.completedAt - execution.startedAt;

            protocol.executionCount++;
            _updateProtocolMetrics(protocol.protocolType, true, execution.totalDuration);
        }

        emit StepCompleted(_executionId, _stepId, msg.sender);
    }

    /**
     * @notice Approve protocol execution
     */
    function approveExecution(bytes32 _executionId) public {
        ProtocolExecution storage execution = executions[_executionId];
        OperationalProtocol storage protocol = protocols[execution.protocolId];

        require(protocol.requiresApproval, "Approval not required");
        require(!execution.approvals[msg.sender], "Already approved");

        execution.approvals[msg.sender] = true;
        execution.approvalCount++;
    }

    /**
     * @notice Escalate protocol execution
     */
    function escalateExecution(bytes32 _executionId, SeverityLevel _newSeverity) public {
        ProtocolExecution storage execution = executions[_executionId];
        require(_newSeverity > execution.triggerSeverity, "Cannot de-escalate");

        execution.triggerSeverity = _newSeverity;

        emit ProtocolEscalated(_executionId, _newSeverity);
    }

    /**
     * @notice Report incident from protocol execution
     */
    function reportIncident(bytes32 _executionId, string memory _incidentDetails) public returns (bytes32) {
        ProtocolExecution storage execution = executions[_executionId];
        require(!execution.incidentReported, "Incident already reported");

        bytes32 incidentId = keccak256(abi.encodePacked(
            _executionId,
            _incidentDetails,
            block.timestamp
        ));

        execution.incidentReported = true;
        execution.incidentReportId = incidentId;

        emit IncidentReported(_executionId, incidentId);
        return incidentId;
    }

    /**
     * @notice Set escalation rule
     */
    function setEscalationRule(
        SeverityLevel _triggerLevel,
        uint256 _timeoutThreshold,
        address[] memory _escalationContacts,
        string memory _escalationMessage,
        bool _autoEscalate,
        uint256 _escalationDelay
    ) public onlyOwner {
        bytes32 ruleId = keccak256(abi.encodePacked(
            _triggerLevel,
            _timeoutThreshold,
            block.timestamp
        ));

        EscalationRule storage rule = escalationRules[_triggerLevel];
        rule.ruleId = ruleId;
        rule.triggerLevel = _triggerLevel;
        rule.timeoutThreshold = _timeoutThreshold;
        rule.escalationContacts = _escalationContacts;
        rule.escalationMessage = _escalationMessage;
        rule.autoEscalate = _autoEscalate;
        rule.escalationDelay = _escalationDelay;
    }

    /**
     * @notice Get protocol details
     */
    function getProtocol(bytes32 _protocolId) public view
        returns (
            ProtocolType protocolType,
            string memory name,
            SeverityLevel severityLevel,
            ProtocolStatus status,
            uint256 stepCount,
            uint256 executionCount,
            uint256 successRate
        )
    {
        OperationalProtocol storage protocol = protocols[_protocolId];
        return (
            protocol.protocolType,
            protocol.name,
            protocol.severityLevel,
            protocol.status,
            protocol.stepSequence.length,
            protocol.executionCount,
            protocol.successRate
        );
    }

    /**
     * @notice Get protocol step details
     */
    function getProtocolStep(bytes32 _protocolId, bytes32 _stepId) public view
        returns (
            string memory name,
            string memory description,
            address responsibleRole,
            ProtocolExecutionStatus status,
            bool isCritical,
            uint256 startedAt,
            uint256 completedAt
        )
    {
        ProtocolStep memory step = protocols[_protocolId].steps[_stepId];
        return (
            step.name,
            step.description,
            step.responsibleRole,
            step.status,
            step.isCritical,
            step.startedAt,
            step.completedAt
        );
    }

    /**
     * @notice Get execution details
     */
    function getExecution(bytes32 _executionId) public view
        returns (
            bytes32 protocolId,
            SeverityLevel triggerSeverity,
            ProtocolExecutionStatus status,
            uint256 startedAt,
            uint256 completedAt,
            uint256 totalDuration,
            uint256 completedStepsCount
        )
    {
        ProtocolExecution storage execution = executions[_executionId];
        return (
            execution.protocolId,
            execution.triggerSeverity,
            execution.status,
            execution.startedAt,
            execution.completedAt,
            execution.totalDuration,
            execution.completedSteps.length
        );
    }

    /**
     * @notice Get escalation rule
     */
    function getEscalationRule(SeverityLevel _level) public view
        returns (
            uint256 timeoutThreshold,
            address[] memory escalationContacts,
            string memory escalationMessage,
            bool autoEscalate,
            uint256 escalationDelay
        )
    {
        EscalationRule memory rule = escalationRules[_level];
        return (
            rule.timeoutThreshold,
            rule.escalationContacts,
            rule.escalationMessage,
            rule.autoEscalate,
            rule.escalationDelay
        );
    }

    /**
     * @notice Get protocols by type
     */
    function getProtocolsByType(ProtocolType _type) public view
        returns (bytes32[] memory)
    {
        return protocolsByType[_type];
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _defaultMaxExecutionTime,
        uint256 _defaultMinApprovals,
        uint256 _escalationCheckInterval
    ) public onlyOwner {
        defaultMaxExecutionTime = _defaultMaxExecutionTime;
        defaultMinApprovals = _defaultMinApprovals;
        escalationCheckInterval = _escalationCheckInterval;
    }

    /**
     * @notice Get global operational statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalProtocols,
            uint256 _totalExecutions,
            uint256 _overallSuccessRate,
            uint256 _averageExecutionTime
        )
    {
        return (totalProtocols, totalExecutions, overallSuccessRate, averageExecutionTime);
    }

    // Internal functions
    function _updateProtocolMetrics(ProtocolType _type, bool _success, uint256 _duration) internal {
        // Simplified metrics update - in production would track per-protocol metrics
        if (_success) {
            overallSuccessRate = (overallSuccessRate + 10000) / 2; // Simplified
        }

        averageExecutionTime = (averageExecutionTime + _duration) / 2;
    }
}
