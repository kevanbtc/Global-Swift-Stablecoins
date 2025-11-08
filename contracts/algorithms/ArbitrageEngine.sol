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
    }

    struct ArbitrageStrategy {
        bytes32 strategyId;
        string strategyName;
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
    event StrategyDeployed(bytes32 indexed strategyId, string name, address owner);
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
        string memory _strategyName,
        ArbitrageType[] memory _supportedTypes,
        uint256 _minProfitThreshold,
        uint256 _maxSlippage,
        uint256 _maxGasPrice,
        uint256 _maxTradeSize,
        bytes32 _riskParameters
    ) public returns (bytes32) {
        bytes32 strategyId = keccak256(abi.encodePacked(
            _strategyName,
            msg.sender,
            block.timestamp
        ));

        ArbitrageStrategy storage strategy = arbitrageStrategies[strategyId];
        strategy.strategyId = strategyId;
        strategy.strategyName = _strategyName;
        strategy.owner = msg.sender;
        strategy.supportedTypes = _supportedTypes;
        strategy.minProfitThreshold = _minProfitThreshold;
        strategy.maxSlippage = _maxSlippage;
        strategy.maxGasPrice = _maxGasPrice;
        strategy.maxTradeSize = _maxTradeSize;
        strategy.riskParameters = _riskParameters;
        strategy.isActive = true;

        emit StrategyDeployed(strategyId, _strategyName, msg.sender);
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
        uint256[] memory _amounts
    ) public returns (bytes32) {
        require(_exchanges.length >= 3, "Need at least 3 exchanges");
        require(_amounts.length == 3, "Need 3 amounts");

        // Calculate arbitrage path: A -> B -> C -> A
        uint256 startAmount = _amounts[0];
        uint256 amountB = _calculateSwapAmount(_tokenA, _tokenB, _exchanges[0], startAmount);
        uint256 amountC = _calculateSwapAmount(_tokenB, _tokenC, _exchanges[1], amountB);
        uint256 finalAmount = _calculateSwapAmount(_tokenC, _tokenA, _exchanges[2], amountC);

        uint256 profit = finalAmount > startAmount ? finalAmount - startAmount : 0;
        uint256 profitPercentage = (profit * 10000) / startAmount;

        if (profitPercentage >= minProfitThreshold) {
            bytes32 opportunityId = keccak256(abi.encodePacked(
                "TRIANGULAR",
                _tokenA,
                _tokenB,
                _tokenC,
                block.timestamp
            ));

            ArbitrageOpportunity storage opportunity = arbitrageOpportunities[opportunityId];
            opportunity.opportunityId = opportunityId;
            opportunity.arbType = ArbitrageType.TRIANGULAR;
            opportunity.tokens = [_tokenA, _tokenB, _tokenC];
            opportunity.exchanges = _exchanges;
            opportunity.amounts = _amounts;
            opportunity.expectedProfit = profit;
            opportunity.status = OpportunityStatus.DETECTED;
            opportunity.detectedAt = block.timestamp;
            opportunity.expiresAt = block.timestamp + opportunityTimeout;
            opportunity.isActive = true;

            totalOpportunities++;

            emit ArbitrageOpportunityDetected(opportunityId, ArbitrageType.TRIANGULAR, profit);
            return opportunityId;
        }

        return bytes32(0);
    }

    /**
     * @notice Detect cross-DEX arbitrage opportunity
     */
    function detectCrossDEXArbitrage(
        address _tokenA,
        address _tokenB,
        address[] memory _exchanges,
        uint256 _amount
    ) public returns (bytes32) {
        require(_exchanges.length >= 2, "Need at least 2 exchanges");

        uint256[] memory buyPrices = new uint256[](_exchanges.length);
        uint256[] memory sellPrices = new uint256[](_exchanges.length);

        // Get prices from each exchange
        for (uint256 i = 0; i < _exchanges.length; i++) {
            buyPrices[i] = _getBuyPrice(_tokenA, _tokenB, _exchanges[i]);
            sellPrices[i] = _getSellPrice(_tokenA, _tokenB, _exchanges[i]);
        }

        // Find best buy and sell prices
        uint256 bestBuyPrice = _findMin(buyPrices);
        uint256 bestSellPrice = _findMax(sellPrices);

        if (bestSellPrice > bestBuyPrice) {
            uint256 spread = bestSellPrice - bestBuyPrice;
            uint256 profitPercentage = (spread * 10000) / bestBuyPrice;

            if (profitPercentage >= minProfitThreshold) {
                bytes32 opportunityId = keccak256(abi.encodePacked(
                    "CROSS_DEX",
                    _tokenA,
                    _tokenB,
                    block.timestamp
                ));

                ArbitrageOpportunity storage opportunity = arbitrageOpportunities[opportunityId];
                opportunity.opportunityId = opportunityId;
                opportunity.arbType = ArbitrageType.CROSS_DEX;
                opportunity.tokens = [_tokenA, _tokenB];
                opportunity.exchanges = _exchanges;
                opportunity.prices = [bestBuyPrice, bestSellPrice];
                opportunity.amounts = [_amount];
                opportunity.expectedProfit = (spread * _amount) / bestBuyPrice;
                opportunity.status = OpportunityStatus.DETECTED;
                opportunity.detectedAt = block.timestamp;
                opportunity.expiresAt = block.timestamp + opportunityTimeout;
                opportunity.isActive = true;

                totalOpportunities++;

                emit ArbitrageOpportunityDetected(opportunityId, ArbitrageType.CROSS_DEX, opportunity.expectedProfit);
                return opportunityId;
            }
        }

        return bytes32(0);
    }

    /**
     * @notice Execute arbitrage opportunity
     */
    function executeArbitrage(
        bytes32 _opportunityId,
        bytes32 _strategyId
    ) public validOpportunity(_opportunityId) validStrategy(_strategyId) nonReentrant {
        ArbitrageOpportunity storage opportunity = arbitrageOpportunities[_opportunityId];
        ArbitrageStrategy memory strategy = arbitrageStrategies[_strategyId];

        require(block.timestamp <= opportunity.expiresAt, "Opportunity expired");
        require(opportunity.expectedProfit >= strategy.minProfitThreshold, "Below profit threshold");
        require(tx.gasprice <= strategy.maxGasPrice, "Gas price too high");

        opportunity.status = OpportunityStatus.EXECUTING;
        opportunity.executor = msg.sender;

        // Execute arbitrage based on type
        (bool success, uint256 actualProfit, bytes32 failureReason) = _executeArbitrageByType(opportunity);

        bytes32 executionId = keccak256(abi.encodePacked(
            _opportunityId,
            block.timestamp
        ));

        ArbitrageExecution storage execution = arbitrageExecutions[executionId];
        execution.executionId = executionId;
        execution.opportunityId = _opportunityId;
        execution.strategyId = _strategyId;
        execution.startAmount = opportunity.amounts[0];
        execution.actualProfit = actualProfit;
        execution.executionTime = block.timestamp;
        execution.success = success;
        execution.failureReason = failureReason;

        if (success) {
            opportunity.status = OpportunityStatus.COMPLETED;
            opportunity.executedAt = block.timestamp;
            totalSuccessfulArbs++;
            totalProfitGenerated += actualProfit;

            emit ArbitrageExecuted(executionId, _opportunityId, actualProfit, execution.gasUsed);
        } else {
            opportunity.status = OpportunityStatus.FAILED;
            emit ArbitrageFailed(_opportunityId, failureReason);
        }

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
            string memory strategyName,
            address owner,
            uint256 minProfitThreshold,
            uint256 maxSlippage,
            bool isActive
        )
    {
        ArbitrageStrategy memory strategy = arbitrageStrategies[_strategyId];
        return (
            strategy.strategyName,
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
    function _calculateSwapAmount(
        address _tokenIn,
        address _tokenOut,
        address _exchange,
        uint256 _amountIn
    ) internal view returns (uint256) {
        // Simplified swap calculation - in production would query actual DEX
        bytes32 marketId = keccak256(abi.encodePacked(_tokenIn, _tokenOut, _exchange));
        MarketData memory data = marketData[marketId];

        if (!data.isActive) return 0;

        // Apply fee
        uint256 amountAfterFee = _amountIn * (10000 - data.fee) / 10000;
        return (amountAfterFee * 1e18) / data.price; // Simplified conversion
    }

    function _getBuyPrice(address _tokenA, address _tokenB, address _exchange) internal view returns (uint256) {
        bytes32 marketId = keccak256(abi.encodePacked(_tokenA, _tokenB, _exchange));
        return marketData[marketId].price;
    }

    function _getSellPrice(address _tokenA, address _tokenB, address _exchange) internal view returns (uint256) {
        bytes32 marketId = keccak256(abi.encodePacked(_tokenA, _tokenB, _exchange));
        return marketData[marketId].price;
    }

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

    function _executeArbitrageByType(ArbitrageOpportunity storage _opportunity)
        internal
        returns (bool success, uint256 profit, bytes32 failureReason)
    {
        if (_opportunity.arbType == ArbitrageType.TRIANGULAR) {
            return _executeTriangularArbitrage(_opportunity);
        } else if (_opportunity.arbType == ArbitrageType.CROSS_DEX) {
            return _executeCrossDEXArbitrage(_opportunity);
        }

        return (false, 0, "UNSUPPORTED_TYPE");
    }

    function _executeTriangularArbitrage(ArbitrageOpportunity storage _opportunity)
        internal
        returns (bool success, uint256 profit, bytes32 failureReason)
    {
        // Simplified triangular arbitrage execution
        // In production, this would execute actual swaps on DEXes

        uint256 startAmount = _opportunity.amounts[0];
        uint256 expectedEndAmount = startAmount + _opportunity.expectedProfit;

        // Simulate execution with some slippage
        uint256 slippage = (_opportunity.expectedProfit * 50) / 10000; // 0.5% slippage
        uint256 actualEndAmount = expectedEndAmount - slippage;

        if (actualEndAmount > startAmount) {
            profit = actualEndAmount - startAmount;
            success = true;
        } else {
            failureReason = "SLIPPAGE_TOO_HIGH";
            success = false;
        }

        return (success, profit, failureReason);
    }

    function _executeCrossDEXArbitrage(ArbitrageOpportunity storage _opportunity)
        internal
        returns (bool success, uint256 profit, bytes32 failureReason)
    {
        // Simplified cross-DEX arbitrage execution
        // In production, this would execute buy on one DEX and sell on another

        uint256 expectedProfit = _opportunity.expectedProfit;

        // Simulate execution with gas costs
        uint256 gasCost = tx.gasprice * 200000; // Estimate 200k gas
        uint256 netProfit = expectedProfit - gasCost;

        if (netProfit > 0) {
            profit = netProfit;
            success = true;
            totalGasSpent += gasCost;
        } else {
            failureReason = "GAS_COST_TOO_HIGH";
            success = false;
        }

        return (success, profit, failureReason);
    }
}
