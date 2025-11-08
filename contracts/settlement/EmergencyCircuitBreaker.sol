// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EmergencyCircuitBreaker
 * @notice Advanced circuit breaker with multiple trigger conditions and recovery mechanisms
 * @dev Provides comprehensive system protection against extreme market conditions
 */
contract EmergencyCircuitBreaker is Ownable, Pausable {
    enum TriggerType { PRICE_VOLATILITY, VOLUME_SPIKE, ORACLE_FAILURE, REGULATORY_FLAG }

    struct CircuitBreaker {
        bool isActive;
        uint256 triggerThreshold;
        uint256 recoveryThreshold;
        uint256 lastTriggered;
        uint256 cooldownPeriod;
        TriggerType triggerType;
    }

    struct MarketData {
        uint256 price;
        uint256 volume24h;
        uint256 volatilityIndex;
        uint256 lastUpdate;
    }

    mapping(bytes32 => CircuitBreaker) public circuitBreakers;
    mapping(address => MarketData) public marketData;
    mapping(address => bool) public authorizedOracles;

    uint256 public constant MAX_VOLATILITY_INDEX = 10000; // 100% volatility threshold
    uint256 public constant MAX_VOLUME_MULTIPLIER = 10; // 10x normal volume
    uint256 public constant COOLDOWN_PERIOD = 1 hours;

    event CircuitBreakerTriggered(bytes32 indexed breakerId, TriggerType triggerType, uint256 timestamp);
    event CircuitBreakerReset(bytes32 indexed breakerId, uint256 timestamp);
    event MarketDataUpdated(address indexed asset, uint256 price, uint256 volume, uint256 volatility);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Configure a circuit breaker
     */
    function configureCircuitBreaker(
        bytes32 breakerId,
        TriggerType triggerType,
        uint256 triggerThreshold,
        uint256 recoveryThreshold,
        uint256 cooldownPeriod
    ) public onlyOwner {
        circuitBreakers[breakerId] = CircuitBreaker({
            isActive: false,
            triggerThreshold: triggerThreshold,
            recoveryThreshold: recoveryThreshold,
            lastTriggered: 0,
            cooldownPeriod: cooldownPeriod,
            triggerType: triggerType
        });
    }

    /**
     * @notice Update market data from authorized oracle
     */
    function updateMarketData(
        address asset,
        uint256 price,
        uint256 volume24h,
        uint256 volatilityIndex
    ) public {
        require(authorizedOracles[msg.sender], "Unauthorized oracle");

        marketData[asset] = MarketData({
            price: price,
            volume24h: volume24h,
            volatilityIndex: volatilityIndex,
            lastUpdate: block.timestamp
        });

        emit MarketDataUpdated(asset, price, volume24h, volatilityIndex);

        // Check all circuit breakers
        _checkAllCircuitBreakers(asset);
    }

    /**
     * @notice Check if settlement is allowed for given assets
     */
    function isSettlementAllowed(address[] memory assets) public view returns (bool) {
        for (uint i = 0; i < assets.length; i++) {
            if (_isAssetCircuitBroken(assets[i])) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Manually trigger circuit breaker (governance only)
     */
    function triggerCircuitBreaker(bytes32 breakerId) public onlyOwner {
        CircuitBreaker storage cb = circuitBreakers[breakerId];
        require(!cb.isActive, "Already active");

        cb.isActive = true;
        cb.lastTriggered = block.timestamp;

        _pauseSystem();
        emit CircuitBreakerTriggered(breakerId, cb.triggerType, block.timestamp);
    }

    /**
     * @notice Reset circuit breaker if conditions met
     */
    function resetCircuitBreaker(bytes32 breakerId) public onlyOwner {
        CircuitBreaker storage cb = circuitBreakers[breakerId];
        require(cb.isActive, "Not active");
        require(block.timestamp >= cb.lastTriggered + cb.cooldownPeriod, "Cooldown active");

        // Check if recovery conditions met
        if (_checkRecoveryConditions(cb)) {
            cb.isActive = false;
            _unpauseSystem();
            emit CircuitBreakerReset(breakerId, block.timestamp);
        }
    }

    /**
     * @notice Authorize oracle for market data updates
     */
    function authorizeOracle(address oracle, bool authorized) public onlyOwner {
        authorizedOracles[oracle] = authorized;
    }

    // Internal functions

    function _checkAllCircuitBreakers(address asset) internal {
        MarketData memory data = marketData[asset];

        // Price volatility breaker
        if (data.volatilityIndex > circuitBreakers[keccak256("PRICE_VOLATILITY")].triggerThreshold) {
            _triggerBreaker(keccak256("PRICE_VOLATILITY"));
        }

        // Volume spike breaker
        // Implementation would compare to historical average
        if (data.volume24h > circuitBreakers[keccak256("VOLUME_SPIKE")].triggerThreshold) {
            _triggerBreaker(keccak256("VOLUME_SPIKE"));
        }
    }

    function _triggerBreaker(bytes32 breakerId) internal {
        CircuitBreaker storage cb = circuitBreakers[breakerId];
        if (!cb.isActive && block.timestamp >= cb.lastTriggered + cb.cooldownPeriod) {
            cb.isActive = true;
            cb.lastTriggered = block.timestamp;
            _pauseSystem();
            emit CircuitBreakerTriggered(breakerId, cb.triggerType, block.timestamp);
        }
    }

    function _isAssetCircuitBroken(address asset) internal view returns (bool) {
        // Check if any circuit breaker is active for this asset type
        return paused(); // Simplified - in production would check specific breakers
    }

    function _checkRecoveryConditions(CircuitBreaker memory cb) internal view returns (bool) {
        // Implementation would check if market conditions have normalized
        return true; // Simplified for demo
    }

    function _pauseSystem() internal {
        _pause();
        // Additional system-wide pause logic would go here
    }

    function _unpauseSystem() internal {
        _unpause();
        // Additional system-wide unpause logic would go here
    }
}
