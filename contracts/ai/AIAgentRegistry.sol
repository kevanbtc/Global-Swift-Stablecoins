// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AIAgentRegistry
 * @notice Registry for AI agents in the Unykorn ecosystem
 * @dev Manages AI agent registration, capabilities, and permissions
 */
contract AIAgentRegistry is Ownable, ReentrancyGuard {

    enum AgentType {
        MONITORING,
        TRADING,
        COMPLIANCE,
        ORACLE,
        GOVERNANCE,
        SECURITY,
        SETTLEMENT
    }

    enum AgentStatus {
        INACTIVE,
        ACTIVE,
        SUSPENDED,
        TERMINATED
    }

    struct AIAgent {
        bytes32 agentId;
        address agentAddress;
        string name;
        string description;
        AgentType agentType;
        AgentStatus status;
        uint256 capabilities; // Bitfield of capabilities
        uint256 trustScore;   // 0-100
        uint256 lastActivity;
        address operator;
        bytes32[] authorizedContracts;
        mapping(bytes32 => bool) permissions;
    }

    struct AgentCapability {
        bytes32 capabilityId;
        string name;
        string description;
        uint256 riskLevel; // 1-5
        bool requiresApproval;
    }

    // Agent registry
    mapping(bytes32 => AIAgent) public agents;
    mapping(address => bytes32) public addressToAgentId;
    bytes32[] public agentIds;

    // Capabilities
    mapping(bytes32 => AgentCapability) public capabilities;
    bytes32[] public capabilityIds;

    // Authorization
    mapping(address => bool) public authorizedOperators;
    mapping(bytes32 => mapping(address => bool)) public contractAuthorizations;

    // Events
    event AgentRegistered(bytes32 indexed agentId, address indexed agentAddress, AgentType agentType);
    event AgentStatusChanged(bytes32 indexed agentId, AgentStatus oldStatus, AgentStatus newStatus);
    event CapabilityGranted(bytes32 indexed agentId, bytes32 indexed capabilityId);
    event CapabilityRevoked(bytes32 indexed agentId, bytes32 indexed capabilityId);
    event TrustScoreUpdated(bytes32 indexed agentId, uint256 oldScore, uint256 newScore);

    modifier onlyAuthorizedOperator() {
        require(authorizedOperators[msg.sender] || msg.sender == owner(), "Not authorized operator");
        _;
    }

    modifier agentExists(bytes32 _agentId) {
        require(agents[_agentId].agentAddress != address(0), "Agent does not exist");
        _;
    }

    constructor() Ownable(msg.sender) {
        // Initialize default capabilities
        _addCapability("MONITORING", "System monitoring and alerting", 1, false);
        _addCapability("TRADING", "Automated trading execution", 4, true);
        _addCapability("COMPLIANCE", "Regulatory compliance checking", 2, false);
        _addCapability("ORACLE", "Price and data feeds", 3, false);
        _addCapability("GOVERNANCE", "Governance proposal creation", 5, true);
        _addCapability("SECURITY", "Security monitoring and response", 3, false);
        _addCapability("SETTLEMENT", "Transaction settlement", 4, true);
    }

    /**
     * @notice Register a new AI agent
     */
    function registerAgent(
        address _agentAddress,
        string memory _name,
        string memory _description,
        AgentType _agentType,
        address _operator
    ) public onlyAuthorizedOperator returns (bytes32) {
        require(_agentAddress != address(0), "Invalid agent address");
        require(addressToAgentId[_agentAddress] == bytes32(0), "Agent already registered");

        bytes32 agentId = keccak256(abi.encodePacked(_agentAddress, _name, block.timestamp));

        AIAgent storage agent = agents[agentId];
        agent.agentId = agentId;
        agent.agentAddress = _agentAddress;
        agent.name = _name;
        agent.description = _description;
        agent.agentType = _agentType;
        agent.status = AgentStatus.ACTIVE;
        agent.capabilities = 0;
        agent.trustScore = 50; // Default trust score
        agent.lastActivity = block.timestamp;
        agent.operator = _operator;

        addressToAgentId[_agentAddress] = agentId;
        agentIds.push(agentId);

        emit AgentRegistered(agentId, _agentAddress, _agentType);
        return agentId;
    }

    /**
     * @notice Update agent status
     */
    function updateAgentStatus(bytes32 _agentId, AgentStatus _status) public onlyAuthorizedOperator
        agentExists(_agentId)
    {
        AgentStatus oldStatus = agents[_agentId].status;
        agents[_agentId].status = _status;

        emit AgentStatusChanged(_agentId, oldStatus, _status);
    }

    /**
     * @notice Grant capability to agent
     */
    function grantCapability(bytes32 _agentId, bytes32 _capabilityId) public onlyAuthorizedOperator
        agentExists(_agentId)
    {
        require(capabilities[_capabilityId].capabilityId != bytes32(0), "Capability does not exist");

        agents[_agentId].permissions[_capabilityId] = true;
        agents[_agentId].capabilities |= (1 << uint256(_capabilityId));

        emit CapabilityGranted(_agentId, _capabilityId);
    }

    /**
     * @notice Revoke capability from agent
     */
    function revokeCapability(bytes32 _agentId, bytes32 _capabilityId) public onlyAuthorizedOperator
        agentExists(_agentId)
    {
        agents[_agentId].permissions[_capabilityId] = false;
        agents[_agentId].capabilities &= ~(1 << uint256(_capabilityId));

        emit CapabilityRevoked(_agentId, _capabilityId);
    }

    /**
     * @notice Update agent trust score
     */
    function updateTrustScore(bytes32 _agentId, uint256 _newScore) public onlyAuthorizedOperator
        agentExists(_agentId)
    {
        require(_newScore <= 100, "Invalid trust score");

        uint256 oldScore = agents[_agentId].trustScore;
        agents[_agentId].trustScore = _newScore;

        emit TrustScoreUpdated(_agentId, oldScore, _newScore);
    }

    /**
     * @notice Authorize operator
     */
    function authorizeOperator(address _operator, bool _authorized) public onlyOwner {
        authorizedOperators[_operator] = _authorized;
    }

    /**
     * @notice Add new capability
     */
    function addCapability(
        string memory _name,
        string memory _description,
        uint256 _riskLevel,
        bool _requiresApproval
    ) public onlyOwner returns (bytes32) {
        return _addCapability(_name, _description, _riskLevel, _requiresApproval);
    }

    /**
     * @notice Check if agent has capability
     */
    function hasCapability(bytes32 _agentId, bytes32 _capabilityId) public view returns (bool) {
        return agents[_agentId].permissions[_capabilityId];
    }

    /**
     * @notice Get agent details
     */
    function getAgent(bytes32 _agentId) public view
        returns (
            address agentAddress,
            string memory name,
            AgentType agentType,
            AgentStatus status,
            uint256 capabilities,
            uint256 trustScore,
            address operator
        )
    {
        // AIAgent contains mappings, so use storage reference
        AIAgent storage agent = agents[_agentId];
        return (
            agent.agentAddress,
            agent.name,
            agent.agentType,
            agent.status,
            agent.capabilities,
            agent.trustScore,
            agent.operator
        );
    }

    /**
     * @notice Get all agent IDs
     */
    function getAllAgentIds() public view returns (bytes32[] memory) {
        return agentIds;
    }

    /**
     * @notice Get all capability IDs
     */
    function getAllCapabilityIds() public view returns (bytes32[] memory) {
        return capabilityIds;
    }

    /**
     * @notice Get capability details
     */
    function getCapability(bytes32 _capabilityId) public view
        returns (
            string memory name,
            string memory description,
            uint256 riskLevel,
            bool requiresApproval
        )
    {
        AgentCapability memory cap = capabilities[_capabilityId];
        return (
            cap.name,
            cap.description,
            cap.riskLevel,
            cap.requiresApproval
        );
    }

    // Internal functions
    function _addCapability(
        string memory _name,
        string memory _description,
        uint256 _riskLevel,
        bool _requiresApproval
    ) internal returns (bytes32) {
        bytes32 capabilityId = keccak256(abi.encodePacked(_name, _description, _riskLevel));

        AgentCapability storage cap = capabilities[capabilityId];
        cap.capabilityId = capabilityId;
        cap.name = _name;
        cap.description = _description;
        cap.riskLevel = _riskLevel;
        cap.requiresApproval = _requiresApproval;

        capabilityIds.push(capabilityId);
        return capabilityId;
    }
}
