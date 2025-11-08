// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UnykornDNACore} from "./UnykornDNACore.sol";

/**
 * @title DNASequencer
 * @notice AI-driven DNA sequencer for Unykorn Layer 1 operations
 * @dev Sequences and executes DNA-based commands through AI agents
 */
contract DNASequencer is Ownable, ReentrancyGuard {

    enum SequenceType {
        DEPLOYMENT_SEQUENCE,
        UPGRADE_SEQUENCE,
        MAINTENANCE_SEQUENCE,
        EMERGENCY_SEQUENCE,
        GOVERNANCE_SEQUENCE,
        FINANCIAL_SEQUENCE,
        COMPLIANCE_SEQUENCE,
        SETTLEMENT_SEQUENCE
    }

    enum SequenceStatus {
        DRAFT,
        VALIDATING,
        APPROVED,
        EXECUTING,
        COMPLETED,
        FAILED,
        ROLLED_BACK
    }

    enum ExecutionMode {
        AUTOMATIC,      // Full AI automation
        SEMI_AUTOMATIC, // AI with human approval
        MANUAL,         // Human execution
        HYBRID          // AI planning, human execution
    }

    struct DNASequence {
        bytes32 sequenceId;
        SequenceType sequenceType;
        string name;
        string description;
        ExecutionMode executionMode;
        SequenceStatus status;
        address creator;
        uint256 createdAt;
        uint256 executedAt;
        bytes32[] geneSequence;     // Ordered list of genes to execute
        mapping(bytes32 => bytes) geneParameters; // Gene-specific parameters
        mapping(bytes32 => bool) geneExecuted;
        bytes32[] executedGenes;
        uint256 successCount;
        uint256 failureCount;
        bytes32 ipfsSequenceHash;
        string executionLog;
        mapping(address => bool) authorizedExecutors;
    }

    struct SequenceTemplate {
        bytes32 templateId;
        SequenceType sequenceType;
        string name;
        string description;
        bytes32[] defaultGeneSequence;
        ExecutionMode defaultMode;
        bool isActive;
        uint256 usageCount;
        uint256 successRate; // in basis points
    }

    struct AIExecutionContext {
        bytes32 contextId;
        bytes32 sequenceId;
        address aiAgent;
        bytes32 currentGene;
        uint256 stepNumber;
        bytes executionState;
        uint256 confidenceLevel; // 0-100
        string reasoning;
        bytes32[] alternativePaths;
        uint256 timestamp;
    }

    // Core components
    UnykornDNACore public dnaCore;

    // Sequence storage
    mapping(bytes32 => DNASequence) public sequences;
    mapping(bytes32 => SequenceTemplate) public templates;
    mapping(bytes32 => AIExecutionContext) public executionContexts;

    // Global statistics
    uint256 public totalSequences;
    uint256 public activeSequences;
    uint256 public completedSequences;
    uint256 public failedSequences;

    // AI Integration
    mapping(address => bool) public authorizedAIAgents;
    address public aiSwarmCoordinator;
    uint256 public aiExecutionCount;

    // Sequence parameters
    uint256 public maxSequenceLength = 50; // Maximum genes per sequence
    uint256 public maxExecutionTime = 3600; // 1 hour
    uint256 public minConfidenceLevel = 80; // Minimum AI confidence for auto-execution

    // Events
    event SequenceCreated(bytes32 indexed sequenceId, SequenceType sequenceType, string name);
    event SequenceExecuted(bytes32 indexed sequenceId, address executor, bool success);
    event GeneExecuted(bytes32 indexed sequenceId, bytes32 indexed geneId, bool success);
    event AIExecutionStarted(bytes32 indexed contextId, bytes32 indexed sequenceId, address aiAgent);
    event SequenceCompleted(bytes32 indexed sequenceId, uint256 successCount, uint256 failureCount);

    modifier onlyAIAgent() {
        require(authorizedAIAgents[msg.sender] || msg.sender == aiSwarmCoordinator, "Not authorized AI agent");
        _;
    }

    modifier validSequence(bytes32 _sequenceId) {
        require(sequences[_sequenceId].creator != address(0), "Sequence not found");
        _;
    }

    modifier sequenceActive(bytes32 _sequenceId) {
        require(sequences[_sequenceId].status == SequenceStatus.EXECUTING, "Sequence not active");
        _;
    }

    constructor(address _dnaCore) Ownable(msg.sender) {
        dnaCore = UnykornDNACore(_dnaCore);
    }

    /**
     * @notice Create a new DNA sequence
     */
    function createSequence(
        SequenceType _sequenceType,
        string memory _name,
        string memory _description,
        ExecutionMode _executionMode,
        bytes32[] memory _geneSequence,
        bytes[] memory _geneParameters
    ) public returns (bytes32) {
        require(_geneSequence.length <= maxSequenceLength, "Sequence too long");
        require(_geneSequence.length == _geneParameters.length, "Parameter array mismatch");

        bytes32 sequenceId = keccak256(abi.encodePacked(
            _sequenceType, _name, msg.sender, block.timestamp
        ));

        DNASequence storage sequence = sequences[sequenceId];
        sequence.sequenceId = sequenceId;
        sequence.sequenceType = _sequenceType;
        sequence.name = _name;
        sequence.description = _description;
        sequence.executionMode = _executionMode;
        sequence.status = SequenceStatus.DRAFT;
        sequence.creator = msg.sender;
        sequence.createdAt = block.timestamp;
        sequence.geneSequence = _geneSequence;

        // Set gene parameters
        for (uint256 i = 0; i < _geneSequence.length; i++) {
            sequence.geneParameters[_geneSequence[i]] = _geneParameters[i];
        }

        // Authorize creator as executor
        sequence.authorizedExecutors[msg.sender] = true;

        totalSequences++;

        emit SequenceCreated(sequenceId, _sequenceType, _name);
        return sequenceId;
    }

    /**
     * @notice Create sequence from template
     */
    function createSequenceFromTemplate(
        bytes32 _templateId,
        string memory _customName,
        ExecutionMode _executionMode
    ) public returns (bytes32) {
        SequenceTemplate memory template = templates[_templateId];
        require(template.isActive, "Template not active");

        bytes32 sequenceId = keccak256(abi.encodePacked(
            template.sequenceType, _customName, msg.sender, block.timestamp
        ));

        DNASequence storage sequence = sequences[sequenceId];
        sequence.sequenceId = sequenceId;
        sequence.sequenceType = template.sequenceType;
        sequence.name = _customName;
        sequence.description = template.description;
        sequence.executionMode = _executionMode;
        sequence.status = SequenceStatus.DRAFT;
        sequence.creator = msg.sender;
        sequence.createdAt = block.timestamp;
        sequence.geneSequence = template.defaultGeneSequence;

        sequence.authorizedExecutors[msg.sender] = true;

        totalSequences++;
        template.usageCount++;

        emit SequenceCreated(sequenceId, template.sequenceType, _customName);
        return sequenceId;
    }

    /**
     * @notice Create sequence template
     */
    function createTemplate(
        SequenceType _sequenceType,
        string memory _name,
        string memory _description,
        bytes32[] memory _defaultGeneSequence,
        ExecutionMode _defaultMode
    ) public onlyOwner returns (bytes32) {
        bytes32 templateId = keccak256(abi.encodePacked(
            _sequenceType, _name, block.timestamp
        ));

        SequenceTemplate storage template = templates[templateId];
        template.templateId = templateId;
        template.sequenceType = _sequenceType;
        template.name = _name;
        template.description = _description;
        template.defaultGeneSequence = _defaultGeneSequence;
        template.defaultMode = _defaultMode;
        template.isActive = true;

        return templateId;
    }

    /**
     * @notice Start sequence execution
     */
    function startExecution(bytes32 _sequenceId) public validSequence(_sequenceId)
    {
        DNASequence storage sequence = sequences[_sequenceId];
        require(sequence.authorizedExecutors[msg.sender], "Not authorized executor");
        require(sequence.status == SequenceStatus.APPROVED ||
                sequence.status == SequenceStatus.DRAFT, "Invalid status");

        sequence.status = SequenceStatus.EXECUTING;
        sequence.executedAt = block.timestamp;
        activeSequences++;

        emit SequenceExecuted(_sequenceId, msg.sender, true);
    }

    /**
     * @notice Execute gene in sequence (AI-driven)
     */
    function executeGene(
        bytes32 _sequenceId,
        bytes32 _geneId,
        bytes memory _executionData,
        string memory _executionLog
    ) public onlyAIAgent validSequence(_sequenceId) sequenceActive(_sequenceId) returns (bool) {
        DNASequence storage sequence = sequences[_sequenceId];

        // Check if gene is in sequence and not already executed
        bool geneInSequence = false;
        for (uint256 i = 0; i < sequence.geneSequence.length; i++) {
            if (sequence.geneSequence[i] == _geneId) {
                geneInSequence = true;
                break;
            }
        }
        require(geneInSequence, "Gene not in sequence");
        require(!sequence.geneExecuted[_geneId], "Gene already executed");

        // Mark gene as executed
        sequence.geneExecuted[_geneId] = true;
        sequence.executedGenes.push(_geneId);

        // Update execution log
        sequence.executionLog = string(abi.encodePacked(
            sequence.executionLog,
            "\n[", Strings.toString(block.timestamp), "] Gene ",
            Strings.toHexString(uint256(_geneId), 32),
            ": ", _executionLog
        ));

        // Check if sequence is complete
        if (sequence.executedGenes.length == sequence.geneSequence.length) {
            sequence.status = SequenceStatus.COMPLETED;
            activeSequences--;
            completedSequences++;

            emit SequenceCompleted(_sequenceId, sequence.successCount, sequence.failureCount);
        }

        emit GeneExecuted(_sequenceId, _geneId, true);
        return true;
    }

    /**
     * @notice AI-driven sequence execution with context
     */
    function executeWithAIContext(
        bytes32 _sequenceId,
        bytes32 _geneId,
        bytes memory _executionData,
        uint256 _confidenceLevel,
        string memory _reasoning,
        bytes32[] memory _alternativePaths
    ) public onlyAIAgent returns (bytes32) {
        // Create execution context
        bytes32 contextId = keccak256(abi.encodePacked(
            _sequenceId, _geneId, msg.sender, block.timestamp
        ));

        AIExecutionContext storage context = executionContexts[contextId];
        context.contextId = contextId;
        context.sequenceId = _sequenceId;
        context.aiAgent = msg.sender;
        context.currentGene = _geneId;
        context.executionState = _executionData;
        context.confidenceLevel = _confidenceLevel;
        context.reasoning = _reasoning;
        context.alternativePaths = _alternativePaths;
        context.timestamp = block.timestamp;

        // Determine step number
        DNASequence storage sequence = sequences[_sequenceId];
        for (uint256 i = 0; i < sequence.geneSequence.length; i++) {
            if (sequence.geneSequence[i] == _geneId) {
                context.stepNumber = i + 1;
                break;
            }
        }

        aiExecutionCount++;

        emit AIExecutionStarted(contextId, _sequenceId, msg.sender);

        // Auto-execute if confidence is high enough and mode allows
        if (_confidenceLevel >= minConfidenceLevel &&
            sequence.executionMode == ExecutionMode.AUTOMATIC) {
            executeGene(_sequenceId, _geneId, _executionData, _reasoning);
        }

        return contextId;
    }

    /**
     * @notice Approve sequence for execution
     */
    function approveSequence(bytes32 _sequenceId) public validSequence(_sequenceId) {
        DNASequence storage sequence = sequences[_sequenceId];
        require(sequence.status == SequenceStatus.VALIDATING, "Not in validation");

        sequence.status = SequenceStatus.APPROVED;
    }

    /**
     * @notice Fail sequence execution
     */
    function failSequence(bytes32 _sequenceId, string memory _reason) public onlyAIAgent
        validSequence(_sequenceId)
        sequenceActive(_sequenceId)
    {
        DNASequence storage sequence = sequences[_sequenceId];
        sequence.status = SequenceStatus.FAILED;
        sequence.executionLog = string(abi.encodePacked(
            sequence.executionLog,
            "\n[FAILED] ", _reason
        ));

        activeSequences--;
        failedSequences++;

        emit SequenceExecuted(_sequenceId, msg.sender, false);
    }

    /**
     * @notice Rollback sequence execution
     */
    function rollbackSequence(bytes32 _sequenceId, string memory _reason) public onlyOwner
        validSequence(_sequenceId)
    {
        DNASequence storage sequence = sequences[_sequenceId];
        require(sequence.status == SequenceStatus.EXECUTING ||
                sequence.status == SequenceStatus.FAILED, "Cannot rollback");

        sequence.status = SequenceStatus.ROLLED_BACK;
        sequence.executionLog = string(abi.encodePacked(
            sequence.executionLog,
            "\n[ROLLED BACK] ", _reason
        ));

        activeSequences--;
    }

    /**
     * @notice Authorize executor for sequence
     */
    function authorizeExecutor(bytes32 _sequenceId, address _executor, bool _authorized) public validSequence(_sequenceId)
    {
        DNASequence storage sequence = sequences[_sequenceId];
        require(sequence.creator == msg.sender || msg.sender == owner(), "Not authorized");

        sequence.authorizedExecutors[_executor] = _authorized;
    }

    /**
     * @notice Set AI swarm coordinator
     */
    function setAISwarmCoordinator(address _coordinator) public onlyOwner {
        aiSwarmCoordinator = _coordinator;
        authorizedAIAgents[_coordinator] = true;
    }

    /**
     * @notice Authorize AI agent
     */
    function authorizeAIAgent(address _agent, bool _authorized) public onlyOwner {
        authorizedAIAgents[_agent] = _authorized;
    }

    /**
     * @notice Update sequence parameters
     */
    function updateSequenceParameters(
        uint256 _maxSequenceLength,
        uint256 _maxExecutionTime,
        uint256 _minConfidenceLevel
    ) public onlyOwner {
        maxSequenceLength = _maxSequenceLength;
        maxExecutionTime = _maxExecutionTime;
        minConfidenceLevel = _minConfidenceLevel;
    }

    /**
     * @notice Get sequence details
     */
    function getSequence(bytes32 _sequenceId) public view
        returns (
            SequenceType sequenceType,
            string memory name,
            ExecutionMode executionMode,
            SequenceStatus status,
            uint256 geneCount,
            uint256 executedCount,
            uint256 successCount,
            uint256 failureCount
        )
    {
        DNASequence storage sequence = sequences[_sequenceId];
        return (
            sequence.sequenceType,
            sequence.name,
            sequence.executionMode,
            sequence.status,
            sequence.geneSequence.length,
            sequence.executedGenes.length,
            sequence.successCount,
            sequence.failureCount
        );
    }

    /**
     * @notice Get sequence gene sequence
     */
    function getSequenceGenes(bytes32 _sequenceId) public view
        returns (bytes32[] memory)
    {
        return sequences[_sequenceId].geneSequence;
    }

    /**
     * @notice Get sequence executed genes
     */
    function getExecutedGenes(bytes32 _sequenceId) public view
        returns (bytes32[] memory)
    {
        return sequences[_sequenceId].executedGenes;
    }

    /**
     * @notice Get AI execution context
     */
    function getExecutionContext(bytes32 _contextId) public view
        returns (
            bytes32 sequenceId,
            address aiAgent,
            bytes32 currentGene,
            uint256 stepNumber,
            uint256 confidenceLevel,
            string memory reasoning,
            uint256 timestamp
        )
    {
        AIExecutionContext memory context = executionContexts[_contextId];
        return (
            context.sequenceId,
            context.aiAgent,
            context.currentGene,
            context.stepNumber,
            context.confidenceLevel,
            context.reasoning,
            context.timestamp
        );
    }

    /**
     * @notice Get template details
     */
    function getTemplate(bytes32 _templateId) public view
        returns (
            SequenceType sequenceType,
            string memory name,
            ExecutionMode defaultMode,
            bool isActive,
            uint256 usageCount,
            uint256 successRate
        )
    {
        SequenceTemplate memory template = templates[_templateId];
        return (
            template.sequenceType,
            template.name,
            template.defaultMode,
            template.isActive,
            template.usageCount,
            template.successRate
        );
    }

    /**
     * @notice Get global sequencer statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalSequences,
            uint256 _activeSequences,
            uint256 _completedSequences,
            uint256 _failedSequences,
            uint256 _aiExecutionCount
        )
    {
        return (totalSequences, activeSequences, completedSequences, failedSequences, aiExecutionCount);
    }

    /**
     * @notice Check if gene is executed in sequence
     */
    function isGeneExecuted(bytes32 _sequenceId, bytes32 _geneId) public view
        returns (bool)
    {
        return sequences[_sequenceId].geneExecuted[_geneId];
    }

    /**
     * @notice Get sequence execution log
     */
    function getExecutionLog(bytes32 _sequenceId) public view
        returns (string memory)
    {
        return sequences[_sequenceId].executionLog;
    }
}

// Helper library for string conversion
library Strings {
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = bytes1(uint8(48 + uint256(value & 0xf)));
            if (uint8(buffer[i]) > 57) {
                buffer[i] = bytes1(uint8(buffer[i]) + 39);
            }
            value >>= 4;
        }
        require(value == 0, "HEX_LENGTH_INSUFFICIENT");
        return string(buffer);
    }
}
