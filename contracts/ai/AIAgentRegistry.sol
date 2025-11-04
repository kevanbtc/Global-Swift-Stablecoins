 use and manuever
 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title AIAgentRegistry
 * @notice Registry for AI agents with reputation and capability management
 * @dev Manages AI agent registration, reputation scoring, and capability verification
 */
contract AIAgentRegistry is OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    enum AgentCategory {
        COMPLIANCE,
        RISK_MANAGEMENT,
        TRADING,
        GOVERNANCE,
        MONITORING,
        ANALYTICS,
        SECURITY,
        INFRASTRUCTURE
    }

    enum ReputationLevel {
        NOVICE,
        INTERMEDIATE,
        ADVANCED,
        EXPERT,
        MASTER
    }

    struct AgentProfile {
        bytes32 agentId;
        string name;
        string description;
        address agentAddress;
        address operator;
        AgentCategory category;
        ReputationLevel reputationLevel;
        uint256 reputationScore; // 0-10000 (basis points)
        uint256 totalTasksCompleted;
        uint256 successRate; // BPS
        uint256 uptime; // Percentage BPS
        uint256 lastActive;
        bool isActive;
        bool isVerified;
        bytes32[] capabilities;
        mapping(bytes32 => uint256) skillRatings;
        mapping(bytes32 => bool) certifications;
    }

    struct Capability {
        bytes32 capabilityId;
        string name;
        string description;
        uint256 requiredReputation;
        bool isActive;
    }

    struct Certification {
        bytes32 certId;
        string name;
        string issuer;
        uint256 validityPeriod;
        bool isActive;
    }

    // Storage
    mapping(bytes32 => AgentProfile) public agentProfiles;
    mapping(bytes32 => Capability) public capabilities;
    mapping(bytes32 => Certification) public certifications;
    mapping(address => bytes32[]) public operatorAgents;
    mapping(AgentCategory => bytes32[]) public agentsByCategory;
    mapping(ReputationLevel => bytes32[]) public agentsByReputation;

    bytes32[] public allAgents;
    bytes32[] public allCapabilities;
    bytes32[] public allCertifications;

    // Configuration
    uint256 public minReputationForVerification = 3000; // 30%
    uint256 public reputationDecayRate = 100; // BPS per day
    uint256 public maxAgentsPerOperator = 10;
    uint256 public taskCompletionWeight = 4000; // 40% weight
    uint256 public successRateWeight = 3000; // 30% weight
    uint256 public uptimeWeight = 3000; // 30% weight

    // Events
    event AgentRegistered(bytes32 indexed agentId, string name, AgentCategory category);
    event AgentVerified(bytes32 indexed agentId, address verifier);
    event ReputationUpdated(bytes32 indexed agentId, uint256 newScore, ReputationLevel newLevel);
    event CapabilityAdded(bytes32 indexed capabilityId, string name);
    event CertificationGranted(bytes32 indexed agentId, bytes32 indexed certId);
    event TaskCompleted(bytes32 indexed agentId, bool success, uint256 uptime);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Register a new AI agent
     */
    function registerAgent(
        string memory _name,
        string memory _description,
        address _agentAddress,
        AgentCategory _category,
        bytes32[] memory _capabilities
    ) external returns (bytes32) {
        require(_agentAddress != address(0), "Invalid agent address");
        require(bytes(_name).length > 0, "Name required");
        require(operatorAgents[msg.sender].length < maxAgentsPerOperator, "Max agents per operator reached");

        bytes32 agentId = keccak256(abi.encodePacked(
            _name,
            _agentAddress,
            msg.sender,
            block.timestamp
        ));

        require(agentProfiles[agentId].agentAddress == address(0), "Agent already exists");

        AgentProfile storage profile = agentProfiles[agentId];
        profile.agentId = agentId;
        profile.name = _name;
        profile.description = _description;
        profile.agentAddress = _agentAddress;
        profile.operator = msg.sender;
        profile.category = _category;
        profile.reputationScore = 1000; // Base reputation
        profile.reputationLevel = ReputationLevel.NOVICE;
        profile.lastActive = block.timestamp;
        profile.isActive = true;
        profile.capabilities = _capabilities;

        operatorAgents[msg.sender].push(agentId);
        agentsByCategory[_category].push(agentId);
        agentsByReputation[ReputationLevel.NOVICE].push(agentId);
        allAgents.push(agentId);

        emit AgentRegistered(agentId, _name, _category);
        return agentId;
    }

    /**
     * @notice Update agent activity and performance
     */
    function updateAgentPerformance(
        bytes32 _agentId,
        bool _taskSuccess,
        uint256 _uptime
    ) external {
        AgentProfile storage profile = agentProfiles[_agentId];
        require(profile.agentAddress == msg.sender || profile.operator == msg.sender, "Not authorized");

        profile.totalTasksCompleted++;
        profile.lastActive = block.timestamp;

        // Update success rate
        if (_taskSuccess) {
            profile.successRate = ((profile.successRate * (profile.totalTasksCompleted - 1)) + 10000) / profile.totalTasksCompleted;
        } else {
            profile.successRate = ((profile.successRate * (profile.totalTasksCompleted - 1))) / profile.totalTasksCompleted;
        }

        // Update uptime (weighted average)
        profile.uptime = ((profile.uptime * (profile.totalTasksCompleted - 1)) + _uptime) / profile.totalTasksCompleted;

        // Recalculate reputation
        _updateReputation(_agentId);

        emit TaskCompleted(_agentId, _taskSuccess, _uptime);
    }

    /**
     * @notice Verify an agent (admin only)
     */
    function verifyAgent(bytes32 _agentId) external onlyOwner {
        AgentProfile storage profile = agentProfiles[_agentId];
        require(profile.agentAddress != address(0), "Agent not found");
        require(profile.reputationScore >= minReputationForVerification, "Insufficient reputation");

        profile.isVerified = true;
        emit AgentVerified(_agentId, msg.sender);
    }

    /**
     * @notice Add a new capability
     */
    function addCapability(
        string memory _name,
        string memory _description,
        uint256 _requiredReputation
    ) external onlyOwner returns (bytes32) {
        bytes32 capabilityId = keccak256(abi.encodePacked(_name, block.timestamp));

        Capability storage capability = capabilities[capabilityId];
        capability.capabilityId = capabilityId;
        capability.name = _name;
        capability.description = _description;
        capability.requiredReputation = _requiredReputation;
        capability.isActive = true;

        allCapabilities.push(capabilityId);
        emit CapabilityAdded(capabilityId, _name);

        return capabilityId;
    }

    /**
     * @notice Grant certification to agent
     */
    function grantCertification(
        bytes32 _agentId,
        bytes32 _certId
    ) external onlyOwner {
        AgentProfile storage profile = agentProfiles[_agentId];
        require(profile.agentAddress != address(0), "Agent not found");

        profile.certifications[_certId] = true;
        emit CertificationGranted(_agentId, _certId);
    }

    /**
     * @notice Update agent skill rating
     */
    function updateSkillRating(
        bytes32 _agentId,
        bytes32 _capabilityId,
        uint256 _rating
    ) external {
        AgentProfile storage profile = agentProfiles[_agentId];
        require(profile.agentAddress == msg.sender || profile.operator == msg.sender, "Not authorized");
        require(_rating <= 10000, "Invalid rating");

        profile.skillRatings[_capabilityId] = _rating;
    }

    /**
     * @notice Get agent profile
     */
    function getAgentProfile(bytes32 _agentId)
        external
        view
        returns (
            string memory name,
            AgentCategory category,
            ReputationLevel reputationLevel,
            uint256 reputationScore,
            uint256 totalTasksCompleted,
            uint256 successRate,
            bool isVerified
        )
    {
        AgentProfile storage profile = agentProfiles[_agentId];
        return (
            profile.name,
            profile.category,
            profile.reputationLevel,
            profile.reputationScore,
            profile.totalTasksCompleted,
            profile.successRate,
            profile.isVerified
        );
    }

    /**
     * @notice Get agent capabilities
     */
    function getAgentCapabilities(bytes32 _agentId)
        external
        view
        returns (bytes32[] memory)
    {
        return agentProfiles[_agentId].capabilities;
    }

    /**
     * @notice Check if agent has certification
     */
    function hasCertification(bytes32 _agentId, bytes32 _certId)
        external
        view
        returns (bool)
    {
        return agentProfiles[_agentId].certifications[_certId];
    }

    /**
     * @notice Get agents by category
     */
    function getAgentsByCategory(AgentCategory _category)
        external
        view
        returns (bytes32[] memory)
    {
        return agentsByCategory[_category];
    }

    /**
     * @notice Get agents by reputation level
     */
    function getAgentsByReputation(ReputationLevel _level)
        external
        view
        returns (bytes32[] memory)
    {
        return agentsByReputation[_level];
    }

    /**
     * @notice Get operator's agents
     */
    function getOperatorAgents(address _operator)
        external
        view
        returns (bytes32[] memory)
    {
        return operatorAgents[_operator];
    }

    /**
     * @notice Get capability details
     */
    function getCapability(bytes32 _capabilityId)
        external
        view
        returns (
            string memory name,
            string memory description,
            uint256 requiredReputation,
            bool isActive
        )
    {
        Capability memory capability = capabilities[_capabilityId];
        return (
            capability.name,
            capability.description,
            capability.requiredReputation,
            capability.isActive
        );
    }

    /**
     * @notice Get certification details
     */
    function getCertification(bytes32 _certId)
        external
        view
        returns (
            string memory name,
            string memory issuer,
            uint256 validityPeriod,
            bool isActive
        )
    {
        Certification memory cert = certifications[_certId];
        return (
            cert.name,
            cert.issuer,
            cert.validityPeriod,
            cert.isActive
        );
    }

    /**
     * @notice Update registry parameters
     */
    function updateParameters(
        uint256 _minReputationForVerification,
        uint256 _reputationDecayRate,
        uint256 _maxAgentsPerOperator,
        uint256 _taskCompletionWeight,
        uint256 _successRateWeight,
        uint256 _uptimeWeight
    ) external onlyOwner {
        require(_taskCompletionWeight + _successRateWeight + _uptimeWeight == 10000, "Weights must sum to 100%");

        minReputationForVerification = _minReputationForVerification;
        reputationDecayRate = _reputationDecayRate;
        maxAgentsPerOperator = _maxAgentsPerOperator;
        taskCompletionWeight = _taskCompletionWeight;
        successRateWeight = _successRateWeight;
        uptimeWeight = _uptimeWeight;
    }

    /**
     * @notice Internal function to update reputation
     */
    function _updateReputation(bytes32 _agentId) internal {
        AgentProfile storage profile = agentProfiles[_agentId];

        // Calculate weighted reputation score
        uint256 taskScore = (profile.totalTasksCompleted * taskCompletionWeight) / 10000;
        uint256 successScore = (profile.successRate * successRateWeight) / 10000;
        uint256 uptimeScore = (profile.uptime * uptimeWeight) / 10000;

        uint256 newScore = taskScore + successScore + uptimeScore;

        // Apply decay for inactivity
        uint256 daysInactive = (block.timestamp - profile.lastActive) / 1 days;
        if (daysInactive > 0) {
            uint256 decay = (newScore * reputationDecayRate * daysInactive) / 10000;
            newScore = newScore > decay ? newScore - decay : 0;
        }

        // Cap at 10000
        newScore = newScore > 10000 ? 10000 : newScore;

        // Update reputation level
        ReputationLevel newLevel = _calculateReputationLevel(newScore);

        // Update arrays if level changed
        if (newLevel != profile.reputationLevel) {
            _removeFromReputationArray(profile.agentId, profile.reputationLevel);
            agentsByReputation[newLevel].push(profile.agentId);
        }

        profile.reputationScore = newScore;
        profile.reputationLevel = newLevel;

        emit ReputationUpdated(_agentId, newScore, newLevel);
    }

    /**
     * @notice Calculate reputation level from score
     */
    function _calculateReputationLevel(uint256 _score)
        internal
        pure
        returns (ReputationLevel)
    {
        if (_score >= 9000) return ReputationLevel.MASTER;
        if (_score >= 7000) return ReputationLevel.EXPERT;
        if (_score >= 5000) return ReputationLevel.ADVANCED;
        if (_score >= 3000) return ReputationLevel.INTERMEDIATE;
        return ReputationLevel.NOVICE;
    }

    /**
     * @notice Remove agent from reputation array
     */
    function _removeFromReputationArray(bytes32 _agentId, ReputationLevel _level) internal {
        bytes32[] storage agents = agentsByReputation[_level];
        for (uint i = 0; i < agents.length; i++) {
            if (agents[i] == _agentId) {
                agents[i] = agents[agents.length - 1];
                agents.pop();
                break;
            }
        }
    }

    /**
     * @notice Get all agents
     */
    function getAllAgents() external view returns (bytes32[] memory) {
        return allAgents;
    }

    /**
     * @notice Get all capabilities
     */
    function getAllCapabilities() external view returns (bytes32[] memory) {
        return allCapabilities;
    }

    /**
     * @notice Get all certifications
     */
    function getAllCertifications() external view returns (bytes32[] memory) {
        return allCertifications;
    }

    /**
     * @notice Emergency deactivate agent
     */
    function emergencyDeactivateAgent(bytes32 _agentId) external onlyOwner {
        agentProfiles[_agentId].isActive = false;
    }
}
