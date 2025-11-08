// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UnykornDNACore} from "./UnykornDNACore.sol";

/**
 * @title ChainInfrastructure
 * @notice Manages Unykorn Layer 1 blockchain infrastructure with public/private separation
 * @dev Handles chain deployment, privacy groups, explorer integration, and verification
 */
contract ChainInfrastructure is Ownable, ReentrancyGuard {

    enum ChainMode {
        PUBLIC,         // Fully public blockchain
        HYBRID,         // Public with private components
        PRIVATE,        // Permissioned private blockchain
        CONSORTIUM      // Multi-party consortium
    }

    enum PrivacyLevel {
        PUBLIC,         // Fully visible
        RESTRICTED,     // Limited visibility
        PRIVATE,        // Confidential
        ENCRYPTED       // Encrypted data
    }

    enum NodeType {
        VALIDATOR,      // Consensus validator
        ARCHIVE,        // Full history node
        LIGHT,          // Light client
        EXPLORER,       // Block explorer
        API,            // API endpoint
        PRIVATE         // Private infrastructure
    }

    struct ChainConfig {
        ChainMode mode;
        uint256 chainId;
        bytes32 chainNameHash;
        address genesisValidator;
        uint256 blockTime;           // seconds
        uint256 gasLimit;
        uint256 maxValidators;
        bool privacyEnabled;
        bytes32 genesisHash;
        uint256 launchTimestamp;
    }

    struct NodeConfig {
        NodeType nodeType;
        address nodeAddress;
        bytes32 endpointHash;
        PrivacyLevel privacyLevel;
        bool isActive;
        uint256 stakeAmount;
        bytes32 publicKey;
        bytes32 ipfsConfigHash;
    }

    struct PrivacyGroup {
        bytes32 groupId;
        bytes32 nameHash;
        PrivacyLevel privacyLevel;
        address[] members;
        bytes32[] privateContracts;
        mapping(address => bool) authorizedViewers;
        bool isActive;
        bytes32 ipfsMetadataHash;
    }

    struct ExplorerConfig {
        bytes32 explorerUrlHash;
        address explorerContract;
        PrivacyLevel publicDataLevel;
        bool realTimeUpdates;
        bytes32[] publicContractTags;
        mapping(bytes32 => PrivacyLevel) contractPrivacy;
        uint256 updateInterval;
    }

    struct VerificationProof {
        bytes32 proofId;
        bytes32 targetHash;
        address verifier;
        uint256 timestamp;
        bytes32 merkleRoot;
        bytes32[] proofPath;
        bool isValid;
        bytes32 verificationMethodHash;
        bytes32 ipfsEvidenceHash;
    }

    // Core configuration
    ChainConfig public chainConfig;
    ExplorerConfig public explorerConfig;

    // Node management
    mapping(address => NodeConfig) public nodeConfigs;
    address[] public activeNodes;
    mapping(NodeType => address[]) public nodesByType;

    // Privacy groups
    mapping(bytes32 => PrivacyGroup) public privacyGroups;
    bytes32[] public activeGroups;

    // Verification proofs
    mapping(bytes32 => VerificationProof) public verificationProofs;
    bytes32[] public proofHistory;

    // Access control
    mapping(address => PrivacyLevel) public addressPrivacy;
    mapping(bytes32 => PrivacyLevel) public contractPrivacy;

    // Events
    event ChainLaunched(uint256 chainId, ChainMode mode, uint256 timestamp);
    event NodeRegistered(address indexed nodeAddress, NodeType nodeType);
    event PrivacyGroupCreated(bytes32 indexed groupId, bytes32 nameHash, PrivacyLevel level);
    event ContractPrivacySet(address indexed contractAddress, PrivacyLevel level);
    event VerificationProofSubmitted(bytes32 indexed proofId, bytes32 targetHash, bool isValid);
    event ExplorerUpdated(bytes32 explorerUrlHash, PrivacyLevel publicDataLevel);

    modifier onlyGenesisValidator() {
        require(msg.sender == chainConfig.genesisValidator, "Not genesis validator");
        _;
    }

    modifier validPrivacyGroup(bytes32 _groupId) {
        require(privacyGroups[_groupId].isActive, "Privacy group not active");
        _;
    }

    constructor(
        uint256 _chainId,
        bytes32 _chainNameHash,
        ChainMode _mode,
        bool _privacyEnabled
    ) Ownable(msg.sender) {
        chainConfig = ChainConfig({
            mode: _mode,
            chainId: _chainId,
            chainNameHash: _chainNameHash,
            genesisValidator: msg.sender,
            blockTime: 2,              // 2 seconds like Ethereum
            gasLimit: 30_000_000,      // 30M gas limit
            maxValidators: 100,
            privacyEnabled: _privacyEnabled,
            genesisHash: bytes32(0),   // Set during launch
            launchTimestamp: 0
        });
    }

    /**
     * @notice Launch the Unykorn Layer 1 blockchain
     */
    function launchChain(
        address _dnaCore,
        string memory _genesisData,
        bytes32 _explorerUrlHash
    ) public onlyGenesisValidator {
        require(chainConfig.launchTimestamp == 0, "Chain already launched");

        chainConfig.launchTimestamp = block.timestamp;
        chainConfig.genesisHash = keccak256(abi.encodePacked(
            chainConfig.chainId,
            chainConfig.chainNameHash,
            _dnaCore,
            _genesisData,
            block.timestamp
        ));

        // Initialize explorer
        explorerConfig.explorerUrlHash = _explorerUrlHash;
        explorerConfig.explorerContract = address(this);
        explorerConfig.publicDataLevel = chainConfig.mode == ChainMode.PUBLIC ?
            PrivacyLevel.PUBLIC : PrivacyLevel.RESTRICTED;
        explorerConfig.realTimeUpdates = true;
        explorerConfig.updateInterval = 12; // 12 seconds

        // Register genesis validator
        _registerNode(msg.sender, NodeType.VALIDATOR, PrivacyLevel.PRIVATE);

        emit ChainLaunched(chainConfig.chainId, chainConfig.mode, block.timestamp);
    }

    /**
     * @notice Register a node in the infrastructure
     */
    function registerNode(
        address _nodeAddress,
        NodeType _nodeType,
        bytes32 _endpointHash,
        bytes32 _publicKey,
        bytes32 _ipfsConfigHash
    ) public onlyOwner {
        _registerNode(_nodeAddress, _nodeType, _endpointHash, _publicKey, _ipfsConfigHash);
    }

    /**
     * @notice Create a privacy group for confidential operations
     */
    function createPrivacyGroup(
        bytes32 _nameHash,
        PrivacyLevel _privacyLevel,
        address[] memory _members,
        string memory _ipfsMetadataHash
    ) public onlyOwner returns (bytes32) {
        bytes32 groupId = keccak256(abi.encodePacked(
            _nameHash, _privacyLevel, _members.length, block.timestamp
        ));

        PrivacyGroup storage group = privacyGroups[groupId];
        group.groupId = groupId;
        group.nameHash = _nameHash;
        group.privacyLevel = _privacyLevel;
        group.members = _members;
        group.isActive = true;
        group.ipfsMetadataHash = keccak256(abi.encodePacked(_ipfsMetadataHash));

        // Set member authorizations
        for (uint256 i = 0; i < _members.length; i++) {
            group.authorizedViewers[_members[i]] = true;
        }

        activeGroups.push(groupId);

        emit PrivacyGroupCreated(groupId, _nameHash, _privacyLevel);
        return groupId;
    }

    /**
     * @notice Add contract to privacy group
     */
    function addContractToPrivacyGroup(
        bytes32 _groupId,
        address _contractAddress
    ) public onlyOwner validPrivacyGroup(_groupId) {
        PrivacyGroup storage group = privacyGroups[_groupId];
        group.privateContracts.push(bytes32(uint256(uint160(_contractAddress))));

        contractPrivacy[bytes32(uint256(uint160(_contractAddress)))] = group.privacyLevel;
    }

    /**
     * @notice Set contract privacy level
     */
    function setContractPrivacy(
        address _contractAddress,
        PrivacyLevel _privacyLevel
    ) public onlyOwner {
        bytes32 contractId = bytes32(uint256(uint160(_contractAddress)));
        contractPrivacy[contractId] = _privacyLevel;

        // Add to explorer public tags if public
        if (_privacyLevel == PrivacyLevel.PUBLIC) {
            explorerConfig.publicContractTags.push(contractId);
        }

        emit ContractPrivacySet(_contractAddress, _privacyLevel);
    }

    /**
     * @notice Submit verification proof
     */
    function submitVerificationProof(
        bytes32 _targetHash,
        bytes32 _merkleRoot,
        bytes32[] memory _proofPath,
        bytes32 _verificationMethodHash,
        string memory _ipfsEvidenceHash
    ) public returns (bytes32) {
        bytes32 proofId = keccak256(abi.encodePacked(
            _targetHash, msg.sender, block.timestamp
        ));

        // Verify proof (simplified Merkle proof verification)
        bool isValid = _verifyMerkleProof(_targetHash, _merkleRoot, _proofPath);

        VerificationProof storage proof = verificationProofs[proofId];
        proof.proofId = proofId;
        proof.targetHash = _targetHash;
        proof.verifier = msg.sender;
        proof.timestamp = block.timestamp;
        proof.merkleRoot = _merkleRoot;
        proof.proofPath = _proofPath;
        proof.isValid = isValid;
        proof.verificationMethodHash = _verificationMethodHash;
        proof.ipfsEvidenceHash = keccak256(abi.encodePacked(_ipfsEvidenceHash));

        proofHistory.push(proofId);

        emit VerificationProofSubmitted(proofId, _targetHash, isValid);
        return proofId;
    }

    /**
     * @notice Get chain information for explorer
     */
    function getChainInfo() public view returns (
        uint256 chainId,
        bytes32 chainNameHash,
        ChainMode mode,
        uint256 blockTime,
        uint256 validatorCount,
        bool privacyEnabled,
        bytes32 explorerUrlHash
    ) {
        return (
            chainConfig.chainId,
            chainConfig.chainNameHash,
            chainConfig.mode,
            chainConfig.blockTime,
            activeNodes.length,
            chainConfig.privacyEnabled,
            explorerConfig.explorerUrlHash
        );
    }

    /**
     * @notice Get public contract list for explorer
     */
    function getPublicContracts() public view returns (
        address[] memory contracts,
        string[] memory names,
        PrivacyLevel[] memory privacyLevels
    ) {
        uint256 publicCount = 0;
        for (uint256 i = 0; i < explorerConfig.publicContractTags.length; i++) {
            if (contractPrivacy[explorerConfig.publicContractTags[i]] == PrivacyLevel.PUBLIC) {
                publicCount++;
            }
        }

        address[] memory publicContracts = new address[](publicCount);
        string[] memory contractNames = new string[](publicCount);
        PrivacyLevel[] memory privacyLevels_ = new PrivacyLevel[](publicCount);

        uint256 index = 0;
        for (uint256 i = 0; i < explorerConfig.publicContractTags.length; i++) {
            bytes32 contractId = explorerConfig.publicContractTags[i];
            if (contractPrivacy[contractId] == PrivacyLevel.PUBLIC) {
                address contractAddr = address(uint160(uint256(contractId)));
                publicContracts[index] = contractAddr;
                // Contract names would be looked up from a registry
                contractNames[index] = "Public Contract";
                privacyLevels_[index] = PrivacyLevel.PUBLIC;
                index++;
            }
        }

        return (publicContracts, contractNames, privacyLevels_);
    }

    /**
     * @notice Check if address can view private data
     */
    function canViewPrivateData(address _viewer, bytes32 _groupId) public view returns (bool) {
        if (chainConfig.mode == ChainMode.PUBLIC) return true;
        if (contractPrivacy[_groupId] == PrivacyLevel.PUBLIC) return true;

        PrivacyGroup storage group = privacyGroups[_groupId];
        return group.authorizedViewers[_viewer];
    }

    /**
     * @notice Get privacy group members
     */
    function getPrivacyGroupMembers(bytes32 _groupId) public view
        validPrivacyGroup(_groupId)
        returns (address[] memory)
    {
        return privacyGroups[_groupId].members;
    }

    /**
     * @notice Get verification proof details
     */
    function getVerificationProof(bytes32 _proofId) public view
        returns (
            bytes32 targetHash,
            address verifier,
            uint256 timestamp,
            bool isValid,
            bytes32 verificationMethodHash
        )
    {
        VerificationProof memory proof = verificationProofs[_proofId];
        return (
            proof.targetHash,
            proof.verifier,
            proof.timestamp,
            proof.isValid,
            proof.verificationMethodHash
        );
    }

    /**
     * @notice Update explorer configuration
     */
    function updateExplorerConfig(
        bytes32 _explorerUrlHash,
        PrivacyLevel _publicDataLevel,
        uint256 _updateInterval
    ) public onlyOwner {
        explorerConfig.explorerUrlHash = _explorerUrlHash;
        explorerConfig.publicDataLevel = _publicDataLevel;
        explorerConfig.updateInterval = _updateInterval;

        emit ExplorerUpdated(_explorerUrlHash, _publicDataLevel);
    }

    /**
     * @notice Get infrastructure statistics
     */
    function getInfrastructureStats() public view returns (
        uint256 totalNodes,
        uint256 totalActiveGroups,
        uint256 totalProofs,
        uint256 publicContracts,
        ChainMode mode,
        bool privacyEnabled
    ) {
        uint256 publicContractCount = 0;
        for (uint256 i = 0; i < explorerConfig.publicContractTags.length; i++) {
            if (contractPrivacy[explorerConfig.publicContractTags[i]] == PrivacyLevel.PUBLIC) {
                publicContractCount++;
            }
        }

        return (
            activeNodes.length,
            activeGroups.length,
            proofHistory.length,
            publicContractCount,
            chainConfig.mode,
            chainConfig.privacyEnabled
        );
    }

    // Internal functions
    function _registerNode(
        address _nodeAddress,
        NodeType _nodeType,
        bytes32 _endpointHash,
        bytes32 _publicKey,
        bytes32 _ipfsConfigHash
    ) internal {
        NodeConfig storage node = nodeConfigs[_nodeAddress];
        node.nodeType = _nodeType;
        node.nodeAddress = _nodeAddress;
        node.endpointHash = _endpointHash;
        node.privacyLevel = _nodeType == NodeType.PRIVATE ? PrivacyLevel.PRIVATE : PrivacyLevel.PUBLIC;
        node.isActive = true;
        node.publicKey = _publicKey;
        node.ipfsConfigHash = _ipfsConfigHash;

        activeNodes.push(_nodeAddress);
        nodesByType[_nodeType].push(_nodeAddress);

        emit NodeRegistered(_nodeAddress, _nodeType);
    }

    function _registerNode(address _nodeAddress, NodeType _nodeType, PrivacyLevel _privacyLevel) internal {
        _registerNode(_nodeAddress, _nodeType, bytes32(0), bytes32(0), bytes32(0));
    }

    function _verifyMerkleProof(
        bytes32 _leaf,
        bytes32 _root,
        bytes32[] memory _proof
    ) internal pure returns (bool) {
        bytes32 computedHash = _leaf;

        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == _root;
    }
}
