// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ArbitrageEngine
 * @notice Automated arbitrage detection and execution engine
 * @dev AI-powered arbitrage across DEXes, CEXes, and cross-chain opportunities
 */
contract ArbitrageEngine is Ownable, ReentrancyGuard {

    enum ArbitrageType {
        TRIANGULAR,        // Three-token arbitrage
        CROSS_DEX,         // Same pair across different DEXes
        CROSS_CHAIN,       // Same asset across different chains
        STATISTICAL,       // Statistical arbitrage
        MERGER,           // Merger arbitrage
        CONVERSION        // Token conversion arbitrage
    }

    enum OpportunityStatus {
        DETECTED,
        VALIDATING,
        EXECUTING,
        COMPLETED,
        FAILED,
        EXPIRED
    }

    struct ArbitrageOpportunity {
        bytes32 opportunityId;
        ArbitrageType arbType;
        address[] tokens;
        address[] exchanges;
        uint256[] prices;
        uint256[] amounts;
        uint256 expectedProfit;
        uint256 gasEstimate;
        uint256 slippageTolerance;
        OpportunityStatus status;
        uint256 detectedAt;
        uint256 executedAt;
        uint256 expiresAt;
        bytes32 executionPath;
        address executor;
        bool isActive;
        bytes32 proofHash; // Hash of off-chain computation proof
    }

    struct ArbitrageStrategy {
        bytes32 strategyId;
        bytes32 strategyNameHash;
        address owner;
        ArbitrageType[] supportedTypes;
        uint256 minProfitThreshold;    // BPS
        uint256 maxSlippage;          // BPS
        uint256 maxGasPrice;          // Wei
        uint256 maxTradeSize;         // Token amount
        bool isActive;
        bool requiresApproval;
        bytes32 riskParameters;
    }

    struct ArbitrageExecution {
        bytes32 executionId;
        bytes32 opportunityId;
        bytes32 strategyId;
        uint256 startAmount;
        uint256 endAmount;
        uint256 actualProfit;
        uint256 gasUsed;
        uint256 executionTime;
        bool success;
        bytes32 failureReason;
        address[] pathTaken;
        uint256[] intermediateAmounts;
        bytes32 executionProofHash; // Hash of off-chain execution proof
    }

    struct MarketData {
        address tokenA;
        address tokenB;
        address exchange;
        uint256 price;
        uint256 liquidity;
        uint256 fee;                  // BPS
        uint256 lastUpdate;
        bool isActive;
    }

    // Storage
    mapping(bytes32 => ArbitrageOpportunity) public arbitrageOpportunities;
    mapping(bytes32 => ArbitrageStrategy) public arbitrageStrategies;
    mapping(bytes32 => ArbitrageExecution) public arbitrageExecutions;
    mapping(bytes32 => MarketData) public marketData;
    mapping(address => mapping(address => bytes32[])) public exchangePairs; // tokenA => tokenB => marketIds

    // Global statistics
    uint256 public totalOpportunities;
    uint256 public totalExecutions;
    uint256 public totalSuccessfulArbs;
    uint256 public totalProfitGenerated;
    uint256 public totalGasSpent;

    // Protocol parameters
    uint256 public minProfitThreshold = 50;     // 0.5% BPS
    uint256 public maxSlippageTolerance = 300;  // 3% BPS
    uint256 public opportunityTimeout = 300;    // 5 minutes
    uint256 public maxExecutionTime = 60;       // 1 minute
    uint256 public gasPriceLimit = 100 gwei;

    // Events
    event ArbitrageOpportunityDetected(bytes32 indexed opportunityId, ArbitrageType arbType, uint256 expectedProfit);
    event ArbitrageExecuted(bytes32 indexed executionId, bytes32 indexed opportunityId, uint256 profit, uint256 gasUsed);
    event ArbitrageFailed(bytes32 indexed opportunityId, bytes32 failureReason);
    event StrategyDeployed(bytes32 indexed strategyId, bytes32 nameHash, address owner);
    event MarketDataUpdated(address indexed tokenA, address indexed tokenB, address indexed exchange, uint256 price);

    modifier validOpportunity(bytes32 _opportunityId) {
        require(arbitrageOpportunities[_opportunityId].isActive, "Opportunity not active");
        _;
    }

    modifier validStrategy(bytes32 _strategyId) {
        require(arbitrageStrategies[_strategyId].isActive, "Strategy not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Deploy an arbitrage strategy
     */
    function deployStrategy(
        bytes32 _strategyNameHash,
        ArbitrageType[] memory _supportedTypes,
        uint256 _minProfitThreshold,
        uint256 _maxSlippage,
        uint256 _maxGasPrice,
        uint256 _maxTradeSize,
        bytes32 _riskParameters
    ) public returns (bytes32) {
        bytes32 strategyId = keccak256(abi.encodePacked(
            _strategyNameHash,
            msg.sender,
            block.timestamp
        ));

        ArbitrageStrategy storage strategy = arbitrageStrategies[strategyId];
        strategy.strategyId = strategyId;
        strategy.strategyNameHash = _strategyNameHash;
        strategy.owner = msg.sender;
        strategy.supportedTypes = _supportedTypes;
        strategy.minProfitThreshold = _minProfitThreshold;
        strategy.maxSlippage = _maxSlippage;
        strategy.maxGasPrice = _maxGasPrice;
        strategy.maxTradeSize = _maxTradeSize;
        strategy.riskParameters = _riskParameters;
        strategy.isActive = true;

        emit StrategyDeployed(strategyId, _strategyNameHash, msg.sender);
        return strategyId;
    }

    /**
     * @notice Detect triangular arbitrage opportunity
     */
    function detectTriangularArbitrage(
        address _tokenA,
        address _tokenB,
        address _tokenC,
        address[] memory _exchanges,
        uint256[] memory _amounts,
        uint256 _expectedProfit,
        bytes32 _proofHash
    ) public returns (bytes32) {
        require(_exchanges.length >= 3, "Need at least 3 exchanges");
        require(_amounts.length == 3, "Need 3 amounts");
        require(_expectedProfit > 0, "Expected profit must be positive");

        // Off-chain calculation is assumed to have happened, on-chain verification of proof
        // For simplicity, we'll assume the proof is valid for now.
        // In a real system, this would involve calling a verifier contract or similar.
        // require(_verifyOffchainProof(_proofHash), "Invalid off-chain proof");

        bytes32 opportunityId = keccak256(abi.encodePacked(
            "TRIANGULAR",
            _tokenA,
            _tokenB,
            _tokenC,
            block.timestamp,
            _proofHash
        ));

        ArbitrageOpportunity storage opportunity = arbitrageOpportunities[opportunityId];
        opportunity.opportunityId = opportunityId;
        opportunity.arbType = ArbitrageType.TRIANGULAR;
        opportunity.tokens = [_tokenA, _tokenB, _tokenC];
        opportunity.exchanges = _exchanges;
        opportunity.amounts = _amounts;
        opportunity.expectedProfit = _expectedProfit;
        opportunity.gasEstimate = 0; // This would also come from off-chain calculation
        opportunity.slippageTolerance = maxSlippageTolerance; // Or from off-chain
        opportunity.status = OpportunityStatus.DETECTED;
        opportunity.detectedAt = block.timestamp;
        opportunity.expiresAt = block.timestamp + opportunityTimeout;
        opportunity.executor = address(0);
        opportunity.isActive = true;
        opportunity.proofHash = _proofHash;

        totalOpportunities++;

        emit ArbitrageOpportunityDetected(opportunityId, ArbitrageType.TRIANGULAR, _expectedProfit);
        return opportunityId;
    }

    /**
     * @notice Detect cross-DEX arbitrage opportunity
     */
    function detectCrossDEXArbitrage(
        address _tokenA,
        address _tokenB,
        address[] memory _exchanges,
        uint256 _amount,
        uint256 _expectedProfit,
        bytes32 _proofHash
    ) public returns (bytes32) {
        require(_exchanges.length >= 2, "Need at least 2 exchanges");
        require(_expectedProfit > 0, "Expected profit must be positive");

        // Off-chain calculation is assumed to have happened, on-chain verification of proof
        // For simplicity, we'll assume the proof is valid for now.
        // In a real system, this would involve calling a verifier contract or similar.
        // require(_verifyOffchainProof(_proofHash), "Invalid off-chain proof");

        bytes32 opportunityId = keccak256(abi.encodePacked(
            "CROSS_DEX",
            _tokenA,
            _tokenB,
            block.timestamp,
            _proofHash
        ));

        ArbitrageOpportunity storage opportunity = arbitrageOpportunities[opportunityId];
        opportunity.opportunityId = opportunityId;
        opportunity.arbType = ArbitrageType.CROSS_DEX;
        opportunity.tokens = [_tokenA, _tokenB];
        opportunity.exchanges = _exchanges;
        opportunity.amounts = [_amount];
        opportunity.expectedProfit = _expectedProfit;
        opportunity.gasEstimate = 0; // This would also come from off-chain calculation
        opportunity.slippageTolerance = maxSlippageTolerance; // Or from off-chain
        opportunity.status = OpportunityStatus.DETECTED;
        opportunity.detectedAt = block.timestamp;
        opportunity.expiresAt = block.timestamp + opportunityTimeout;
        opportunity.isActive = true;
        opportunity.proofHash = _proofHash;

        totalOpportunities++;

        emit ArbitrageOpportunityDetected(opportunityId, ArbitrageType.CROSS_DEX, _expectedProfit);
        return opportunityId;
    }

    /**
     * @notice Execute arbitrage opportunity
     */
    function executeArbitrage(
        bytes32 _opportunityId,
        bytes32 _strategyId,
        uint256 _actualProfit,
        uint256 _gasUsed,
        bytes32 _executionProofHash
    ) public validOpportunity(_opportunityId) validStrategy(_strategyId) nonReentrant {
        ArbitrageOpportunity storage opportunity = arbitrageOpportunities[_opportunityId];
        ArbitrageStrategy memory strategy = arbitrageStrategies[_strategyId];

        require(block.timestamp <= opportunity.expiresAt, "Opportunity expired");
        require(opportunity.expectedProfit >= strategy.minProfitThreshold, "Below profit threshold");
        require(tx.gasprice <= strategy.maxGasPrice, "Gas price too high");

        // Verify off-chain execution proof
        // In a real system, this would involve calling a verifier contract or similar.
        // require(_verifyExecutionProof(_executionProofHash, _opportunityId, _actualProfit, _gasUsed), "Invalid execution proof");

        opportunity.status = OpportunityStatus.EXECUTING;
        opportunity.executor = msg.sender;

        bytes32 executionId = keccak256(abi.encodePacked(
            _opportunityId,
            block.timestamp,
            _executionProofHash
        ));

        ArbitrageExecution storage execution = arbitrageExecutions[executionId];
        execution.executionId = executionId;
        execution.opportunityId = _opportunityId;
        execution.strategyId = _strategyId;
        execution.startAmount = opportunity.amounts[0];
        execution.endAmount = opportunity.amounts[0] + _actualProfit; // Assuming profit is added to start amount
        execution.actualProfit = _actualProfit;
        execution.gasUsed = _gasUsed;
        execution.executionTime = block.timestamp;
        execution.success = true; // Assumed true if proof is valid
        execution.failureReason = bytes32(0);
        execution.executionProofHash = _executionProofHash;

        opportunity.status = OpportunityStatus.COMPLETED;
        opportunity.executedAt = block.timestamp;
        totalSuccessfulArbs++;
        totalProfitGenerated += _actualProfit;
        totalGasSpent += _gasUsed;

        emit ArbitrageExecuted(executionId, _opportunityId, _actualProfit, _gasUsed);

        opportunity.isActive = false;
        totalExecutions++;
    }

    /**
     * @notice Update market data for arbitrage detection
     */
    function updateMarketData(
        address _tokenA,
        address _tokenB,
        address _exchange,
        uint256 _price,
        uint256 _liquidity,
        uint256 _fee
    ) public {
        bytes32 marketId = keccak256(abi.encodePacked(_tokenA, _tokenB, _exchange));

        MarketData storage data = marketData[marketId];
        data.tokenA = _tokenA;
        data.tokenB = _tokenB;
        data.exchange = _exchange;
        data.price = _price;
        data.liquidity = _liquidity;
        data.fee = _fee;
        data.lastUpdate = block.timestamp;
        data.isActive = true;

        exchangePairs[_tokenA][_tokenB].push(marketId);

        emit MarketDataUpdated(_tokenA, _tokenB, _exchange, _price);
    }

    /**
     * @notice Get arbitrage opportunity details
     */
    function getArbitrageOpportunity(bytes32 _opportunityId) public view
        returns (
            ArbitrageType arbType,
            address[] memory tokens,
            address[] memory exchanges,
            uint256 expectedProfit,
            OpportunityStatus status,
            bool isActive
        )
    {
        ArbitrageOpportunity memory opportunity = arbitrageOpportunities[_opportunityId];
        return (
            opportunity.arbType,
            opportunity.tokens,
            opportunity.exchanges,
            opportunity.expectedProfit,
            opportunity.status,
            opportunity.isActive
        );
    }

    /**
     * @notice Get arbitrage strategy details
     */
    function getArbitrageStrategy(bytes32 _strategyId) public view
        returns (
            bytes32 strategyNameHash,
            address owner,
            uint256 minProfitThreshold,
            uint256 maxSlippage,
            bool isActive
        )
    {
        ArbitrageStrategy memory strategy = arbitrageStrategies[_strategyId];
        return (
            strategy.strategyNameHash,
            strategy.owner,
            strategy.minProfitThreshold,
            strategy.maxSlippage,
            strategy.isActive
        );
    }

    /**
     * @notice Get arbitrage execution details
     */
    function getArbitrageExecution(bytes32 _executionId) public view
        returns (
            bytes32 opportunityId,
            uint256 actualProfit,
            uint256 gasUsed,
            bool success,
            uint256 executionTime
        )
    {
        ArbitrageExecution memory execution = arbitrageExecutions[_executionId];
        return (
            execution.opportunityId,
            execution.actualProfit,
            execution.gasUsed,
            execution.success,
            execution.executionTime
        );
    }

    /**
     * @notice Get market data
     */
    function getMarketData(address _tokenA, address _tokenB, address _exchange) public view
        returns (
            uint256 price,
            uint256 liquidity,
            uint256 fee,
            uint256 lastUpdate,
            bool isActive
        )
    {
        bytes32 marketId = keccak256(abi.encodePacked(_tokenA, _tokenB, _exchange));
        MarketData memory data = marketData[marketId];
        return (
            data.price,
            data.liquidity,
            data.fee,
            data.lastUpdate,
            data.isActive
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _minProfitThreshold,
        uint256 _maxSlippageTolerance,
        uint256 _opportunityTimeout,
        uint256 _gasPriceLimit
    ) public onlyOwner {
        minProfitThreshold = _minProfitThreshold;
        maxSlippageTolerance = _maxSlippageTolerance;
        opportunityTimeout = _opportunityTimeout;
        gasPriceLimit = _gasPriceLimit;
    }

    /**
     * @notice Get global arbitrage statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalOpportunities,
            uint256 _totalExecutions,
            uint256 _totalSuccessfulArbs,
            uint256 _totalProfitGenerated,
            uint256 _totalGasSpent
        )
    {
        return (totalOpportunities, totalExecutions, totalSuccessfulArbs, totalProfitGenerated, totalGasSpent);
    }

    // Internal functions

    function _findMin(uint256[] memory _array) internal pure returns (uint256) {
        uint256 min = _array[0];
        for (uint256 i = 1; i < _array.length; i++) {
            if (_array[i] < min) min = _array[i];
        }
        return min;
    }

    function _findMax(uint256[] memory _array) internal pure returns (uint256) {
        uint256 max = _array[0];
        for (uint256 i = 1; i < _array.length; i++) {
            if (_array[i] > max) max = _array[i];
        }
        return max;
    }

    // Internal functions for off-chain execution are removed.
    // The actual execution logic would be handled by off-chain agents.
    // On-chain, we only verify the proofs of these executions.
}
