// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title GlobalInfrastructureCodex
 * @notice Universal codex for global infrastructure integration and AI agent swarm coordination
 * @dev Integrates IMF, World Bank, WEF, BIS, and all global financial infrastructure standards
 */
contract GlobalInfrastructureCodex is Ownable, ReentrancyGuard {

    enum InfrastructureType {
        IMF_STANDARD,
        WORLD_BANK_FRAMEWORK,
        WEF_DIGITAL_CURRENCY,
        BIS_INNOVATION_HUB,
        SWIFT_GPI_NETWORK,
        ISO20022_STANDARD,
        BASEL_COMMITTEE,
        IOSCO_REGULATORY,
        FATF_COMPLIANCE,
        UN_SUSTAINABLE_DEV,
        CBDC_NETWORK,
        CROSS_CHAIN_BRIDGE,
        AI_AGENT_SWARM,
        QUANTUM_RESISTANT_LEDGER,
        DECENTRALIZED_IDENTITY,
        GLOBAL_STABLECOIN_REGISTRY,
        RENEWABLE_ENERGY_TOKEN,
        FRACTIONAL_ASSET_PROTOCOL,
        INSTITUTIONAL_LENDING,
        PROFESSIONAL_TRADING
    }

    enum ComplianceLevel {
        BASIC,
        INTERMEDIATE,
        ADVANCED,
        PREMIUM,
        ENTERPRISE
    }

    enum IntegrationStatus {
        PROPOSED,
        UNDER_REVIEW,
        APPROVED,
        IMPLEMENTED,
        ACTIVE,
        DEPRECATED
    }

    struct InfrastructureModule {
        bytes32 moduleId;
        string moduleName;
        InfrastructureType moduleType;
        ComplianceLevel complianceLevel;
        IntegrationStatus status;
        address implementingContract;
        address governingBody;
        uint256 implementationDate;
        uint256 lastComplianceCheck;
        string ipfsDocumentation;
        bytes32 complianceHash;
        bool requiresGovernanceApproval;
        uint256 governanceThreshold; // Votes required for approval
        mapping(address => bool) authorizedImplementers;
        bytes32[] dependencies; // Other modules this depends on
    }

    struct AI_Agent {
        bytes32 agentId;
        string agentName;
        string agentType; // "compliance_monitor", "risk_assessor", "yield_optimizer", etc.
        address agentAddress;
        uint256 trustScore;
        uint256 lastActivity;
        bool isActive;
        bytes32[] capabilities;
        mapping(bytes32 => uint256) performanceMetrics;
    }

    struct GlobalStandard {
        bytes32 standardId;
        string standardName;
        string issuingBody;
        uint256 version;
        uint256 effectiveDate;
        uint256 expiryDate;
        string ipfsSpecification;
        bytes32 implementationHash;
        bool isMandatory;
        ComplianceLevel requiredLevel;
        mapping(address => bool) certifiedImplementations;
    }

    struct InfrastructureIntegration {
        bytes32 integrationId;
        InfrastructureType primaryType;
        bytes32[] participatingModules;
        address coordinator;
        uint256 integrationDate;
        uint256 lastSync;
        bool isActive;
        string integrationPurpose;
        bytes32[] sharedStandards;
        mapping(bytes32 => bytes) sharedData;
    }

    // Storage
    mapping(bytes32 => InfrastructureModule) public infrastructureModules;
    mapping(bytes32 => AI_Agent) public aiAgents;
    mapping(bytes32 => GlobalStandard) public globalStandards;
    mapping(bytes32 => InfrastructureIntegration) public infrastructureIntegrations;
    mapping(InfrastructureType => bytes32[]) public modulesByType;
    mapping(address => bytes32[]) public contractsByImplementer;
    mapping(string => bytes32) public standardNameToId;

    // Global governance
    mapping(bytes32 => mapping(address => bool)) public governanceVotes;
    mapping(bytes32 => uint256) public governanceVoteCount;
    uint256 public globalGovernanceThreshold = 100; // Minimum votes for approval

    // AI Agent Swarm coordination
    mapping(bytes32 => bytes32[]) public agentCapabilities;
    mapping(string => bytes32[]) public agentsByType;
    uint256 public totalAgents;
    uint256 public activeIntegrations;

    // Events
    event ModuleRegistered(bytes32 indexed moduleId, string moduleName, InfrastructureType moduleType);
    event StandardEstablished(bytes32 indexed standardId, string standardName, string issuingBody);
    event AIAgentRegistered(bytes32 indexed agentId, string agentName, string agentType);
    event IntegrationEstablished(bytes32 indexed integrationId, InfrastructureType primaryType);
    event GovernanceVote(bytes32 indexed moduleId, address indexed voter, bool approve);
    event ComplianceVerified(bytes32 indexed moduleId, ComplianceLevel level);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new infrastructure module
     */
    function registerInfrastructureModule(
        string memory _moduleName,
        InfrastructureType _moduleType,
        ComplianceLevel _complianceLevel,
        address _implementingContract,
        address _governingBody,
        string memory _ipfsDocumentation,
        bytes32[] memory _dependencies
    ) external returns (bytes32) {
        require(_implementingContract != address(0), "Invalid contract address");
        require(bytes(_moduleName).length > 0, "Invalid module name");

        bytes32 moduleId = keccak256(abi.encodePacked(
            _moduleName,
            _moduleType,
            _implementingContract,
            block.timestamp
        ));

        require(infrastructureModules[moduleId].implementingContract == address(0), "Module already exists");

        InfrastructureModule storage module = infrastructureModules[moduleId];
        module.moduleId = moduleId;
        module.moduleName = _moduleName;
        module.moduleType = _moduleType;
        module.complianceLevel = _complianceLevel;
        module.status = IntegrationStatus.PROPOSED;
        module.implementingContract = _implementingContract;
        module.governingBody = _governingBody;
        module.implementationDate = block.timestamp;
        module.ipfsDocumentation = _ipfsDocumentation;
        module.dependencies = _dependencies;
        module.authorizedImplementers[msg.sender] = true;

        modulesByType[_moduleType].push(moduleId);
        contractsByImplementer[msg.sender].push(moduleId);

        emit ModuleRegistered(moduleId, _moduleName, _moduleType);
        return moduleId;
    }

    /**
     * @notice Establish a global standard
     */
    function establishGlobalStandard(
        string memory _standardName,
        string memory _issuingBody,
        uint256 _version,
        uint256 _effectiveDate,
        uint256 _expiryDate,
        string memory _ipfsSpecification,
        bool _isMandatory,
        ComplianceLevel _requiredLevel
    ) external onlyOwner returns (bytes32) {
        require(bytes(_standardName).length > 0, "Invalid standard name");
        require(bytes(_issuingBody).length > 0, "Invalid issuing body");
        require(_effectiveDate < _expiryDate, "Invalid date range");

        bytes32 standardId = keccak256(abi.encodePacked(
            _standardName,
            _issuingBody,
            _version,
            block.timestamp
        ));

        require(globalStandards[standardId].effectiveDate == 0, "Standard already exists");

        GlobalStandard storage standard = globalStandards[standardId];
        standard.standardId = standardId;
        standard.standardName = _standardName;
        standard.issuingBody = _issuingBody;
        standard.version = _version;
        standard.effectiveDate = _effectiveDate;
        standard.expiryDate = _expiryDate;
        standard.ipfsSpecification = _ipfsSpecification;
        standard.isMandatory = _isMandatory;
        standard.requiredLevel = _requiredLevel;

        standardNameToId[_standardName] = standardId;

        emit StandardEstablished(standardId, _standardName, _issuingBody);
        return standardId;
    }

    /**
     * @notice Register an AI agent in the swarm
     */
    function registerAIAgent(
        string memory _agentName,
        string memory _agentType,
        address _agentAddress,
        bytes32[] memory _capabilities
    ) external returns (bytes32) {
        require(_agentAddress != address(0), "Invalid agent address");
        require(bytes(_agentName).length > 0, "Invalid agent name");

        bytes32 agentId = keccak256(abi.encodePacked(
            _agentName,
            _agentType,
            _agentAddress,
            block.timestamp
        ));

        require(aiAgents[agentId].agentAddress == address(0), "Agent already exists");

        AI_Agent storage agent = aiAgents[agentId];
        agent.agentId = agentId;
        agent.agentName = _agentName;
        agent.agentType = _agentType;
        agent.agentAddress = _agentAddress;
        agent.trustScore = 500; // Base trust score
        agent.lastActivity = block.timestamp;
        agent.isActive = true;
        agent.capabilities = _capabilities;

        agentsByType[_agentType].push(agentId);
        totalAgents++;

        emit AIAgentRegistered(agentId, _agentName, _agentType);
        return agentId;
    }

    /**
     * @notice Create infrastructure integration
     */
    function createInfrastructureIntegration(
        InfrastructureType _primaryType,
        bytes32[] memory _participatingModules,
        string memory _integrationPurpose,
        bytes32[] memory _sharedStandards
    ) external onlyOwner returns (bytes32) {
        require(_participatingModules.length > 0, "No participating modules");

        bytes32 integrationId = keccak256(abi.encodePacked(
            _primaryType,
            _participatingModules,
            block.timestamp
        ));

        require(infrastructureIntegrations[integrationId].coordinator == address(0), "Integration already exists");

        InfrastructureIntegration storage integration = infrastructureIntegrations[integrationId];
        integration.integrationId = integrationId;
        integration.primaryType = _primaryType;
        integration.participatingModules = _participatingModules;
        integration.coordinator = msg.sender;
        integration.integrationDate = block.timestamp;
        integration.lastSync = block.timestamp;
        integration.isActive = true;
        integration.integrationPurpose = _integrationPurpose;
        integration.sharedStandards = _sharedStandards;

        activeIntegrations++;

        emit IntegrationEstablished(integrationId, _primaryType);
        return integrationId;
    }

    /**
     * @notice Vote on governance proposal
     */
    function voteOnGovernance(bytes32 _moduleId, bool _approve) external {
        require(infrastructureModules[_moduleId].implementingContract != address(0), "Module not found");

        InfrastructureModule storage module = infrastructureModules[_moduleId];
        require(module.requiresGovernanceApproval, "Governance not required");

        // Prevent double voting
        require(!governanceVotes[_moduleId][msg.sender], "Already voted");

        governanceVotes[_moduleId][msg.sender] = true;

        if (_approve) {
            governanceVoteCount[_moduleId]++;
        }

        emit GovernanceVote(_moduleId, msg.sender, _approve);

        // Check if threshold reached
        if (governanceVoteCount[_moduleId] >= module.governanceThreshold) {
            module.status = IntegrationStatus.APPROVED;
        }
    }

    /**
     * @notice Verify compliance of a module
     */
    function verifyCompliance(
        bytes32 _moduleId,
        ComplianceLevel _achievedLevel,
        bytes32 _complianceHash
    ) external {
        InfrastructureModule storage module = infrastructureModules[_moduleId];
        require(module.authorizedImplementers[msg.sender] || owner() == msg.sender, "Not authorized");

        module.complianceLevel = _achievedLevel;
        module.complianceHash = _complianceHash;
        module.lastComplianceCheck = block.timestamp;

        if (_achievedLevel >= module.complianceLevel) {
            module.status = IntegrationStatus.IMPLEMENTED;
        }

        emit ComplianceVerified(_moduleId, _achievedLevel);
    }

    /**
     * @notice Certify implementation against global standard
     */
    function certifyImplementation(
        bytes32 _standardId,
        address _implementation
    ) external onlyOwner {
        require(globalStandards[_standardId].effectiveDate > 0, "Standard not found");
        require(_implementation != address(0), "Invalid implementation");

        globalStandards[_standardId].certifiedImplementations[_implementation] = true;
    }

    /**
     * @notice Update AI agent performance
     */
    function updateAIAgentPerformance(
        bytes32 _agentId,
        bytes32 _metricType,
        uint256 _value
    ) external {
        AI_Agent storage agent = aiAgents[_agentId];
        require(agent.agentAddress == msg.sender || owner() == msg.sender, "Not authorized");

        agent.performanceMetrics[_metricType] = _value;
        agent.lastActivity = block.timestamp;

        // Adjust trust score based on performance
        if (_metricType == keccak256("success_rate")) {
            if (_value > 9500) { // 95% success rate
                agent.trustScore = agent.trustScore + 50 > 1000 ? 1000 : agent.trustScore + 50;
            } else if (_value < 8000) { // Below 80% success rate
                agent.trustScore = agent.trustScore > 100 ? agent.trustScore - 100 : 0;
            }
        }
    }

    /**
     * @notice Sync integration data
     */
    function syncIntegrationData(
        bytes32 _integrationId,
        bytes32 _dataKey,
        bytes memory _data
    ) external {
        InfrastructureIntegration storage integration = infrastructureIntegrations[_integrationId];
        require(integration.isActive, "Integration not active");
        require(integration.coordinator == msg.sender || owner() == msg.sender, "Not authorized");

        integration.sharedData[_dataKey] = _data;
        integration.lastSync = block.timestamp;
    }

    /**
     * @notice Get module details
     */
    function getInfrastructureModule(bytes32 _moduleId)
        external
        view
        returns (
            string memory moduleName,
            InfrastructureType moduleType,
            ComplianceLevel complianceLevel,
            IntegrationStatus status,
            address implementingContract
        )
    {
        InfrastructureModule memory module = infrastructureModules[_moduleId];
        return (
            module.moduleName,
            module.moduleType,
            module.complianceLevel,
            module.status,
            module.implementingContract
        );
    }

    /**
     * @notice Get AI agent details
     */
    function getAIAgent(bytes32 _agentId)
        external
        view
        returns (
            string memory agentName,
            string memory agentType,
            address agentAddress,
            uint256 trustScore,
            bool isActive
        )
    {
        AI_Agent memory agent = aiAgents[_agentId];
        return (
            agent.agentName,
            agent.agentType,
            agent.agentAddress,
            agent.trustScore,
            agent.isActive
        );
    }

    /**
     * @notice Get global standard details
     */
    function getGlobalStandard(bytes32 _standardId)
        external
        view
        returns (
            string memory standardName,
            string memory issuingBody,
            uint256 version,
            bool isMandatory,
            ComplianceLevel requiredLevel
        )
    {
        GlobalStandard memory standard = globalStandards[_standardId];
        return (
            standard.standardName,
            standard.issuingBody,
            standard.version,
            standard.isMandatory,
            standard.requiredLevel
        );
    }

    /**
     * @notice Check if implementation is certified
     */
    function isCertifiedImplementation(bytes32 _standardId, address _implementation)
        external
        view
        returns (bool)
    {
        return globalStandards[_standardId].certifiedImplementations[_implementation];
    }

    /**
     * @notice Get modules by type
     */
    function getModulesByType(InfrastructureType _type)
        external
        view
        returns (bytes32[] memory)
    {
        return modulesByType[_type];
    }

    /**
     * @notice Get agents by type
     */
    function getAgentsByType(string memory _type)
        external
        view
        returns (bytes32[] memory)
    {
        return agentsByType[_type];
    }

    /**
     * @notice Update governance parameters
     */
    function updateGovernanceParameters(
        uint256 _globalGovernanceThreshold
    ) external onlyOwner {
        globalGovernanceThreshold = _globalGovernanceThreshold;
    }

    /**
     * @notice Get global statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalModules,
            uint256 _totalStandards,
            uint256 _totalAgents,
            uint256 _activeIntegrations
        )
    {
        uint256 totalModules = 0;
        for (uint256 i = 0; i <= uint256(InfrastructureType.PROFESSIONAL_TRADING); i++) {
            totalModules += modulesByType[InfrastructureType(i)].length;
        }

        uint256 totalStandards = 0;
        // Count would be implemented with additional mapping

        return (totalModules, totalStandards, totalAgents, activeIntegrations);
    }
}
