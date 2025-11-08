// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ImplementationProcedures
 * @notice Standardized procedures for system implementation and operation
 * @dev Defines operational procedures, checklists, and implementation protocols
 */
contract ImplementationProcedures is Ownable, ReentrancyGuard {

    enum ProcedureType {
        DEPLOYMENT,
        UPGRADE,
        MAINTENANCE,
        EMERGENCY,
        AUDIT,
        COMPLIANCE,
        TESTING,
        MONITORING,
        BACKUP,
        RECOVERY
    }

    enum ProcedureStatus {
        DRAFT,
        REVIEW,
        APPROVED,
        ACTIVE,
        DEPRECATED,
        ARCHIVED
    }

    enum ExecutionStatus {
        NOT_STARTED,
        IN_PROGRESS,
        COMPLETED,
        FAILED,
        ROLLED_BACK,
        CANCELLED
    }

    enum ChecklistItemStatus {
        PENDING,
        IN_PROGRESS,
        COMPLETED,
        SKIPPED,
        FAILED
    }

    struct Procedure {
        bytes32 procedureId;
        ProcedureType procedureType;
        string name;
        string description;
        string version;
        ProcedureStatus status;
        address author;
        uint256 createdAt;
        uint256 lastUpdated;
        bytes32[] checklistItems;
        mapping(bytes32 => ChecklistItem) items;
        uint256 executionCount;
        uint256 successRate; // in basis points
    }

    struct ChecklistItem {
        bytes32 itemId;
        string description;
        string instructions;
        ChecklistItemStatus status;
        address assignedTo;
        uint256 estimatedTime; // minutes
        uint256 actualTime;
        bytes32[] dependencies;
        bytes32[] prerequisites;
        bool isRequired;
        string evidence;
        uint256 completedAt;
    }

    struct ProcedureExecution {
        bytes32 executionId;
        bytes32 procedureId;
        address executor;
        uint256 startedAt;
        uint256 completedAt;
        ExecutionStatus status;
        bytes32[] completedItems;
        mapping(bytes32 => bytes32) itemEvidence;
        string notes;
        uint256 totalTime;
        bool requiresApproval;
        mapping(address => bool) approvals;
        uint256 approvalCount;
    }

    struct ProcedureMetrics {
        uint256 totalExecutions;
        uint256 successfulExecutions;
        uint256 averageCompletionTime;
        uint256 complianceRate; // percentage of required items completed
        uint256 errorRate;
        uint256 rollbackRate;
    }

    // Storage
    mapping(bytes32 => Procedure) public procedures;
    mapping(bytes32 => ProcedureExecution) public executions;
    mapping(ProcedureType => bytes32[]) public proceduresByType;
    mapping(address => bytes32[]) public proceduresByAuthor;
    mapping(ProcedureType => ProcedureMetrics) public procedureMetrics;

    // Global statistics
    uint256 public totalProcedures;
    uint256 public totalExecutions;
    uint256 public overallComplianceRate;

    // Protocol parameters
    uint256 public minApprovalCount = 2;
    uint256 public maxExecutionTime = 7 days;
    uint256 public evidenceRetentionPeriod = 365 days;

    // Events
    event ProcedureCreated(bytes32 indexed procedureId, ProcedureType procedureType, string name);
    event ProcedureExecuted(bytes32 indexed executionId, bytes32 indexed procedureId, address executor);
    event ChecklistItemCompleted(bytes32 indexed procedureId, bytes32 indexed itemId, address completedBy);
    event ProcedureApproved(bytes32 indexed executionId, address approver);

    modifier validProcedure(bytes32 _procedureId) {
        require(procedures[_procedureId].author != address(0), "Procedure not found");
        _;
    }

    modifier activeProcedure(bytes32 _procedureId) {
        require(procedures[_procedureId].status == ProcedureStatus.ACTIVE, "Procedure not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new procedure
     */
    function createProcedure(
        ProcedureType _procedureType,
        string memory _name,
        string memory _description,
        string memory _version,
        bytes32[] memory _checklistItemIds,
        string[] memory _itemDescriptions,
        string[] memory _itemInstructions,
        uint256[] memory _estimatedTimes,
        bool[] memory _isRequired
    ) public returns (bytes32) {
        require(_checklistItemIds.length == _itemDescriptions.length, "Array length mismatch");
        require(_itemDescriptions.length == _itemInstructions.length, "Array length mismatch");
        require(_itemInstructions.length == _estimatedTimes.length, "Array length mismatch");
        require(_estimatedTimes.length == _isRequired.length, "Array length mismatch");

        bytes32 procedureId = keccak256(abi.encodePacked(
            _procedureType,
            _name,
            _version,
            msg.sender,
            block.timestamp
        ));

        Procedure storage procedure = procedures[procedureId];
        procedure.procedureId = procedureId;
        procedure.procedureType = _procedureType;
        procedure.name = _name;
        procedure.description = _description;
        procedure.version = _version;
        procedure.status = ProcedureStatus.DRAFT;
        procedure.author = msg.sender;
        procedure.createdAt = block.timestamp;
        procedure.lastUpdated = block.timestamp;

        // Create checklist items
        for (uint256 i = 0; i < _checklistItemIds.length; i++) {
            bytes32 itemId = _checklistItemIds[i];
            procedure.checklistItems.push(itemId);

            ChecklistItem storage item = procedure.items[itemId];
            item.itemId = itemId;
            item.description = _itemDescriptions[i];
            item.instructions = _itemInstructions[i];
            item.status = ChecklistItemStatus.PENDING;
            item.estimatedTime = _estimatedTimes[i];
            item.isRequired = _isRequired[i];
        }

        proceduresByType[_procedureType].push(procedureId);
        proceduresByAuthor[msg.sender].push(procedureId);
        totalProcedures++;

        emit ProcedureCreated(procedureId, _procedureType, _name);
        return procedureId;
    }

    /**
     * @notice Update procedure status
     */
    function updateProcedureStatus(bytes32 _procedureId, ProcedureStatus _status) public validProcedure(_procedureId)
    {
        Procedure storage procedure = procedures[_procedureId];
        require(procedure.author == msg.sender || msg.sender == owner(), "Not authorized");

        procedure.status = _status;
        procedure.lastUpdated = block.timestamp;
    }

    /**
     * @notice Start procedure execution
     */
    function startExecution(bytes32 _procedureId, bool _requiresApproval) public validProcedure(_procedureId)
        activeProcedure(_procedureId)
        returns (bytes32)
    {
        bytes32 executionId = keccak256(abi.encodePacked(
            _procedureId,
            msg.sender,
            block.timestamp
        ));

        ProcedureExecution storage execution = executions[executionId];
        execution.executionId = executionId;
        execution.procedureId = _procedureId;
        execution.executor = msg.sender;
        execution.startedAt = block.timestamp;
        execution.status = ExecutionStatus.IN_PROGRESS;
        execution.requiresApproval = _requiresApproval;

        totalExecutions++;

        emit ProcedureExecuted(executionId, _procedureId, msg.sender);
        return executionId;
    }

    /**
     * @notice Complete checklist item
     */
    function completeChecklistItem(
        bytes32 _executionId,
        bytes32 _itemId,
        string memory _evidence,
        uint256 _actualTime
    ) public {
        ProcedureExecution storage execution = executions[_executionId];
        require(execution.executor == msg.sender, "Not executor");
        require(execution.status == ExecutionStatus.IN_PROGRESS, "Execution not in progress");

        Procedure storage procedure = procedures[execution.procedureId];
        ChecklistItem storage item = procedure.items[_itemId];
        require(item.status != ChecklistItemStatus.COMPLETED, "Item already completed");

        item.status = ChecklistItemStatus.COMPLETED;
        item.evidence = _evidence;
        item.actualTime = _actualTime;
        item.completedAt = block.timestamp;

        execution.completedItems.push(_itemId);
        execution.itemEvidence[_itemId] = keccak256(abi.encodePacked(_evidence));

        emit ChecklistItemCompleted(execution.procedureId, _itemId, msg.sender);
    }

    /**
     * @notice Approve procedure execution
     */
    function approveExecution(bytes32 _executionId) public {
        ProcedureExecution storage execution = executions[_executionId];
        require(execution.requiresApproval, "Approval not required");
        require(!execution.approvals[msg.sender], "Already approved");

        execution.approvals[msg.sender] = true;
        execution.approvalCount++;
    }

    /**
     * @notice Complete procedure execution
     */
    function completeExecution(bytes32 _executionId, string memory _notes) public {
        ProcedureExecution storage execution = executions[_executionId];
        require(execution.executor == msg.sender, "Not executor");
        require(execution.status == ExecutionStatus.IN_PROGRESS, "Execution not in progress");

        // Check approvals if required
        if (execution.requiresApproval && execution.approvalCount < minApprovalCount) {
            revert("Insufficient approvals");
        }

        Procedure storage procedure = procedures[execution.procedureId];

        // Check required items completion
        bool allRequiredCompleted = true;
        for (uint256 i = 0; i < procedure.checklistItems.length; i++) {
            ChecklistItem memory item = procedure.items[procedure.checklistItems[i]];
            if (item.isRequired && item.status != ChecklistItemStatus.COMPLETED) {
                allRequiredCompleted = false;
                break;
            }
        }

        execution.completedAt = block.timestamp;
        execution.totalTime = execution.completedAt - execution.startedAt;
        execution.notes = _notes;

        if (allRequiredCompleted) {
            execution.status = ExecutionStatus.COMPLETED;
            procedure.executionCount++;
            _updateProcedureMetrics(procedure.procedureType, true, execution.totalTime);
        } else {
            execution.status = ExecutionStatus.FAILED;
            _updateProcedureMetrics(procedure.procedureType, false, execution.totalTime);
        }
    }

    /**
     * @notice Rollback procedure execution
     */
    function rollbackExecution(bytes32 _executionId, string memory _reason) public {
        ProcedureExecution storage execution = executions[_executionId];
        require(execution.executor == msg.sender || msg.sender == owner(), "Not authorized");
        require(execution.status == ExecutionStatus.IN_PROGRESS, "Cannot rollback");

        execution.status = ExecutionStatus.ROLLED_BACK;
        execution.notes = string(abi.encodePacked("ROLLED BACK: ", _reason));

        Procedure storage procedure = procedures[execution.procedureId];
        _updateProcedureMetrics(procedure.procedureType, false, block.timestamp - execution.startedAt);
    }

    /**
     * @notice Get procedure details
     */
    function getProcedure(bytes32 _procedureId) public view
        returns (
            ProcedureType procedureType,
            string memory name,
            string memory description,
            ProcedureStatus status,
            uint256 checklistItemsCount,
            uint256 executionCount,
            uint256 successRate
        )
    {
        Procedure storage procedure = procedures[_procedureId];
        return (
            procedure.procedureType,
            procedure.name,
            procedure.description,
            procedure.status,
            procedure.checklistItems.length,
            procedure.executionCount,
            procedure.successRate
        );
    }

    /**
     * @notice Get checklist item details
     */
    function getChecklistItem(bytes32 _procedureId, bytes32 _itemId) public view
        returns (
            string memory description,
            string memory instructions,
            ChecklistItemStatus status,
            uint256 estimatedTime,
            uint256 actualTime,
            bool isRequired,
            string memory evidence
        )
    {
        ChecklistItem memory item = procedures[_procedureId].items[_itemId];
        return (
            item.description,
            item.instructions,
            item.status,
            item.estimatedTime,
            item.actualTime,
            item.isRequired,
            item.evidence
        );
    }

    /**
     * @notice Get execution details
     */
    function getExecution(bytes32 _executionId) public view
        returns (
            bytes32 procedureId,
            address executor,
            ExecutionStatus status,
            uint256 startedAt,
            uint256 completedAt,
            uint256 totalTime,
            uint256 completedItemsCount,
            bool requiresApproval,
            uint256 approvalCount
        )
    {
        ProcedureExecution storage execution = executions[_executionId];
        return (
            execution.procedureId,
            execution.executor,
            execution.status,
            execution.startedAt,
            execution.completedAt,
            execution.totalTime,
            execution.completedItems.length,
            execution.requiresApproval,
            execution.approvalCount
        );
    }

    /**
     * @notice Get procedure metrics
     */
    function getProcedureMetrics(ProcedureType _type) public view
        returns (
            uint256 totalExecutions,
            uint256 successfulExecutions,
            uint256 averageCompletionTime,
            uint256 complianceRate,
            uint256 errorRate
        )
    {
        ProcedureMetrics memory metrics = procedureMetrics[_type];
        return (
            metrics.totalExecutions,
            metrics.successfulExecutions,
            metrics.averageCompletionTime,
            metrics.complianceRate,
            metrics.errorRate
        );
    }

    /**
     * @notice Get procedures by type
     */
    function getProceduresByType(ProcedureType _type) public view
        returns (bytes32[] memory)
    {
        return proceduresByType[_type];
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _minApprovalCount,
        uint256 _maxExecutionTime,
        uint256 _evidenceRetentionPeriod
    ) public onlyOwner {
        minApprovalCount = _minApprovalCount;
        maxExecutionTime = _maxExecutionTime;
        evidenceRetentionPeriod = _evidenceRetentionPeriod;
    }

    /**
     * @notice Get global procedure statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalProcedures,
            uint256 _totalExecutions,
            uint256 _overallComplianceRate
        )
    {
        return (totalProcedures, totalExecutions, overallComplianceRate);
    }

    // Internal functions
    function _updateProcedureMetrics(ProcedureType _type, bool _success, uint256 _completionTime) internal {
        ProcedureMetrics storage metrics = procedureMetrics[_type];
        metrics.totalExecutions++;

        if (_success) {
            metrics.successfulExecutions++;
        }

        // Update average completion time
        metrics.averageCompletionTime = (metrics.averageCompletionTime + _completionTime) / 2;

        // Update compliance rate (simplified)
        metrics.complianceRate = (metrics.successfulExecutions * 10000) / metrics.totalExecutions;

        // Update error rate
        metrics.errorRate = ((metrics.totalExecutions - metrics.successfulExecutions) * 10000) / metrics.totalExecutions;

        // Update overall compliance rate
        overallComplianceRate = metrics.complianceRate;
    }
}
