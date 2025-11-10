// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StakeholderRegistry
 * @notice Comprehensive stakeholder management for global financial system
 * @dev Manages all stakeholders: IMF, World Bank, Central Banks, Governments, Institutions, Citizens
 */
contract StakeholderRegistry is Ownable, ReentrancyGuard {

    enum StakeholderType {
        IMF,                    // International Monetary Fund
        WORLD_BANK,            // World Bank Group
        WEF,                   // World Economic Forum
        BIS,                   // Bank for International Settlements
        SWIFT,                 // Society for Worldwide Interbank Financial Telecommunication
        CENTRAL_BANK,          // National Central Banks
        COMMERCIAL_BANK,       // Commercial Banks
        INVESTMENT_BANK,       // Investment Banks
        SOVEREIGN_FUND,        // Sovereign Wealth Funds
        PENSION_FUND,          // Pension Funds
        INSURANCE_COMPANY,     // Insurance Companies
        ASSET_MANAGER,         // Asset Management Firms
        HEDGE_FUND,            // Hedge Funds
        PRIVATE_EQUITY,        // Private Equity Firms
        VENTURE_CAPITAL,       // Venture Capital Firms
        FAMILY_OFFICE,         // Family Offices
        ENDOWMENT,             // University Endowments
        FOUNDATION,            // Charitable Foundations
        CORPORATION,           // Public Corporations
        GOVERNMENT,            // National Governments
        REGULATOR,             // Financial Regulators
        EXCHANGE,              // Stock Exchanges
        CLEARING_HOUSE,        // Clearing Houses
        CUSTODIAN,             // Custodians
        AUDITOR,               // Audit Firms
        LAW_FIRM,              // Legal Firms
        CONSULTANT,            // Consulting Firms
        RATING_AGENCY,         // Credit Rating Agencies
        CITIZEN,               // Individual Citizens
        INSTITUTION            // Other Financial Institutions
    }

    enum Jurisdiction {
        UNITED_STATES,
        UNITED_KINGDOM,
        EUROPEAN_UNION,
        JAPAN,
        CHINA,
        SINGAPORE,
        SWITZERLAND,
        CANADA,
        AUSTRALIA,
        HONG_KONG,
        UNITED_ARAB_EMIRATES,
        INDIA,
        BRAZIL,
        SOUTH_KOREA,
        MEXICO,
        SOUTH_AFRICA,
        RUSSIA,
        SAUDI_ARABIA,
        INTERNATIONAL,         // IMF, BIS, etc.
        OTHER
    }

    enum AccreditationLevel {
        NONE,                  // No accreditation
        BASIC,                 // Basic KYC/AML
        QUALIFIED,             // Qualified Investor
        ACCREDITED,            // Accredited Investor
        INSTITUTIONAL,         // Institutional Investor
        SOVEREIGN,             // Sovereign/Government
        REGULATORY             // Regulatory Authority
    }

    enum VotingPower {
        NONE,                  // No voting rights
        OBSERVER,              // Observer status
        LIMITED,               // Limited voting
        STANDARD,              // Standard voting
        ENHANCED,              // Enhanced voting
        SUPER,                 // Super majority
        VETO                   // Veto power
    }

    struct Stakeholder {
        bytes32 stakeholderId;
        string name;
        string description;
        StakeholderType stakeholderType;
        Jurisdiction jurisdiction;
        AccreditationLevel accreditationLevel;
        VotingPower votingPower;
        address wallet;
        address custodian;          // Custodian wallet for assets
        uint256 registrationDate;
        uint256 lastActivity;
        uint256 totalAssets;        // Total assets under management
        uint256 votingWeight;       // Calculated voting weight
        bool isActive;
        bool isVerified;
        bool isBlacklisted;
        bytes32 kycHash;
        bytes32 accreditationHash;
        mapping(bytes32 => bool) permissions;
        mapping(bytes32 => uint256) holdings; // Asset holdings
    }

    struct StakeholderGroup {
        bytes32 groupId;
        string groupName;
        StakeholderType[] memberTypes;
        Jurisdiction[] jurisdictions;
        uint256 minVotingWeight;
        uint256 totalVotingWeight;
        bool requiresConsensus;
        bytes32[] policies;
        address groupAdmin;
    }

    struct GovernanceProposal {
        bytes32 proposalId;
        bytes32 groupId;
        string title;
        string description;
        address proposer;
        uint256 createdAt;
        uint256 votingDeadline;
        uint256 totalVotes;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
        bool executed;
        bytes32 executionHash;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) voteWeight;
    }

    // Storage
    mapping(bytes32 => Stakeholder) public stakeholders;
    mapping(bytes32 => StakeholderGroup) public stakeholderGroups;
    mapping(bytes32 => GovernanceProposal) public governanceProposals;
    mapping(address => bytes32) public walletToStakeholder;
    mapping(StakeholderType => bytes32[]) public stakeholdersByType;
    mapping(Jurisdiction => bytes32[]) public stakeholdersByJurisdiction;
    mapping(bytes32 => bytes32[]) public proposalsByGroup;

    // Global statistics
    uint256 public totalStakeholders;
    uint256 public totalActiveStakeholders;
    uint256 public totalVotingWeight;
    uint256 public totalAssetsUnderManagement;

    // Protocol parameters
    uint256 public minVotingWeight = 1;
    uint256 public maxVotingWeight = 1000000;
    uint256 public votingPeriod = 7 days;
    uint256 public proposalQuorum = 5000; // 50% BPS

    // Events
    event StakeholderRegistered(bytes32 indexed stakeholderId, string name, StakeholderType stakeholderType);
    event AccreditationUpdated(bytes32 indexed stakeholderId, AccreditationLevel level);
    event VotingPowerChanged(bytes32 indexed stakeholderId, VotingPower power);
    event GroupCreated(bytes32 indexed groupId, string name);
    event ProposalCreated(bytes32 indexed proposalId, bytes32 indexed groupId, string title);
    event VoteCast(bytes32 indexed proposalId, bytes32 indexed stakeholderId, bool approve, uint256 weight);

    modifier validStakeholder(bytes32 _stakeholderId) {
        require(stakeholders[_stakeholderId].wallet != address(0), "Stakeholder not found");
        _;
    }

    modifier onlyStakeholder(bytes32 _stakeholderId) {
        require(walletToStakeholder[msg.sender] == _stakeholderId, "Not stakeholder");
        _;
    }

    modifier activeStakeholder(bytes32 _stakeholderId) {
        require(stakeholders[_stakeholderId].isActive, "Stakeholder not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new stakeholder
     */
    function registerStakeholder(
        string memory _name,
        string memory _description,
        StakeholderType _stakeholderType,
        Jurisdiction _jurisdiction,
        address _custodian,
        bytes32 _kycHash
    ) public returns (bytes32) {
        require(walletToStakeholder[msg.sender] == bytes32(0), "Already registered");

        bytes32 stakeholderId = keccak256(abi.encodePacked(
            _name,
            _stakeholderType,
            msg.sender,
            block.timestamp
        ));

        require(stakeholders[stakeholderId].wallet == address(0), "Stakeholder already exists");

        Stakeholder storage stakeholder = stakeholders[stakeholderId];
        stakeholder.stakeholderId = stakeholderId;
        stakeholder.name = _name;
        stakeholder.description = _description;
        stakeholder.stakeholderType = _stakeholderType;
        stakeholder.jurisdiction = _jurisdiction;
        stakeholder.accreditationLevel = AccreditationLevel.NONE;
        stakeholder.votingPower = VotingPower.NONE;
        stakeholder.wallet = msg.sender;
        stakeholder.custodian = _custodian;
        stakeholder.registrationDate = block.timestamp;
        stakeholder.lastActivity = block.timestamp;
        stakeholder.isActive = true;
        stakeholder.kycHash = _kycHash;

        // Calculate initial voting weight
        stakeholder.votingWeight = _calculateInitialVotingWeight(_stakeholderType, _jurisdiction);

        walletToStakeholder[msg.sender] = stakeholderId;
        stakeholdersByType[_stakeholderType].push(stakeholderId);
        stakeholdersByJurisdiction[_jurisdiction].push(stakeholderId);

        totalStakeholders++;
        totalActiveStakeholders++;
        totalVotingWeight += stakeholder.votingWeight;

        emit StakeholderRegistered(stakeholderId, _name, _stakeholderType);
        return stakeholderId;
    }

    /**
     * @notice Update stakeholder accreditation
     */
    function updateAccreditation(
        bytes32 _stakeholderId,
        AccreditationLevel _level,
        bytes32 _accreditationHash
    ) public onlyOwner validStakeholder(_stakeholderId) {
        Stakeholder storage stakeholder = stakeholders[_stakeholderId];
        AccreditationLevel oldLevel = stakeholder.accreditationLevel;

        stakeholder.accreditationLevel = _level;
        stakeholder.accreditationHash = _accreditationHash;

        // Update voting power based on accreditation
        _updateVotingPower(_stakeholderId);

        emit AccreditationUpdated(_stakeholderId, _level);
    }

    /**
     * @notice Update stakeholder voting power
     */
    function updateVotingPower(
        bytes32 _stakeholderId,
        VotingPower _power
    ) public onlyOwner validStakeholder(_stakeholderId) {
        Stakeholder storage stakeholder = stakeholders[_stakeholderId];
        VotingPower oldPower = stakeholder.votingPower;

        stakeholder.votingPower = _power;

        // Recalculate voting weight
        stakeholder.votingWeight = _calculateVotingWeight(_stakeholderId);

        // Update global totals
        totalVotingWeight = totalVotingWeight - _calculateVotingWeightFromPower(oldPower) + stakeholder.votingWeight;

        emit VotingPowerChanged(_stakeholderId, _power);
    }

    /**
     * @notice Create a stakeholder group
     */
    function createStakeholderGroup(
        string memory _groupName,
        StakeholderType[] memory _memberTypes,
        Jurisdiction[] memory _jurisdictions,
        uint256 _minVotingWeight,
        bool _requiresConsensus
    ) public onlyOwner returns (bytes32) {
        bytes32 groupId = keccak256(abi.encodePacked(
            _groupName,
            msg.sender,
            block.timestamp
        ));

        require(stakeholderGroups[groupId].groupAdmin == address(0), "Group already exists");

        StakeholderGroup storage group = stakeholderGroups[groupId];
        group.groupId = groupId;
        group.groupName = _groupName;
        group.memberTypes = _memberTypes;
        group.jurisdictions = _jurisdictions;
        group.minVotingWeight = _minVotingWeight;
        group.requiresConsensus = _requiresConsensus;
        group.groupAdmin = msg.sender;

        emit GroupCreated(groupId, _groupName);
        return groupId;
    }

    /**
     * @notice Create a governance proposal
     */
    function createProposal(
        bytes32 _groupId,
        string memory _title,
        string memory _description
    ) public returns (bytes32) {
        require(stakeholderGroups[_groupId].groupAdmin != address(0), "Group not found");

        bytes32 stakeholderId = walletToStakeholder[msg.sender];
        require(stakeholderId != bytes32(0), "Not a registered stakeholder");

        // Check if stakeholder is eligible for this group
        require(_isEligibleForGroup(stakeholderId, _groupId), "Not eligible for group");

        bytes32 proposalId = keccak256(abi.encodePacked(
            _groupId,
            _title,
            msg.sender,
            block.timestamp
        ));

        GovernanceProposal storage proposal = governanceProposals[proposalId];
        proposal.proposalId = proposalId;
        proposal.groupId = _groupId;
        proposal.title = _title;
        proposal.description = _description;
        proposal.proposer = msg.sender;
        proposal.createdAt = block.timestamp;
        proposal.votingDeadline = block.timestamp + votingPeriod;

        proposalsByGroup[_groupId].push(proposalId);

        emit ProposalCreated(proposalId, _groupId, _title);
        return proposalId;
    }

    /**
     * @notice Cast a vote on a proposal
     */
    function castVote(
        bytes32 _proposalId,
        bool _approve
    ) public {
        GovernanceProposal storage proposal = governanceProposals[_proposalId];
        require(proposal.createdAt > 0, "Proposal not found");
        require(block.timestamp <= proposal.votingDeadline, "Voting period ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");

        bytes32 stakeholderId = walletToStakeholder[msg.sender];
        require(stakeholderId != bytes32(0), "Not a registered stakeholder");

        Stakeholder storage stakeholder = stakeholders[stakeholderId];
        require(stakeholder.isActive, "Stakeholder not active");

        uint256 voteWeight = stakeholder.votingWeight;
        proposal.hasVoted[msg.sender] = true;
        proposal.voteWeight[msg.sender] = voteWeight;

        if (_approve) {
            proposal.yesVotes += voteWeight;
        } else {
            proposal.noVotes += voteWeight;
        }
        proposal.totalVotes += voteWeight;

        emit VoteCast(_proposalId, stakeholderId, _approve, voteWeight);
    }

    /**
     * @notice Execute a passed proposal
     */
    function executeProposal(bytes32 _proposalId) public {
        GovernanceProposal storage proposal = governanceProposals[_proposalId];
        require(!proposal.executed, "Already executed");
        require(block.timestamp > proposal.votingDeadline, "Voting still open");

        StakeholderGroup memory group = stakeholderGroups[proposal.groupId];
        uint256 totalGroupWeight = _calculateGroupVotingWeight(proposal.groupId);

        // Check quorum
        uint256 quorumThreshold = (totalGroupWeight * proposalQuorum) / 10000;
        require(proposal.totalVotes >= quorumThreshold, "Quorum not reached");

        // Check approval
        if (group.requiresConsensus) {
            require(proposal.yesVotes > proposal.noVotes, "Consensus not reached");
        } else {
            require(proposal.yesVotes > totalGroupWeight / 2, "Simple majority not reached");
        }

        proposal.executed = true;
        proposal.executionHash = keccak256(abi.encodePacked(
            _proposalId,
            proposal.yesVotes,
            proposal.noVotes,
            block.timestamp
        ));

        // Execute proposal logic here (would be implemented based on proposal type)
        _executeProposalLogic(_proposalId);
    }

    /**
     * @notice Update stakeholder assets
     */
    function updateStakeholderAssets(
        bytes32 _stakeholderId,
        uint256 _newTotalAssets
    ) public onlyOwner validStakeholder(_stakeholderId) {
        Stakeholder storage stakeholder = stakeholders[_stakeholderId];
        uint256 oldAssets = stakeholder.totalAssets;

        stakeholder.totalAssets = _newTotalAssets;
        stakeholder.lastActivity = block.timestamp;

        totalAssetsUnderManagement = totalAssetsUnderManagement - oldAssets + _newTotalAssets;
    }

    /**
     * @notice Get stakeholder details
     */
    function getStakeholder(bytes32 _stakeholderId) public view
        returns (
            string memory name,
            StakeholderType stakeholderType,
            Jurisdiction jurisdiction,
            AccreditationLevel accreditationLevel,
            VotingPower votingPower,
            uint256 votingWeight,
            bool isActive,
            bool isVerified
        )
    {
        Stakeholder storage stakeholder = stakeholders[_stakeholderId];
        return (
            stakeholder.name,
            stakeholder.stakeholderType,
            stakeholder.jurisdiction,
            stakeholder.accreditationLevel,
            stakeholder.votingPower,
            stakeholder.votingWeight,
            stakeholder.isActive,
            stakeholder.isVerified
        );
    }

    /**
     * @notice Get proposal details
     */
    function getProposal(bytes32 _proposalId) public view
        returns (
            string memory title,
            string memory description,
            uint256 yesVotes,
            uint256 noVotes,
            uint256 totalVotes,
            uint256 votingDeadline,
            bool executed
        )
    {
        GovernanceProposal storage proposal = governanceProposals[_proposalId];
        return (
            proposal.title,
            proposal.description,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.totalVotes,
            proposal.votingDeadline,
            proposal.executed
        );
    }

    /**
     * @notice Check if stakeholder has permission
     */
    function hasPermission(bytes32 _stakeholderId, bytes32 _permission) public view
        returns (bool)
    {
        return stakeholders[_stakeholderId].permissions[_permission];
    }

    /**
     * @notice Get stakeholder asset holdings
     */
    function getStakeholderHoldings(bytes32 _stakeholderId, bytes32 _assetId) public view
        returns (uint256)
    {
        return stakeholders[_stakeholderId].holdings[_assetId];
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _minVotingWeight,
        uint256 _maxVotingWeight,
        uint256 _votingPeriod,
        uint256 _proposalQuorum
    ) public onlyOwner {
        minVotingWeight = _minVotingWeight;
        maxVotingWeight = _maxVotingWeight;
        votingPeriod = _votingPeriod;
        proposalQuorum = _proposalQuorum;
    }

    /**
     * @notice Get global stakeholder statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalStakeholders,
            uint256 _totalActiveStakeholders,
            uint256 _totalVotingWeight,
            uint256 _totalAssetsUnderManagement
        )
    {
        return (totalStakeholders, totalActiveStakeholders, totalVotingWeight, totalAssetsUnderManagement);
    }

    // Internal functions
    function _calculateInitialVotingWeight(StakeholderType _type, Jurisdiction _jurisdiction) internal pure returns (uint256) {
        uint256 baseWeight = 1;

        // Type-based weighting
        if (_type == StakeholderType.CENTRAL_BANK) baseWeight = 1000;
        else if (_type == StakeholderType.IMF || _type == StakeholderType.WORLD_BANK) baseWeight = 500;
        else if (_type == StakeholderType.COMMERCIAL_BANK) baseWeight = 100;
        else if (_type == StakeholderType.INSTITUTION) baseWeight = 50;
        else if (_type == StakeholderType.CITIZEN) baseWeight = 1;

        // Jurisdiction multiplier (simplified)
        if (_jurisdiction == Jurisdiction.INTERNATIONAL) baseWeight *= 2;

        return baseWeight;
    }

    function _calculateVotingWeight(bytes32 _stakeholderId) internal view returns (uint256) {
        Stakeholder storage stakeholder = stakeholders[_stakeholderId];
        uint256 baseWeight = _calculateInitialVotingWeight(stakeholder.stakeholderType, stakeholder.jurisdiction);

        // Accreditation multiplier
        if (stakeholder.accreditationLevel == AccreditationLevel.INSTITUTIONAL) baseWeight *= 2;
        else if (stakeholder.accreditationLevel == AccreditationLevel.SOVEREIGN) baseWeight *= 5;
        else if (stakeholder.accreditationLevel == AccreditationLevel.REGULATORY) baseWeight *= 10;

        // Voting power multiplier
        if (stakeholder.votingPower == VotingPower.ENHANCED) baseWeight *= 2;
        else if (stakeholder.votingPower == VotingPower.SUPER) baseWeight *= 3;
        else if (stakeholder.votingPower == VotingPower.VETO) baseWeight *= 5;

        // Cap at maximum
        if (baseWeight > maxVotingWeight) baseWeight = maxVotingWeight;

        return baseWeight;
    }

    function _calculateVotingWeightFromPower(VotingPower _power) internal pure returns (uint256) {
        // Simplified calculation - would be more complex in production
        if (_power == VotingPower.NONE) return 0;
        if (_power == VotingPower.OBSERVER) return 1;
        if (_power == VotingPower.LIMITED) return 10;
        if (_power == VotingPower.STANDARD) return 100;
        if (_power == VotingPower.ENHANCED) return 200;
        if (_power == VotingPower.SUPER) return 300;
        if (_power == VotingPower.VETO) return 500;
        return 0;
    }

    function _updateVotingPower(bytes32 _stakeholderId) internal {
        Stakeholder storage stakeholder = stakeholders[_stakeholderId];

        // Auto-update voting power based on accreditation
        if (stakeholder.accreditationLevel == AccreditationLevel.NONE) {
            stakeholder.votingPower = VotingPower.NONE;
        } else if (stakeholder.accreditationLevel == AccreditationLevel.BASIC) {
            stakeholder.votingPower = VotingPower.OBSERVER;
        } else if (stakeholder.accreditationLevel == AccreditationLevel.QUALIFIED) {
            stakeholder.votingPower = VotingPower.LIMITED;
        } else if (stakeholder.accreditationLevel == AccreditationLevel.ACCREDITED) {
            stakeholder.votingPower = VotingPower.STANDARD;
        } else if (stakeholder.accreditationLevel == AccreditationLevel.INSTITUTIONAL) {
            stakeholder.votingPower = VotingPower.ENHANCED;
        } else if (stakeholder.accreditationLevel == AccreditationLevel.SOVEREIGN) {
            stakeholder.votingPower = VotingPower.SUPER;
        } else if (stakeholder.accreditationLevel == AccreditationLevel.REGULATORY) {
            stakeholder.votingPower = VotingPower.VETO;
        }

        stakeholder.votingWeight = _calculateVotingWeight(_stakeholderId);
    }

    function _isEligibleForGroup(bytes32 _stakeholderId, bytes32 _groupId) internal view returns (bool) {
        Stakeholder storage stakeholder = stakeholders[_stakeholderId];
        StakeholderGroup memory group = stakeholderGroups[_groupId];

        // Check stakeholder type
        bool typeEligible = false;
        for (uint256 i = 0; i < group.memberTypes.length; i++) {
            if (stakeholder.stakeholderType == group.memberTypes[i]) {
                typeEligible = true;
                break;
            }
        }

        // Check jurisdiction
        bool jurisdictionEligible = false;
        for (uint256 i = 0; i < group.jurisdictions.length; i++) {
            if (stakeholder.jurisdiction == group.jurisdictions[i]) {
                jurisdictionEligible = true;
                break;
            }
        }

        // Check voting weight
        bool weightEligible = stakeholder.votingWeight >= group.minVotingWeight;

        return typeEligible && jurisdictionEligible && weightEligible;
    }

    function _calculateGroupVotingWeight(bytes32 _groupId) internal view returns (uint256) {
        StakeholderGroup memory group = stakeholderGroups[_groupId];
        // Simplified - would calculate actual voting weight of eligible members
        return group.totalVotingWeight > 0 ? group.totalVotingWeight : 10000; // Default
    }

    function _executeProposalLogic(bytes32 _proposalId) internal {
        // Implementation would depend on proposal type
        // This is a placeholder for actual execution logic
    }
}
