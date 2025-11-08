// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title UnykornDNACore
 * @notice The central DNA helix of Unykorn Layer 1 infrastructure
 * @dev Organizes all system components in a DNA-like double-helix structure
 *      with IPFS integration and AI-driven operations
 */
contract UnykornDNACore is Ownable, ReentrancyGuard {

    enum DNAStrand {
        GOVERNANCE_STRAND,    // Governance & Policy
        SECURITY_STRAND,      // Security & Cryptography
        FINANCIAL_STRAND,     // Financial Operations
        COMPLIANCE_STRAND,    // Regulatory Compliance
        SETTLEMENT_STRAND,    // Settlement & Rails
        ORACLE_STRAND,        // Oracles & Data
        TOKEN_STRAND,         // Token Standards
        INFRASTRUCTURE_STRAND // Infrastructure & Operations
    }

    enum DNAHelix {
        PRIMARY_HELIX,        // Core system components
        SECONDARY_HELIX,      // Supporting infrastructure
        TERTIARY_HELIX,       // Advanced features
        QUATERNARY_HELIX      // Integration & interoperability
    }

    enum DNABasePair {
        ADENINE_THYMINE,      // Stable pairs (core functionality)
        GUANINE_CYTOSINE,     // Variable pairs (configurable features)
        MUTATION_POINT,       // Upgrade/modification points
        REPLICATION_ORIGIN    // Self-replication capabilities
    }

    struct DNAGene {
        bytes32 geneId;
        DNAStrand strand;
        DNAHelix helix;
        DNABasePair basePair;
        bytes32 nameHash;
        bytes32 descriptionHash;
        address contractAddress;
        // string ipfsHash;           // IPFS hash of contract code/metadata - moved to ipfsHashes mapping
        bytes32 parentGene;        // Parent gene in inheritance chain
        bytes32[] childGenes;      // Child genes in inheritance chain
        uint256 expressionLevel;   // Activity level (0-100)
        bool isActive;
        uint256 lastReplication;   // Last self-replication timestamp
        mapping(bytes32 => bytes32) geneticMarkers; // Key-value genetic data
    }

    struct DNAChromosome {
        bytes32 chromosomeId;
        DNAStrand strand;
        bytes32 nameHash;
        bytes32[] genes;
        uint256 geneCount;
        uint256 totalExpression;
        bool isReplicating;
        uint256 replicationProgress; // 0-100
        bytes32 ipfsMetadataHash;
    }

    struct DNANucleus {
        bytes32 nucleusId;
        bytes32 organismNameHash;       // "Unykorn Layer 1"
        DNAChromosome[8] chromosomes; // One per strand
        uint256 totalGenes;
        uint256 activeGenes;
        uint256 replicationCycle;  // Current replication cycle
        bool isAlive;              // System health status
        uint256 lastHeartbeat;     // Last system heartbeat
        bytes32 ipfsGenomeHash;    // Complete genome on IPFS
        mapping(address => bool) authorizedOperators;
    }

    struct AICommand {
        bytes32 commandId;
        address aiAgent;
        bytes32 commandHash;
        bytes parameters;
        uint256 timestamp;
        bool executed;
        bytes32 resultHash;
        bytes32 ipfsResultHash;
    }

    struct ReplicationEvent {
        bytes32 eventId;
        DNAStrand strand;
        DNAHelix helix;
        bytes32 eventTypeHash;
        bytes32 sourceGene;
        bytes32 targetGene;
        uint256 timestamp;
        bytes32 ipfsEvidenceHash;
    }

    // Core DNA Structure
    DNANucleus public nucleus;
    mapping(bytes32 => DNAGene) public genes;
    mapping(bytes32 => AICommand) public aiCommands;
    mapping(bytes32 => ReplicationEvent) public replicationEvents;

    // IPFS Integration
    mapping(bytes32 => string) public ipfsHashes; // Contract ID => IPFS hash
    string public genomeIpfsHash; // Complete genome hash

    // AI Integration
    address public aiSwarmCoordinator;
    mapping(address => bool) public authorizedAIAgents;
    uint256 public aiCommandCount;

    // System Health
    uint256 public heartbeatInterval = 300; // 5 minutes
    uint256 public lastSystemCheck;
    bool public emergencyMode;

    // Events
    event GeneActivated(bytes32 indexed geneId, DNAStrand strand, DNAHelix helix);
    event GeneDeactivated(bytes32 indexed geneId, string reason);
    event ReplicationStarted(bytes32 indexed chromosomeId, DNAStrand strand);
    event ReplicationCompleted(bytes32 indexed chromosomeId, uint256 geneCount);
    event AICommandExecuted(bytes32 indexed commandId, address aiAgent, bool success);
    event SystemHeartbeat(uint256 timestamp, bool healthy);
    event EmergencyModeActivated(string reason);
    event GenomeUpdated(string newIpfsHash);

    modifier onlyAIAgent() {
        require(authorizedAIAgents[msg.sender] || msg.sender == aiSwarmCoordinator, "Not authorized AI agent");
        _;
    }

    modifier systemHealthy() {
        require(nucleus.isAlive && !emergencyMode, "System not healthy");
        _;
    }

    modifier validGene(bytes32 _geneId) {
        require(genes[_geneId].contractAddress != address(0), "Gene not found");
        _;
    }

    constructor() Ownable(msg.sender) {
        _initializeDNACore();
    }

    /**
     * @notice Initialize the DNA core structure
     */
    function _initializeDNACore() internal {
        // Initialize nucleus
        nucleus.nucleusId = keccak256(abi.encodePacked("UnykornDNACore", block.timestamp));
        nucleus.organismNameHash = keccak256(abi.encodePacked("Unykorn Layer 1"));
        nucleus.isAlive = true;
        nucleus.lastHeartbeat = block.timestamp;
        nucleus.authorizedOperators[msg.sender] = true;

        // Initialize chromosomes (one per strand)
        _initializeChromosomes();

        // Set initial genome hash
        genomeIpfsHash = "QmInitialGenomeHash"; // Placeholder - would be actual IPFS hash
    }

    /**
     * @notice Initialize DNA chromosomes
     */
    function _initializeChromosomes() internal {
        // Governance Strand
        nucleus.chromosomes[uint256(DNAStrand.GOVERNANCE_STRAND)].chromosomeId =
            keccak256(abi.encodePacked("GovernanceChromosome", block.timestamp));
        nucleus.chromosomes[uint256(DNAStrand.GOVERNANCE_STRAND)].nameHash = keccak256(abi.encodePacked("Governance Chromosome"));
        nucleus.chromosomes[uint256(DNAStrand.GOVERNANCE_STRAND)].strand = DNAStrand.GOVERNANCE_STRAND;

        // Security Strand
        nucleus.chromosomes[uint256(DNAStrand.SECURITY_STRAND)].chromosomeId =
            keccak256(abi.encodePacked("SecurityChromosome", block.timestamp));
        nucleus.chromosomes[uint256(DNAStrand.SECURITY_STRAND)].nameHash = keccak256(abi.encodePacked("Security Chromosome"));
        nucleus.chromosomes[uint256(DNAStrand.SECURITY_STRAND)].strand = DNAStrand.SECURITY_STRAND;

        // Financial Strand
        nucleus.chromosomes[uint256(DNAStrand.FINANCIAL_STRAND)].chromosomeId =
            keccak256(abi.encodePacked("FinancialChromosome", block.timestamp));
        nucleus.chromosomes[uint256(DNAStrand.FINANCIAL_STRAND)].nameHash = keccak256(abi.encodePacked("Financial Chromosome"));
        nucleus.chromosomes[uint256(DNAStrand.FINANCIAL_STRAND)].strand = DNAStrand.FINANCIAL_STRAND;

        // Compliance Strand
        nucleus.chromosomes[uint256(DNAStrand.COMPLIANCE_STRAND)].chromosomeId =
            keccak256(abi.encodePacked("ComplianceChromosome", block.timestamp));
        nucleus.chromosomes[uint256(DNAStrand.COMPLIANCE_STRAND)].nameHash = keccak256(abi.encodePacked("Compliance Chromosome"));
        nucleus.chromosomes[uint256(DNAStrand.COMPLIANCE_STRAND)].strand = DNAStrand.COMPLIANCE_STRAND;

        // Settlement Strand
        nucleus.chromosomes[uint256(DNAStrand.SETTLEMENT_STRAND)].chromosomeId =
            keccak256(abi.encodePacked("SettlementChromosome", block.timestamp));
        nucleus.chromosomes[uint256(DNAStrand.SETTLEMENT_STRAND)].nameHash = keccak256(abi.encodePacked("Settlement Chromosome"));
        nucleus.chromosomes[uint256(DNAStrand.SETTLEMENT_STRAND)].strand = DNAStrand.SETTLEMENT_STRAND;

        // Oracle Strand
        nucleus.chromosomes[uint256(DNAStrand.ORACLE_STRAND)].chromosomeId =
            keccak256(abi.encodePacked("OracleChromosome", block.timestamp));
        nucleus.chromosomes[uint256(DNAStrand.ORACLE_STRAND)].nameHash = keccak256(abi.encodePacked("Oracle Chromosome"));
        nucleus.chromosomes[uint256(DNAStrand.ORACLE_STRAND)].strand = DNAStrand.ORACLE_STRAND;

        // Token Strand
        nucleus.chromosomes[uint256(DNAStrand.TOKEN_STRAND)].chromosomeId =
            keccak256(abi.encodePacked("TokenChromosome", block.timestamp));
        nucleus.chromosomes[uint256(DNAStrand.TOKEN_STRAND)].nameHash = keccak256(abi.encodePacked("Token Chromosome"));
        nucleus.chromosomes[uint256(DNAStrand.TOKEN_STRAND)].strand = DNAStrand.TOKEN_STRAND;

        // Infrastructure Strand
        nucleus.chromosomes[uint256(DNAStrand.INFRASTRUCTURE_STRAND)].chromosomeId =
            keccak256(abi.encodePacked("InfrastructureChromosome", block.timestamp));
        nucleus.chromosomes[uint256(DNAStrand.INFRASTRUCTURE_STRAND)].nameHash = keccak256(abi.encodePacked("Infrastructure Chromosome"));
        nucleus.chromosomes[uint256(DNAStrand.INFRASTRUCTURE_STRAND)].strand = DNAStrand.INFRASTRUCTURE_STRAND;
    }

    /**
     * @notice Add a gene to the DNA structure
     */
    function addGene(
        DNAStrand _strand,
        DNAHelix _helix,
        DNABasePair _basePair,
        bytes32 _nameHash,
        bytes32 _descriptionHash,
        address _contractAddress,
        string memory _ipfsHash, // IPFS hash of contract code/metadata
        bytes32 _parentGene
    ) public onlyOwner returns (bytes32) {
        bytes32 geneId = keccak256(abi.encodePacked(
            _strand, _helix, _nameHash, _contractAddress, block.timestamp
        ));

        DNAGene storage gene = genes[geneId];
        gene.geneId = geneId;
        gene.strand = _strand;
        gene.helix = _helix;
        gene.basePair = _basePair;
        gene.nameHash = _nameHash;
        gene.descriptionHash = _descriptionHash;
        gene.contractAddress = _contractAddress;
        // gene.ipfsHash = _ipfsHash; // Stored in ipfsHashes mapping
        gene.parentGene = _parentGene;
        gene.isActive = true;
        gene.lastReplication = block.timestamp;

        // Add to parent gene's children if parent exists
        if (_parentGene != bytes32(0)) {
            genes[_parentGene].childGenes.push(geneId);
        }

        // Add to chromosome
        DNAChromosome storage chromosome = nucleus.chromosomes[uint256(_strand)];
        chromosome.genes.push(geneId);
        chromosome.geneCount++;

        nucleus.totalGenes++;
        nucleus.activeGenes++;

        // Store IPFS hash
        ipfsHashes[geneId] = _ipfsHash;

        emit GeneActivated(geneId, _strand, _helix);
        return geneId;
    }

    /**
     * @notice Activate/deactivate a gene
     */
    function setGeneActivity(bytes32 _geneId, bool _active, string memory _reason) public onlyOwner
        validGene(_geneId)
    {
        genes[_geneId].isActive = _active;

        if (_active) {
            nucleus.activeGenes++;
            emit GeneActivated(_geneId, genes[_geneId].strand, genes[_geneId].helix);
        } else {
            nucleus.activeGenes--;
            emit GeneDeactivated(_geneId, _reason);
        }
    }

    /**
     * @notice Start chromosome replication
     */
    function startReplication(DNAStrand _strand) public onlyOwner {
        DNAChromosome storage chromosome = nucleus.chromosomes[uint256(_strand)];
        require(!chromosome.isReplicating, "Already replicating");

        chromosome.isReplicating = true;
        chromosome.replicationProgress = 0;

        nucleus.replicationCycle++;

        emit ReplicationStarted(chromosome.chromosomeId, _strand);
    }

    /**
     * @notice Complete chromosome replication
     */
    function completeReplication(DNAStrand _strand, string memory _ipfsMetadataHash) public onlyOwner
    {
        DNAChromosome storage chromosome = nucleus.chromosomes[uint256(_strand)];
        require(chromosome.isReplicating, "Not replicating");

        chromosome.isReplicating = false;
        chromosome.replicationProgress = 100;
        chromosome.ipfsMetadataHash = keccak256(abi.encodePacked(_ipfsMetadataHash));

        emit ReplicationCompleted(chromosome.chromosomeId, chromosome.geneCount);
    }

    /**
     * @notice Execute AI command
     */
    function executeAICommand(
        bytes32 _commandHash,
        bytes memory _parameters,
        bytes32 _ipfsResultHash
    ) public onlyAIAgent returns (bytes32) {
        bytes32 commandId = keccak256(abi.encodePacked(
            msg.sender, _commandHash, block.timestamp
        ));

        AICommand storage aiCommand = aiCommands[commandId];
        aiCommand.commandId = commandId;
        aiCommand.aiAgent = msg.sender;
        aiCommand.commandHash = _commandHash;
        aiCommand.parameters = _parameters;
        aiCommand.timestamp = block.timestamp;
        aiCommand.executed = true;
        aiCommand.ipfsResultHash = _ipfsResultHash;
        aiCommand.resultHash = _ipfsResultHash; // resultHash is already a bytes32, no need to hash again

        aiCommandCount++;

        emit AICommandExecuted(commandId, msg.sender, true);
        return commandId;
    }

    /**
     * @notice System heartbeat - called by AI agents
     */
    function systemHeartbeat(bool _healthy, string memory _statusReport) public onlyAIAgent {
        nucleus.lastHeartbeat = block.timestamp;

        if (!_healthy && !emergencyMode) {
            emergencyMode = true;
            emit EmergencyModeActivated(_statusReport);
        } else if (_healthy && emergencyMode) {
            emergencyMode = false;
        }

        emit SystemHeartbeat(block.timestamp, _healthy);
    }

    /**
     * @notice Update genome IPFS hash
     */
    function updateGenomeHash(string memory _newGenomeHash) public onlyOwner {
        genomeIpfsHash = _newGenomeHash;
        nucleus.ipfsGenomeHash = keccak256(abi.encodePacked(_newGenomeHash));

        emit GenomeUpdated(_newGenomeHash);
    }

    /**
     * @notice Set genetic marker on a gene
     */
    function setGeneticMarker(bytes32 _geneId, bytes32 _key, bytes32 _value) public onlyOwner
        validGene(_geneId)
    {
        genes[_geneId].geneticMarkers[_key] = _value;
    }

    /**
     * @notice Authorize AI agent
     */
    function authorizeAIAgent(address _agent, bool _authorized) public onlyOwner {
        authorizedAIAgents[_agent] = _authorized;
    }

    /**
     * @notice Set AI swarm coordinator
     */
    function setAISwarmCoordinator(address _coordinator) public onlyOwner {
        aiSwarmCoordinator = _coordinator;
        authorizedAIAgents[_coordinator] = true;
    }

    /**
     * @notice Get gene details
     */
    function getGene(bytes32 _geneId) public view
        returns (
            DNAStrand strand,
            DNAHelix helix,
            bytes32 nameHash,
            address contractAddress,
            bool isActive,
            uint256 expressionLevel,
            bytes32 parentGene,
            uint256 childCount
        )
    {
        DNAGene storage gene = genes[_geneId];
        return (
            gene.strand,
            gene.helix,
            gene.nameHash,
            gene.contractAddress,
            gene.isActive,
            gene.expressionLevel,
            gene.parentGene,
            gene.childGenes.length
        );
    }

    /**
     * @notice Get chromosome details
     */
    function getChromosome(DNAStrand _strand) public view
        returns (
            bytes32 nameHash,
            uint256 geneCount,
            uint256 totalExpression,
            bool isReplicating,
            uint256 replicationProgress
        )
    {
        DNAChromosome memory chromosome = nucleus.chromosomes[uint256(_strand)];
        return (
            chromosome.nameHash,
            chromosome.geneCount,
            chromosome.totalExpression,
            chromosome.isReplicating,
            chromosome.replicationProgress
        );
    }

    /**
     * @notice Get nucleus status
     */
    function getNucleusStatus() public view
        returns (
            bytes32 organismNameHash,
            uint256 totalGenes,
            uint256 activeGenes,
            bool isAlive,
            uint256 lastHeartbeat,
            bool emergencyMode,
            uint256 replicationCycle
        )
    {
        return (
            nucleus.organismNameHash,
            nucleus.totalGenes,
            nucleus.activeGenes,
            nucleus.isAlive,
            nucleus.lastHeartbeat,
            emergencyMode,
            nucleus.replicationCycle
        );
    }

    /**
     * @notice Get AI command details
     */
    function getAICommand(bytes32 _commandId) public view
        returns (
            address aiAgent,
            bytes32 commandHash,
            uint256 timestamp,
            bool executed,
            bytes32 ipfsResultHash
        )
    {
        AICommand memory cmd = aiCommands[_commandId];
        return (
            cmd.aiAgent,
            cmd.commandHash,
            cmd.timestamp,
            cmd.executed,
            cmd.ipfsResultHash
        );
    }

    /**
     * @notice Get genetic marker
     */
    function getGeneticMarker(bytes32 _geneId, bytes32 _key) public view
        returns (bytes32)
    {
        return genes[_geneId].geneticMarkers[_key];
    }

    /**
     * @notice Get chromosome genes
     */
    function getChromosomeGenes(DNAStrand _strand) public view
        returns (bytes32[] memory)
    {
        return nucleus.chromosomes[uint256(_strand)].genes;
    }

    /**
     * @notice Get gene children
     */
    function getGeneChildren(bytes32 _geneId) public view
        returns (bytes32[] memory)
    {
        return genes[_geneId].childGenes;
    }

    /**
     * @notice Emergency system shutdown
     */
    function emergencyShutdown(string memory _reason) public onlyOwner {
        nucleus.isAlive = false;
        emergencyMode = true;

        emit EmergencyModeActivated(string(abi.encodePacked("EMERGENCY SHUTDOWN: ", _reason)));
    }

    /**
     * @notice Emergency system restart
     */
    function emergencyRestart() public onlyOwner {
        require(!nucleus.isAlive, "System already alive");

        nucleus.isAlive = true;
        nucleus.lastHeartbeat = block.timestamp;
        emergencyMode = false;
    }
}
