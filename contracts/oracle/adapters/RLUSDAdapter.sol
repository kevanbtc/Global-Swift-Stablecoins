// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQuoteAdapter} from "../../interfaces/IQuoteAdapter.sol";

/**
 * @title RLUSDAdapter
 * @notice Price oracle adapter for Ripple USD (RLUSD)
 * @dev RLUSD is designed to maintain 1:1 peg with USD, but we allow
 *      for minimal variance monitoring and multi-source price aggregation
 */
contract RLUSDAdapter {
    address public immutable rlusdToken;
    address public admin;
    
    // Price sources with weights
    struct PriceSource {
        address oracle;
        uint16 weightBps; // weight in basis points (10000 = 100%)
        bool active;
    }
    
    PriceSource[] public sources;
    uint256 public maxDeviation = 50; // 0.5% max deviation from $1.00
    uint256 public stalePeriod = 3600; // 1 hour
    
    struct PriceData {
        uint256 price;
        uint256 timestamp;
    }
    
    mapping(address => PriceData) public lastPriceBySource;
    
    event SourceAdded(address indexed oracle, uint16 weight);
    event SourceRemoved(address indexed oracle);
    event PriceUpdated(uint256 aggregatedPrice, uint256 timestamp);
    event DeviationAlert(uint256 price, uint256 deviation);
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "RLUSD: not admin");
        _;
    }
    
    constructor(address _rlusdToken, address _admin) {
        require(_rlusdToken != address(0) && _admin != address(0), "RLUSD: zero address");
        rlusdToken = _rlusdToken;
        admin = _admin;
    }
    
    /**
     * @notice Add a price source with weight
     * @param oracle Address of the price oracle
     * @param weightBps Weight in basis points (must sum to 10000 across all sources)
     */
    function addSource(address oracle, uint16 weightBps) external onlyAdmin {
        require(oracle != address(0), "RLUSD: zero oracle");
        require(weightBps > 0 && weightBps <= 10000, "RLUSD: invalid weight");
        
        sources.push(PriceSource({
            oracle: oracle,
            weightBps: weightBps,
            active: true
        }));
        
        emit SourceAdded(oracle, weightBps);
    }
    
    /**
     * @notice Deactivate a price source
     * @param index Index of the source to remove
     */
    function removeSource(uint256 index) external onlyAdmin {
        require(index < sources.length, "RLUSD: invalid index");
        sources[index].active = false;
        emit SourceRemoved(sources[index].oracle);
    }
    
    /**
     * @notice Update maximum allowed deviation from $1.00 peg
     * @param bps Deviation in basis points (e.g., 50 = 0.5%)
     */
    function setMaxDeviation(uint256 bps) external onlyAdmin {
        require(bps <= 500, "RLUSD: deviation too high"); // max 5%
        maxDeviation = bps;
    }
    
    /**
     * @notice Set stale period for price data
     * @param seconds_ Time in seconds after which price is considered stale
     */
    function setStalePeriod(uint256 seconds_) external onlyAdmin {
        require(seconds_ >= 60 && seconds_ <= 86400, "RLUSD: invalid period");
        stalePeriod = seconds_;
    }
    
    /**
     * @notice Get current RLUSD price (aggregated from all sources)
     * @return price RLUSD price in USD with 18 decimals (should be ~1e18)
     * @return decimals Always 18 for RLUSD
     * @return lastUpdate Timestamp of most recent price update
     */
    function quoteInCash(address /* instrument */) 
        external 
        view 
        returns (uint256 price, uint8 decimals, uint64 lastUpdate) 
    {
        decimals = 18;
        uint256 totalWeight = 0;
        uint256 weightedSum = 0;
        uint256 latestTimestamp = 0;
        
        for (uint256 i = 0; i < sources.length; i++) {
            if (!sources[i].active) continue;
            
            PriceData memory data = lastPriceBySource[sources[i].oracle];
            
            // Skip stale prices
            if (block.timestamp - data.timestamp > stalePeriod) continue;
            
            weightedSum += data.price * sources[i].weightBps;
            totalWeight += sources[i].weightBps;
            
            if (data.timestamp > latestTimestamp) {
                latestTimestamp = data.timestamp;
            }
        }
        
        require(totalWeight > 0, "RLUSD: no active sources");
        
        price = weightedSum / totalWeight;
        lastUpdate = uint64(latestTimestamp);
        
        // Check deviation from $1.00 peg
        uint256 deviation = price > 1e18 
            ? ((price - 1e18) * 10000) / 1e18 
            : ((1e18 - price) * 10000) / 1e18;
            
        require(deviation <= maxDeviation, "RLUSD: price deviation too high");
    }
    
    /**
     * @notice Check if RLUSD price data is fresh
     * @param maxAgeSec Maximum acceptable age in seconds
     * @return true if at least one active source has fresh data
     */
    function isFresh(address /* instrument */, uint64 maxAgeSec) 
        external 
        view 
        returns (bool) 
    {
        for (uint256 i = 0; i < sources.length; i++) {
            if (!sources[i].active) continue;
            
            PriceData memory data = lastPriceBySource[sources[i].oracle];
            
            if (block.timestamp - data.timestamp <= maxAgeSec) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @notice Update price from a specific source
     * @dev Called by authorized price feed oracles
     * @param price Price in USD with 18 decimals
     */
    function updatePrice(uint256 price) external {
        bool authorized = false;
        for (uint256 i = 0; i < sources.length; i++) {
            if (sources[i].oracle == msg.sender && sources[i].active) {
                authorized = true;
                break;
            }
        }
        require(authorized, "RLUSD: not authorized");
        
        lastPriceBySource[msg.sender] = PriceData({
            price: price,
            timestamp: block.timestamp
        });
        
        emit PriceUpdated(price, block.timestamp);
        
        // Alert if deviation is significant
        uint256 deviation = price > 1e18 
            ? ((price - 1e18) * 10000) / 1e18 
            : ((1e18 - price) * 10000) / 1e18;
            
        if (deviation > maxDeviation / 2) {
            emit DeviationAlert(price, deviation);
        }
    }
    
    /**
     * @notice Get aggregated price with metadata
     * @return price Current aggregated price
     * @return timestamp Most recent update timestamp
     * @return isStable Whether price is within acceptable deviation
     */
    function getPriceWithMetadata() external view returns (
        uint256 price,
        uint256 timestamp,
        bool isStable
    ) {
        uint256 totalWeight = 0;
        uint256 weightedSum = 0;
        uint256 latestTimestamp = 0;
        
        for (uint256 i = 0; i < sources.length; i++) {
            if (!sources[i].active) continue;
            
            PriceData memory data = lastPriceBySource[sources[i].oracle];
            
            if (block.timestamp - data.timestamp > stalePeriod) continue;
            
            weightedSum += data.price * sources[i].weightBps;
            totalWeight += sources[i].weightBps;
            
            if (data.timestamp > latestTimestamp) {
                latestTimestamp = data.timestamp;
            }
        }
        
        require(totalWeight > 0, "RLUSD: no active sources");
        
        price = weightedSum / totalWeight;
        timestamp = latestTimestamp;
        
        uint256 deviation = price > 1e18 
            ? ((price - 1e18) * 10000) / 1e18 
            : ((1e18 - price) * 10000) / 1e18;
            
        isStable = deviation <= maxDeviation;
    }
    
    /**
     * @notice Transfer admin rights
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "RLUSD: zero address");
        admin = newAdmin;
    }
}
