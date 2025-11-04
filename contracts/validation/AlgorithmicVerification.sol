// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AlgorithmicVerification
 * @notice Algorithmic verification of system accuracy and integrity
 * @dev Uses mathematical algorithms to verify system correctness
 */
contract AlgorithmicVerification is Ownable, ReentrancyGuard {

    enum VerificationAlgorithm {
        MERKLE_PROOF,
        ZERO_KNOWLEDGE_PROOF,
        STATISTICAL_ANALYSIS,
        CONSENSUS_VERIFICATION,
        RISK_WEIGHTED_VALIDATION,
        COMPLIANCE_SCORING,
        PREDICTIVE_MODELING,
        ANOMALY_DETECTION
    }

    enum VerificationResult {
        UNVERIFIED,
        PENDING,
        VERIFIED,
        FAILED,
        INCONCLUSIVE,
        REQUIRES_REVIEW
    }

    enum ConfidenceLevel {
        LOW,
        MEDIUM,
        HIGH,
        VERY_HIGH,
        CERTAIN
    }

    struct VerificationRequest {
        bytes32 requestId;
        VerificationAlgorithm algorithm;
        address requester;
        bytes32 targetId; // ID of what to verify
        bytes inputData;
        uint256 timestamp;
        uint256 deadline;
        VerificationResult result;
        ConfidenceLevel confidence;
        bytes32 proofHash;
        uint256 verificationFee;
        bool isProcessed;
    }

    struct AlgorithmModel {
        bytes32 modelId;
        VerificationAlgorithm algorithmType;
        string modelName;
        string modelVersion;
        address modelProvider;
        uint256 accuracy; // in basis points (0-10000)
        uint256 lastUpdated;
        bool isActive;
        bytes32 modelHash;
        mapping(bytes32 => bytes32) parameters; // key => value
    }

    struct VerificationMetrics {
        uint256 totalRequests;
        uint256 successfulVerifications;
        uint256 failedVerifications;
        uint256 averageConfidence; // in basis points
        uint256 averageProcessingTime; // in seconds
        uint256 falsePositiveRate; // in basis points
        uint256 falseNegativeRate; // in basis points
    }

    // Storage
    mapping(bytes32 => VerificationRequest) public verificationRequests;
    mapping(bytes32 => AlgorithmModel) public algorithmModels;
    mapping(VerificationAlgorithm => bytes32[]) public modelsByAlgorithm;
    mapping(address => bytes32[]) public requestsByRequester;
    mapping(VerificationAlgorithm => VerificationMetrics) public algorithmMetrics;

    // Global statistics
    uint256 public totalRequests;
    uint256 public totalModels;
    uint256 public overallAccuracy; // in basis points

    // Protocol parameters
    uint256 public baseVerificationFee = 0.01 ether;
    uint256 public maxProcessingTime = 1 hours;
    uint256 public minConfidenceThreshold = 7500; // 75%
    uint256 public maxInputDataSize = 10000; // bytes

    // Events
    event VerificationRequested(bytes32 indexed requestId, VerificationAlgorithm algorithm, address requester);
    event VerificationCompleted(bytes32 indexed requestId, VerificationResult result, ConfidenceLevel confidence);
    event AlgorithmModelRegistered(bytes32 indexed modelId, VerificationAlgorithm algorithmType);
    event MetricsUpdated(VerificationAlgorithm algorithm, uint256 accuracy);

    modifier validRequest(bytes32 _requestId) {
        require(verificationRequests[_requestId].requester != address(0), "Request not found");
        _;
    }

    modifier validModel(bytes32 _modelId) {
        require(algorithmModels[_modelId].isActive, "Model not found or inactive");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Request algorithmic verification
     */
    function requestVerification(
        VerificationAlgorithm _algorithm,
        bytes32 _targetId,
        bytes memory _inputData
    ) external payable returns (bytes32) {
        require(_inputData.length <= maxInputDataSize, "Input data too large");
        require(msg.value >= baseVerificationFee, "Insufficient verification fee");

        bytes32 requestId = keccak256(abi.encodePacked(
            _algorithm,
            _targetId,
            msg.sender,
            block.timestamp
        ));

        VerificationRequest storage request = verificationRequests[requestId];
        request.requestId = requestId;
        request.algorithm = _algorithm;
        request.requester = msg.sender;
        request.targetId = _targetId;
        request.inputData = _inputData;
        request.timestamp = block.timestamp;
        request.deadline = block.timestamp + maxProcessingTime;
        request.verificationFee = msg.value;

        requestsByRequester[msg.sender].push(requestId);
        totalRequests++;

        emit VerificationRequested(requestId, _algorithm, msg.sender);
        return requestId;
    }

    /**
     * @notice Register algorithm model
     */
    function registerAlgorithmModel(
        VerificationAlgorithm _algorithmType,
        string memory _modelName,
        string memory _modelVersion,
        uint256 _accuracy,
        bytes32 _modelHash
    ) external returns (bytes32) {
        bytes32 modelId = keccak256(abi.encodePacked(
            _algorithmType,
            _modelName,
            _modelVersion,
            msg.sender,
            block.timestamp
        ));

        AlgorithmModel storage model = algorithmModels[modelId];
        model.modelId = modelId;
        model.algorithmType = _algorithmType;
        model.modelName = _modelName;
        model.modelVersion = _modelVersion;
        model.modelProvider = msg.sender;
        model.accuracy = _accuracy;
        model.lastUpdated = block.timestamp;
        model.isActive = true;
        model.modelHash = _modelHash;

        modelsByAlgorithm[_algorithmType].push(modelId);
        totalModels++;

        emit AlgorithmModelRegistered(modelId, _algorithmType);
        return modelId;
    }

    /**
     * @notice Submit verification result
     */
    function submitVerificationResult(
        bytes32 _requestId,
        VerificationResult _result,
        ConfidenceLevel _confidence,
        bytes32 _proofHash
    ) external validRequest(_requestId) {
        VerificationRequest storage request = verificationRequests[_requestId];
        require(!request.isProcessed, "Request already processed");
        require(block.timestamp <= request.deadline, "Request deadline exceeded");

        request.result = _result;
        request.confidence = _confidence;
        request.proofHash = _proofHash;
        request.isProcessed = true;

        // Update metrics
        _updateAlgorithmMetrics(request.algorithm, _result, _confidence);

        emit VerificationCompleted(_requestId, _result, _confidence);
    }

    /**
     * @notice Update algorithm model parameters
     */
    function updateModelParameters(bytes32 _modelId, bytes32 _key, bytes32 _value)
        external
        validModel(_modelId)
    {
        AlgorithmModel storage model = algorithmModels[_modelId];
        require(model.modelProvider == msg.sender, "Not model provider");

        model.parameters[_key] = _value;
        model.lastUpdated = block.timestamp;
    }

    /**
     * @notice Get model parameter
     */
    function getModelParameter(bytes32 _modelId, bytes32 _key)
        external
        view
        returns (bytes32)
    {
        return algorithmModels[_modelId].parameters[_key];
    }

    /**
     * @notice Get verification request details
     */
    function getVerificationRequest(bytes32 _requestId)
        external
        view
        returns (
            VerificationAlgorithm algorithm,
            address requester,
            bytes32 targetId,
            uint256 timestamp,
            VerificationResult result,
            ConfidenceLevel confidence,
            bool isProcessed
        )
    {
        VerificationRequest memory request = verificationRequests[_requestId];
        return (
            request.algorithm,
            request.requester,
            request.targetId,
            request.timestamp,
            request.result,
            request.confidence,
            request.isProcessed
        );
    }

    /**
     * @notice Get algorithm model details
     */
    function getAlgorithmModel(bytes32 _modelId)
        external
        view
        returns (
            VerificationAlgorithm algorithmType,
            string memory modelName,
            string memory modelVersion,
            address modelProvider,
            uint256 accuracy,
            bool isActive
        )
    {
        AlgorithmModel memory model = algorithmModels[_modelId];
        return (
            model.algorithmType,
            model.modelName,
            model.modelVersion,
            model.modelProvider,
            model.accuracy,
            model.isActive
        );
    }

    /**
     * @notice Get algorithm metrics
     */
    function getAlgorithmMetrics(VerificationAlgorithm _algorithm)
        external
        view
        returns (
            uint256 totalRequests,
            uint256 successfulVerifications,
            uint256 failedVerifications,
            uint256 averageConfidence,
            uint256 averageProcessingTime
        )
    {
        VerificationMetrics memory metrics = algorithmMetrics[_algorithm];
        return (
            metrics.totalRequests,
            metrics.successfulVerifications,
            metrics.failedVerifications,
            metrics.averageConfidence,
            metrics.averageProcessingTime
        );
    }

    /**
     * @notice Get models by algorithm type
     */
    function getModelsByAlgorithm(VerificationAlgorithm _algorithm)
        external
        view
        returns (bytes32[] memory)
    {
        return modelsByAlgorithm[_algorithm];
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
     * @notice Verify Merkle proof
     */
    function verifyMerkleProof(
        bytes32 _root,
        bytes32 _leaf,
        bytes32[] memory _proof,
        uint256 _index
    ) external pure returns (bool) {
        bytes32 computedHash = _leaf;

        for (uint256 i = 0; i < _proof.length; i++) {
            if (_index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, _proof[i]));
            } else {
                computedHash = keccak256(abi.encodePacked(_proof[i], computedHash));
            }
            _index /= 2;
        }

        return computedHash == _root;
    }

    /**
     * @notice Calculate statistical confidence
     */
    function calculateStatisticalConfidence(
        uint256[] memory _dataPoints,
        uint256 _expectedValue,
        uint256 _tolerance
    ) external pure returns (ConfidenceLevel) {
        if (_dataPoints.length == 0) return ConfidenceLevel.LOW;

        uint256 sum = 0;
        uint256 variance = 0;

        for (uint256 i = 0; i < _dataPoints.length; i++) {
            sum += _dataPoints[i];
        }

        uint256 mean = sum / _dataPoints.length;

        for (uint256 i = 0; i < _dataPoints.length; i++) {
            if (_dataPoints[i] > mean) {
                variance += (_dataPoints[i] - mean) ** 2;
            } else {
                variance += (mean - _dataPoints[i]) ** 2;
            }
        }

        variance /= _dataPoints.length;
        uint256 standardDeviation = _sqrt(variance);

        // Calculate confidence based on deviation from expected value
        uint256 deviation = _expectedValue > mean ? _expectedValue - mean : mean - _expectedValue;
        uint256 relativeDeviation = (deviation * 10000) / mean;

        if (relativeDeviation <= _tolerance) {
            return ConfidenceLevel.VERY_HIGH;
        } else if (relativeDeviation <= _tolerance * 2) {
            return ConfidenceLevel.HIGH;
        } else if (relativeDeviation <= _tolerance * 4) {
            return ConfidenceLevel.MEDIUM;
        } else {
            return ConfidenceLevel.LOW;
        }
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _baseVerificationFee,
        uint256 _maxProcessingTime,
        uint256 _minConfidenceThreshold,
        uint256 _maxInputDataSize
    ) external onlyOwner {
        baseVerificationFee = _baseVerificationFee;
        maxProcessingTime = _maxProcessingTime;
        minConfidenceThreshold = _minConfidenceThreshold;
        maxInputDataSize = _maxInputDataSize;
    }

    /**
     * @notice Get global verification statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalRequests,
            uint256 _totalModels,
            uint256 _overallAccuracy
        )
    {
        return (totalRequests, totalModels, overallAccuracy);
    }

    // Internal functions
    function _updateAlgorithmMetrics(
        VerificationAlgorithm _algorithm,
        VerificationResult _result,
        ConfidenceLevel _confidence
    ) internal {
        VerificationMetrics storage metrics = algorithmMetrics[_algorithm];
        metrics.totalRequests++;

        if (_result == VerificationResult.VERIFIED) {
            metrics.successfulVerifications++;
        } else if (_result == VerificationResult.FAILED) {
            metrics.failedVerifications++;
        }

        // Update average confidence (simplified)
        uint256 confidenceValue = uint256(_confidence) * 2500; // Convert enum to basis points
        metrics.averageConfidence = (metrics.averageConfidence + confidenceValue) / 2;

        // Update overall accuracy
        if (metrics.totalRequests > 0) {
            overallAccuracy = (metrics.successfulVerifications * 10000) / metrics.totalRequests;
        }
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
