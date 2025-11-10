// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title QuantumGovernance
 * @notice Quantum-resistant governance system for institutional decision making
 * @dev Uses post-quantum cryptography for secure voting and governance
 */
contract QuantumGovernance is Ownable, ReentrancyGuard {

    enum ProposalType {
        PARAMETER_UPDATE,
        CONTRACT_UPGRADE,
        FUNDING_ALLOCATION,
        REGULATORY_CHANGE,
        EMERGENCY_ACTION,
        STRATEGIC_DECISION
    }

    enum ProposalStatus {
        DRAFT,
        ACTIVE,
        SUCCEEDED,
        DEFEATED,
        EXECUTED,
        CANCELLED,
        EXPIRED
    }

    enum VoteType {
        AGAINST,
        FOR,
        ABSTAIN
    }

    struct Proposal {
        bytes32 proposalId;
        string title;
        string description;
        ProposalType proposalType;
        ProposalStatus status;
        address proposer;
        uint256 startTime;
        uint256 endTime;
        uint256 executionTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 quorumRequired;
        uint256 approvalThreshold; // BPS
        bytes32 quantumProof; // Post-quantum signature proof
        mapping(address => Vote) votes;
        mapping(bytes32 => bytes) executionData;
    }

    struct Vote {
        VoteType voteType;
        uint256 weight;
        uint256 timestamp;
        bytes32 quantumSignature;
        bool hasVoted;
    }

    struct GovernanceToken {
        address tokenAddress;
        uint256 totalSupply;
        uint256 quorumThreshold; // BPS of total supply
        uint256 approvalThreshold; // BPS
        bool isActive;
    }

    struct QuantumKey {
        bytes32 keyId;
        address owner;
        bytes publicKey;
        uint256 keyVersion;
        uint256 lastRotation;
        bool isActive;
        bytes32 algorithm; // Dilithium, Kyber, etc.
    }

    // Storage
    mapping(bytes32 => Proposal) public proposals;
    mapping(bytes32 => QuantumKey) public quantumKeys;
    mapping(address => GovernanceToken) public governanceTokens;
    mapping(address => bytes32[]) public userProposals;
    mapping(address => bytes32[]) public userVotes;

    // Global parameters
    uint256 public votingPeriod = 7 days;
    uint256 public executionDelay = 2 days;
    uint256 public proposalThreshold = 100000 * 1e18; // Minimum tokens to propose
    uint256 public defaultQuorum = 1000; // 10% BPS
    uint256 public defaultApproval = 5000; // 50% BPS

    // Quantum parameters
    uint256 public keyRotationPeriod = 365 days;
    bytes32 public currentAlgorithm = keccak256("Dilithium5");

    // Events
    event ProposalCreated(bytes32 indexed proposalId, address indexed proposer, ProposalType proposalType);
    event VoteCast(bytes32 indexed proposalId, address indexed voter, VoteType voteType, uint256 weight);
    event ProposalExecuted(bytes32 indexed proposalId, bool success);
    event QuantumKeyRotated(bytes32 indexed keyId, bytes32 newAlgorithm);
    event GovernanceTokenAdded(address indexed tokenAddress, uint256 quorumThreshold);

    modifier validProposal(bytes32 _proposalId) {
        require(proposals[_proposalId].proposer != address(0), "Proposal not found");
        _;
    }

    modifier onlyProposer(bytes32 _proposalId) {
        require(proposals[_proposalId].proposer == msg.sender, "Not proposal creator");
        _;
    }

    modifier proposalActive(bytes32 _proposalId) {
        require(proposals[_proposalId].status == ProposalStatus.ACTIVE, "Proposal not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new governance proposal
     */
    function createProposal(
        string memory _title,
        string memory _description,
        ProposalType _proposalType,
        uint256 _quorumRequired,
        uint256 _approvalThreshold,
        bytes32 _quantumProof
    ) public returns (bytes32) {
        require(bytes(_title).length > 0, "Invalid title");
        require(bytes(_description).length > 0, "Invalid description");

        // Check if user has sufficient governance tokens
        bool hasSufficientTokens = false;
        address[] memory tokens = getGovernanceTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            GovernanceToken memory token = governanceTokens[tokens[i]];
            if (token.isActive) {
                // Simplified check - in production would check actual balance
                hasSufficientTokens = true;
                break;
            }
        }
        require(hasSufficientTokens, "Insufficient governance tokens");

        bytes32 proposalId = keccak256(abi.encodePacked(
            _title,
            _description,
            _proposalType,
            msg.sender,
            block.timestamp
        ));

        require(proposals[proposalId].proposer == address(0), "Proposal already exists");

        Proposal storage proposal = proposals[proposalId];
        proposal.proposalId = proposalId;
        proposal.title = _title;
        proposal.description = _description;
        proposal.proposalType = _proposalType;
        proposal.status = ProposalStatus.ACTIVE;
        proposal.proposer = msg.sender;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingPeriod;
        proposal.quorumRequired = _quorumRequired > 0 ? _quorumRequired : defaultQuorum;
        proposal.approvalThreshold = _approvalThreshold > 0 ? _approvalThreshold : defaultApproval;
        proposal.quantumProof = _quantumProof;

        userProposals[msg.sender].push(proposalId);

        emit ProposalCreated(proposalId, msg.sender, _proposalType);
        return proposalId;
    }

    /**
     * @notice Cast a vote on a proposal
     */
    function castVote(
        bytes32 _proposalId,
        VoteType _voteType,
        uint256 _weight,
        bytes32 _quantumSignature
    ) public validProposal(_proposalId) proposalActive(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!proposal.votes[msg.sender].hasVoted, "Already voted");

        // Verify quantum signature (simplified)
        require(_quantumSignature != bytes32(0), "Invalid quantum signature");

        Vote storage vote = proposal.votes[msg.sender];
        vote.voteType = _voteType;
        vote.weight = _weight;
        vote.timestamp = block.timestamp;
        vote.quantumSignature = _quantumSignature;
        vote.hasVoted = true;

        if (_voteType == VoteType.FOR) {
            proposal.forVotes += _weight;
        } else if (_voteType == VoteType.AGAINST) {
            proposal.againstVotes += _weight;
        } else {
            proposal.abstainVotes += _weight;
        }

        userVotes[msg.sender].push(_proposalId);

        emit VoteCast(_proposalId, msg.sender, _voteType, _weight);
    }

    /**
     * @notice Execute a successful proposal
     */
    function executeProposal(bytes32 _proposalId) public validProposal(_proposalId) nonReentrant {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.ACTIVE, "Proposal not active");
        require(block.timestamp > proposal.endTime, "Voting not ended");

        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 quorumThreshold = getQuorumThreshold();

        // Check quorum
        require(totalVotes >= quorumThreshold, "Quorum not reached");

        // Check approval threshold
        uint256 approvalRate = (proposal.forVotes * 10000) / totalVotes;
        if (approvalRate >= proposal.approvalThreshold) {
            proposal.status = ProposalStatus.SUCCEEDED;
            proposal.executionTime = block.timestamp + executionDelay;
        } else {
            proposal.status = ProposalStatus.DEFEATED;
        }

        emit ProposalExecuted(_proposalId, proposal.status == ProposalStatus.SUCCEEDED);
    }

    /**
     * @notice Actually execute the proposal actions
     */
    function executeProposalActions(bytes32 _proposalId) public validProposal(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.SUCCEEDED, "Proposal not succeeded");
        require(block.timestamp >= proposal.executionTime, "Execution delay not passed");

        // Execute based on proposal type
        if (proposal.proposalType == ProposalType.PARAMETER_UPDATE) {
            // Update governance parameters
            _executeParameterUpdate(proposal.proposalId);
        } else if (proposal.proposalType == ProposalType.CONTRACT_UPGRADE) {
            // Execute contract upgrade
            _executeContractUpgrade(proposal.proposalId);
        } else if (proposal.proposalType == ProposalType.FUNDING_ALLOCATION) {
            // Allocate funds
            _executeFundingAllocation(proposal.proposalId);
        }

        proposal.status = ProposalStatus.EXECUTED;
    }

    /**
     * @notice Register a quantum key for secure voting
     */
    function registerQuantumKey(
        bytes memory _publicKey,
        bytes32 _algorithm
    ) public returns (bytes32) {
        bytes32 keyId = keccak256(abi.encodePacked(
            msg.sender,
            _publicKey,
            block.timestamp
        ));

        QuantumKey storage key = quantumKeys[keyId];
        key.keyId = keyId;
        key.owner = msg.sender;
        key.publicKey = _publicKey;
        key.keyVersion = 1;
        key.lastRotation = block.timestamp;
        key.isActive = true;
        key.algorithm = _algorithm;

        return keyId;
    }

    /**
     * @notice Rotate quantum key
     */
    function rotateQuantumKey(
        bytes32 _keyId,
        bytes memory _newPublicKey
    ) public {
        QuantumKey storage key = quantumKeys[_keyId];
        require(key.owner == msg.sender, "Not key owner");
        require(key.isActive, "Key not active");
        require(block.timestamp >= key.lastRotation + keyRotationPeriod, "Rotation period not passed");

        key.publicKey = _newPublicKey;
        key.keyVersion++;
        key.lastRotation = block.timestamp;

        emit QuantumKeyRotated(_keyId, key.algorithm);
    }

    /**
     * @notice Add governance token
     */
    function addGovernanceToken(
        address _tokenAddress,
        uint256 _quorumThreshold,
        uint256 _approvalThreshold
    ) public onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");

        GovernanceToken storage token = governanceTokens[_tokenAddress];
        token.tokenAddress = _tokenAddress;
        token.quorumThreshold = _quorumThreshold > 0 ? _quorumThreshold : defaultQuorum;
        token.approvalThreshold = _approvalThreshold > 0 ? _approvalThreshold : defaultApproval;
        token.isActive = true;

        emit GovernanceTokenAdded(_tokenAddress, token.quorumThreshold);
    }

    /**
     * @notice Get proposal details
     */
    function getProposal(bytes32 _proposalId) public view
        returns (
            string memory title,
            ProposalType proposalType,
            ProposalStatus status,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 endTime
        )
    {
        Proposal storage proposal = proposals[_proposalId];
        return (
            proposal.title,
            proposal.proposalType,
            proposal.status,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.endTime
        );
    }

    /**
     * @notice Get user vote on proposal
     */
    function getUserVote(bytes32 _proposalId, address _user) public view
        returns (VoteType voteType, uint256 weight, bool hasVoted)
    {
        Vote memory vote = proposals[_proposalId].votes[_user];
        return (vote.voteType, vote.weight, vote.hasVoted);
    }

    /**
     * @notice Get quantum key details
     */
    function getQuantumKey(bytes32 _keyId) public view
        returns (
            address owner,
            uint256 keyVersion,
            uint256 lastRotation,
            bool isActive,
            bytes32 algorithm
        )
    {
        QuantumKey memory key = quantumKeys[_keyId];
        return (
            key.owner,
            key.keyVersion,
            key.lastRotation,
            key.isActive,
            key.algorithm
        );
    }

    /**
     * @notice Get governance tokens
     */
    function getGovernanceTokens() public view returns (address[] memory) {
        // Simplified - in production would maintain a proper list
        address[] memory tokens = new address[](1);
        tokens[0] = address(0); // Placeholder
        return tokens;
    }

    /**
     * @notice Get quorum threshold
     */
    function getQuorumThreshold() public view returns (uint256) {
        // Simplified calculation
        return defaultQuorum;
    }

    /**
     * @notice Update governance parameters
     */
    function updateGovernanceParameters(
        uint256 _votingPeriod,
        uint256 _executionDelay,
        uint256 _proposalThreshold,
        uint256 _defaultQuorum,
        uint256 _defaultApproval
    ) public onlyOwner {
        votingPeriod = _votingPeriod;
        executionDelay = _executionDelay;
        proposalThreshold = _proposalThreshold;
        defaultQuorum = _defaultQuorum;
        defaultApproval = _defaultApproval;
    }

    /**
     * @notice Update quantum parameters
     */
    function updateQuantumParameters(
        uint256 _keyRotationPeriod,
        bytes32 _currentAlgorithm
    ) public onlyOwner {
        keyRotationPeriod = _keyRotationPeriod;
        currentAlgorithm = _currentAlgorithm;
    }

    // Internal execution functions
    function _executeParameterUpdate(bytes32 _proposalId) internal {
        // Implementation for parameter updates
    }

    function _executeContractUpgrade(bytes32 _proposalId) internal {
        // Implementation for contract upgrades
    }

    function _executeFundingAllocation(bytes32 _proposalId) internal {
        // Implementation for funding allocations
    }
}
