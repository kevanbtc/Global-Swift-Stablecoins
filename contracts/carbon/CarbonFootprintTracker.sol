// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CarbonFootprintTracker
 * @notice Comprehensive carbon footprint tracking and ESG scoring system
 * @dev Tracks carbon emissions, offsets, and integrates with sustainable finance
 */
contract CarbonFootprintTracker is Ownable, ReentrancyGuard {

    enum EmissionType {
        SCOPE_1,        // Direct emissions
        SCOPE_2,        // Indirect energy emissions
        SCOPE_3,        // Value chain emissions
        BIOGENIC,       // Biological carbon
        AVOIDED         // Avoided emissions
    }

    enum CarbonStandard {
        GHG_PROTOCOL,
        ISO_14064,
        VERRA_VCS,
        GOLD_STANDARD,
        AMERICAN_CARBON,
        PLAN_VIVO,
        SOCIAL_CARBON
    }

    enum ESG_Rating {
        AAA,    // Excellent
        AA,     // Very Good
        A,      // Good
        BBB,    // Adequate
        BB,     // Poor
        B,      // Very Poor
        CCC     // Critical
    }

    struct CarbonFootprint {
        bytes32 entityId;
        string entityName;
        address entityAddress;
        uint256 totalEmissions;        // Tonnes CO2e
        uint256 scope1Emissions;
        uint256 scope2Emissions;
        uint256 scope3Emissions;
        uint256 biogenicEmissions;
        uint256 avoidedEmissions;
        uint256 lastMeasurement;
        uint256 measurementFrequency;  // Days
        CarbonStandard reportingStandard;
        bytes32 verificationHash;
        bool isVerified;
        address verifier;
    }

    struct CarbonOffset {
        bytes32 offsetId;
        bytes32 projectId;
        uint256 tonnesCO2;
        uint256 vintage;           // Year of offset generation
        CarbonStandard standard;
        address issuer;
        address currentOwner;
        uint256 pricePerTonne;
        bool isRetired;
        bytes32 serialNumber;
        bytes32 provenanceHash;
    }

    struct ESG_Score {
        bytes32 entityId;
        uint256 environmentalScore;    // 0-1000
        uint256 socialScore;          // 0-1000
        uint256 governanceScore;      // 0-1000
        uint256 overallScore;         // 0-1000
        ESG_Rating rating;
        uint256 lastAssessment;
        address assessor;
        bytes32 assessmentHash;
        mapping(bytes32 => uint256) metricScores;
    }

    struct SustainabilityBond {
        bytes32 bondId;
        string bondName;
        address issuer;
        uint256 faceValue;
        uint256 couponRate;           // BPS
        uint256 maturity;
        uint256 greenAllocation;      // % of proceeds for green projects
        bytes32[] linkedProjects;
        bool isGreenBond;
        bool isSocialBond;
        bool isSustainabilityBond;
        bytes32 impactReportHash;
    }

    // Storage
    mapping(bytes32 => CarbonFootprint) public carbonFootprints;
    mapping(bytes32 => CarbonOffset) public carbonOffsets;
    mapping(bytes32 => ESG_Score) public esgScores;
    mapping(bytes32 => SustainabilityBond) public sustainabilityBonds;
    mapping(address => bytes32[]) public entityFootprints;
    mapping(address => bytes32[]) public ownedOffsets;
    mapping(bytes32 => bytes32[]) public entityOffsets;

    // Global statistics
    uint256 public totalTrackedEntities;
    uint256 public totalCarbonOffsets;
    uint256 public totalOffsetVolume;     // Tonnes CO2e
    uint256 public totalEmissionsTracked; // Tonnes CO2e

    // Protocol parameters
    uint256 public minMeasurementFrequency = 90 days;
    uint256 public maxMeasurementFrequency = 365 days;
    uint256 public verificationValidityPeriod = 365 days;
    uint256 public carbonPriceFloor = 10 * 1e18; // $10 per tonne

    // Events
    event CarbonFootprintReported(bytes32 indexed entityId, uint256 totalEmissions, uint256 timestamp);
    event CarbonOffsetMinted(bytes32 indexed offsetId, uint256 tonnesCO2, CarbonStandard standard);
    event CarbonOffsetTransferred(bytes32 indexed offsetId, address indexed from, address indexed to);
    event CarbonOffsetRetired(bytes32 indexed offsetId, uint256 tonnesCO2);
    event ESGScoreUpdated(bytes32 indexed entityId, uint256 overallScore, ESG_Rating rating);
    event SustainabilityBondIssued(bytes32 indexed bondId, uint256 faceValue, uint256 greenAllocation);

    modifier validEntity(bytes32 _entityId) {
        require(carbonFootprints[_entityId].entityAddress != address(0), "Entity not found");
        _;
    }

    modifier validOffset(bytes32 _offsetId) {
        require(carbonOffsets[_offsetId].issuer != address(0), "Offset not found");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new entity for carbon tracking
     */
    function registerEntity(
        string memory _entityName,
        uint256 _measurementFrequency,
        CarbonStandard _reportingStandard
    ) public returns (bytes32) {
        require(_measurementFrequency >= minMeasurementFrequency, "Frequency too short");
        require(_measurementFrequency <= maxMeasurementFrequency, "Frequency too long");

        bytes32 entityId = keccak256(abi.encodePacked(
            _entityName,
            msg.sender,
            block.timestamp
        ));

        require(carbonFootprints[entityId].entityAddress == address(0), "Entity already registered");

        CarbonFootprint storage footprint = carbonFootprints[entityId];
        footprint.entityId = entityId;
        footprint.entityName = _entityName;
        footprint.entityAddress = msg.sender;
        footprint.measurementFrequency = _measurementFrequency;
        footprint.reportingStandard = _reportingStandard;
        footprint.lastMeasurement = block.timestamp;

        entityFootprints[msg.sender].push(entityId);
        totalTrackedEntities++;

        return entityId;
    }

    /**
     * @notice Report carbon emissions for an entity
     */
    function reportEmissions(
        bytes32 _entityId,
        uint256 _scope1Emissions,
        uint256 _scope2Emissions,
        uint256 _scope3Emissions,
        uint256 _biogenicEmissions,
        bytes32 _verificationHash
    ) public validEntity(_entityId) {
        CarbonFootprint storage footprint = carbonFootprints[_entityId];
        require(msg.sender == footprint.entityAddress, "Not entity owner");
        require(block.timestamp >= footprint.lastMeasurement + footprint.measurementFrequency, "Too early for measurement");

        footprint.scope1Emissions = _scope1Emissions;
        footprint.scope2Emissions = _scope2Emissions;
        footprint.scope3Emissions = _scope3Emissions;
        footprint.biogenicEmissions = _biogenicEmissions;
        footprint.totalEmissions = _scope1Emissions + _scope2Emissions + _scope3Emissions;
        footprint.lastMeasurement = block.timestamp;
        footprint.verificationHash = _verificationHash;

        totalEmissionsTracked += footprint.totalEmissions;

        emit CarbonFootprintReported(_entityId, footprint.totalEmissions, block.timestamp);
    }

    /**
     * @notice Mint carbon offset tokens
     */
    function mintCarbonOffset(
        bytes32 _projectId,
        uint256 _tonnesCO2,
        uint256 _vintage,
        CarbonStandard _standard,
        uint256 _pricePerTonne,
        bytes32 _provenanceHash
    ) public returns (bytes32) {
        require(_tonnesCO2 > 0, "Invalid offset amount");

        bytes32 offsetId = keccak256(abi.encodePacked(
            _projectId,
            msg.sender,
            _tonnesCO2,
            block.timestamp
        ));

        require(carbonOffsets[offsetId].issuer == address(0), "Offset already exists");

        CarbonOffset storage offset = carbonOffsets[offsetId];
        offset.offsetId = offsetId;
        offset.projectId = _projectId;
        offset.tonnesCO2 = _tonnesCO2;
        offset.vintage = _vintage;
        offset.standard = _standard;
        offset.issuer = msg.sender;
        offset.currentOwner = msg.sender;
        offset.pricePerTonne = _pricePerTonne;
        offset.provenanceHash = _provenanceHash;
        offset.serialNumber = keccak256(abi.encodePacked(offsetId, _tonnesCO2, _vintage));

        ownedOffsets[msg.sender].push(offsetId);
        totalCarbonOffsets++;
        totalOffsetVolume += _tonnesCO2;

        emit CarbonOffsetMinted(offsetId, _tonnesCO2, _standard);
        return offsetId;
    }

    /**
     * @notice Transfer carbon offset ownership
     */
    function transferCarbonOffset(bytes32 _offsetId, address _to) public validOffset(_offsetId) {
        CarbonOffset storage offset = carbonOffsets[_offsetId];
        require(offset.currentOwner == msg.sender, "Not offset owner");
        require(!offset.isRetired, "Offset already retired");
        require(_to != address(0), "Invalid recipient");

        address from = offset.currentOwner;
        offset.currentOwner = _to;

        // Update ownership mappings
        _removeFromOwnedOffsets(from, _offsetId);
        ownedOffsets[_to].push(_offsetId);

        emit CarbonOffsetTransferred(_offsetId, from, _to);
    }

    /**
     * @notice Retire carbon offsets (permanent removal from circulation)
     */
    function retireCarbonOffset(bytes32 _offsetId, uint256 _tonnesToRetire) public validOffset(_offsetId) {
        CarbonOffset storage offset = carbonOffsets[_offsetId];
        require(offset.currentOwner == msg.sender, "Not offset owner");
        require(!offset.isRetired, "Offset already retired");
        require(_tonnesToRetire <= offset.tonnesCO2, "Amount exceeds available offset");

        if (_tonnesToRetire == offset.tonnesCO2) {
            offset.isRetired = true;
        } else {
            // Split offset - simplified, in production would create new offset
            offset.tonnesCO2 -= _tonnesToRetire;
        }

        emit CarbonOffsetRetired(_offsetId, _tonnesToRetire);
    }

    /**
     * @notice Update ESG score for an entity
     */
    function updateESGScore(
        bytes32 _entityId,
        uint256 _environmentalScore,
        uint256 _socialScore,
        uint256 _governanceScore,
        bytes32[] memory _metrics,
        uint256[] memory _metricScores,
        bytes32 _assessmentHash
    ) public onlyOwner validEntity(_entityId) {
        require(_metrics.length == _metricScores.length, "Array length mismatch");
        require(_environmentalScore <= 1000 && _socialScore <= 1000 && _governanceScore <= 1000, "Invalid scores");

        ESG_Score storage esgScore = esgScores[_entityId];
        esgScore.entityId = _entityId;
        esgScore.environmentalScore = _environmentalScore;
        esgScore.socialScore = _socialScore;
        esgScore.governanceScore = _governanceScore;
        esgScore.overallScore = (_environmentalScore + _socialScore + _governanceScore) / 3;
        esgScore.lastAssessment = block.timestamp;
        esgScore.assessor = msg.sender;
        esgScore.assessmentHash = _assessmentHash;

        // Set metric scores
        for (uint256 i = 0; i < _metrics.length; i++) {
            esgScore.metricScores[_metrics[i]] = _metricScores[i];
        }

        // Determine rating
        esgScore.rating = _calculateESGRating(esgScore.overallScore);

        emit ESGScoreUpdated(_entityId, esgScore.overallScore, esgScore.rating);
    }

    /**
     * @notice Issue a sustainability bond
     */
    function issueSustainabilityBond(
        string memory _bondName,
        uint256 _faceValue,
        uint256 _couponRate,
        uint256 _maturity,
        uint256 _greenAllocation,
        bytes32[] memory _linkedProjects,
        bool _isGreenBond,
        bool _isSocialBond,
        bool _isSustainabilityBond
    ) public returns (bytes32) {
        require(_faceValue > 0, "Invalid face value");
        require(_maturity > block.timestamp, "Invalid maturity");
        require(_greenAllocation <= 10000, "Invalid green allocation");
        require(_isGreenBond || _isSocialBond || _isSustainabilityBond, "Must be at least one bond type");

        bytes32 bondId = keccak256(abi.encodePacked(
            _bondName,
            msg.sender,
            _faceValue,
            block.timestamp
        ));

        require(sustainabilityBonds[bondId].issuer == address(0), "Bond already exists");

        SustainabilityBond storage bond = sustainabilityBonds[bondId];
        bond.bondId = bondId;
        bond.bondName = _bondName;
        bond.issuer = msg.sender;
        bond.faceValue = _faceValue;
        bond.couponRate = _couponRate;
        bond.maturity = _maturity;
        bond.greenAllocation = _greenAllocation;
        bond.linkedProjects = _linkedProjects;
        bond.isGreenBond = _isGreenBond;
        bond.isSocialBond = _isSocialBond;
        bond.isSustainabilityBond = _isSustainabilityBond;

        emit SustainabilityBondIssued(bondId, _faceValue, _greenAllocation);
        return bondId;
    }

    /**
     * @notice Get carbon footprint details
     */
    function getCarbonFootprint(bytes32 _entityId) public view
        returns (
            string memory entityName,
            uint256 totalEmissions,
            uint256 scope1Emissions,
            uint256 scope2Emissions,
            uint256 scope3Emissions,
            bool isVerified
        )
    {
        CarbonFootprint memory footprint = carbonFootprints[_entityId];
        return (
            footprint.entityName,
            footprint.totalEmissions,
            footprint.scope1Emissions,
            footprint.scope2Emissions,
            footprint.scope3Emissions,
            footprint.isVerified
        );
    }

    /**
     * @notice Get carbon offset details
     */
    function getCarbonOffset(bytes32 _offsetId) public view
        returns (
            uint256 tonnesCO2,
            uint256 vintage,
            CarbonStandard standard,
            address currentOwner,
            bool isRetired
        )
    {
        CarbonOffset memory offset = carbonOffsets[_offsetId];
        return (
            offset.tonnesCO2,
            offset.vintage,
            offset.standard,
            offset.currentOwner,
            offset.isRetired
        );
    }

    /**
     * @notice Get ESG score details
     */
    function getESGScore(bytes32 _entityId) public view
        returns (
            uint256 environmentalScore,
            uint256 socialScore,
            uint256 governanceScore,
            uint256 overallScore,
            ESG_Rating rating
        )
    {
        ESG_Score storage esgScore = esgScores[_entityId];
        return (
            esgScore.environmentalScore,
            esgScore.socialScore,
            esgScore.governanceScore,
            esgScore.overallScore,
            esgScore.rating
        );
    }

    /**
     * @notice Get sustainability bond details
     */
    function getSustainabilityBond(bytes32 _bondId) public view
        returns (
            string memory bondName,
            uint256 faceValue,
            uint256 couponRate,
            uint256 greenAllocation,
            bool isGreenBond,
            bool isSocialBond,
            bool isSustainabilityBond
        )
    {
        SustainabilityBond memory bond = sustainabilityBonds[_bondId];
        return (
            bond.bondName,
            bond.faceValue,
            bond.couponRate,
            bond.greenAllocation,
            bond.isGreenBond,
            bond.isSocialBond,
            bond.isSustainabilityBond
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _minMeasurementFrequency,
        uint256 _verificationValidityPeriod,
        uint256 _carbonPriceFloor
    ) public onlyOwner {
        minMeasurementFrequency = _minMeasurementFrequency;
        verificationValidityPeriod = _verificationValidityPeriod;
        carbonPriceFloor = _carbonPriceFloor;
    }

    /**
     * @notice Get global carbon statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalTrackedEntities,
            uint256 _totalCarbonOffsets,
            uint256 _totalOffsetVolume,
            uint256 _totalEmissionsTracked
        )
    {
        return (totalTrackedEntities, totalCarbonOffsets, totalOffsetVolume, totalEmissionsTracked);
    }

    // Internal functions
    function _calculateESGRating(uint256 _overallScore) internal pure returns (ESG_Rating) {
        if (_overallScore >= 900) return ESG_Rating.AAA;
        if (_overallScore >= 800) return ESG_Rating.AA;
        if (_overallScore >= 700) return ESG_Rating.A;
        if (_overallScore >= 600) return ESG_Rating.BBB;
        if (_overallScore >= 500) return ESG_Rating.BB;
        if (_overallScore >= 400) return ESG_Rating.B;
        return ESG_Rating.CCC;
    }

    function _removeFromOwnedOffsets(address _owner, bytes32 _offsetId) internal {
        bytes32[] storage offsets = ownedOffsets[_owner];
        for (uint256 i = 0; i < offsets.length; i++) {
            if (offsets[i] == _offsetId) {
                offsets[i] = offsets[offsets.length - 1];
                offsets.pop();
                break;
            }
        }
    }
}
