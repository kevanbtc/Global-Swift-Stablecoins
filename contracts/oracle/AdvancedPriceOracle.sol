// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title AdvancedPriceOracle
 * @notice Enhanced price oracle with staleness checks, fallback mechanisms, and circuit breakers
 * @dev Provides reliable price feeds for DeFi protocols with multiple safeguards
 */
contract AdvancedPriceOracle is Ownable, ReentrancyGuard {

    struct PriceFeed {
        AggregatorV3Interface aggregator;
        uint8 decimals;
        bool isActive;
        uint256 heartbeat;          // Maximum age of price in seconds
        uint256 deviationThreshold; // Maximum deviation from TWAP in basis points
        address fallbackOracle;     // Backup price source
        uint256 lastUpdateTime;
        int256 lastPrice;
    }

    struct TWAPData {
        uint256 cumulativePrice;    // Sum of prices over time
        uint256 lastUpdateTime;     // Last update timestamp
        uint256 observationPeriod;  // TWAP observation window
        uint256 totalObservations;  // Number of price observations
    }

    struct CircuitBreaker {
        bool isActive;
        uint256 maxDeviation;       // Maximum allowed deviation in basis points
        uint256 cooldownPeriod;     // Cooldown after circuit breaker triggers
        uint256 lastTriggerTime;
        uint256 triggerCount;
    }

    // Storage
    mapping(address => PriceFeed) public priceFeeds;
    mapping(address => TWAPData) public twapData;
    mapping(address => CircuitBreaker) public circuitBreakers;

    address[] public supportedAssets;

    // Constants
    uint256 public constant MAX_DEVIATION = 5000; // 50% max deviation
    uint256 public constant GRACE_PERIOD = 3600;  // 1 hour grace period
    uint256 public constant BASIS_POINTS = 10000;

    // Events
    event PriceFeedAdded(address indexed asset, address aggregator, uint256 heartbeat);
    event PriceFeedUpdated(address indexed asset, int256 price, uint256 timestamp);
    event CircuitBreakerTriggered(address indexed asset, uint256 deviation);
    event CircuitBreakerReset(address indexed asset);
    event FallbackUsed(address indexed asset, address fallbackOracle);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Add a new price feed for an asset
     */
    function addPriceFeed(
        address asset,
        address aggregator,
        uint256 heartbeat,
        uint256 deviationThreshold,
        address fallbackOracle,
        uint256 observationPeriod
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(aggregator != address(0), "Invalid aggregator address");
        require(heartbeat > 0, "Heartbeat must be > 0");
        require(deviationThreshold <= BASIS_POINTS, "Invalid deviation threshold");

        AggregatorV3Interface priceAggregator = AggregatorV3Interface(aggregator);
        uint8 decimals = priceAggregator.decimals();

        PriceFeed memory feed = PriceFeed({
            aggregator: priceAggregator,
            decimals: decimals,
            isActive: true,
            heartbeat: heartbeat,
            deviationThreshold: deviationThreshold,
            fallbackOracle: fallbackOracle,
            lastUpdateTime: 0,
            lastPrice: 0
        });

        priceFeeds[asset] = feed;
        twapData[asset] = TWAPData({
            cumulativePrice: 0,
            lastUpdateTime: block.timestamp,
            observationPeriod: observationPeriod,
            totalObservations: 0
        });

        // Initialize circuit breaker
        circuitBreakers[asset] = CircuitBreaker({
            isActive: true,
            maxDeviation: MAX_DEVIATION,
            cooldownPeriod: 3600, // 1 hour
            lastTriggerTime: 0,
            triggerCount: 0
        });

        supportedAssets.push(asset);

        emit PriceFeedAdded(asset, aggregator, heartbeat);
    }

    /**
     * @notice Get the latest price for an asset with all safety checks
     */
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp) {
        require(priceFeeds[asset].isActive, "Price feed not active");

        PriceFeed memory feed = priceFeeds[asset];
        CircuitBreaker memory breaker = circuitBreakers[asset];

        // Check if circuit breaker is active
        if (breaker.isActive && breaker.lastTriggerTime > 0) {
            require(
                block.timestamp >= breaker.lastTriggerTime + breaker.cooldownPeriod,
                "Circuit breaker active"
            );
        }

        // Try primary oracle
        (int256 primaryPrice, uint256 primaryTimestamp) = _getPriceFromAggregator(feed.aggregator);

        // Check staleness
        require(
            block.timestamp <= primaryTimestamp + feed.heartbeat + GRACE_PERIOD,
            "Primary price feed stale"
        );

        // Check deviation from TWAP
        if (twapData[asset].totalObservations > 0) {
            uint256 twapPrice = _getTWAP(asset);
            uint256 deviation = _calculateDeviation(uint256(primaryPrice), twapPrice);

            if (deviation > feed.deviationThreshold) {
                // Try fallback oracle
                if (feed.fallbackOracle != address(0)) {
                    (int256 fallbackPrice, uint256 fallbackTimestamp) = _getPriceFromAggregator(
                        AggregatorV3Interface(feed.fallbackOracle)
                    );

                    // Check fallback staleness
                    require(
                        block.timestamp <= fallbackTimestamp + feed.heartbeat + GRACE_PERIOD,
                        "Fallback price feed stale"
                    );

                    // Check fallback deviation
                    uint256 fallbackDeviation = _calculateDeviation(uint256(fallbackPrice), twapPrice);
                    require(fallbackDeviation <= feed.deviationThreshold, "Price deviation too high");

                    return (uint256(fallbackPrice), fallbackTimestamp);
                }

                revert("Price deviation too high, no valid fallback");
            }
        }

        return (uint256(primaryPrice), primaryTimestamp);
    }

    /**
     * @notice Get price without safety checks (for internal use)
     */
    function getRawPrice(address asset) external view returns (int256 price, uint256 timestamp) {
        require(priceFeeds[asset].isActive, "Price feed not active");
        return _getPriceFromAggregator(priceFeeds[asset].aggregator);
    }

    /**
     * @notice Get TWAP price for an asset
     */
    function getTWAP(address asset) external view returns (uint256) {
        return _getTWAP(asset);
    }

    /**
     * @notice Update TWAP with latest price observation
     */
    function updateTWAP(address asset) external {
        require(priceFeeds[asset].isActive, "Price feed not active");

        (int256 price, uint256 timestamp) = _getPriceFromAggregator(priceFeeds[asset].aggregator);
        require(price > 0, "Invalid price");

        TWAPData storage twap = twapData[asset];
        uint256 timeElapsed = timestamp - twap.lastUpdateTime;

        if (timeElapsed > 0) {
            twap.cumulativePrice += uint256(price) * timeElapsed;
            twap.lastUpdateTime = timestamp;
            twap.totalObservations++;
        }
    }

    /**
     * @notice Check if price feed is healthy
     */
    function isHealthy(address asset) external view returns (bool) {
        if (!priceFeeds[asset].isActive) return false;

        PriceFeed memory feed = priceFeeds[asset];
        CircuitBreaker memory breaker = circuitBreakers[asset];

        // Check circuit breaker
        if (breaker.isActive && breaker.lastTriggerTime > 0) {
            if (block.timestamp < breaker.lastTriggerTime + breaker.cooldownPeriod) {
                return false;
            }
        }

        // Check staleness
        (, uint256 timestamp) = _getPriceFromAggregator(feed.aggregator);
        if (block.timestamp > timestamp + feed.heartbeat + GRACE_PERIOD) {
            return false;
        }

        // Check deviation
        if (twapData[asset].totalObservations > 0) {
            (int256 price,) = _getPriceFromAggregator(feed.aggregator);
            uint256 twapPrice = _getTWAP(asset);
            uint256 deviation = _calculateDeviation(uint256(price), twapPrice);

            if (deviation > feed.deviationThreshold) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Manually trigger circuit breaker
     */
    function triggerCircuitBreaker(address asset) external onlyOwner {
        CircuitBreaker storage breaker = circuitBreakers[asset];
        breaker.lastTriggerTime = block.timestamp;
        breaker.triggerCount++;

        emit CircuitBreakerTriggered(asset, 0); // Deviation not calculated here
    }

    /**
     * @notice Reset circuit breaker
     */
    function resetCircuitBreaker(address asset) external onlyOwner {
        CircuitBreaker storage breaker = circuitBreakers[asset];
        breaker.lastTriggerTime = 0;

        emit CircuitBreakerReset(asset);
    }

    /**
     * @notice Update circuit breaker settings
     */
    function updateCircuitBreaker(
        address asset,
        bool isActive,
        uint256 maxDeviation,
        uint256 cooldownPeriod
    ) external onlyOwner {
        CircuitBreaker storage breaker = circuitBreakers[asset];
        breaker.isActive = isActive;
        breaker.maxDeviation = maxDeviation;
        breaker.cooldownPeriod = cooldownPeriod;
    }

    /**
     * @notice Get supported assets
     */
    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    // Internal functions

    function _getPriceFromAggregator(AggregatorV3Interface aggregator)
        internal
        view
        returns (int256 price, uint256 timestamp)
    {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.latestRoundData();

        require(answer > 0, "Invalid price from aggregator");
        require(updatedAt > 0, "Round not complete");

        return (answer, updatedAt);
    }

    function _getTWAP(address asset) internal view returns (uint256) {
        TWAPData memory twap = twapData[asset];
        if (twap.totalObservations == 0) return 0;

        uint256 timeElapsed = block.timestamp - twap.lastUpdateTime;
        if (timeElapsed >= twap.observationPeriod) {
            return twap.cumulativePrice / twap.observationPeriod;
        }

        return 0; // Not enough data
    }

    function _calculateDeviation(uint256 price, uint256 referencePrice)
        internal
        pure
        returns (uint256)
    {
        if (referencePrice == 0) return 0;

        if (price > referencePrice) {
            return ((price - referencePrice) * BASIS_POINTS) / referencePrice;
        } else {
            return ((referencePrice - price) * BASIS_POINTS) / referencePrice;
        }
    }
}
