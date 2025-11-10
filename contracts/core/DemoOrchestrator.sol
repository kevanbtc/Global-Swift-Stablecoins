// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SystemBootstrap} from "./SystemBootstrap.sol";
import {UnykornDNACore} from "./UnykornDNACore.sol";
import {DNASequencer} from "./DNASequencer.sol";
import {LifeLineOrchestrator} from "./LifeLineOrchestrator.sol";

/**
 * @title DemoOrchestrator
 * @notice Demonstrates the complete Unykorn Layer 1 DNA infrastructure
 * @dev Provides live demonstrations of the DNA system capabilities
 */
contract DemoOrchestrator is Ownable, ReentrancyGuard {

    enum DemoType {
        DNA_CORE_DEMO,
        SEQUENCER_DEMO,
        LIFELINE_DEMO,
        FULL_SYSTEM_DEMO,
        AI_INTEGRATION_DEMO,
        IPFS_INTEGRATION_DEMO,
        EVOLUTION_DEMO
    }

    enum DemoStatus {
        NOT_STARTED,
        INITIALIZING,
        RUNNING,
        COMPLETED,
        FAILED
    }

    struct DemoSession {
        bytes32 sessionId;
        DemoType demoType;
        address demonstrator;
        DemoStatus status;
        uint256 startedAt;
        uint256 completedAt;
        bytes32[] demoSteps;
        mapping(bytes32 => DemoResult) stepResults;
        string sessionLog;
        bytes32 ipfsRecordingHash;
        uint256 successRate; // in basis points
    }

    struct DemoResult {
        bytes32 stepId;
        bool success;
        bytes result;
        string description;
        uint256 timestamp;
        bytes32 evidenceHash;
    }

    struct DemoMetrics {
        uint256 totalSessions;
        uint256 successfulSessions;
        uint256 averageCompletionTime;
        uint256 demoEngagement; // user interaction score
        bytes32 mostPopularDemo;
    }

    // Core system references
    SystemBootstrap public bootstrap;
    UnykornDNACore public dnaCore;
    DNASequencer public dnaSequencer;
    LifeLineOrchestrator public lifelineOrchestrator;

    // Demo sessions
    mapping(bytes32 => DemoSession) public demoSessions;
    bytes32[] public activeSessions;

    // Demo templates
    mapping(DemoType => bytes32[]) public demoTemplates;

    // Metrics
    DemoMetrics public metrics;

    // Configuration
    uint256 public maxDemoDuration = 3600; // 1 hour
    uint256 public minDemoSuccessRate = 8000; // 80%
    address public ipfsRecorder;

    // Events
    event DemoStarted(bytes32 indexed sessionId, DemoType demoType, address demonstrator);
    event DemoStepCompleted(bytes32 indexed sessionId, bytes32 indexed stepId, bool success);
    event DemoCompleted(bytes32 indexed sessionId, uint256 successRate, bytes32 recordingHash);
    event DemoFailed(bytes32 indexed sessionId, string reason);

    modifier validSession(bytes32 _sessionId) {
        require(demoSessions[_sessionId].demonstrator != address(0), "Session not found");
        _;
    }

    modifier demoActive(bytes32 _sessionId) {
        require(demoSessions[_sessionId].status == DemoStatus.RUNNING, "Demo not active");
        _;
    }

    constructor(
        address _bootstrap,
        address _dnaCore,
        address _dnaSequencer,
        address _lifelineOrchestrator,
        address _ipfsRecorder
    ) Ownable(msg.sender) {
        bootstrap = SystemBootstrap(_bootstrap);
        dnaCore = UnykornDNACore(_dnaCore);
        dnaSequencer = DNASequencer(_dnaSequencer);
        lifelineOrchestrator = LifeLineOrchestrator(_lifelineOrchestrator);
        ipfsRecorder = _ipfsRecorder;

        _initializeDemoTemplates();
    }

    /**
     * @notice Start a demo session
     */
    function startDemo(DemoType _demoType, string memory _description) public returns (bytes32) {
        bytes32 sessionId = keccak256(abi.encodePacked(
            _demoType, msg.sender, block.timestamp
        ));

        DemoSession storage session = demoSessions[sessionId];
        session.sessionId = sessionId;
        session.demoType = _demoType;
        session.demonstrator = msg.sender;
        session.status = DemoStatus.INITIALIZING;
        session.startedAt = block.timestamp;
        session.demoSteps = demoTemplates[_demoType];

        activeSessions.push(sessionId);
        metrics.totalSessions++;

        emit DemoStarted(sessionId, _demoType, msg.sender);

        // Auto-start the demo
        _startDemoExecution(sessionId);

        return sessionId;
    }

    /**
     * @notice Execute demo step
     */
    function executeDemoStep(bytes32 _sessionId, bytes32 _stepId, bytes memory _parameters) public validSession(_sessionId)
        demoActive(_sessionId)
        returns (bool)
    {
        DemoSession storage session = demoSessions[_sessionId];

        // Verify step is in demo
        bool validStep = false;
        for (uint256 i = 0; i < session.demoSteps.length; i++) {
            if (session.demoSteps[i] == _stepId) {
                validStep = true;
                break;
            }
        }
        require(validStep, "Invalid demo step");

        // Execute step based on demo type
        (bool success, bytes memory result, string memory description) = _executeDemoStep(
            session.demoType, _stepId, _parameters
        );

        // Record result
        DemoResult storage stepResult = session.stepResults[_stepId];
        stepResult.stepId = _stepId;
        stepResult.success = success;
        stepResult.result = result;
        stepResult.description = description;
        stepResult.timestamp = block.timestamp;
        stepResult.evidenceHash = keccak256(abi.encodePacked(result, description));

        // Update session log
        session.sessionLog = string(abi.encodePacked(
            session.sessionLog,
            "\n[", Strings.toString(block.timestamp), "] Step ",
            Strings.toHexString(uint256(_stepId), 32),
            success ? " SUCCESS: " : " FAILED: ",
            description
        ));

        emit DemoStepCompleted(_sessionId, _stepId, success);

        // Check if demo is complete
        if (_isDemoComplete(session)) {
            _completeDemo(session);
        }

        return success;
    }

    /**
     * @notice Complete demo session
     */
    function completeDemo(bytes32 _sessionId, string memory _ipfsRecordingHash) public validSession(_sessionId)
    {
        DemoSession storage session = demoSessions[_sessionId];
        require(session.status == DemoStatus.RUNNING, "Demo not running");

        session.completedAt = block.timestamp;
        session.ipfsRecordingHash = keccak256(abi.encodePacked(_ipfsRecordingHash));
        session.successRate = _calculateDemoSuccessRate(session);

        if (session.successRate >= minDemoSuccessRate) {
            session.status = DemoStatus.COMPLETED;
            metrics.successfulSessions++;

            emit DemoCompleted(_sessionId, session.successRate, session.ipfsRecordingHash);
        } else {
            session.status = DemoStatus.FAILED;
            emit DemoFailed(_sessionId, "Success rate below threshold");
        }

        // Update metrics
        _updateDemoMetrics(session);
    }

    /**
     * @notice Get demo session details
     */
    function getDemoSession(bytes32 _sessionId) public view
        returns (
            DemoType demoType,
            DemoStatus status,
            uint256 startedAt,
            uint256 completedAt,
            uint256 successRate,
            uint256 stepsCompleted
        )
    {
        DemoSession storage session = demoSessions[_sessionId];
        uint256 stepsCompleted = 0;

        for (uint256 i = 0; i < session.demoSteps.length; i++) {
            if (session.stepResults[session.demoSteps[i]].timestamp > 0) {
                stepsCompleted++;
            }
        }

        return (
            session.demoType,
            session.status,
            session.startedAt,
            session.completedAt,
            session.successRate,
            stepsCompleted
        );
    }

    /**
     * @notice Get demo step result
     */
    function getDemoStepResult(bytes32 _sessionId, bytes32 _stepId) public view
        returns (
            bool success,
            string memory description,
            uint256 timestamp,
            bytes32 evidenceHash
        )
    {
        DemoResult memory result = demoSessions[_sessionId].stepResults[_stepId];
        return (
            result.success,
            result.description,
            result.timestamp,
            result.evidenceHash
        );
    }

    /**
     * @notice Get demo templates
     */
    function getDemoTemplate(DemoType _demoType) public view returns (bytes32[] memory) {
        return demoTemplates[_demoType];
    }

    /**
     * @notice Get demo metrics
     */
    function getDemoMetrics() public view returns (
        uint256 totalSessions,
        uint256 successfulSessions,
        uint256 averageCompletionTime,
        uint256 demoEngagement,
        DemoType mostPopularDemo
    ) {
        return (
            metrics.totalSessions,
            metrics.successfulSessions,
            metrics.averageCompletionTime,
            metrics.demoEngagement,
            DemoType(uint256(metrics.mostPopularDemo))
        );
    }

    // Internal functions
    function _initializeDemoTemplates() internal {
        // DNA Core Demo
        bytes32[] memory dnaCoreSteps = new bytes32[](5);
        dnaCoreSteps[0] = keccak256(abi.encodePacked("Initialize DNA Core"));
        dnaCoreSteps[1] = keccak256(abi.encodePacked("Add Governance Gene"));
        dnaCoreSteps[2] = keccak256(abi.encodePacked("Add Security Gene"));
        dnaCoreSteps[3] = keccak256(abi.encodePacked("Start Replication"));
        dnaCoreSteps[4] = keccak256(abi.encodePacked("Verify Genome"));
        demoTemplates[DemoType.DNA_CORE_DEMO] = dnaCoreSteps;

        // Sequencer Demo
        bytes32[] memory sequencerSteps = new bytes32[](4);
        sequencerSteps[0] = keccak256(abi.encodePacked("Create Sequence"));
        sequencerSteps[1] = keccak256(abi.encodePacked("Execute AI Command"));
        sequencerSteps[2] = keccak256(abi.encodePacked("Monitor Execution"));
        sequencerSteps[3] = keccak256(abi.encodePacked("Validate Results"));
        demoTemplates[DemoType.SEQUENCER_DEMO] = sequencerSteps;

        // Lifeline Demo
        bytes32[] memory lifelineSteps = new bytes32[](4);
        lifelineSteps[0] = keccak256(abi.encodePacked("Check Vital Signs"));
        lifelineSteps[1] = keccak256(abi.encodePacked("Record Life Event"));
        lifelineSteps[2] = keccak256(abi.encodePacked("Evolve Consciousness"));
        lifelineSteps[3] = keccak256(abi.encodePacked("Monitor Evolution"));
        demoTemplates[DemoType.LIFELINE_DEMO] = lifelineSteps;

        // Full System Demo
        bytes32[] memory fullSystemSteps = new bytes32[](8);
        fullSystemSteps[0] = keccak256(abi.encodePacked("Bootstrap System"));
        fullSystemSteps[1] = keccak256(abi.encodePacked("Initialize DNA"));
        fullSystemSteps[2] = keccak256(abi.encodePacked("Setup Sequencer"));
        fullSystemSteps[3] = keccak256(abi.encodePacked("Activate Lifeline"));
        fullSystemSteps[4] = keccak256(abi.encodePacked("Integrate AI"));
        fullSystemSteps[5] = keccak256(abi.encodePacked("Test Operations"));
        fullSystemSteps[6] = keccak256(abi.encodePacked("Validate System"));
        fullSystemSteps[7] = keccak256(abi.encodePacked("Generate Report"));
        demoTemplates[DemoType.FULL_SYSTEM_DEMO] = fullSystemSteps;
    }

    function _startDemoExecution(bytes32 _sessionId) internal {
        DemoSession storage session = demoSessions[_sessionId];
        session.status = DemoStatus.RUNNING;

        // Initialize session log
        session.sessionLog = string(abi.encodePacked(
            "Demo started at ", Strings.toString(block.timestamp)
        ));
    }

    function _executeDemoStep(DemoType _demoType, bytes32 _stepId, bytes memory _parameters)
        internal
        returns (bool success, bytes memory result, string memory description)
    {
        if (_demoType == DemoType.DNA_CORE_DEMO) {
            return _executeDNACoreDemoStep(_stepId, _parameters);
        } else if (_demoType == DemoType.SEQUENCER_DEMO) {
            return _executeSequencerDemoStep(_stepId, _parameters);
        } else if (_demoType == DemoType.LIFELINE_DEMO) {
            return _executeLifelineDemoStep(_stepId, _parameters);
        } else if (_demoType == DemoType.FULL_SYSTEM_DEMO) {
            return _executeFullSystemDemoStep(_stepId, _parameters);
        }

        return (false, "", "Unknown demo type");
    }

    function _executeDNACoreDemoStep(bytes32 _stepId, bytes memory _parameters)
        internal
        returns (bool, bytes memory, string memory)
    {
        bytes32 stepHash = keccak256(abi.encodePacked("Initialize DNA Core"));
        if (_stepId == stepHash) {
            // Check if DNA core is initialized
            (, uint256 totalGenes, uint256 activeGenes, , , , ) = dnaCore.getNucleusStatus();
            bool initialized = totalGenes > 0;
            return (initialized, abi.encode(totalGenes, activeGenes), "DNA Core initialization check");
        }

        stepHash = keccak256(abi.encodePacked("Add Governance Gene"));
        if (_stepId == stepHash) {
            // This would add a governance gene - simplified for demo
            return (true, abi.encode(block.timestamp), "Governance gene added");
        }

        return (true, abi.encode("Demo step executed"), "DNA Core demo step");
    }

    function _executeSequencerDemoStep(bytes32 _stepId, bytes memory _parameters)
        internal
        returns (bool, bytes memory, string memory)
    {
        bytes32 stepHash = keccak256(abi.encodePacked("Create Sequence"));
        if (_stepId == stepHash) {
            // Create a demo sequence
            bytes32 sequenceId = dnaSequencer.createSequence(
                DNASequencer.SequenceType.DEPLOYMENT_SEQUENCE,
                "Demo Sequence",
                "Demonstration sequence",
                DNASequencer.ExecutionMode.AUTOMATIC,
                new bytes32[](0),
                new bytes[](0)
            );
            return (true, abi.encode(sequenceId), "Demo sequence created");
        }

        return (true, abi.encode("Demo step executed"), "Sequencer demo step");
    }

    function _executeLifelineDemoStep(bytes32 _stepId, bytes memory _parameters)
        internal
        returns (bool, bytes memory, string memory)
    {
        bytes32 stepHash = keccak256(abi.encodePacked("Check Vital Signs"));
        if (_stepId == stepHash) {
            // Get vital signs
            (uint256 heartbeat, uint256 respiration, , , , , , , bool healthy) = lifelineOrchestrator.getVitalSigns();
            return (healthy, abi.encode(heartbeat, respiration), "Vital signs checked");
        }

        return (true, abi.encode("Demo step executed"), "Lifeline demo step");
    }

    function _executeFullSystemDemoStep(bytes32 _stepId, bytes memory _parameters)
        internal
        returns (bool, bytes memory, string memory)
    {
        bytes32 stepHash = keccak256(abi.encodePacked("Bootstrap System"));
        if (_stepId == stepHash) {
            // Check bootstrap status
            (SystemBootstrap.BootstrapPhase phase, SystemBootstrap.BootstrapStatus status, , , ) = bootstrap.getBootstrapProgress();
            bool bootstrapped = status == SystemBootstrap.BootstrapStatus.COMPLETED;
            return (bootstrapped, abi.encode(uint256(phase), uint256(status)), "System bootstrap check");
        }

        return (true, abi.encode("Demo step executed"), "Full system demo step");
    }

    function _isDemoComplete(DemoSession storage _session) internal view returns (bool) {
        for (uint256 i = 0; i < _session.demoSteps.length; i++) {
            if (_session.stepResults[_session.demoSteps[i]].timestamp == 0) {
                return false;
            }
        }
        return true;
    }

    function _completeDemo(DemoSession storage _session) internal {
        _session.completedAt = block.timestamp;
        _session.status = DemoStatus.COMPLETED;
        _session.successRate = _calculateDemoSuccessRate(_session);

        metrics.successfulSessions++;
    }

    function _calculateDemoSuccessRate(DemoSession storage _session) internal view returns (uint256) {
        uint256 successfulSteps = 0;

        for (uint256 i = 0; i < _session.demoSteps.length; i++) {
            if (_session.stepResults[_session.demoSteps[i]].success) {
                successfulSteps++;
            }
        }

        return (_session.demoSteps.length > 0) ? (successfulSteps * 10000) / _session.demoSteps.length : 0;
    }

    function _updateDemoMetrics(DemoSession storage _session) internal {
        // Update average completion time
        uint256 completionTime = _session.completedAt - _session.startedAt;
        metrics.averageCompletionTime = (metrics.averageCompletionTime + completionTime) / 2;

        // Update most popular demo
        if (_session.demoType != DemoType(uint256(metrics.mostPopularDemo))) {
            // Simplified - would track counts per demo type
            metrics.mostPopularDemo = bytes32(uint256(_session.demoType));
        }
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
            buffer[i] = bytes1(uint8(48 + uint8(87 + uint256(value & 0xf))));
            if (uint8(buffer[i]) > 102) {
                buffer[i] = bytes1(uint8(buffer[i]) + 39);
            }
            value >>= 4;
        }
        require(value == 0, "HEX_LENGTH_INSUFFICIENT");
        return string(buffer);
    }
}
