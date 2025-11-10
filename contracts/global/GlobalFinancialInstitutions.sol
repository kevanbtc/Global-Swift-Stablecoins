// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GlobalFinancialInstitutions
 * @notice Integration framework for IMF, World Bank, WEF, BIS, and global financial infrastructure
 * @dev Coordinates global financial institutions and their digital asset initiatives
 */
contract GlobalFinancialInstitutions is Ownable, ReentrancyGuard {

    enum InstitutionType {
        IMF,                    // International Monetary Fund
        WORLD_BANK,            // World Bank Group
        WEF,                   // World Economic Forum
        BIS,                   // Bank for International Settlements
        SWIFT,                 // Society for Worldwide Interbank Financial Telecommunication
        IOSCO,                 // International Organization of Securities Commissions
        BASEL_COMMITTEE,       // Basel Committee on Banking Supervision
        FATF,                  // Financial Action Task Force
        CENTRAL_BANK,          // National Central Banks
        REGULATORY_AUTHORITY,  // Financial Regulators
        DEVELOPMENT_BANK,      // Regional Development Banks
        SOVEREIGN_FUND         // Sovereign Wealth Funds
    }

    enum InitiativeStatus {
        PROPOSED,
        PILOTING,
        IMPLEMENTING,
        OPERATIONAL,
        DEPRECATED
    }

    enum DigitalAssetType {
        CBDC,                  // Central Bank Digital Currency
        SDR_BACKED_TOKEN,      // IMF SDR-backed tokens
        GREEN_BOND,           // Sustainable finance instruments
        DEVELOPMENT_TOKEN,    // Development finance tokens
        STABILITY_FUND,       // Macro-stability instruments
        INCLUSION_TOKEN       // Financial inclusion instruments
    }

    struct FinancialInstitution {
        bytes32 institutionId;
        string institutionName;
        InstitutionType institutionType;
        address institutionAddress;
        string jurisdiction;
        uint256 memberSince;
        uint256 votingPower;
        bool isActive;
        bytes32 governanceRights;
        mapping(bytes32 => bool) approvedInitiatives;
    }

    struct DigitalAssetInitiative {
        bytes32 initiativeId;
        string initiativeName;
        DigitalAssetType assetType;
        InstitutionType leadInstitution;
        InitiativeStatus status;
        uint256 launchDate;
        uint256 targetCompletion;
        uint256 fundingRequired;
        uint256 fundingReceived;
        bytes32[] participatingInstitutions;
        bytes32[] supportedStandards;
        string ipfsDocumentation;
        mapping(address => uint256) contributions;
        bool isMultilateral;
    }

    struct GlobalStandard {
        bytes32 standardId;
        string standardName;
        InstitutionType issuingBody;
        uint256 version;
        uint256 effectiveDate;
        bool isMandatory;
        bytes32[] implementingInitiatives;
        string ipfsSpecification;
        mapping(bytes32 => bool) compliantImplementations;
    }

    struct CrossBorderSettlement {
        bytes32 settlementId;
        bytes32 sourceInitiative;
        bytes32 targetInitiative;
        uint256 amount;
        address sender;
        address receiver;
        uint256 settlementDate;
        bytes32 complianceProof;
        bool isCompleted;
    }

    // Storage
    mapping(bytes32 => FinancialInstitution) public financialInstitutions;
    mapping(bytes32 => DigitalAssetInitiative) public digitalAssetInitiatives;
    mapping(bytes32 => GlobalStandard) public globalStandards;
    mapping(bytes32 => CrossBorderSettlement) public crossBorderSettlements;
    mapping(InstitutionType => bytes32[]) public institutionsByType;
    mapping(DigitalAssetType => bytes32[]) public initiativesByType;

    // Global governance
    uint256 public totalInstitutions;
    uint256 public totalInitiatives;
    uint256 public totalStandards;
    mapping(bytes32 => uint256) public institutionVotes;
    uint256 public governanceQuorum = 5000; // 50% BPS

    // Protocol parameters
    uint256 public minVotingPower = 1;
    uint256 public maxVotingPower = 1000;
    uint256 public initiativeFundingPeriod = 365 days;

    // Events
    event InstitutionRegistered(bytes32 indexed institutionId, string name, InstitutionType institutionType);
    event InitiativeLaunched(bytes32 indexed initiativeId, string name, DigitalAssetType assetType);
    event StandardEstablished(bytes32 indexed standardId, string name, InstitutionType issuingBody);
    event CrossBorderSettlementExecuted(bytes32 indexed settlementId, uint256 amount);
    event GovernanceVote(bytes32 indexed proposalId, bytes32 indexed institutionId, bool approve);

    modifier validInstitution(bytes32 _institutionId) {
        require(financialInstitutions[_institutionId].institutionAddress != address(0), "Institution not found");
        _;
    }

    modifier validInitiative(bytes32 _initiativeId) {
        require(digitalAssetInitiatives[_initiativeId].launchDate > 0, "Initiative not found");
        _;
    }

    modifier onlyInstitution(bytes32 _institutionId) {
        require(financialInstitutions[_institutionId].institutionAddress == msg.sender, "Not institution");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a financial institution
     */
    function registerInstitution(
        string memory _institutionName,
        InstitutionType _institutionType,
        string memory _jurisdiction,
        uint256 _votingPower
    ) public returns (bytes32) {
        require(_votingPower >= minVotingPower && _votingPower <= maxVotingPower, "Invalid voting power");

        bytes32 institutionId = keccak256(abi.encodePacked(
            _institutionName,
            _institutionType,
            msg.sender,
            block.timestamp
        ));

        require(financialInstitutions[institutionId].institutionAddress == address(0), "Institution already registered");

        FinancialInstitution storage institution = financialInstitutions[institutionId];
        institution.institutionId = institutionId;
        institution.institutionName = _institutionName;
        institution.institutionType = _institutionType;
        institution.institutionAddress = msg.sender;
        institution.jurisdiction = _jurisdiction;
        institution.memberSince = block.timestamp;
        institution.votingPower = _votingPower;
        institution.isActive = true;

        institutionsByType[_institutionType].push(institutionId);
        totalInstitutions++;

        emit InstitutionRegistered(institutionId, _institutionName, _institutionType);
        return institutionId;
    }

    /**
     * @notice Launch a digital asset initiative
     */
    function launchInitiative(
        string memory _initiativeName,
        DigitalAssetType _assetType,
        InstitutionType _leadInstitution,
        uint256 _fundingRequired,
        uint256 _targetCompletion,
        bytes32[] memory _supportedStandards,
        string memory _ipfsDocumentation,
        bool _isMultilateral
    ) public returns (bytes32) {
        require(_targetCompletion > block.timestamp, "Invalid completion date");

        bytes32 initiativeId = keccak256(abi.encodePacked(
            _initiativeName,
            _assetType,
            msg.sender,
            block.timestamp
        ));

        require(digitalAssetInitiatives[initiativeId].launchDate == 0, "Initiative already exists");

        DigitalAssetInitiative storage initiative = digitalAssetInitiatives[initiativeId];
        initiative.initiativeId = initiativeId;
        initiative.initiativeName = _initiativeName;
        initiative.assetType = _assetType;
        initiative.leadInstitution = _leadInstitution;
        initiative.status = InitiativeStatus.PILOTING;
        initiative.launchDate = block.timestamp;
        initiative.targetCompletion = _targetCompletion;
        initiative.fundingRequired = _fundingRequired;
        initiative.supportedStandards = _supportedStandards;
        initiative.ipfsDocumentation = _ipfsDocumentation;
        initiative.isMultilateral = _isMultilateral;

        initiativesByType[_assetType].push(initiativeId);
        totalInitiatives++;

        emit InitiativeLaunched(initiativeId, _initiativeName, _assetType);
        return initiativeId;
    }

    /**
     * @notice Establish a global standard
     */
    function establishStandard(
        string memory _standardName,
        InstitutionType _issuingBody,
        uint256 _version,
        bool _isMandatory,
        string memory _ipfsSpecification
    ) public onlyOwner returns (bytes32) {
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
        standard.effectiveDate = block.timestamp;
        standard.isMandatory = _isMandatory;
        standard.ipfsSpecification = _ipfsSpecification;

        totalStandards++;

        emit StandardEstablished(standardId, _standardName, _issuingBody);
        return standardId;
    }

    /**
     * @notice Contribute funding to an initiative
     */
    function contributeToInitiative(bytes32 _initiativeId) public payable validInitiative(_initiativeId) {
        DigitalAssetInitiative storage initiative = digitalAssetInitiatives[_initiativeId];
        require(initiative.status != InitiativeStatus.DEPRECATED, "Initiative deprecated");
        require(initiative.fundingReceived < initiative.fundingRequired, "Funding complete");

        uint256 contribution = msg.value;
        uint256 remaining = initiative.fundingRequired - initiative.fundingReceived;

        if (contribution > remaining) {
            contribution = remaining;
            // Refund excess
            payable(msg.sender).transfer(msg.value - contribution);
        }

        initiative.contributions[msg.sender] += contribution;
        initiative.fundingReceived += contribution;

        // Check if funding complete
        if (initiative.fundingReceived >= initiative.fundingRequired) {
            initiative.status = InitiativeStatus.IMPLEMENTING;
        }
    }

    /**
     * @notice Execute cross-border settlement
     */
    function executeCrossBorderSettlement(
        bytes32 _sourceInitiative,
        bytes32 _targetInitiative,
        address _receiver,
        uint256 _amount,
        bytes32 _complianceProof
    ) public validInitiative(_sourceInitiative) validInitiative(_targetInitiative) returns (bytes32) {
        bytes32 settlementId = keccak256(abi.encodePacked(
            _sourceInitiative,
            _targetInitiative,
            msg.sender,
            _receiver,
            _amount,
            block.timestamp
        ));

        CrossBorderSettlement storage settlement = crossBorderSettlements[settlementId];
        settlement.settlementId = settlementId;
        settlement.sourceInitiative = _sourceInitiative;
        settlement.targetInitiative = _targetInitiative;
        settlement.amount = _amount;
        settlement.sender = msg.sender;
        settlement.receiver = _receiver;
        settlement.settlementDate = block.timestamp;
        settlement.complianceProof = _complianceProof;
        settlement.isCompleted = true; // Simplified - in production would have proper settlement logic

        emit CrossBorderSettlementExecuted(settlementId, _amount);
        return settlementId;
    }

    /**
     * @notice Vote on governance proposal
     */
    function voteOnGovernance(
        bytes32 _proposalId,
        bytes32 _institutionId,
        bool _approve
    ) public validInstitution(_institutionId) onlyInstitution(_institutionId) {
        FinancialInstitution storage institution = financialInstitutions[_institutionId];
        require(institution.isActive, "Institution not active");

        // Simplified voting - in production would have proper proposal system
        if (_approve) {
            institutionVotes[_proposalId] += institution.votingPower;
        }

        emit GovernanceVote(_proposalId, _institutionId, _approve);
    }

    /**
     * @notice Certify implementation compliance
     */
    function certifyImplementation(
        bytes32 _standardId,
        bytes32 _implementationId,
        bool _compliant
    ) public onlyOwner {
        globalStandards[_standardId].compliantImplementations[_implementationId] = _compliant;
    }

    /**
     * @notice Update initiative status
     */
    function updateInitiativeStatus(
        bytes32 _initiativeId,
        InitiativeStatus _newStatus
    ) public validInitiative(_initiativeId) {
        DigitalAssetInitiative storage initiative = digitalAssetInitiatives[_initiativeId];
        // Only lead institution or governance can update
        require(msg.sender == owner() || _isLeadInstitution(initiative.leadInstitution, msg.sender), "Not authorized");

        initiative.status = _newStatus;
    }

    /**
     * @notice Get institution details
     */
    function getInstitution(bytes32 _institutionId) public view
        returns (
            string memory institutionName,
            InstitutionType institutionType,
            string memory jurisdiction,
            uint256 votingPower,
            bool isActive
        )
    {
        FinancialInstitution storage institution = financialInstitutions[_institutionId];
        return (
            institution.institutionName,
            institution.institutionType,
            institution.jurisdiction,
            institution.votingPower,
            institution.isActive
        );
    }

    /**
     * @notice Get initiative details
     */
    function getInitiative(bytes32 _initiativeId) public view
        returns (
            string memory initiativeName,
            DigitalAssetType assetType,
            InitiativeStatus status,
            uint256 fundingReceived,
            uint256 fundingRequired,
            bool isMultilateral
        )
    {
        DigitalAssetInitiative storage initiative = digitalAssetInitiatives[_initiativeId];
        return (
            initiative.initiativeName,
            initiative.assetType,
            initiative.status,
            initiative.fundingReceived,
            initiative.fundingRequired,
            initiative.isMultilateral
        );
    }

    /**
     * @notice Get global standard details
     */
    function getStandard(bytes32 _standardId) public view
        returns (
            string memory standardName,
            InstitutionType issuingBody,
            uint256 version,
            bool isMandatory
        )
    {
        GlobalStandard storage standard = globalStandards[_standardId];
        return (
            standard.standardName,
            standard.issuingBody,
            standard.version,
            standard.isMandatory
        );
    }

    /**
     * @notice Get cross-border settlement details
     */
    function getCrossBorderSettlement(bytes32 _settlementId) public view
        returns (
            bytes32 sourceInitiative,
            bytes32 targetInitiative,
            uint256 amount,
            address sender,
            address receiver,
            bool isCompleted
        )
    {
        CrossBorderSettlement memory settlement = crossBorderSettlements[_settlementId];
        return (
            settlement.sourceInitiative,
            settlement.targetInitiative,
            settlement.amount,
            settlement.sender,
            settlement.receiver,
            settlement.isCompleted
        );
    }

    /**
     * @notice Get institutions by type
     */
    function getInstitutionsByType(InstitutionType _type) public view
        returns (bytes32[] memory)
    {
        return institutionsByType[_type];
    }

    /**
     * @notice Get initiatives by type
     */
    function getInitiativesByType(DigitalAssetType _type) public view
        returns (bytes32[] memory)
    {
        return initiativesByType[_type];
    }

    /**
     * @notice Check if implementation is compliant
     */
    function isCompliantImplementation(bytes32 _standardId, bytes32 _implementationId) public view
        returns (bool)
    {
        return globalStandards[_standardId].compliantImplementations[_implementationId];
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _governanceQuorum,
        uint256 _minVotingPower,
        uint256 _maxVotingPower,
        uint256 _initiativeFundingPeriod
    ) public onlyOwner {
        governanceQuorum = _governanceQuorum;
        minVotingPower = _minVotingPower;
        maxVotingPower = _maxVotingPower;
        initiativeFundingPeriod = _initiativeFundingPeriod;
    }

    /**
     * @notice Get global statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalInstitutions,
            uint256 _totalInitiatives,
            uint256 _totalStandards
        )
    {
        return (totalInstitutions, totalInitiatives, totalStandards);
    }

    // Internal functions
    function _isLeadInstitution(InstitutionType _leadType, address _address) internal view returns (bool) {
        // Simplified check - in production would verify institution membership
        bytes32[] memory institutions = institutionsByType[_leadType];
        for (uint256 i = 0; i < institutions.length; i++) {
            if (financialInstitutions[institutions[i]].institutionAddress == _address) {
                return true;
            }
        }
        return false;
    }
}
