// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ThirdPartyValidation
 * @notice Third-party validation services integration
 * @dev Integrates with external auditors, rating agencies, and validation services
 */
contract ThirdPartyValidation is Ownable, ReentrancyGuard {

    enum ValidationProvider {
        CHAINALYSIS,
        ELLIPTIC,
        TRM_LABS,
        CIPHERTRACE,
        STANDARD_CHARTERED,
        DELOITTE,
        PWC,
        EY,
        KPMG,
        MOODY,
        SP,
        FITCH,
        DBRS,
        COINBASE_CUSTODY,
        FIDELITY_DIGITAL_ASSETS,
        ANCHOR,
        OPENZEPPELIN,
        TRAIL_OF_BITS,
        CERTIK,
        QUANTSTAMP
    }

    enum ValidationType {
        AML_KYC_COMPLIANCE,
        SECURITY_AUDIT,
        FINANCIAL_AUDIT,
        CREDIT_RATING,
        RISK_ASSESSMENT,
        CODE_AUDIT,
        REGULATORY_COMPLIANCE,
        FINANCIAL_REPORTING,
        ESG_RATING,
        CYBER_SECURITY,
        OPERATIONAL_RESILIENCE,
        MARKET_INTEGRITY
    }

    enum ValidationStatus {
        REQUESTED,
        IN_PROGRESS,
        COMPLETED,
        FAILED,
        DISPUTED,
        REVOKED
    }

    enum ValidationOutcome {
        PASS,
        FAIL,
        CONDITIONAL_PASS,
        INCONCLUSIVE,
        REQUIRES_REVIEW
    }

    struct ValidationRequest {
        bytes32 requestId;
        ValidationProvider provider;
        ValidationType validationType;
        address requester;
        bytes32 targetId; // What is being validated
        uint256 requestTimestamp;
        uint256 deadline;
        uint256 fee;
        ValidationStatus status;
        ValidationOutcome outcome;
        string reportURI;
        bytes32 reportHash;
        uint256 validityPeriod; // seconds
        bool isRenewable;
        mapping(address => bool) authorizedReviewers;
    }

    struct ProviderProfile {
        ValidationProvider provider;
        string name;
        string description;
        address providerAddress;
        uint256 reputationScore; // 0-100
        uint256 totalValidations;
        uint256 successfulValidations;
        uint256 averageResponseTime; // seconds
        bool isActive;
        mapping(ValidationType => bool) supportedTypes;
        mapping(ValidationType => uint256) typeFees;
    }

    struct ValidationMetrics {
        uint256 totalRequests;
        uint256 completedValidations;
        uint256 disputedValidations;
        uint256 averageCompletionTime;
        uint256 providerSatisfaction; // 0-100
        uint256 falsePositiveRate;
        uint256 falseNegativeRate;
    }

    // Storage
    mapping(bytes32 => ValidationRequest) public validationRequests;
    mapping(ValidationProvider => ProviderProfile) public providerProfiles;
    mapping(ValidationType => bytes32[]) public requestsByType;
    mapping(ValidationProvider => bytes32[]) public requestsByProvider;
    mapping(address => bytes32[]) public requestsByRequester;
    mapping(ValidationType => ValidationMetrics) public typeMetrics;

    // Global statistics
    uint256 public totalRequests;
    uint256 public totalProviders;
    uint256 public overallSatisfaction; // 0-100

    // Protocol parameters
    uint256 public baseValidationFee = 1 ether;
    uint256 public maxDeadline = 30 days;
    uint256 public minReputationScore = 70;
    uint256 public disputePeriod = 7 days;

    // Events
    event ValidationRequested(bytes32 indexed requestId, ValidationProvider provider, ValidationType validationType);
    event ValidationCompleted(bytes32 indexed requestId, ValidationOutcome outcome, string reportURI);
    event ProviderRegistered(ValidationProvider provider, string name);
    event ValidationDisputed(bytes32 indexed requestId, address disputer, string reason);

    modifier validRequest(bytes32 _requestId) {
        require(validationRequests[_requestId].requester != address(0), "Request not found");
        _;
    }

    modifier validProvider(ValidationProvider _provider) {
        require(providerProfiles[_provider].isActive, "Provider not active");
        _;
    }

    modifier authorizedProvider(bytes32 _requestId) {
        ValidationRequest memory request = validationRequests[_requestId];
        require(providerProfiles[request.provider].providerAddress == msg.sender, "Not authorized provider");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register validation provider
     */
    function registerProvider(
        ValidationProvider _provider,
        string memory _name,
        string memory _description,
        ValidationType[] memory _supportedTypes,
        uint256[] memory _typeFees
    ) external onlyOwner {
        require(_supportedTypes.length == _typeFees.length, "Array length mismatch");

        ProviderProfile storage profile = providerProfiles[_provider];
        profile.provider = _provider;
        profile.name = _name;
        profile.description = _description;
        profile.providerAddress = msg.sender;
        profile.reputationScore = 80; // Default starting score
        profile.isActive = true;

        for (uint256 i = 0; i < _supportedTypes.length; i++) {
            profile.supportedTypes[_supportedTypes[i]] = true;
            profile.typeFees[_supportedTypes[i]] = _typeFees[i];
        }

        totalProviders++;

        emit ProviderRegistered(_provider, _name);
    }

    /**
     * @notice Request third-party validation
     */
    function requestValidation(
        ValidationProvider _provider,
        ValidationType _validationType,
        bytes32 _targetId,
        uint256 _deadline,
        bool _isRenewable
    ) external payable validProvider(_provider) returns (bytes32) {
        ProviderProfile memory profile = providerProfiles[_provider];
        require(profile.supportedTypes[_validationType], "Validation type not supported");
        require(_deadline <= maxDeadline, "Deadline too far");
        require(profile.reputationScore >= minReputationScore, "Provider reputation too low");

        uint256 fee = profile.typeFees[_validationType];
        require(msg.value >= fee, "Insufficient fee");

        bytes32 requestId = keccak256(abi.encodePacked(
            _provider,
            _validationType,
            _targetId,
            msg.sender,
            block.timestamp
        ));

        ValidationRequest storage request = validationRequests[requestId];
        request.requestId = requestId;
        request.provider = _provider;
        request.validationType = _validationType;
        request.requester = msg.sender;
        request.targetId = _targetId;
        request.requestTimestamp = block.timestamp;
        request.deadline = block.timestamp + _deadline;
        request.fee = fee;
        request.status = ValidationStatus.REQUESTED;
        request.isRenewable = _isRenewable;

        requestsByType[_validationType].push(requestId);
        requestsByProvider[_provider].push(requestId);
        requestsByRequester[msg.sender].push(requestId);
        totalRequests++;

        emit ValidationRequested(requestId, _provider, _validationType);
        return requestId;
    }

    /**
     * @notice Submit validation report
     */
    function submitValidationReport(
        bytes32 _requestId,
        ValidationOutcome _outcome,
        string memory _reportURI,
        bytes32 _reportHash,
        uint256 _validityPeriod
    ) external validRequest(_requestId) authorizedProvider(_requestId) {
        ValidationRequest storage request = validationRequests[_requestId];
        require(request.status == ValidationStatus.REQUESTED || request.status == ValidationStatus.IN_PROGRESS, "Invalid status");
        require(block.timestamp <= request.deadline, "Deadline exceeded");

        request.status = ValidationStatus.COMPLETED;
        request.outcome = _outcome;
        request.reportURI = _reportURI;
        request.reportHash = _reportHash;
        request.validityPeriod = _validityPeriod;

        // Update provider metrics
        ProviderProfile storage profile = providerProfiles[request.provider];
        profile.totalValidations++;
        if (_outcome == ValidationOutcome.PASS || _outcome == ValidationOutcome.CONDITIONAL_PASS) {
            profile.successfulValidations++;
        }

        // Update metrics
        _updateValidationMetrics(request.validationType, _outcome);

        emit ValidationCompleted(_requestId, _outcome, _reportURI);
    }

    /**
     * @notice Dispute validation result
     */
    function disputeValidation(bytes32 _requestId, string memory _reason)
        external
        validRequest(_requestId)
    {
        ValidationRequest storage request = validationRequests[_requestId];
        require(request.status == ValidationStatus.COMPLETED, "Validation not completed");
        require(request.requester == msg.sender, "Not request owner");
        require(block.timestamp <= request.requestTimestamp + disputePeriod, "Dispute period expired");

        request.status = ValidationStatus.DISPUTED;

        // Decrease provider reputation
        ProviderProfile storage profile = providerProfiles[request.provider];
        if (profile.reputationScore > 5) {
            profile.reputationScore -= 5;
        }

        emit ValidationDisputed(_requestId, msg.sender, _reason);
    }

    /**
     * @notice Authorize reviewer for validation
     */
    function authorizeReviewer(bytes32 _requestId, address _reviewer)
        external
        validRequest(_requestId)
    {
        ValidationRequest storage request = validationRequests[_requestId];
        require(request.requester == msg.sender, "Not request owner");

        request.authorizedReviewers[_reviewer] = true;
    }

    /**
     * @notice Get validation request details
     */
    function getValidationRequest(bytes32 _requestId)
        external
        view
        returns (
            ValidationProvider provider,
            ValidationType validationType,
            address requester,
            ValidationStatus status,
            ValidationOutcome outcome,
            string memory reportURI,
            uint256 deadline
        )
    {
        ValidationRequest memory request = validationRequests[_requestId];
        return (
            request.provider,
            request.validationType,
            request.requester,
            request.status,
            request.outcome,
            request.reportURI,
            request.deadline
        );
    }

    /**
     * @notice Get provider profile
     */
    function getProviderProfile(ValidationProvider _provider)
        external
        view
        returns (
            string memory name,
            string memory description,
            uint256 reputationScore,
            uint256 totalValidations,
            uint256 successfulValidations,
            bool isActive
        )
    {
        ProviderProfile memory profile = providerProfiles[_provider];
        return (
            profile.name,
            profile.description,
            profile.reputationScore,
            profile.totalValidations,
            profile.successfulValidations,
            profile.isActive
        );
    }

    /**
     * @notice Check if provider supports validation type
     */
    function providerSupportsType(ValidationProvider _provider, ValidationType _type)
        external
        view
        returns (bool)
    {
        return providerProfiles[_provider].supportedTypes[_type];
    }

    /**
     * @notice Get provider fee for validation type
     */
    function getProviderFee(ValidationProvider _provider, ValidationType _type)
        external
        view
        returns (uint256)
    {
        return providerProfiles[_provider].typeFees[_type];
    }

    /**
     * @notice Get validation metrics by type
     */
    function getValidationMetrics(ValidationType _type)
        external
        view
        returns (
            uint256 totalRequests,
            uint256 completedValidations,
            uint256 disputedValidations,
            uint256 averageCompletionTime,
            uint256 providerSatisfaction
        )
    {
        ValidationMetrics memory metrics = typeMetrics[_type];
        return (
            metrics.totalRequests,
            metrics.completedValidations,
            metrics.disputedValidations,
            metrics.averageCompletionTime,
            metrics.providerSatisfaction
        );
    }

    /**
     * @notice Get requests by type
     */
    function getRequestsByType(ValidationType _type)
        external
        view
        returns (bytes32[] memory)
    {
        return requestsByType[_type];
    }

    /**
     * @notice Get requests by provider
     */
    function getRequestsByProvider(ValidationProvider _provider)
        external
        view
        returns (bytes32[] memory)
    {
        return requestsByProvider[_provider];
    }

    /**
     * @notice Get requests by requester
     */
    function getRequestsByRequester(address _requester)
        external
        view
        returns (bytes32[] memory)
    {
        return requestsByRequester[_requester];
    }

    /**
     * @notice Update provider reputation
     */
    function updateProviderReputation(ValidationProvider _provider, uint256 _newScore)
        external
        onlyOwner
    {
        require(_newScore <= 100, "Invalid score");
        providerProfiles[_provider].reputationScore = _newScore;
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _baseValidationFee,
        uint256 _maxDeadline,
        uint256 _minReputationScore,
        uint256 _disputePeriod
    ) external onlyOwner {
        baseValidationFee = _baseValidationFee;
        maxDeadline = _maxDeadline;
        minReputationScore = _minReputationScore;
        disputePeriod = _disputePeriod;
    }

    /**
     * @notice Get global validation statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalRequests,
            uint256 _totalProviders,
            uint256 _overallSatisfaction
        )
    {
        return (totalRequests, totalProviders, overallSatisfaction);
    }

    // Internal functions
    function _updateValidationMetrics(ValidationType _type, ValidationOutcome _outcome) internal {
        ValidationMetrics storage metrics = typeMetrics[_type];
        metrics.totalRequests++;

        if (_outcome != ValidationOutcome.INCONCLUSIVE) {
            metrics.completedValidations++;
        }

        // Update overall satisfaction (simplified calculation)
        uint256 outcomeScore = _outcome == ValidationOutcome.PASS ? 100 :
                              _outcome == ValidationOutcome.CONDITIONAL_PASS ? 75 :
                              _outcome == ValidationOutcome.FAIL ? 25 : 50;

        metrics.providerSatisfaction = (metrics.providerSatisfaction + outcomeScore) / 2;
        overallSatisfaction = metrics.providerSatisfaction; // Simplified
    }
}
