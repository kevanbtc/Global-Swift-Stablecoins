// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title PortfolioRiskEngine
 * @notice Advanced portfolio risk management with VaR calculations and risk metrics
 * @dev Implements Value at Risk (VaR), Expected Shortfall (ES), and stress testing
 */
contract PortfolioRiskEngine is Ownable, ReentrancyGuard {

    using Math for uint256;

    enum RiskMeasure {
        VaR_95,         // 95% Value at Risk
        VaR_99,         // 99% Value at Risk
        ES_95,          // 95% Expected Shortfall
        ES_99,          // 99% Expected Shortfall
        MAX_DRAWDOWN,   // Maximum drawdown
        VOLATILITY,     // Portfolio volatility
        SHARPE_RATIO,   // Risk-adjusted return
        STRESS_TEST     // Stress test loss
    }

    enum RiskLevel {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    struct PortfolioPosition {
        address asset;
        uint256 quantity;           // In wei/base units
        uint256 entryPrice;         // Entry price in USD (18 decimals)
        uint256 currentPrice;       // Current price in USD (18 decimals)
        uint256 volatility;         // Annualized volatility (basis points)
        int256 correlation;         // Correlation coefficient (18 decimals, -1e18 to 1e18)
        uint256 lastUpdate;
    }

    struct RiskMetrics {
        uint256 portfolioValue;     // Total portfolio value in USD
        uint256 var95;             // 95% VaR in USD
        uint256 var99;             // 99% VaR in USD
        uint256 expectedShortfall95; // 95% ES in USD
        uint256 expectedShortfall99; // 99% ES in USD
        uint256 maxDrawdown;       // Maximum drawdown percentage (basis points)
        uint256 volatility;        // Portfolio volatility (basis points)
        uint256 sharpeRatio;       // Sharpe ratio (18 decimals)
        RiskLevel overallRisk;     // Overall risk assessment
        uint256 lastCalculated;
    }

    struct HistoricalReturn {
        int256 dailyReturn;             // Daily return (18 decimals)
        uint256 timestamp;
        uint256 portfolioValue;    // Portfolio value at time of return
    }

    struct StressScenario {
        string name;
        int256[] assetShocks;      // Price shocks for each asset (18 decimals)
        uint256 probability;       // Probability of scenario (basis points)
        bool isActive;
    }

    // Storage
    mapping(address => PortfolioPosition[]) public portfolioPositions;
    mapping(address => RiskMetrics) public portfolioRiskMetrics;
    mapping(address => HistoricalReturn[]) public historicalReturns;
    mapping(address => StressScenario[]) public stressScenarios;

    address[] public portfolios;

    // Risk parameters
    uint256 public constant CONFIDENCE_95 = 9500;  // 95% confidence level
    uint256 public constant CONFIDENCE_99 = 9900;  // 99% confidence level
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant DAYS_PER_YEAR = 365;

    // Risk thresholds
    uint256 public var95Threshold = 500000 * DECIMAL_PRECISION; // $500k VaR limit
    uint256 public maxDrawdownThreshold = 2000; // 20% max drawdown
    uint256 public volatilityThreshold = 5000;  // 50% max volatility

    // Events
    event PortfolioCreated(address indexed portfolio);
    event PositionAdded(address indexed portfolio, address asset, uint256 quantity);
    event PositionUpdated(address indexed portfolio, address asset, uint256 newQuantity);
    event RiskMetricsCalculated(address indexed portfolio, uint256 var95, RiskLevel riskLevel);
    event StressTestExecuted(address indexed portfolio, string scenario, uint256 loss);
    event RiskThresholdBreached(address indexed portfolio, RiskMeasure measure, uint256 value);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new portfolio for risk tracking
     */
    function createPortfolio(address portfolio) public onlyOwner {
        require(portfolio != address(0), "Invalid portfolio address");

        // Check if portfolio already exists
        for (uint256 i = 0; i < portfolios.length; i++) {
            require(portfolios[i] != portfolio, "Portfolio already exists");
        }

        portfolios.push(portfolio);
        emit PortfolioCreated(portfolio);
    }

    /**
     * @notice Add a position to a portfolio
     */
    function addPosition(
        address portfolio,
        address asset,
        uint256 quantity,
        uint256 entryPrice,
        uint256 volatility,
        int256 correlation
    ) public onlyOwner {
        require(quantity > 0, "Quantity must be > 0");
        require(entryPrice > 0, "Entry price must be > 0");

        PortfolioPosition memory position = PortfolioPosition({
            asset: asset,
            quantity: quantity,
            entryPrice: entryPrice,
            currentPrice: entryPrice,
            volatility: volatility,
            correlation: correlation,
            lastUpdate: block.timestamp
        });

        portfolioPositions[portfolio].push(position);
        emit PositionAdded(portfolio, asset, quantity);
    }

    /**
     * @notice Update position quantity and price
     */
    function updatePosition(
        address portfolio,
        uint256 positionIndex,
        uint256 newQuantity,
        uint256 currentPrice
    ) public onlyOwner {
        require(positionIndex < portfolioPositions[portfolio].length, "Invalid position index");
        require(currentPrice > 0, "Current price must be > 0");

        PortfolioPosition storage position = portfolioPositions[portfolio][positionIndex];
        position.quantity = newQuantity;
        position.currentPrice = currentPrice;
        position.lastUpdate = block.timestamp;

        emit PositionUpdated(portfolio, position.asset, newQuantity);
    }

    /**
     * @notice Calculate comprehensive risk metrics for a portfolio
     */
    function calculateRiskMetrics(address portfolio) public returns (RiskMetrics memory) {
        PortfolioPosition[] memory positions = portfolioPositions[portfolio];
        require(positions.length > 0, "Portfolio has no positions");

        // Calculate portfolio value
        uint256 portfolioValue = _calculatePortfolioValue(positions);

        // Calculate VaR using historical simulation
        uint256 var95 = _calculateVaR(portfolio, CONFIDENCE_95);
        uint256 var99 = _calculateVaR(portfolio, CONFIDENCE_99);

        // Calculate Expected Shortfall
        uint256 es95 = _calculateExpectedShortfall(portfolio, CONFIDENCE_95);
        uint256 es99 = _calculateExpectedShortfall(portfolio, CONFIDENCE_99);

        // Calculate maximum drawdown
        uint256 maxDrawdown = _calculateMaxDrawdown(portfolio);

        // Calculate portfolio volatility
        uint256 volatility = _calculatePortfolioVolatility(positions);

        // Calculate Sharpe ratio (simplified)
        uint256 sharpeRatio = _calculateSharpeRatio(portfolio);

        // Assess overall risk level
        RiskLevel overallRisk = _assessOverallRisk(var95, maxDrawdown, volatility);

        RiskMetrics memory metrics = RiskMetrics({
            portfolioValue: portfolioValue,
            var95: var95,
            var99: var99,
            expectedShortfall95: es95,
            expectedShortfall99: es99,
            maxDrawdown: maxDrawdown,
            volatility: volatility,
            sharpeRatio: sharpeRatio,
            overallRisk: overallRisk,
            lastCalculated: block.timestamp
        });

        portfolioRiskMetrics[portfolio] = metrics;

        // Check risk thresholds
        _checkRiskThresholds(portfolio, metrics);

        emit RiskMetricsCalculated(portfolio, var95, overallRisk);
        return metrics;
    }

    /**
     * @notice Execute stress test scenario
     */
    function executeStressTest(
        address portfolio,
        string memory scenarioName
    ) public returns (uint256 loss) {
        StressScenario[] memory scenarios = stressScenarios[portfolio];
        StressScenario memory scenario;

        // Find the scenario
        for (uint256 i = 0; i < scenarios.length; i++) {
            if (keccak256(bytes(scenarios[i].name)) == keccak256(bytes(scenarioName))) {
                scenario = scenarios[i];
                break;
            }
        }

        require(scenario.isActive, "Stress scenario not found or inactive");

        PortfolioPosition[] memory positions = portfolioPositions[portfolio];
        require(positions.length == scenario.assetShocks.length, "Scenario asset count mismatch");

        // Calculate portfolio loss under stress scenario
        loss = 0;
        for (uint256 i = 0; i < positions.length; i++) {
            int256 priceShock = scenario.assetShocks[i];
            uint256 positionValue = (positions[i].quantity * positions[i].currentPrice) / DECIMAL_PRECISION;

            if (priceShock < 0) {
                // Loss scenario
                uint256 lossAmount = (positionValue * uint256(-priceShock)) / DECIMAL_PRECISION;
                loss += lossAmount;
            }
        }

        emit StressTestExecuted(portfolio, scenarioName, loss);
        return loss;
    }

    /**
     * @notice Add historical return data
     */
    function addHistoricalReturn(
        address portfolio,
        int256 dailyReturn,
        uint256 portfolioValue
    ) public onlyOwner {
        HistoricalReturn memory histReturn = HistoricalReturn({
            dailyReturn: dailyReturn,
            timestamp: block.timestamp,
            portfolioValue: portfolioValue
        });

        historicalReturns[portfolio].push(histReturn);
    }

    /**
     * @notice Add stress test scenario
     */
    function addStressScenario(
        address portfolio,
        string memory name,
        int256[] memory assetShocks,
        uint256 probability
    ) public onlyOwner {
        require(probability <= BASIS_POINTS, "Invalid probability");

        StressScenario memory scenario = StressScenario({
            name: name,
            assetShocks: assetShocks,
            probability: probability,
            isActive: true
        });

        stressScenarios[portfolio].push(scenario);
    }

    /**
     * @notice Get portfolio positions
     */
    function getPortfolioPositions(address portfolio) public view
        returns (PortfolioPosition[] memory)
    {
        return portfolioPositions[portfolio];
    }

    /**
     * @notice Get risk metrics
     */
    function getRiskMetrics(address portfolio) public view
        returns (RiskMetrics memory)
    {
        return portfolioRiskMetrics[portfolio];
    }

    /**
     * @notice Update risk thresholds
     */
    function updateRiskThresholds(
        uint256 _var95Threshold,
        uint256 _maxDrawdownThreshold,
        uint256 _volatilityThreshold
    ) public onlyOwner {
        var95Threshold = _var95Threshold;
        maxDrawdownThreshold = _maxDrawdownThreshold;
        volatilityThreshold = _volatilityThreshold;
    }

    // Internal helper functions

    function _calculatePortfolioValue(PortfolioPosition[] memory positions)
        internal
        pure
        returns (uint256)
    {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < positions.length; i++) {
            uint256 positionValue = (positions[i].quantity * positions[i].currentPrice) / DECIMAL_PRECISION;
            totalValue += positionValue;
        }
        return totalValue;
    }

    function _calculateVaR(address portfolio, uint256 confidenceLevel)
        internal
        view
        returns (uint256)
    {
        HistoricalReturn[] memory histReturns = historicalReturns[portfolio];
        if (histReturns.length < 30) return 0; // Need at least 30 days of data

        // Sort returns to find percentile
        int256[] memory sortedReturns = new int256[](histReturns.length);
        for (uint256 i = 0; i < histReturns.length; i++) {
            sortedReturns[i] = histReturns[i].dailyReturn;
        }

        // Simple sort (bubble sort for small arrays)
        for (uint256 i = 0; i < sortedReturns.length; i++) {
            for (uint256 j = i + 1; j < sortedReturns.length; j++) {
                if (sortedReturns[i] > sortedReturns[j]) {
                    int256 temp = sortedReturns[i];
                    sortedReturns[i] = sortedReturns[j];
                    sortedReturns[j] = temp;
                }
            }
        }

        // Find the appropriate percentile
        uint256 index = (histReturns.length * (BASIS_POINTS - confidenceLevel)) / BASIS_POINTS;
        int256 varReturn = sortedReturns[index];

        // Convert to dollar amount (simplified)
        uint256 currentValue = portfolioRiskMetrics[portfolio].portfolioValue;
        if (varReturn < 0) {
            return (currentValue * uint256(-varReturn)) / DECIMAL_PRECISION;
        }

        return 0;
    }

    function _calculateExpectedShortfall(address portfolio, uint256 confidenceLevel)
        internal
        view
        returns (uint256)
    {
        HistoricalReturn[] memory histReturns = historicalReturns[portfolio];
        if (histReturns.length < 30) return 0;

        uint256 varValue = _calculateVaR(portfolio, confidenceLevel);
        if (varValue == 0) return 0;

        // Calculate average of returns worse than VaR
        uint256 count = 0;
        int256 totalLoss = 0;

        for (uint256 i = 0; i < histReturns.length; i++) {
            int256 dailyReturn = histReturns[i].dailyReturn;
            if (dailyReturn < 0) { // Only consider losses
                uint256 lossAmount = (portfolioRiskMetrics[portfolio].portfolioValue *
                                    uint256(-dailyReturn)) / DECIMAL_PRECISION;
                if (lossAmount >= varValue) {
                    totalLoss += dailyReturn;
                    count++;
                }
            }
        }

        if (count == 0) return varValue;

        int256 avgLoss = totalLoss / int256(count);
        return (portfolioRiskMetrics[portfolio].portfolioValue * uint256(-avgLoss)) / DECIMAL_PRECISION;
    }

    function _calculateMaxDrawdown(address portfolio) internal view returns (uint256) {
        HistoricalReturn[] memory histReturns = historicalReturns[portfolio];
        if (histReturns.length < 2) return 0;

        uint256 peak = histReturns[0].portfolioValue;
        uint256 maxDrawdown = 0;

        for (uint256 i = 1; i < histReturns.length; i++) {
            if (histReturns[i].portfolioValue > peak) {
                peak = histReturns[i].portfolioValue;
            }

            if (peak > 0) {
                uint256 drawdown = ((peak - histReturns[i].portfolioValue) * BASIS_POINTS) / peak;
                if (drawdown > maxDrawdown) {
                    maxDrawdown = drawdown;
                }
            }
        }

        return maxDrawdown;
    }

    function _calculatePortfolioVolatility(PortfolioPosition[] memory positions)
        internal
        view
        returns (uint256)
    {
        if (positions.length == 0) return 0;

        // Simplified volatility calculation using position weights and individual volatilities
        uint256 totalValue = _calculatePortfolioValue(positions);
        uint256 weightedVolatility = 0;

        for (uint256 i = 0; i < positions.length; i++) {
            uint256 positionValue = (positions[i].quantity * positions[i].currentPrice) / DECIMAL_PRECISION;
            uint256 weight = (positionValue * DECIMAL_PRECISION) / totalValue;
            weightedVolatility += (weight * positions[i].volatility) / DECIMAL_PRECISION;
        }

        return weightedVolatility;
    }

    function _calculateSharpeRatio(address portfolio) internal view returns (uint256) {
        HistoricalReturn[] memory histReturns = historicalReturns[portfolio];
        if (histReturns.length < 30) return 0;

        // Calculate average return
        int256 totalReturn = 0;
        for (uint256 i = 0; i < histReturns.length; i++) {
            totalReturn += histReturns[i].dailyReturn;
        }
        int256 avgReturn = totalReturn / int256(histReturns.length);

        // Calculate standard deviation (simplified)
        int256 sumSquaredDiffs = 0;
        for (uint256 i = 0; i < histReturns.length; i++) {
            int256 diff = histReturns[i].dailyReturn - avgReturn;
            sumSquaredDiffs += int256(uint256(diff * diff) / DECIMAL_PRECISION);
        }
        uint256 variance = uint256(sumSquaredDiffs) / histReturns.length;
        uint256 stdDev = Math.sqrt(variance * DECIMAL_PRECISION);

        // Sharpe ratio = (avg return - risk free rate) / std dev
        // Simplified: assume 0% risk-free rate
        if (stdDev == 0) return 0;

        return (uint256(avgReturn) * DECIMAL_PRECISION) / stdDev;
    }

    function _assessOverallRisk(
        uint256 var95,
        uint256 maxDrawdown,
        uint256 volatility
    ) internal view returns (RiskLevel) {
        uint256 riskScore = 0;

        // VaR risk
        if (var95 > var95Threshold) {
            riskScore += 40;
        } else if (var95 > var95Threshold / 2) {
            riskScore += 20;
        }

        // Drawdown risk
        if (maxDrawdown > maxDrawdownThreshold) {
            riskScore += 35;
        } else if (maxDrawdown > maxDrawdownThreshold / 2) {
            riskScore += 15;
        }

        // Volatility risk
        if (volatility > volatilityThreshold) {
            riskScore += 25;
        } else if (volatility > volatilityThreshold / 2) {
            riskScore += 10;
        }

        if (riskScore >= 80) return RiskLevel.CRITICAL;
        if (riskScore >= 50) return RiskLevel.HIGH;
        if (riskScore >= 25) return RiskLevel.MEDIUM;
        return RiskLevel.LOW;
    }

    function _checkRiskThresholds(address portfolio, RiskMetrics memory metrics) internal {
        if (metrics.var95 > var95Threshold) {
            emit RiskThresholdBreached(portfolio, RiskMeasure.VaR_95, metrics.var95);
        }
        if (metrics.maxDrawdown > maxDrawdownThreshold) {
            emit RiskThresholdBreached(portfolio, RiskMeasure.MAX_DRAWDOWN, metrics.maxDrawdown);
        }
        if (metrics.volatility > volatilityThreshold) {
            emit RiskThresholdBreached(portfolio, RiskMeasure.VOLATILITY, metrics.volatility);
        }
    }
}
