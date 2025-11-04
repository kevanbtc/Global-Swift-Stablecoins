// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title UniversalBasicIncome
 * @notice Decentralized Universal Basic Income distribution system
 * @dev Implements UBI with eligibility criteria, distribution mechanisms, and governance
 */
contract UniversalBasicIncome is Ownable, ReentrancyGuard {

    enum EligibilityStatus {
        INELIGIBLE,
        PENDING_VERIFICATION,
        ELIGIBLE,
        SUSPENDED,
        GRADUATED
    }

    enum DistributionMethod {
        EQUAL_SHARE,
        NEEDS_BASED,
        CONTRIBUTION_BASED,
        GEOGRAPHIC_WEIGHTED,
        ESG_WEIGHTED
    }

    struct CitizenProfile {
        bytes32 citizenId;
        address wallet;
        EligibilityStatus status;
        uint256 registrationDate;
        uint256 lastClaimDate;
        uint256 totalClaimed;
        uint256 eligibilityScore;     // 0-1000, based on various factors
        bytes32 kycHash;
        bytes32 residencyHash;
        mapping(bytes32 => uint256) socialMetrics;
        bool isActive;
    }

    struct DistributionPool {
        bytes32 poolId;
        string poolName;
        DistributionMethod method;
        address fundingSource;
        uint256 totalFunds;
        uint256 distributedFunds;
        uint256 monthlyBudget;
        uint256 eligibleCitizens;
        uint256 distributionFrequency; // seconds
        uint256 lastDistribution;
        bool isActive;
        bytes32 eligibilityCriteria;
    }

    struct UBIClaim {
        bytes32 claimId;
        bytes32 citizenId;
        bytes32 poolId;
        uint256 amount;
        uint256 claimDate;
        bytes32 proofOfEligibility;
        bool isProcessed;
    }

    // Storage
    mapping(bytes32 => CitizenProfile) public citizenProfiles;
    mapping(bytes32 => DistributionPool) public distributionPools;
    mapping(bytes32 => UBIClaim) public ubiClaims;
    mapping(address => bytes32[]) public citizenIdsByWallet;
    mapping(bytes32 => bytes32[]) public claimsByCitizen;
    mapping(bytes32 => bytes32[]) public claimsByPool;

    // Global statistics
    uint256 public totalCitizens;
    uint256 public totalEligibleCitizens;
    uint256 public totalDistributed;
    uint256 public totalPools;

    // Protocol parameters
    uint256 public baseMonthlyUBI = 1000 * 1e18;     // $1000 in wei
    uint256 public minEligibilityScore = 500;         // Minimum score to be eligible
    uint256 public maxMonthlyClaims = 1;              // Prevent double claiming
    uint256 public verificationPeriod = 30 days;      // KYC verification period
    uint256 public claimCooldown = 30 days;           // Minimum time between claims

    // Events
    event CitizenRegistered(bytes32 indexed citizenId, address indexed wallet);
    event EligibilityUpdated(bytes32 indexed citizenId, EligibilityStatus status);
    event UBIDistributed(bytes32 indexed poolId, uint256 totalAmount, uint256 citizens);
    event UBIClaimed(bytes32 indexed citizenId, bytes32 indexed claimId, uint256 amount);
    event DistributionPoolCreated(bytes32 indexed poolId, string name, DistributionMethod method);

    modifier validCitizen(bytes32 _citizenId) {
        require(citizenProfiles[_citizenId].wallet != address(0), "Citizen not found");
        _;
    }

    modifier validPool(bytes32 _poolId) {
        require(distributionPools[_poolId].fundingSource != address(0), "Pool not found");
        _;
    }

    modifier eligibleCitizen(bytes32 _citizenId) {
        require(citizenProfiles[_citizenId].status == EligibilityStatus.ELIGIBLE, "Not eligible");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new citizen for UBI
     */
    function registerCitizen(
        bytes32 _kycHash,
        bytes32 _residencyHash,
        bytes32[] memory _socialMetrics
    ) external returns (bytes32) {
        require(citizenIdsByWallet[msg.sender].length == 0, "Already registered");

        bytes32 citizenId = keccak256(abi.encodePacked(
            msg.sender,
            _kycHash,
            block.timestamp
        ));

        require(citizenProfiles[citizenId].wallet == address(0), "Citizen already exists");

        CitizenProfile storage citizen = citizenProfiles[citizenId];
        citizen.citizenId = citizenId;
        citizen.wallet = msg.sender;
        citizen.status = EligibilityStatus.PENDING_VERIFICATION;
        citizen.registrationDate = block.timestamp;
        citizen.kycHash = _kycHash;
        citizen.residencyHash = _residencyHash;
        citizen.isActive = true;

        // Initialize social metrics
        for (uint256 i = 0; i < _socialMetrics.length; i++) {
            citizen.socialMetrics[_socialMetrics[i]] = 0;
        }

        citizenIdsByWallet[msg.sender].push(citizenId);
        totalCitizens++;

        emit CitizenRegistered(citizenId, msg.sender);
        return citizenId;
    }

    /**
     * @notice Update citizen eligibility status
     */
    function updateEligibility(
        bytes32 _citizenId,
        EligibilityStatus _status,
        uint256 _eligibilityScore
    ) external onlyOwner validCitizen(_citizenId) {
        CitizenProfile storage citizen = citizenProfiles[_citizenId];
        EligibilityStatus oldStatus = citizen.status;

        citizen.status = _status;
        citizen.eligibilityScore = _eligibilityScore;

        // Update global counters
        if (oldStatus != EligibilityStatus.ELIGIBLE && _status == EligibilityStatus.ELIGIBLE) {
            totalEligibleCitizens++;
        } else if (oldStatus == EligibilityStatus.ELIGIBLE && _status != EligibilityStatus.ELIGIBLE) {
            totalEligibleCitizens--;
        }

        emit EligibilityUpdated(_citizenId, _status);
    }

    /**
     * @notice Create a new UBI distribution pool
     */
    function createDistributionPool(
        string memory _poolName,
        DistributionMethod _method,
        uint256 _monthlyBudget,
        uint256 _distributionFrequency,
        bytes32 _eligibilityCriteria
    ) external returns (bytes32) {
        bytes32 poolId = keccak256(abi.encodePacked(
            _poolName,
            msg.sender,
            block.timestamp
        ));

        require(distributionPools[poolId].fundingSource == address(0), "Pool already exists");

        DistributionPool storage pool = distributionPools[poolId];
        pool.poolId = poolId;
        pool.poolName = _poolName;
        pool.method = _method;
        pool.fundingSource = msg.sender;
        pool.monthlyBudget = _monthlyBudget;
        pool.distributionFrequency = _distributionFrequency;
        pool.eligibilityCriteria = _eligibilityCriteria;
        pool.isActive = true;
        pool.lastDistribution = block.timestamp;

        totalPools++;

        emit DistributionPoolCreated(poolId, _poolName, _method);
        return poolId;
    }

    /**
     * @notice Fund a distribution pool
     */
    function fundPool(bytes32 _poolId) external payable validPool(_poolId) {
        DistributionPool storage pool = distributionPools[_poolId];
        pool.totalFunds += msg.value;
    }

    /**
     * @notice Claim UBI from a distribution pool
     */
    function claimUBI(bytes32 _citizenId, bytes32 _poolId) external validCitizen(_citizenId) validPool(_poolId) eligibleCitizen(_citizenId) nonReentrant {
        CitizenProfile storage citizen = citizenProfiles[_citizenId];
        DistributionPool storage pool = distributionPools[_poolId];

        require(citizen.wallet == msg.sender, "Not citizen wallet");
        require(pool.isActive, "Pool not active");
        require(pool.totalFunds >= baseMonthlyUBI, "Insufficient pool funds");
        require(block.timestamp >= citizen.lastClaimDate + claimCooldown, "Claim cooldown active");
        require(claimsByCitizen[_citizenId].length < maxMonthlyClaims, "Monthly limit reached");

        // Calculate claim amount based on distribution method
        uint256 claimAmount = _calculateClaimAmount(_citizenId, _poolId);

        bytes32 claimId = keccak256(abi.encodePacked(
            _citizenId,
            _poolId,
            block.timestamp
        ));

        UBIClaim storage claim = ubiClaims[claimId];
        claim.claimId = claimId;
        claim.citizenId = _citizenId;
        claim.poolId = _poolId;
        claim.amount = claimAmount;
        claim.claimDate = block.timestamp;
        claim.proofOfEligibility = keccak256(abi.encodePacked(_citizenId, citizen.eligibilityScore));
        claim.isProcessed = false;

        claimsByCitizen[_citizenId].push(claimId);
        claimsByPool[_poolId].push(claimId);

        // Process the claim
        _processClaim(claimId);

        emit UBIClaimed(_citizenId, claimId, claimAmount);
    }

    /**
     * @notice Distribute UBI to all eligible citizens in a pool
     */
    function distributeUBI(bytes32 _poolId) external validPool(_poolId) {
        DistributionPool storage pool = distributionPools[_poolId];
        require(pool.isActive, "Pool not active");
        require(block.timestamp >= pool.lastDistribution + pool.distributionFrequency, "Too early for distribution");

        // Simplified distribution logic - in production would iterate through all citizens
        uint256 totalDistributed = 0;
        uint256 citizensPaid = 0;

        // This is a simplified version - production would need more sophisticated distribution
        if (pool.totalFunds >= baseMonthlyUBI && totalEligibleCitizens > 0) {
            uint256 perCitizenAmount = pool.monthlyBudget / totalEligibleCitizens;
            if (perCitizenAmount > baseMonthlyUBI) {
                perCitizenAmount = baseMonthlyUBI;
            }

            totalDistributed = perCitizenAmount * totalEligibleCitizens;
            citizensPaid = totalEligibleCitizens;

            pool.distributedFunds += totalDistributed;
            pool.totalFunds -= totalDistributed;
            pool.lastDistribution = block.timestamp;

            totalDistributed += totalDistributed;
        }

        emit UBIDistributed(_poolId, totalDistributed, citizensPaid);
    }

    /**
     * @notice Update citizen social metrics
     */
    function updateSocialMetrics(
        bytes32 _citizenId,
        bytes32[] memory _metrics,
        uint256[] memory _values
    ) external onlyOwner validCitizen(_citizenId) {
        require(_metrics.length == _values.length, "Array length mismatch");

        CitizenProfile storage citizen = citizenProfiles[_citizenId];
        for (uint256 i = 0; i < _metrics.length; i++) {
            citizen.socialMetrics[_metrics[i]] = _values[i];
        }

        // Recalculate eligibility score
        citizen.eligibilityScore = _calculateEligibilityScore(_citizenId);
    }

    /**
     * @notice Get citizen details
     */
    function getCitizen(bytes32 _citizenId)
        external
        view
        returns (
            address wallet,
            EligibilityStatus status,
            uint256 eligibilityScore,
            uint256 totalClaimed,
            bool isActive
        )
    {
        CitizenProfile memory citizen = citizenProfiles[_citizenId];
        return (
            citizen.wallet,
            citizen.status,
            citizen.eligibilityScore,
            citizen.totalClaimed,
            citizen.isActive
        );
    }

    /**
     * @notice Get distribution pool details
     */
    function getDistributionPool(bytes32 _poolId)
        external
        view
        returns (
            string memory poolName,
            DistributionMethod method,
            uint256 totalFunds,
            uint256 monthlyBudget,
            uint256 eligibleCitizens,
            bool isActive
        )
    {
        DistributionPool memory pool = distributionPools[_poolId];
        return (
            pool.poolName,
            pool.method,
            pool.totalFunds,
            pool.monthlyBudget,
            pool.eligibleCitizens,
            pool.isActive
        );
    }

    /**
     * @notice Get UBI claim details
     */
    function getUBIClaim(bytes32 _claimId)
        external
        view
        returns (
            bytes32 citizenId,
            bytes32 poolId,
            uint256 amount,
            uint256 claimDate,
            bool isProcessed
        )
    {
        UBIClaim memory claim = ubiClaims[_claimId];
        return (
            claim.citizenId,
            claim.poolId,
            claim.amount,
            claim.claimDate,
            claim.isProcessed
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _baseMonthlyUBI,
        uint256 _minEligibilityScore,
        uint256 _claimCooldown
    ) external onlyOwner {
        baseMonthlyUBI = _baseMonthlyUBI;
        minEligibilityScore = _minEligibilityScore;
        claimCooldown = _claimCooldown;
    }

    /**
     * @notice Get global UBI statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalCitizens,
            uint256 _totalEligibleCitizens,
            uint256 _totalDistributed,
            uint256 _totalPools
        )
    {
        return (totalCitizens, totalEligibleCitizens, totalDistributed, totalPools);
    }

    // Internal functions
    function _calculateClaimAmount(bytes32 _citizenId, bytes32 _poolId) internal view returns (uint256) {
        DistributionPool memory pool = distributionPools[_poolId];
        CitizenProfile memory citizen = citizenProfiles[_citizenId];

        if (pool.method == DistributionMethod.EQUAL_SHARE) {
            return baseMonthlyUBI;
        } else if (pool.method == DistributionMethod.NEEDS_BASED) {
            // Simplified needs-based calculation
            return (baseMonthlyUBI * citizen.eligibilityScore) / 1000;
        } else if (pool.method == DistributionMethod.CONTRIBUTION_BASED) {
            // Based on social contributions
            return baseMonthlyUBI; // Simplified
        }

        return baseMonthlyUBI;
    }

    function _calculateEligibilityScore(bytes32 _citizenId) internal view returns (uint256) {
        CitizenProfile storage citizen = citizenProfiles[_citizenId];

        // Simplified scoring based on social metrics
        uint256 score = 500; // Base score

        // Add points for various social metrics
        // This would be more sophisticated in production
        if (citizen.socialMetrics[keccak256("community_contribution")] > 0) {
            score += 100;
        }
        if (citizen.socialMetrics[keccak256("education_level")] > 0) {
            score += 50;
        }

        return score > 1000 ? 1000 : score;
    }

    function _processClaim(bytes32 _claimId) internal {
        UBIClaim storage claim = ubiClaims[_claimId];
        require(!claim.isProcessed, "Claim already processed");

        CitizenProfile storage citizen = citizenProfiles[claim.citizenId];
        DistributionPool storage pool = distributionPools[claim.poolId];

        require(pool.totalFunds >= claim.amount, "Insufficient pool funds");

        // Transfer UBI to citizen
        payable(citizen.wallet).transfer(claim.amount);

        // Update records
        claim.isProcessed = true;
        citizen.lastClaimDate = block.timestamp;
        citizen.totalClaimed += claim.amount;
        pool.totalFunds -= claim.amount;
        pool.distributedFunds += claim.amount;

        totalDistributed += claim.amount;
    }
}
