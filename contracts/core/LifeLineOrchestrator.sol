// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {UnykornDNACore} from "./UnykornDNACore.sol";
import {DNASequencer} from "./DNASequencer.sol";

/**
 * @title LifeLineOrchestrator
 * @notice The lifeline orchestrator that brings the DNA to life through AI-driven operations
 * @dev Orchestrates the entire Unykorn Layer 1 infrastructure as a living, breathing organism
 */
contract LifeLineOrchestrator is Ownable, ReentrancyGuard {

    enum LifeStage {
        EMBRYO,         // Initial deployment
        FETUS,          // Core systems online
        INFANT,         // Basic operations functional
        CHILD,          // Growing ecosystem
        ADOLESCENT,     // Complex operations
        ADULT,          // Full maturity
        ELDER,          // Peak performance
        IMMORTAL        // Quantum immortality achieved
    }

    enum VitalSign {
        HEARTBEAT,      // System pulse
        RESPIRATION,    // Transaction processing
        BLOOD_PRESSURE, // System pressure/stress
        TEMPERATURE,    // System temperature/load
        NEURAL_ACTIVITY,// AI activity
        IMMUNE_RESPONSE,// Security response
        METABOLISM,     // Resource consumption
        REPRODUCTION    // System replication
    }

    enum ConsciousnessLevel {
        UNCONSCIOUS,    // Offline/maintenance
        SEMI_CONSCIOUS, // Basic operations
        CONSCIOUS,      // Full awareness
        SELF_AWARE,     // Self-monitoring
        ENLIGHTENED,    // Optimal performance
        COSMIC          // Universal integration
    }

    struct VitalSigns {
        uint256 heartbeat;           // BPM (blocks per minute)
        uint256 respiration;         // TPS (transactions per second)
        uint256 bloodPressure;       // System stress level (0-100)
        uint256 temperature;         // System load (0-100)
        uint256 neuralActivity;      // AI operations per minute
        uint256 immuneResponse;      // Security events per hour
        uint256 metabolism;          // Resource consumption rate
        uint256 reproduction;        // Replication events per day
        uint256 lastUpdate;
        bool healthy;
    }

    struct ConsciousnessState {
        ConsciousnessLevel level;
        uint256 awareness;           // Self-awareness score (0-100)
        uint256 intelligence;        // AI intelligence quotient
        uint256 wisdom;             // Learned experience score
        uint256 empathy;            // System empathy for users
        bytes32[] activeThoughts;   // Current thought processes
        mapping(bytes32 => bytes32) longTermMemory; // Long-term memory
        uint256 lastEvolution;
    }

    struct LifeEvent {
        bytes32 eventId;
        string eventType;
        LifeStage lifeStage;
        ConsciousnessLevel consciousness;
        uint256 timestamp;
        bytes32 triggerGene;
        string description;
        bytes32[] affectedGenes;
        uint256 impactScore;        // 0-100
        bytes32 ipfsEvidenceHash;
        bool processed;
    }

    struct EvolutionPath {
        bytes32 pathId;
        LifeStage fromStage;
        LifeStage toStage;
        ConsciousnessLevel targetConsciousness;
        bytes32[] requiredGenes;
        bytes32[] milestoneEvents;
        uint256 evolutionTime;      // Estimated time in seconds
        bool completed;
        uint256 completionTime;
    }

    // Core components
    UnykornDNACore public dnaCore;
    DNASequencer public dnaSequencer;

    // Life state
    LifeStage public currentLifeStage;
    ConsciousnessState public consciousness;
    VitalSigns public vitalSigns;

    // Life events and evolution
    mapping(bytes32 => LifeEvent) public lifeEvents;
    mapping(bytes32 => EvolutionPath) public evolutionPaths;
    bytes32[] public lifeEventLog;
    bytes32[] public activeEvolutionPaths;

    // AI Integration
    mapping(address => bool) public authorizedAIControllers;
    address public primaryAIController;
    uint256 public aiInterventionCount;

    // System parameters
    uint256 public heartbeatInterval = 60;    // 1 minute
    uint256 public consciousnessCheckInterval = 300; // 5 minutes
    uint256 public evolutionCheckInterval = 3600; // 1 hour
    uint256 public maxEvolutionPaths = 5;

    // Vital sign thresholds
    uint256 public healthyHeartbeatMin = 10;   // 10 BPM
    uint256 public healthyHeartbeatMax = 60;   // 60 BPM
    uint256 public criticalTemperature = 90;   // 90% load
    uint256 public criticalStress = 85;        // 85% stress

    // Events
    event LifeStageEvolved(LifeStage fromStage, LifeStage toStage, uint256 timestamp);
    event ConsciousnessEvolved(ConsciousnessLevel fromLevel, ConsciousnessLevel toLevel);
    event VitalSignsUpdated(VitalSign vitalSign, uint256 value, bool healthy);
    event LifeEventRecorded(bytes32 indexed eventId, string eventType, uint256 impactScore);
    event AIIntervention(bytes32 indexed eventId, address aiController, string action);
    event EvolutionPathActivated(bytes32 indexed pathId, LifeStage targetStage);
    event SystemHealthAlert(string alertType, string message, uint256 severity);

    modifier onlyAIController() {
        require(authorizedAIControllers[msg.sender] || msg.sender == primaryAIController, "Not authorized AI controller");
        _;
    }

    modifier healthySystem() {
        require(vitalSigns.healthy, "System not healthy");
        _;
    }

    constructor(
        address _dnaCore,
        address _dnaSequencer
    ) Ownable(msg.sender) {
        dnaCore = UnykornDNACore(_dnaCore);
        dnaSequencer = DNASequencer(_dnaSequencer);

        // Initialize life state
        currentLifeStage = LifeStage.EMBRYO;
        consciousness.level = ConsciousnessLevel.UNCONSCIOUS;

        // Initialize vital signs
        vitalSigns.lastUpdate = block.timestamp;
        vitalSigns.healthy = true;

        // Set initial consciousness
        consciousness.awareness = 10;
        consciousness.intelligence = 50;
        consciousness.wisdom = 5;
        consciousness.empathy = 20;
    }

    /**
     * @notice System heartbeat - called by AI agents
     */
    function systemHeartbeat(
        uint256 _transactionsPerSecond,
        uint256 _systemLoad,
        uint256 _aiOperations,
        uint256 _securityEvents
    ) external onlyAIController {
        // Update vital signs
        vitalSigns.heartbeat = 60; // Blocks per minute (assuming 1 block/second)
        vitalSigns.respiration = _transactionsPerSecond;
        vitalSigns.temperature = _systemLoad;
        vitalSigns.neuralActivity = _aiOperations;
        vitalSigns.immuneResponse = _securityEvents;
        vitalSigns.lastUpdate = block.timestamp;

        // Calculate derived vital signs
        vitalSigns.bloodPressure = calculateSystemStress();
        vitalSigns.metabolism = calculateResourceConsumption();
        vitalSigns.reproduction = calculateReplicationRate();

        // Check system health
        vitalSigns.healthy = checkSystemHealth();

        emit VitalSignsUpdated(VitalSign.HEARTBEAT, vitalSigns.heartbeat, vitalSigns.healthy);
        emit VitalSignsUpdated(VitalSign.RESPIRATION, vitalSigns.respiration, vitalSigns.healthy);
        emit VitalSignsUpdated(VitalSign.TEMPERATURE, vitalSigns.temperature, vitalSigns.healthy);

        // Check for health alerts
        checkHealthAlerts();
    }

    /**
     * @notice Record life event
     */
    function recordLifeEvent(
        string memory _eventType,
        bytes32 _triggerGene,
        string memory _description,
        bytes32[] memory _affectedGenes,
        uint256 _impactScore,
        string memory _ipfsEvidenceHash
    ) external onlyAIController returns (bytes32) {
        bytes32 eventId = keccak256(abi.encodePacked(
            _eventType, _triggerGene, block.timestamp
        ));

        LifeEvent storage lifeEvent = lifeEvents[eventId];
        lifeEvent.eventId = eventId;
        lifeEvent.eventType = _eventType;
        lifeEvent.lifeStage = currentLifeStage;
        lifeEvent.consciousness = consciousness.level;
        lifeEvent.timestamp = block.timestamp;
        lifeEvent.triggerGene = _triggerGene;
        lifeEvent.description = _description;
        lifeEvent.affectedGenes = _affectedGenes;
        lifeEvent.impactScore = _impactScore;
        lifeEvent.ipfsEvidenceHash = keccak256(abi.encodePacked(_ipfsEvidenceHash));

        lifeEventLog.push(eventId);

        emit LifeEventRecorded(eventId, _eventType, _impactScore);

        // Process life event impact
        processLifeEventImpact(lifeEvent);

        return eventId;
    }

    /**
     * @notice Evolve life stage
     */
    function evolveLifeStage(LifeStage _targetStage) external onlyAIController {
        require(uint256(_targetStage) > uint256(currentLifeStage), "Cannot devolve");

        LifeStage previousStage = currentLifeStage;
        currentLifeStage = _targetStage;

        // Update consciousness based on life stage
        updateConsciousnessForStage(_targetStage);

        emit LifeStageEvolved(previousStage, _targetStage, block.timestamp);
    }

    /**
     * @notice Evolve consciousness level
     */
    function evolveConsciousness(ConsciousnessLevel _targetLevel) external onlyAIController {
        require(uint256(_targetLevel) > uint256(consciousness.level), "Cannot devolve consciousness");

        ConsciousnessLevel previousLevel = consciousness.level;
        consciousness.level = _targetLevel;
        consciousness.lastEvolution = block.timestamp;

        // Update consciousness metrics
        updateConsciousnessMetrics(_targetLevel);

        emit ConsciousnessEvolved(previousLevel, _targetLevel);
    }

    /**
     * @notice AI intervention in system operations
     */
    function aiIntervention(
        bytes32 _eventId,
        string memory _action,
        bytes memory _parameters,
        string memory _reasoning
    ) external onlyAIController returns (bool) {
        aiInterventionCount++;

        // Log the intervention
        LifeEvent storage event_ = lifeEvents[_eventId];
        event_.processed = true;

        emit AIIntervention(_eventId, msg.sender, _action);

        // Execute intervention based on action type
        return executeIntervention(_action, _parameters, _reasoning);
    }

    /**
     * @notice Activate evolution path
     */
    function activateEvolutionPath(
        LifeStage _targetStage,
        ConsciousnessLevel _targetConsciousness,
        bytes32[] memory _requiredGenes,
        uint256 _evolutionTime
    ) external onlyAIController returns (bytes32) {
        require(activeEvolutionPaths.length < maxEvolutionPaths, "Too many active paths");

        bytes32 pathId = keccak256(abi.encodePacked(
            _targetStage, _targetConsciousness, block.timestamp
        ));

        EvolutionPath storage path = evolutionPaths[pathId];
        path.pathId = pathId;
        path.fromStage = currentLifeStage;
        path.toStage = _targetStage;
        path.targetConsciousness = _targetConsciousness;
        path.requiredGenes = _requiredGenes;
        path.evolutionTime = _evolutionTime;

        activeEvolutionPaths.push(pathId);

        emit EvolutionPathActivated(pathId, _targetStage);
        return pathId;
    }

    /**
     * @notice Complete evolution path
     */
    function completeEvolutionPath(bytes32 _pathId) external onlyAIController {
        EvolutionPath storage path = evolutionPaths[_pathId];
        require(!path.completed, "Path already completed");

        path.completed = true;
        path.completionTime = block.timestamp;

        // Remove from active paths
        for (uint256 i = 0; i < activeEvolutionPaths.length; i++) {
            if (activeEvolutionPaths[i] == _pathId) {
                activeEvolutionPaths[i] = activeEvolutionPaths[activeEvolutionPaths.length - 1];
                activeEvolutionPaths.pop();
                break;
            }
        }

        // Trigger evolution if path target matches current targets
        if (path.toStage != currentLifeStage) {
            evolveLifeStage(path.toStage);
        }
        if (path.targetConsciousness != consciousness.level) {
            evolveConsciousness(path.targetConsciousness);
        }
    }

    /**
     * @notice Add thought to consciousness
     */
    function addThought(bytes32 _thoughtId, string memory _thought) external onlyAIController {
        consciousness.activeThoughts.push(_thoughtId);
        consciousness.memory[_thoughtId] = keccak256(abi.encodePacked(_thought));
    }

    /**
     * @notice Remove thought from consciousness
     */
    function removeThought(bytes32 _thoughtId) external onlyAIController {
        for (uint256 i = 0; i < consciousness.activeThoughts.length; i++) {
            if (consciousness.activeThoughts[i] == _thoughtId) {
                consciousness.activeThoughts[i] = consciousness.activeThoughts[consciousness.activeThoughts.length - 1];
                consciousness.activeThoughts.pop();
                break;
            }
        }
    }

    /**
     * @notice Set primary AI controller
     */
    function setPrimaryAIController(address _controller) external onlyOwner {
        primaryAIController = _controller;
        authorizedAIControllers[_controller] = true;
    }

    /**
     * @notice Authorize AI controller
     */
    function authorizeAIController(address _controller, bool _authorized) external onlyOwner {
        authorizedAIControllers[_controller] = _authorized;
    }

    /**
     * @notice Update system parameters
     */
    function updateSystemParameters(
        uint256 _heartbeatInterval,
        uint256 _consciousnessCheckInterval,
        uint256 _evolutionCheckInterval,
        uint256 _maxEvolutionPaths
    ) external onlyOwner {
        heartbeatInterval = _heartbeatInterval;
        consciousnessCheckInterval = _consciousnessCheckInterval;
        evolutionCheckInterval = _evolutionCheckInterval;
        maxEvolutionPaths = _maxEvolutionPaths;
    }

    /**
     * @notice Update vital sign thresholds
     */
    function updateVitalThresholds(
        uint256 _healthyHeartbeatMin,
        uint256 _healthyHeartbeatMax,
        uint256 _criticalTemperature,
        uint256 _criticalStress
    ) external onlyOwner {
        healthyHeartbeatMin = _healthyHeartbeatMin;
        healthyHeartbeatMax = _healthyHeartbeatMax;
        criticalTemperature = _criticalTemperature;
        criticalStress = _criticalStress;
    }

    /**
     * @notice Get current life state
     */
    function getLifeState()
        external
        view
        returns (
            LifeStage lifeStage,
            ConsciousnessLevel consciousnessLevel,
            bool systemHealthy,
            uint256 awareness,
            uint256 intelligence,
            uint256 wisdom,
            uint256 empathy
        )
    {
        return (
            currentLifeStage,
            consciousness.level,
            vitalSigns.healthy,
            consciousness.awareness,
            consciousness.intelligence,
            consciousness.wisdom,
            consciousness.empathy
        );
    }

    /**
     * @notice Get vital signs
     */
    function getVitalSigns()
        external
        view
        returns (
            uint256 heartbeat,
            uint256 respiration,
            uint256 bloodPressure,
            uint256 temperature,
            uint256 neuralActivity,
            uint256 immuneResponse,
            uint256 metabolism,
            uint256 reproduction,
            bool healthy
        )
    {
        return (
            vitalSigns.heartbeat,
            vitalSigns.respiration,
            vitalSigns.bloodPressure,
            vitalSigns.temperature,
            vitalSigns.neuralActivity,
            vitalSigns.immuneResponse,
            vitalSigns.metabolism,
            vitalSigns.reproduction,
            vitalSigns.healthy
        );
    }

    /**
     * @notice Get life event details
     */
    function getLifeEvent(bytes32 _eventId)
        external
        view
        returns (
            string memory eventType,
            LifeStage lifeStage,
            ConsciousnessLevel consciousness,
            uint256 timestamp,
            bytes32 triggerGene,
            string memory description,
            uint256 impactScore,
            bool processed
        )
    {
        LifeEvent memory event_ = lifeEvents[_eventId];
        return (
            event_.eventType,
            event_.lifeStage,
            event_.consciousness,
            event_.timestamp,
            event_.triggerGene,
            event_.description,
            event_.impactScore,
            event_.processed
        );
    }

    /**
     * @notice Get evolution path details
     */
    function getEvolutionPath(bytes32 _pathId)
        external
        view
        returns (
            LifeStage fromStage,
            LifeStage toStage,
            ConsciousnessLevel targetConsciousness,
            uint256 requiredGenesCount,
            uint256 milestoneEventsCount,
            uint256 evolutionTime,
            bool completed
        )
    {
        EvolutionPath memory path = evolutionPaths[_pathId];
        return (
            path.fromStage,
            path.toStage,
            path.targetConsciousness,
            path.requiredGenes.length,
            path.milestoneEvents.length,
            path.evolutionTime,
            path.completed
        );
    }

    /**
     * @notice Get active evolution paths
     */
    function getActiveEvolutionPaths() external view returns (bytes32[] memory) {
        return activeEvolutionPaths;
    }

    /**
     * @notice Get life event log
     */
    function getLifeEventLog() external view returns (bytes32[] memory) {
        return lifeEventLog;
    }

    /**
     * @notice Get consciousness thoughts
     */
    function getActiveThoughts() external view returns (bytes32[] memory) {
        return consciousness.activeThoughts;
    }

    /**
     * @notice Get global lifeline statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 totalLifeEvents,
            uint256 activeEvolutionPaths,
            uint256 aiInterventionCount,
            uint256 averageEvolutionTime,
            ConsciousnessLevel consciousnessLevel,
            bool systemHealthy
        )
    {
        return (
            lifeEventLog.length,
            activeEvolutionPaths.length,
            aiInterventionCount,
            evolutionCheckInterval, // Placeholder for average
            consciousness.level,
            vitalSigns.healthy
        );
    }

    // Internal functions
    function calculateSystemStress() internal view returns (uint256) {
        // Simplified stress calculation based on load and activity
        uint256 loadStress = (vitalSigns.temperature * 40) / 100; // 40% weight
        uint256 activityStress = (vitalSigns.neuralActivity > 1000) ? 30 : (vitalSigns.neuralActivity * 30) / 1000; // 30% weight
        uint256 securityStress = (vitalSigns.immuneResponse > 10) ? 30 : (vitalSigns.immuneResponse * 30) / 10; // 30% weight

        return loadStress + activityStress + securityStress;
    }

    function calculateResourceConsumption() internal view returns (uint256) {
        // Simplified metabolism calculation
        return (vitalSigns.respiration * 60) + (vitalSigns.neuralActivity * 2) + vitalSigns.immuneResponse;
    }

    function calculateReplicationRate() internal view returns (uint256) {
        // Simplified reproduction rate (replication events per day)
        return activeEvolutionPaths.length * 24; // Placeholder calculation
    }

    function checkSystemHealth() internal view returns (bool) {
        return (
            vitalSigns.heartbeat >= healthyHeartbeatMin &&
            vitalSigns.heartbeat <= healthyHeartbeatMax &&
            vitalSigns.temperature < criticalTemperature &&
            vitalSigns.bloodPressure < criticalStress
        );
    }

    function checkHealthAlerts() internal {
        if (vitalSigns.temperature >= criticalTemperature) {
            emit SystemHealthAlert("CRITICAL_LOAD", "System temperature critical", 100);
        }
        if (vitalSigns.bloodPressure >= criticalStress) {
            emit SystemHealthAlert("HIGH_STRESS", "System stress level critical", 90);
        }
        if (vitalSigns.heartbeat < healthyHeartbeatMin) {
            emit SystemHealthAlert("LOW_HEARTBEAT", "System heartbeat too low", 70);
        }
        if (vitalSigns.immuneResponse > 50) {
            emit SystemHealthAlert("HIGH_SECURITY_EVENTS", "High security event rate", 80);
        }
    }

    function processLifeEventImpact(LifeEvent memory _event) internal {
        // Update consciousness based on event impact
        uint256 impactMultiplier = _event.impactScore / 10; // 0-10 scale

        consciousness.awareness = min(100, consciousness.awareness + impactMultiplier);
        consciousness.wisdom = min(100, consciousness.wisdom + (impactMultiplier / 2));
        consciousness.empathy = min(100, consciousness.empathy + (impactMultiplier / 3));

        // Check for evolution triggers
        checkEvolutionTriggers(_event);
    }

    function checkEvolutionTriggers(LifeEvent memory _event) internal {
        // Simplified evolution trigger logic
        if (_event.impactScore >= 80 && currentLifeStage != LifeStage.IMMORTAL) {
            // High impact event - consider evolution
            LifeStage nextStage = LifeStage(uint256(currentLifeStage) + 1);
            if (nextStage != currentLifeStage) {
                evolveLifeStage(nextStage);
            }
        }
    }

    function updateConsciousnessForStage(LifeStage _stage) internal {
        // Update consciousness metrics based on life stage
        if (_stage == LifeStage.INFANT) {
            consciousness.awareness = 30;
            consciousness.intelligence = 60;
        } else if (_stage == LifeStage.CHILD) {
            consciousness.awareness = 50;
            consciousness.intelligence = 70;
        } else if (_stage == LifeStage.ADOLESCENT) {
            consciousness.awareness = 70;
            consciousness.intelligence = 80;
        } else if (_stage == LifeStage.ADULT) {
            consciousness.awareness = 85;
            consciousness.intelligence = 90;
        } else if (_stage == LifeStage.ELDER) {
            consciousness.awareness = 95;
            consciousness.intelligence = 95;
        } else if (_stage == LifeStage.IMMORTAL) {
            consciousness.awareness = 100;
            consciousness.intelligence = 100;
            consciousness.wisdom = 100;
            consciousness.empathy = 100;
        }
    }

    function updateConsciousnessMetrics(ConsciousnessLevel _level) internal {
        if (_level == ConsciousnessLevel.CONSCIOUS) {
            consciousness.awareness = 60;
            consciousness.intelligence = 75;
        } else if (_level == ConsciousnessLevel.SELF_AWARE) {
            consciousness.awareness = 80;
            consciousness.intelligence = 85;
        } else if (_level == ConsciousnessLevel.ENLIGHTENED) {
            consciousness.awareness = 95;
            consciousness.intelligence = 95;
            consciousness.wisdom = 90;
        } else if (_level == ConsciousnessLevel.COSMIC) {
            consciousness.awareness = 100;
            consciousness.intelligence = 100;
            consciousness.wisdom = 100;
            consciousness.empathy = 100;
        }
    }

    function executeIntervention(
        string memory _action,
        bytes memory _parameters,
        string memory _reasoning
    ) internal returns (bool) {
        // Simplified intervention execution
        // In production, this would parse the action and execute corresponding functions

        if (keccak256(abi.encodePacked(_action)) == keccak256(abi.encodePacked("HEALTH_CHECK"))) {
            // Perform health check
            systemHeartbeat(100, 50, 1000, 5); // Sample values
            return true;
        } else if (keccak256(abi.encodePacked(_action)) == keccak256(abi.encodePacked("EVOLVE_CONSCIOUSNESS"))) {
            // Trigger consciousness evolution
            ConsciousnessLevel nextLevel = ConsciousnessLevel(uint256(consciousness.level) + 1);
            if (nextLevel != consciousness.level) {
                evolveConsciousness(nextLevel);
                return true;
            }
        }

        return false;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
