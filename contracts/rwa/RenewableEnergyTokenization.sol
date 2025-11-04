// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RenewableEnergyTokenization
 * @notice Tokenization of renewable energy assets and carbon credits
 * @dev Supports solar, wind, hydro, geothermal, and carbon offset tokenization
 */
contract RenewableEnergyTokenization is Ownable, ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;

    enum EnergyType {
        SOLAR,
        WIND,
        HYDRO,
        GEOTHERMAL,
        BIOMASS,
        TIDAL,
        CARBON_CREDIT,
        RENEWABLE_CERTIFICATE
    }

    enum ProjectStatus {
        PROPOSED,
        VERIFIED,
        ACTIVE,
        SUSPENDED,
        RETIRED
    }

    enum CertificationStandard {
        IREC,           // International Renewable Energy Certificate
        RECS,           // Renewable Energy Certificate System
        TIGR,           // The International GHG Registry
        VERRA,          // Verified Carbon Standard
        GOLD_STANDARD,  // Gold Standard
        PLAN_VIVO,      // Plan Vivo
        AMERICAN_CARBON // American Carbon Registry
    }

    struct RenewableProject {
        bytes32 projectId;
        string projectName;
        string location;
        EnergyType energyType;
        CertificationStandard certification;
        ProjectStatus status;
        address projectOwner;
        address certifier;
        uint256 totalCapacity;      // kWh or tonnes CO2
        uint256 mintedTokens;
        uint256 availableTokens;
        uint256 tokenPrice;        // Price per token in wei
        uint256 certificationDate;
        uint256 expiryDate;
        uint256 lastVerification;
        string ipfsMetadata;
        bytes32 environmentalImpactHash;
        bool isRetired;
    }

    struct EnergyToken {
        bytes32 tokenId;
        bytes32 projectId;
        address owner;
        uint256 amount;
        uint256 mintDate;
        uint256 vestingPeriod;     // Lock-up period
        uint256 claimDate;         // When benefits can be claimed
        bool isRebasing;           // For yield-bearing tokens
        uint256 accumulatedYield;
        bytes32 provenanceHash;    // Supply chain provenance
    }

    struct CarbonOffset {
        bytes32 offsetId;
        bytes32 projectId;
        uint256 tonnesCO2;
        uint256 vintage;           // Year of offset generation
        string methodology;
        address verifier;
        bool isRetired;
        bytes32 serialNumber;
    }

    struct YieldDistribution {
        bytes32 projectId;
        uint256 totalYield;
        uint256 distributedYield;
        uint256 lastDistribution;
        uint256 distributionFrequency; // Seconds between distributions
        address yieldToken;
        uint256 yieldPerToken;     // Accumulated yield per token
    }

    // Storage
    mapping(bytes32 => RenewableProject) public renewableProjects;
    mapping(bytes32 => EnergyToken) public energyTokens;
    mapping(bytes32 => CarbonOffset) public carbonOffsets;
    mapping(bytes32 => YieldDistribution) public yieldDistributions;
    mapping(address => bytes32[]) public ownerTokens;
    mapping(address => bytes32[]) public ownerProjects;

    // Global statistics
    uint256 public totalProjects;
    uint256 public totalCapacity;      // Total energy capacity
    uint256 public totalOffsets;       // Total carbon offsets
    uint256 public totalMintedTokens;

    // Regulatory parameters
    uint256 public minCertificationValidity = 365 days;
    uint256 public maxTokenSupply = 1000000000 * 1e18; // 1B tokens max per project
    uint256 public minVerificationFrequency = 180 days; // 6 months

    // Events
    event ProjectRegistered(bytes32 indexed projectId, string name, EnergyType energyType);
    event TokensMinted(bytes32 indexed projectId, address indexed recipient, uint256 amount);
    event TokensBurned(bytes32 indexed tokenId, uint256 amount);
    event YieldDistributed(bytes32 indexed projectId, uint256 totalYield);
    event CarbonOffsetRetired(bytes32 indexed offsetId, uint256 tonnesCO2);
    event ProjectVerified(bytes32 indexed projectId, address verifier);

    modifier validProject(bytes32 _projectId) {
        require(renewableProjects[_projectId].projectOwner != address(0), "Project not found");
        _;
    }

    modifier onlyProjectOwner(bytes32 _projectId) {
        require(renewableProjects[_projectId].projectOwner == msg.sender, "Not project owner");
        _;
    }

    modifier projectActive(bytes32 _projectId) {
        require(renewableProjects[_projectId].status == ProjectStatus.ACTIVE, "Project not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new renewable energy project
     */
    function registerProject(
        string memory _projectName,
        string memory _location,
        EnergyType _energyType,
        CertificationStandard _certification,
        uint256 _totalCapacity,
        uint256 _tokenPrice,
        string memory _ipfsMetadata
    ) external whenNotPaused returns (bytes32) {
        require(_totalCapacity > 0, "Invalid capacity");
        require(bytes(_projectName).length > 0, "Invalid project name");
        require(bytes(_location).length > 0, "Invalid location");

        bytes32 projectId = keccak256(abi.encodePacked(
            _projectName,
            _location,
            _energyType,
            block.timestamp,
            msg.sender
        ));

        require(renewableProjects[projectId].projectOwner == address(0), "Project already exists");

        renewableProjects[projectId] = RenewableProject({
            projectId: projectId,
            projectName: _projectName,
            location: _location,
            energyType: _energyType,
            certification: _certification,
            status: ProjectStatus.PROPOSED,
            projectOwner: msg.sender,
            certifier: address(0),
            totalCapacity: _totalCapacity,
            mintedTokens: 0,
            availableTokens: _totalCapacity,
            tokenPrice: _tokenPrice,
            certificationDate: 0,
            expiryDate: 0,
            lastVerification: block.timestamp,
            ipfsMetadata: _ipfsMetadata,
            environmentalImpactHash: bytes32(0),
            isRetired: false
        });

        ownerProjects[msg.sender].push(projectId);
        totalProjects++;

        emit ProjectRegistered(projectId, _projectName, _energyType);
        return projectId;
    }

    /**
     * @notice Certify a renewable energy project
     */
    function certifyProject(
        bytes32 _projectId,
        uint256 _certificationDate,
        uint256 _expiryDate,
        bytes32 _environmentalImpactHash
    ) external onlyOwner validProject(_projectId) {
        RenewableProject storage project = renewableProjects[_projectId];
        require(project.status == ProjectStatus.PROPOSED, "Project not in proposed status");
        require(_expiryDate > block.timestamp, "Invalid expiry date");
        require(_expiryDate - _certificationDate >= minCertificationValidity, "Certification validity too short");

        project.certifier = msg.sender;
        project.certificationDate = _certificationDate;
        project.expiryDate = _expiryDate;
        project.environmentalImpactHash = _environmentalImpactHash;
        project.status = ProjectStatus.VERIFIED;

        emit ProjectVerified(_projectId, msg.sender);
    }

    /**
     * @notice Activate a certified project
     */
    function activateProject(bytes32 _projectId) external onlyProjectOwner(_projectId) validProject(_projectId) {
        RenewableProject storage project = renewableProjects[_projectId];
        require(project.status == ProjectStatus.VERIFIED, "Project not verified");
        require(project.certificationDate > 0, "Project not certified");
        require(block.timestamp < project.expiryDate, "Certification expired");

        project.status = ProjectStatus.ACTIVE;
    }

    /**
     * @notice Mint energy tokens for a project
     */
    function mintEnergyTokens(
        bytes32 _projectId,
        address _recipient,
        uint256 _amount,
        uint256 _vestingPeriod
    ) external onlyProjectOwner(_projectId) projectActive(_projectId) whenNotPaused returns (bytes32) {
        RenewableProject storage project = renewableProjects[_projectId];
        require(_amount > 0, "Invalid amount");
        require(project.mintedTokens + _amount <= project.totalCapacity, "Exceeds project capacity");
        require(project.availableTokens >= _amount, "Insufficient available tokens");

        // Calculate payment required
        uint256 paymentRequired = (_amount * project.tokenPrice) / 1e18;
        if (paymentRequired > 0) {
            // Transfer payment (assuming native token, can be modified for ERC20)
            require(msg.value >= paymentRequired, "Insufficient payment");
            payable(project.projectOwner).transfer(paymentRequired);

            // Refund excess
            if (msg.value > paymentRequired) {
                payable(msg.sender).transfer(msg.value - paymentRequired);
            }
        }

        bytes32 tokenId = keccak256(abi.encodePacked(
            _projectId,
            _recipient,
            _amount,
            block.timestamp
        ));

        energyTokens[tokenId] = EnergyToken({
            tokenId: tokenId,
            projectId: _projectId,
            owner: _recipient,
            amount: _amount,
            mintDate: block.timestamp,
            vestingPeriod: _vestingPeriod,
            claimDate: block.timestamp + _vestingPeriod,
            isRebasing: project.energyType != EnergyType.CARBON_CREDIT,
            accumulatedYield: 0,
            provenanceHash: keccak256(abi.encodePacked(_projectId, _recipient, _amount))
        });

        ownerTokens[_recipient].push(tokenId);
        project.mintedTokens += _amount;
        project.availableTokens -= _amount;
        totalMintedTokens += _amount;

        emit TokensMinted(_projectId, _recipient, _amount);
        return tokenId;
    }

    /**
     * @notice Burn energy tokens (retire carbon credits)
     */
    function burnEnergyTokens(bytes32 _tokenId, uint256 _amount) external whenNotPaused {
        EnergyToken storage token = energyTokens[_tokenId];
        require(token.owner == msg.sender, "Not token owner");
        require(token.amount >= _amount, "Insufficient token balance");
        require(block.timestamp >= token.claimDate, "Tokens still vesting");

        RenewableProject storage project = renewableProjects[token.projectId];
        require(!project.isRetired, "Project retired");

        token.amount -= _amount;
        project.availableTokens += _amount;
        totalMintedTokens -= _amount;

        // Create carbon offset record if applicable
        if (project.energyType == EnergyType.CARBON_CREDIT) {
            bytes32 offsetId = keccak256(abi.encodePacked(
                _tokenId,
                _amount,
                block.timestamp
            ));

            carbonOffsets[offsetId] = CarbonOffset({
                offsetId: offsetId,
                projectId: token.projectId,
                tonnesCO2: _amount,
                vintage: block.timestamp / 31536000 + 1970, // Current year
                methodology: "Renewable Energy Tokenization",
                verifier: msg.sender,
                isRetired: true,
                serialNumber: keccak256(abi.encodePacked(offsetId))
            });

            totalOffsets += _amount;

            emit CarbonOffsetRetired(offsetId, _amount);
        }

        emit TokensBurned(_tokenId, _amount);
    }

    /**
     * @notice Distribute yield to token holders
     */
    function distributeYield(
        bytes32 _projectId,
        uint256 _totalYield,
        address _yieldToken
    ) external onlyProjectOwner(_projectId) projectActive(_projectId) whenNotPaused {
        require(_totalYield > 0, "Invalid yield amount");

        YieldDistribution storage distribution = yieldDistributions[_projectId];
        distribution.totalYield += _totalYield;
        distribution.lastDistribution = block.timestamp;
        distribution.yieldToken = _yieldToken;

        RenewableProject storage project = renewableProjects[_projectId];
        if (project.mintedTokens > 0) {
            distribution.yieldPerToken += (_totalYield * 1e18) / project.mintedTokens;
        }

        // Transfer yield tokens to contract for distribution
        IERC20(_yieldToken).safeTransferFrom(msg.sender, address(this), _totalYield);

        emit YieldDistributed(_projectId, _totalYield);
    }

    /**
     * @notice Claim accumulated yield
     */
    function claimYield(bytes32 _tokenId) external whenNotPaused {
        EnergyToken storage token = energyTokens[_tokenId];
        require(token.owner == msg.sender, "Not token owner");
        require(token.isRebasing, "Token not yield-bearing");

        YieldDistribution storage distribution = yieldDistributions[token.projectId];
        uint256 entitledYield = (token.amount * distribution.yieldPerToken) / 1e18;
        uint256 claimableYield = entitledYield - token.accumulatedYield;

        require(claimableYield > 0, "No yield to claim");

        token.accumulatedYield = entitledYield;

        // Transfer yield to owner
        IERC20(distribution.yieldToken).safeTransfer(msg.sender, claimableYield);
        distribution.distributedYield += claimableYield;
    }

    /**
     * @notice Transfer energy tokens
     */
    function transferTokens(bytes32 _tokenId, address _to, uint256 _amount) external whenNotPaused {
        EnergyToken storage token = energyTokens[_tokenId];
        require(token.owner == msg.sender, "Not token owner");
        require(token.amount >= _amount, "Insufficient balance");
        require(block.timestamp >= token.claimDate, "Tokens still vesting");
        require(_to != address(0), "Invalid recipient");

        token.amount -= _amount;

        // Create new token for recipient
        bytes32 newTokenId = keccak256(abi.encodePacked(
            _tokenId,
            _to,
            _amount,
            block.timestamp
        ));

        energyTokens[newTokenId] = EnergyToken({
            tokenId: newTokenId,
            projectId: token.projectId,
            owner: _to,
            amount: _amount,
            mintDate: block.timestamp,
            vestingPeriod: 0, // No vesting for transfers
            claimDate: block.timestamp,
            isRebasing: token.isRebasing,
            accumulatedYield: 0,
            provenanceHash: keccak256(abi.encodePacked(token.provenanceHash, _to, _amount))
        });

        ownerTokens[_to].push(newTokenId);
    }

    /**
     * @notice Get project details
     */
    function getProject(bytes32 _projectId)
        external
        view
        returns (
            string memory projectName,
            EnergyType energyType,
            ProjectStatus status,
            uint256 totalCapacity,
            uint256 mintedTokens,
            uint256 availableTokens
        )
    {
        RenewableProject memory project = renewableProjects[_projectId];
        return (
            project.projectName,
            project.energyType,
            project.status,
            project.totalCapacity,
            project.mintedTokens,
            project.availableTokens
        );
    }

    /**
     * @notice Get token details
     */
    function getToken(bytes32 _tokenId)
        external
        view
        returns (
            bytes32 projectId,
            address owner,
            uint256 amount,
            uint256 accumulatedYield,
            bool isRebasing
        )
    {
        EnergyToken memory token = energyTokens[_tokenId];
        return (
            token.projectId,
            token.owner,
            token.amount,
            token.accumulatedYield,
            token.isRebasing
        );
    }

    /**
     * @notice Get yield distribution info
     */
    function getYieldDistribution(bytes32 _projectId)
        external
        view
        returns (
            uint256 totalYield,
            uint256 distributedYield,
            uint256 yieldPerToken,
            uint256 lastDistribution
        )
    {
        YieldDistribution memory distribution = yieldDistributions[_projectId];
        return (
            distribution.totalYield,
            distribution.distributedYield,
            distribution.yieldPerToken,
            distribution.lastDistribution
        );
    }

    /**
     * @notice Update project verification
     */
    function updateProjectVerification(bytes32 _projectId) external onlyOwner validProject(_projectId) {
        RenewableProject storage project = renewableProjects[_projectId];
        project.lastVerification = block.timestamp;
    }

    /**
     * @notice Retire a project
     */
    function retireProject(bytes32 _projectId) external onlyProjectOwner(_projectId) validProject(_projectId) {
        RenewableProject storage project = renewableProjects[_projectId];
        project.status = ProjectStatus.RETIRED;
        project.isRetired = true;
    }

    /**
     * @notice Update regulatory parameters
     */
    function updateParameters(
        uint256 _minCertificationValidity,
        uint256 _maxTokenSupply,
        uint256 _minVerificationFrequency
    ) external onlyOwner {
        minCertificationValidity = _minCertificationValidity;
        maxTokenSupply = _maxTokenSupply;
        minVerificationFrequency = _minVerificationFrequency;
    }

    /**
     * @notice Emergency pause
     */
    function emergencyPause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause
     */
    function emergencyUnpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Get global statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalProjects,
            uint256 _totalCapacity,
            uint256 _totalOffsets,
            uint256 _totalMintedTokens
        )
    {
        return (totalProjects, totalCapacity, totalOffsets, totalMintedTokens);
    }
}
