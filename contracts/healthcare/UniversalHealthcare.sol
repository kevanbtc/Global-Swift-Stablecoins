 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title UniversalHealthcare
 * @notice Decentralized universal healthcare access and management system
 * @dev Integrates with UBI, carbon tracking, and global financial institutions
 */
contract UniversalHealthcare is Ownable, ReentrancyGuard {

    enum HealthcareTier {
        BASIC,          // Essential care
        STANDARD,       // Comprehensive care
        PREMIUM,        // Advanced/specialized care
        EMERGENCY       // Critical care
    }

    enum ServiceType {
        PRIMARY_CARE,
        SPECIALIST_CARE,
        HOSPITALIZATION,
        EMERGENCY_CARE,
        MENTAL_HEALTH,
        DENTAL_CARE,
        VISION_CARE,
        PREVENTIVE_CARE,
        MATERNITY_CARE,
        PHARMACEUTICALS
    }

    enum ProviderStatus {
        PENDING_VERIFICATION,
        VERIFIED,
        SUSPENDED,
        TERMINATED
    }

    struct HealthcareProvider {
        bytes32 providerId;
        string providerName;
        address providerAddress;
        ProviderStatus status;
        HealthcareTier maxTier;
        string[] specialties;
        string jurisdiction;
        uint256 registrationDate;
        uint256 totalServicesProvided;
        uint256 reputationScore;      // 0-1000
        bytes32 licenseHash;
        bool acceptsUniversalCoverage;
        mapping(ServiceType => bool) offeredServices;
        mapping(HealthcareTier => uint256) serviceFees;
    }

    struct PatientRecord {
        bytes32 patientId;
        address patientAddress;
        bytes32 citizenId;            // Links to UBI system
        HealthcareTier coverageTier;
        uint256 enrollmentDate;
        uint256 lastVisit;
        uint256 annualDeductible;
        uint256 annualDeductibleUsed;
        uint256 lifetimeCoverage;
        uint256 lifetimeUsed;
        bool isActive;
        mapping(ServiceType => uint256) annualLimits;
        mapping(ServiceType => uint256) annualUsed;
        bytes32 medicalHistoryHash;
        bytes32 emergencyContact;
    }

    struct HealthcareService {
        bytes32 serviceId;
        bytes32 patientId;
        bytes32 providerId;
        ServiceType serviceType;
        HealthcareTier tier;
        uint256 serviceDate;
        uint256 cost;
        uint256 coveredAmount;
        uint256 patientPay;
        bytes32 diagnosisHash;
        bytes32 treatmentHash;
        bool isEmergency;
        bool isApproved;
        bytes32 approvalProof;
    }

    struct HealthcarePool {
        bytes32 poolId;
        string poolName;
        address fundingSource;
        uint256 totalFunds;
        uint256 allocatedFunds;
        uint256 monthlyBudget;
        uint256 coveredCitizens;
        uint256 avgCostPerCitizen;
        bool isActive;
        bytes32[] supportedServices;
    }

    // Storage
    mapping(bytes32 => HealthcareProvider) public healthcareProviders;
    mapping(bytes32 => PatientRecord) public patientRecords;
    mapping(bytes32 => HealthcareService) public healthcareServices;
    mapping(bytes32 => HealthcarePool) public healthcarePools;
    mapping(address => bytes32[]) public providerIdsByAddress;
    mapping(address => bytes32) public patientIdByAddress;
    mapping(bytes32 => bytes32[]) public servicesByPatient;
    mapping(bytes32 => bytes32[]) public servicesByProvider;

    // Global statistics
    uint256 public totalProviders;
    uint256 public totalPatients;
    uint256 public totalServices;
    uint256 public totalCoverageAmount;

    // Protocol parameters
    uint256 public baseMonthlyPremium = 50 * 1e18;     // $50 per month
    uint256 public annualDeductibleBasic = 500 * 1e18;  // $500
    uint256 public annualDeductibleStandard = 1000 * 1e18; // $1000
    uint256 public annualDeductiblePremium = 2000 * 1e18;   // $2000
    uint256 public coverageRatio = 8000;               // 80% coverage
    uint256 public maxLifetimeCoverage = 1000000 * 1e18; // $1M lifetime

    // Events
    event ProviderRegistered(bytes32 indexed providerId, string name, HealthcareTier maxTier);
    event PatientEnrolled(bytes32 indexed patientId, HealthcareTier tier);
    event ServiceProvided(bytes32 indexed serviceId, bytes32 patientId, uint256 cost, uint256 covered);
    event CoverageClaimed(bytes32 indexed patientId, uint256 amount, bytes32 serviceId);

    modifier validProvider(bytes32 _providerId) {
        require(healthcareProviders[_providerId].providerAddress != address(0), "Provider not found");
        _;
    }

    modifier validPatient(bytes32 _patientId) {
        require(patientRecords[_patientId].patientAddress != address(0), "Patient not found");
        _;
    }

    modifier verifiedProvider(bytes32 _providerId) {
        require(healthcareProviders[_providerId].status == ProviderStatus.VERIFIED, "Provider not verified");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a healthcare provider
     */
    function registerProvider(
        string memory _providerName,
        HealthcareTier _maxTier,
        string[] memory _specialties,
        string memory _jurisdiction,
        bytes32 _licenseHash
    ) external returns (bytes32) {
        bytes32 providerId = keccak256(abi.encodePacked(
            _providerName,
            msg.sender,
            block.timestamp
        ));

        require(healthcareProviders[providerId].providerAddress == address(0), "Provider already registered");

        HealthcareProvider storage provider = healthcareProviders[providerId];
        provider.providerId = providerId;
        provider.providerName = _providerName;
        provider.providerAddress = msg.sender;
        provider.status = ProviderStatus.PENDING_VERIFICATION;
        provider.maxTier = _maxTier;
        provider.specialties = _specialties;
        provider.jurisdiction = _jurisdiction;
        provider.registrationDate = block.timestamp;
        provider.licenseHash = _licenseHash;
        provider.acceptsUniversalCoverage = true;
        provider.reputationScore = 500; // Base score

        providerIdsByAddress[msg.sender].push(providerId);
        totalProviders++;

        emit ProviderRegistered(providerId, _providerName, _maxTier);
        return providerId;
    }

    /**
     * @notice Enroll a patient in universal healthcare
     */
    function enrollPatient(
        bytes32 _citizenId,
        HealthcareTier _tier,
        bytes32 _emergencyContact
    ) external returns (bytes32) {
        require(patientIdByAddress[msg.sender] == bytes32(0), "Already enrolled");

        bytes32 patientId = keccak256(abi.encodePacked(
            msg.sender,
            _citizenId,
            block.timestamp
        ));

        require(patientRecords[patientId].patientAddress == address(0), "Patient already enrolled");

        PatientRecord storage patient = patientRecords[patientId];
        patient.patientId = patientId;
        patient.patientAddress = msg.sender;
        patient.citizenId = _citizenId;
        patient.coverageTier = _tier;
        patient.enrollmentDate = block.timestamp;
        patient.isActive = true;
        patient.emergencyContact = _emergencyContact;

        // Set deductibles based on tier
        if (_tier == HealthcareTier.BASIC) {
            patient.annualDeductible = annualDeductibleBasic;
        } else if (_tier == HealthcareTier.STANDARD) {
            patient.annualDeductible = annualDeductibleStandard;
        } else {
            patient.annualDeductible = annualDeductiblePremium;
        }

        patient.lifetimeCoverage = maxLifetimeCoverage;
        patientIdByAddress[msg.sender] = patientId;
        totalPatients++;

        emit PatientEnrolled(patientId, _tier);
        return patientId;
    }

    /**
     * @notice Provide healthcare service
     */
    function provideService(
        bytes32 _patientId,
        ServiceType _serviceType,
        uint256 _cost,
        bytes32 _diagnosisHash,
        bytes32 _treatmentHash,
        bool _isEmergency
    ) external validPatient(_patientId) verifiedProvider(_getProviderId(msg.sender)) returns (bytes32) {
        bytes32 providerId = _getProviderId(msg.sender);
        PatientRecord storage patient = patientRecords[_patientId];
        HealthcareProvider storage provider = healthcareProviders[providerId];

        require(patient.isActive, "Patient not active");
        require(provider.offeredServices[_serviceType], "Service not offered");
        require(_cost > 0, "Invalid cost");

        // Check tier compatibility
        HealthcareTier requiredTier = _getRequiredTier(_serviceType);
        require(uint256(patient.coverageTier) >= uint256(requiredTier), "Insufficient coverage tier");

        bytes32 serviceId = keccak256(abi.encodePacked(
            _patientId,
            providerId,
            _serviceType,
            block.timestamp
        ));

        HealthcareService storage service = healthcareServices[serviceId];
        service.serviceId = serviceId;
        service.patientId = _patientId;
        service.providerId = providerId;
        service.serviceType = _serviceType;
        service.tier = requiredTier;
        service.serviceDate = block.timestamp;
        service.cost = _cost;
        service.diagnosisHash = _diagnosisHash;
        service.treatmentHash = _treatmentHash;
        service.isEmergency = _isEmergency;

        // Calculate coverage
        (uint256 coveredAmount, uint256 patientPay) = _calculateCoverage(_patientId, _cost, _serviceType, _isEmergency);
        service.coveredAmount = coveredAmount;
        service.patientPay = patientPay;
        service.isApproved = true; // Auto-approved for universal coverage

        // Update patient records
        patient.lastVisit = block.timestamp;
        patient.annualDeductibleUsed += patientPay;
        patient.annualUsed[_serviceType] += _cost;
        patient.lifetimeUsed += coveredAmount;

        // Update provider stats
        provider.totalServicesProvided++;

        servicesByPatient[_patientId].push(serviceId);
        servicesByProvider[providerId].push(serviceId);
        totalServices++;
        totalCoverageAmount += coveredAmount;

        emit ServiceProvided(serviceId, _patientId, _cost, coveredAmount);
        return serviceId;
    }

    /**
     * @notice Claim coverage for a service
     */
    function claimCoverage(bytes32 _serviceId) external validPatient(_getPatientId(msg.sender)) nonReentrant {
        bytes32 patientId = _getPatientId(msg.sender);
        HealthcareService storage service = healthcareServices[_serviceId];

        require(service.patientId == patientId, "Not patient service");
        require(service.isApproved, "Service not approved");
        require(service.approvalProof == bytes32(0), "Already claimed");

        // Transfer covered amount to provider
        address providerAddress = healthcareProviders[service.providerId].providerAddress;
        payable(providerAddress).transfer(service.coveredAmount);

        service.approvalProof = keccak256(abi.encodePacked(serviceId, block.timestamp));

        emit CoverageClaimed(patientId, service.coveredAmount, _serviceId);
    }

    /**
     * @notice Create a healthcare funding pool
     */
    function createHealthcarePool(
        string memory _poolName,
        uint256 _monthlyBudget,
        bytes32[] memory _supportedServices
    ) external returns (bytes32) {
        bytes32 poolId = keccak256(abi.encodePacked(
            _poolName,
            msg.sender,
            block.timestamp
        ));

        HealthcarePool storage pool = healthcarePools[poolId];
        pool.poolId = poolId;
        pool.poolName = _poolName;
        pool.fundingSource = msg.sender;
        pool.monthlyBudget = _monthlyBudget;
        pool.supportedServices = _supportedServices;
        pool.isActive = true;

        return poolId;
    }

    /**
     * @notice Fund a healthcare pool
     */
    function fundPool(bytes32 _poolId) external payable {
        HealthcarePool storage pool = healthcarePools[_poolId];
        require(pool.fundingSource != address(0), "Pool not found");
        pool.totalFunds += msg.value;
    }

    /**
     * @notice Update provider verification status
     */
    function updateProviderStatus(bytes32 _providerId, ProviderStatus _status) external onlyOwner validProvider(_providerId) {
        healthcareProviders[_providerId].status = _status;
    }

    /**
     * @notice Set provider service offerings
     */
    function setProviderServices(bytes32 _providerId, ServiceType[] memory _services, bool[] memory _offered) external validProvider(_providerId) {
        require(msg.sender == healthcareProviders[_providerId].providerAddress, "Not provider");
        require(_services.length == _offered.length, "Array length mismatch");

        for (uint256 i = 0; i < _services.length; i++) {
            healthcareProviders[_providerId].offeredServices[_services[i]] = _offered[i];
        }
    }

    /**
     * @notice Set provider service fees
     */
    function setProviderFees(bytes32 _providerId, HealthcareTier[] memory _tiers, uint256[] memory _fees) external validProvider(_providerId) {
        require(msg.sender == healthcareProviders[_providerId].providerAddress, "Not provider");
        require(_tiers.length == _fees.length, "Array length mismatch");

        for (uint256 i = 0; i < _tiers.length; i++) {
            healthcareProviders[_providerId].serviceFees[_tiers[i]] = _fees[i];
        }
    }

    /**
     * @notice Get provider details
     */
    function getProvider(bytes32 _providerId)
        external
        view
        returns (
            string memory providerName,
            ProviderStatus status,
            HealthcareTier maxTier,
            uint256 reputationScore,
            bool acceptsUniversalCoverage
        )
    {
        HealthcareProvider memory provider = healthcareProviders[_providerId];
        return (
            provider.providerName,
            provider.status,
            provider.maxTier,
            provider.reputationScore,
            provider.acceptsUniversalCoverage
        );
    }

    /**
     * @notice Get patient details
     */
    function getPatient(bytes32 _patientId)
        external
        view
        returns (
            HealthcareTier coverageTier,
            uint256 annualDeductible,
            uint256 annualDeductibleUsed,
            uint256 lifetimeCoverage,
            uint256 lifetimeUsed,
            bool isActive
        )
    {
        PatientRecord memory patient = patientRecords[_patientId];
        return (
            patient.coverageTier,
            patient.annualDeductible,
            patient.annualDeductibleUsed,
            patient.lifetimeCoverage,
            patient.lifetimeUsed,
            patient.isActive
        );
    }

    /**
     * @notice Get healthcare service details
     */
    function getHealthcareService(bytes32 _serviceId)
        external
        view
        returns (
            bytes32 patientId,
            bytes32 providerId,
            ServiceType serviceType,
            uint256 cost,
            uint256 coveredAmount,
            uint256 patientPay,
            bool isApproved
        )
    {
        HealthcareService memory service = healthcareServices[_serviceId];
        return (
            service.patientId,
            service.providerId,
            service.serviceType,
            service.cost,
            service.coveredAmount,
            service.patientPay,
            service.isApproved
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _baseMonthlyPremium,
        uint256 _coverageRatio,
        uint256 _maxLifetimeCoverage
    ) external onlyOwner {
        baseMonthlyPremium = _baseMonthlyPremium;
        coverageRatio = _coverageRatio;
        maxLifetimeCoverage = _maxLifetimeCoverage;
    }

    /**
     * @notice Get global healthcare statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalProviders,
            uint256 _totalPatients,
            uint256 _totalServices,
            uint256 _totalCoverageAmount
        )
    {
        return (totalProviders, totalPatients, totalServices, totalCoverageAmount);
    }

    // Internal functions
    function _calculateCoverage(
        bytes32 _patientId,
        uint256 _cost,
        ServiceType _serviceType,
        bool _isEmergency
    ) internal view returns (uint256 covered, uint256 patientPay) {
        PatientRecord memory patient = patientRecords[_patientId];

        // Emergency care is fully covered
        if (_isEmergency) {
            return (_cost, 0);
        }

        // Check annual limits
        uint256 annualLimit = patient.annualLimits[_serviceType];
        uint256 annualUsed = patient.annualUsed[_serviceType];

        if (annualLimit > 0 && annualUsed >= annualLimit) {
            return (0, _cost); // No coverage if limit exceeded
        }

        // Calculate base coverage
        uint256 baseCovered = (_cost * coverageRatio) / 10000;

        // Apply deductible
        uint256 remainingDeductible = patient.annualDeductible - patient.annualDeductibleUsed;
        uint256 deductibleApplied = remainingDeductible > baseCovered ? baseCovered : remainingDeductible;
        baseCovered -= deductibleApplied;

        // Apply lifetime limit
        uint256 remainingLifetime = patient.lifetimeCoverage - patient.lifetimeUsed;
        if (baseCovered > remainingLifetime) {
            baseCovered = remainingLifetime;
        }

        patientPay = _cost - baseCovered;
        return (baseCovered, patientPay);
    }

    function _getRequiredTier(ServiceType _serviceType) internal pure returns (HealthcareTier) {
        if (_serviceType == ServiceType.EMERGENCY_CARE) {
            return HealthcareTier.EMERGENCY;
        } else if (_serviceType == ServiceType.SPECIALIST_CARE || _serviceType == ServiceType.HOSPITALIZATION) {
            return HealthcareTier.STANDARD;
        } else if (_serviceType == ServiceType.PRIMARY_CARE || _serviceType == ServiceType.PREVENTIVE_CARE) {
            return HealthcareTier.BASIC;
        } else {
            return HealthcareTier.PREMIUM;
        }
    }

    function _getProviderId(address _providerAddress) internal view returns (bytes32) {
        bytes32[] memory providerIds = providerIdsByAddress[_providerAddress];
        require(providerIds.length > 0, "Not a registered provider");
        return providerIds[0]; // Return first provider ID
    }

    function _getPatientId(address _patientAddress) internal view returns (bytes32) {
        return patientIdByAddress[_patientAddress];
    }
}
