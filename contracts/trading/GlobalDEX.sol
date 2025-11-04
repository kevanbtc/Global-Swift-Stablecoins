// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title GlobalDEX
 * @notice Decentralized exchange for global financial markets
 * @dev Supports spot trading, derivatives, algorithmic trading, and arbitrage
 */
contract GlobalDEX is Ownable, ReentrancyGuard {

    enum OrderType {
        MARKET,
        LIMIT,
        STOP,
        STOP_LIMIT,
        TRAILING_STOP,
        ICEBERG,
        TWAP,
        VWAP
    }

    enum OrderSide {
        BUY,
        SELL
    }

    enum OrderStatus {
        PENDING,
        PARTIAL,
        FILLED,
        CANCELLED,
        EXPIRED,
        REJECTED
    }

    enum InstrumentType {
        SPOT,              // Spot trading
        FUTURE,            // Futures contracts
        OPTION,            // Options contracts
        SWAP,              // Interest rate swaps
        CFD,               // Contracts for Difference
        FOREX,             // Currency pairs
        CRYPTO,            // Cryptocurrency pairs
        COMMODITY,         // Commodities
        INDEX,             // Market indices
        BOND               // Bond trading
    }

    enum TimeInForce {
        GTC,               // Good Till Cancelled
        IOC,               // Immediate Or Cancel
        FOK,               // Fill Or Kill
        GTD,               // Good Till Date
        GTX                // Good Till Crossing
    }

    struct TradingPair {
        bytes32 pairId;
        address baseAsset;
        address quoteAsset;
        InstrumentType instrumentType;
        uint256 minOrderSize;
        uint256 maxOrderSize;
        uint256 tickSize;
        uint256 lotSize;
        uint256 makerFee;          // BPS
        uint256 takerFee;          // BPS
        bool isActive;
        bool requiresKYC;
        bytes32 jurisdiction;
    }

    struct Order {
        bytes32 orderId;
        bytes32 pairId;
        address trader;
        OrderType orderType;
        OrderSide side;
        uint256 quantity;
        uint256 price;
        uint256 stopPrice;
        uint256 limitPrice;
        TimeInForce timeInForce;
        uint256 expiration;
        uint256 filledQuantity;
        uint256 remainingQuantity;
        OrderStatus status;
        uint256 createdAt;
        uint256 updatedAt;
        bytes32 clientOrderId;
        bytes32 strategyId;
    }

    struct Trade {
        bytes32 tradeId;
        bytes32 orderId;
        bytes32 counterOrderId;
        bytes32 pairId;
        address maker;
        address taker;
        uint256 quantity;
        uint256 price;
        uint256 timestamp;
        uint256 makerFee;
        uint256 takerFee;
        bool isBuySide;
    }

    struct MarketData {
        bytes32 pairId;
        uint256 lastPrice;
        uint256 bidPrice;
        uint256 askPrice;
        uint256 volume24h;
        uint256 high24h;
        uint256 low24h;
        uint256 open24h;
        uint256 vwap24h;
        uint256 timestamp;
    }

    struct ArbitrageOpportunity {
        bytes32 opportunityId;
        bytes32[] pairs;
        uint256[] prices;
        uint256 profitPercentage;
        uint256 estimatedProfit;
        address[] path;
        bool isActive;
        uint256 detectedAt;
        uint256 expiresAt;
    }

    struct AlgorithmicStrategy {
        bytes32 strategyId;
        string strategyName;
        address owner;
        bytes32[] targetPairs;
        uint256 maxOrderSize;
        uint256 maxDrawdown;       // BPS
        uint256 profitTarget;      // BPS
        bool isActive;
        bool requiresApproval;
        bytes32 riskParameters;
        mapping(bytes32 => uint256) positionLimits;
    }

    // Storage
    mapping(bytes32 => TradingPair) public tradingPairs;
    mapping(bytes32 => Order) public orders;
    mapping(bytes32 => Trade) public trades;
    mapping(bytes32 => MarketData) public marketData;
    mapping(bytes32 => ArbitrageOpportunity) public arbitrageOpportunities;
    mapping(bytes32 => AlgorithmicStrategy) public algorithmicStrategies;

    // Order books
    mapping(bytes32 => mapping(uint256 => bytes32[])) public buyOrders;  // pairId => price => orderIds
    mapping(bytes32 => mapping(uint256 => bytes32[])) public sellOrders; // pairId => price => orderIds

    // Global statistics
    uint256 public totalPairs;
    uint256 public totalOrders;
    uint256 public totalTrades;
    uint256 public totalVolume;
    uint256 public totalFeesCollected;

    // Protocol parameters
    uint256 public maxSlippage = 300;     // 3% BPS
    uint256 public minOrderSize = 1e18;   // 1 unit
    uint256 public maxOrderSize = 1000000e18; // 1M units
    uint256 public defaultMakerFee = 10;  // 0.1% BPS
    uint256 public defaultTakerFee = 25;  // 0.25% BPS

    // Events
    event TradingPairCreated(bytes32 indexed pairId, address baseAsset, address quoteAsset);
    event OrderPlaced(bytes32 indexed orderId, bytes32 indexed pairId, address indexed trader, OrderType orderType, OrderSide side, uint256 quantity, uint256 price);
    event OrderFilled(bytes32 indexed orderId, bytes32 indexed tradeId, uint256 filledQuantity, uint256 price);
    event OrderCancelled(bytes32 indexed orderId, bytes32 indexed pairId);
    event TradeExecuted(bytes32 indexed tradeId, bytes32 indexed pairId, address maker, address taker, uint256 quantity, uint256 price);
    event ArbitrageDetected(bytes32 indexed opportunityId, uint256 profitPercentage);
    event StrategyDeployed(bytes32 indexed strategyId, string name, address owner);

    modifier validPair(bytes32 _pairId) {
        require(tradingPairs[_pairId].isActive, "Pair not active");
        _;
    }

    modifier validOrder(bytes32 _orderId) {
        require(orders[_orderId].createdAt > 0, "Order not found");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new trading pair
     */
    function createTradingPair(
        address _baseAsset,
        address _quoteAsset,
        InstrumentType _instrumentType,
        uint256 _minOrderSize,
        uint256 _maxOrderSize,
        uint256 _tickSize,
        uint256 _lotSize
    ) external onlyOwner returns (bytes32) {
        bytes32 pairId = keccak256(abi.encodePacked(
            _baseAsset,
            _quoteAsset,
            _instrumentType,
            block.timestamp
        ));

        require(tradingPairs[pairId].pairId == bytes32(0), "Pair already exists");

        TradingPair storage pair = tradingPairs[pairId];
        pair.pairId = pairId;
        pair.baseAsset = _baseAsset;
        pair.quoteAsset = _quoteAsset;
        pair.instrumentType = _instrumentType;
        pair.minOrderSize = _minOrderSize;
        pair.maxOrderSize = _maxOrderSize;
        pair.tickSize = _tickSize;
        pair.lotSize = _lotSize;
        pair.makerFee = defaultMakerFee;
        pair.takerFee = defaultTakerFee;
        pair.isActive = true;

        totalPairs++;

        emit TradingPairCreated(pairId, _baseAsset, _quoteAsset);
        return pairId;
    }

    /**
     * @notice Place a limit order
     */
    function placeLimitOrder(
        bytes32 _pairId,
        OrderSide _side,
        uint256 _quantity,
        uint256 _price,
        TimeInForce _timeInForce,
        uint256 _expiration,
        bytes32 _clientOrderId
    ) external validPair(_pairId) nonReentrant returns (bytes32) {
        TradingPair memory pair = tradingPairs[_pairId];

        // Validate order parameters
        require(_quantity >= pair.minOrderSize && _quantity <= pair.maxOrderSize, "Invalid quantity");
        require(_price % pair.tickSize == 0, "Price not multiple of tick size");
        require(_quantity % pair.lotSize == 0, "Quantity not multiple of lot size");

        bytes32 orderId = keccak256(abi.encodePacked(
            _pairId,
            msg.sender,
            _quantity,
            _price,
            block.timestamp
        ));

        Order storage order = orders[orderId];
        order.orderId = orderId;
        order.pairId = _pairId;
        order.trader = msg.sender;
        order.orderType = OrderType.LIMIT;
        order.side = _side;
        order.quantity = _quantity;
        order.price = _price;
        order.timeInForce = _timeInForce;
        order.expiration = _expiration > 0 ? _expiration : block.timestamp + 365 days;
        order.remainingQuantity = _quantity;
        order.status = OrderStatus.PENDING;
        order.createdAt = block.timestamp;
        order.updatedAt = block.timestamp;
        order.clientOrderId = _clientOrderId;

        // Add to order book
        if (_side == OrderSide.BUY) {
            buyOrders[_pairId][_price].push(orderId);
        } else {
            sellOrders[_pairId][_price].push(orderId);
        }

        totalOrders++;

        // Attempt immediate matching
        _matchOrder(orderId);

        emit OrderPlaced(orderId, _pairId, msg.sender, OrderType.LIMIT, _side, _quantity, _price);
        return orderId;
    }

    /**
     * @notice Place a market order
     */
    function placeMarketOrder(
        bytes32 _pairId,
        OrderSide _side,
        uint256 _quantity,
        bytes32 _clientOrderId
    ) external validPair(_pairId) nonReentrant returns (bytes32) {
        TradingPair memory pair = tradingPairs[_pairId];
        require(_quantity >= pair.minOrderSize && _quantity <= pair.maxOrderSize, "Invalid quantity");

        bytes32 orderId = keccak256(abi.encodePacked(
            _pairId,
            msg.sender,
            _quantity,
            block.timestamp
        ));

        Order storage order = orders[orderId];
        order.orderId = orderId;
        order.pairId = _pairId;
        order.trader = msg.sender;
        order.orderType = OrderType.MARKET;
        order.side = _side;
        order.quantity = _quantity;
        order.remainingQuantity = _quantity;
        order.status = OrderStatus.PENDING;
        order.createdAt = block.timestamp;
        order.updatedAt = block.timestamp;
        order.clientOrderId = _clientOrderId;

        totalOrders++;

        // Execute market order immediately
        _executeMarketOrder(orderId);

        emit OrderPlaced(orderId, _pairId, msg.sender, OrderType.MARKET, _side, _quantity, 0);
        return orderId;
    }

    /**
     * @notice Cancel an order
     */
    function cancelOrder(bytes32 _orderId) external validOrder(_orderId) {
        Order storage order = orders[_orderId];
        require(order.trader == msg.sender, "Not order owner");
        require(order.status == OrderStatus.PENDING || order.status == OrderStatus.PARTIAL, "Cannot cancel");

        order.status = OrderStatus.CANCELLED;
        order.updatedAt = block.timestamp;

        // Remove from order book
        _removeFromOrderBook(_orderId);

        emit OrderCancelled(_orderId, order.pairId);
    }

    /**
     * @notice Deploy an algorithmic trading strategy
     */
    function deployStrategy(
        string memory _strategyName,
        bytes32[] memory _targetPairs,
        uint256 _maxOrderSize,
        uint256 _maxDrawdown,
        uint256 _profitTarget,
        bytes32 _riskParameters
    ) external returns (bytes32) {
        bytes32 strategyId = keccak256(abi.encodePacked(
            _strategyName,
            msg.sender,
            block.timestamp
        ));

        AlgorithmicStrategy storage strategy = algorithmicStrategies[strategyId];
        strategy.strategyId = strategyId;
        strategy.strategyName = _strategyName;
        strategy.owner = msg.sender;
        strategy.targetPairs = _targetPairs;
        strategy.maxOrderSize = _maxOrderSize;
        strategy.maxDrawdown = _maxDrawdown;
        strategy.profitTarget = _profitTarget;
        strategy.riskParameters = _riskParameters;
        strategy.isActive = true;

        emit StrategyDeployed(strategyId, _strategyName, msg.sender);
        return strategyId;
    }

    /**
     * @notice Execute arbitrage trade
     */
    function executeArbitrage(bytes32 _opportunityId) external nonReentrant {
        ArbitrageOpportunity storage opportunity = arbitrageOpportunities[_opportunityId];
        require(opportunity.isActive, "Opportunity not active");
        require(block.timestamp <= opportunity.expiresAt, "Opportunity expired");

        // Execute arbitrage logic (simplified)
        // In production, this would execute the triangular arbitrage
        opportunity.isActive = false;

        // Record profit
        // This is simplified - actual implementation would track real profits
    }

    /**
     * @notice Update market data
     */
    function updateMarketData(
        bytes32 _pairId,
        uint256 _lastPrice,
        uint256 _bidPrice,
        uint256 _askPrice,
        uint256 _volume24h
    ) external onlyOwner validPair(_pairId) {
        MarketData storage data = marketData[_pairId];
        data.pairId = _pairId;
        data.lastPrice = _lastPrice;
        data.bidPrice = _bidPrice;
        data.askPrice = _askPrice;
        data.volume24h = _volume24h;
        data.timestamp = block.timestamp;

        // Update 24h stats
        if (data.open24h == 0) {
            data.open24h = _lastPrice;
        }
        if (_lastPrice > data.high24h) {
            data.high24h = _lastPrice;
        }
        if (data.low24h == 0 || _lastPrice < data.low24h) {
            data.low24h = _lastPrice;
        }

        // Check for arbitrage opportunities
        _checkArbitrageOpportunities(_pairId);
    }

    /**
     * @notice Get order book depth
     */
    function getOrderBook(bytes32 _pairId, uint256 _depth)
        external
        view
        returns (
            uint256[] memory bidPrices,
            uint256[] memory bidVolumes,
            uint256[] memory askPrices,
            uint256[] memory askVolumes
        )
    {
        // Simplified order book retrieval
        // In production, this would return actual order book data
        bidPrices = new uint256[](_depth);
        bidVolumes = new uint256[](_depth);
        askPrices = new uint256[](_depth);
        askVolumes = new uint256[](_depth);

        return (bidPrices, bidVolumes, askPrices, askVolumes);
    }

    /**
     * @notice Get trading pair details
     */
    function getTradingPair(bytes32 _pairId)
        external
        view
        returns (
            address baseAsset,
            address quoteAsset,
            InstrumentType instrumentType,
            uint256 makerFee,
            uint256 takerFee,
            bool isActive
        )
    {
        TradingPair memory pair = tradingPairs[_pairId];
        return (
            pair.baseAsset,
            pair.quoteAsset,
            pair.instrumentType,
            pair.makerFee,
            pair.takerFee,
            pair.isActive
        );
    }

    /**
     * @notice Get order details
     */
    function getOrder(bytes32 _orderId)
        external
        view
        returns (
            bytes32 pairId,
            OrderType orderType,
            OrderSide side,
            uint256 quantity,
            uint256 price,
            uint256 filledQuantity,
            OrderStatus status
        )
    {
        Order memory order = orders[_orderId];
        return (
            order.pairId,
            order.orderType,
            order.side,
            order.quantity,
            order.price,
            order.filledQuantity,
            order.status
        );
    }

    /**
     * @notice Get market data
     */
    function getMarketData(bytes32 _pairId)
        external
        view
        returns (
            uint256 lastPrice,
            uint256 bidPrice,
            uint256 askPrice,
            uint256 volume24h,
            uint256 high24h,
            uint256 low24h
        )
    {
        MarketData memory data = marketData[_pairId];
        return (
            data.lastPrice,
            data.bidPrice,
            data.askPrice,
            data.volume24h,
            data.high24h,
            data.low24h
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _maxSlippage,
        uint256 _minOrderSize,
        uint256 _maxOrderSize,
        uint256 _defaultMakerFee,
        uint256 _defaultTakerFee
    ) external onlyOwner {
        maxSlippage = _maxSlippage;
        minOrderSize = _minOrderSize;
        maxOrderSize = _maxOrderSize;
        defaultMakerFee = _defaultMakerFee;
        defaultTakerFee = _defaultTakerFee;
    }

    /**
     * @notice Get global DEX statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalPairs,
            uint256 _totalOrders,
            uint256 _totalTrades,
            uint256 _totalVolume,
            uint256 _totalFeesCollected
        )
    {
        return (totalPairs, totalOrders, totalTrades, totalVolume, totalFeesCollected);
    }

    // Internal functions
    function _matchOrder(bytes32 _orderId) internal {
        Order storage order = orders[_orderId];
        TradingPair memory pair = tradingPairs[order.pairId];

        // Simplified matching logic
        // In production, this would implement proper order matching engine
        bytes32[] storage counterOrders;

        if (order.side == OrderSide.BUY) {
            // Look for sell orders at or below buy price
            // This is simplified - real implementation would use price-time priority
            for (uint256 price = order.price; price <= order.price + maxSlippage; price += pair.tickSize) {
                counterOrders = sellOrders[order.pairId][price];
                if (counterOrders.length > 0) {
                    _executeTrade(_orderId, counterOrders[0]);
                    break;
                }
            }
        } else {
            // Look for buy orders at or above sell price
            for (uint256 price = order.price; price >= order.price - maxSlippage; price -= pair.tickSize) {
                counterOrders = buyOrders[order.pairId][price];
                if (counterOrders.length > 0) {
                    _executeTrade(_orderId, counterOrders[0]);
                    break;
                }
            }
        }
    }

    function _executeMarketOrder(bytes32 _orderId) internal {
        Order storage order = orders[_orderId];

        // Simplified market order execution
        // In production, this would sweep the order book
        if (order.side == OrderSide.BUY) {
            // Find best available sell orders
            // Simplified implementation
            order.status = OrderStatus.FILLED;
            order.filledQuantity = order.quantity;
            order.remainingQuantity = 0;
        } else {
            // Find best available buy orders
            order.status = OrderStatus.FILLED;
            order.filledQuantity = order.quantity;
            order.remainingQuantity = 0;
        }

        order.updatedAt = block.timestamp;
    }

    function _executeTrade(bytes32 _orderId, bytes32 _counterOrderId) internal {
        Order storage order = orders[_orderId];
        Order storage counterOrder = orders[_counterOrderId];

        // Calculate trade quantity
        uint256 tradeQuantity = order.remainingQuantity < counterOrder.remainingQuantity ?
            order.remainingQuantity : counterOrder.remainingQuantity;

        // Calculate trade price (simplified)
        uint256 tradePrice = (order.price + counterOrder.price) / 2;

        // Create trade record
        bytes32 tradeId = keccak256(abi.encodePacked(
            _orderId,
            _counterOrderId,
            tradeQuantity,
            tradePrice,
            block.timestamp
        ));

        Trade storage trade = trades[tradeId];
        trade.tradeId = tradeId;
        trade.orderId = _orderId;
        trade.counterOrderId = _counterOrderId;
        trade.pairId = order.pairId;
        trade.maker = order.createdAt < counterOrder.createdAt ? order.trader : counterOrder.trader;
        trade.taker = order.createdAt < counterOrder.createdAt ? counterOrder.trader : order.trader;
        trade.quantity = tradeQuantity;
        trade.price = tradePrice;
        trade.timestamp = block.timestamp;
        trade.isBuySide = order.side == OrderSide.BUY;

        // Calculate fees
        TradingPair memory pair = tradingPairs[order.pairId];
        trade.makerFee = (tradeQuantity * tradePrice * pair.makerFee) / 10000;
        trade.takerFee = (tradeQuantity * tradePrice * pair.takerFee) / 10000;

        // Update orders
        order.filledQuantity += tradeQuantity;
        order.remainingQuantity -= tradeQuantity;
        counterOrder.filledQuantity += tradeQuantity;
        counterOrder.remainingQuantity -= tradeQuantity;

        // Update order status
        if (order.remainingQuantity == 0) {
            order.status = OrderStatus.FILLED;
            _removeFromOrderBook(_orderId);
        } else {
            order.status = OrderStatus.PARTIAL;
        }

        if (counterOrder.remainingQuantity == 0) {
            counterOrder.status = OrderStatus.FILLED;
            _removeFromOrderBook(_counterOrderId);
        } else {
            counterOrder.status = OrderStatus.PARTIAL;
        }

        order.updatedAt = block.timestamp;
        counterOrder.updatedAt = block.timestamp;

        // Update global stats
        totalTrades++;
        totalVolume += tradeQuantity * tradePrice;
        totalFeesCollected += trade.makerFee + trade.takerFee;

        emit TradeExecuted(tradeId, order.pairId, trade.maker, trade.taker, tradeQuantity, tradePrice);
    }

    function _removeFromOrderBook(bytes32 _orderId) internal {
        Order memory order = orders[_orderId];

        bytes32[] storage orderList;
        if (order.side == OrderSide.BUY) {
            orderList = buyOrders[order.pairId][order.price];
        } else {
            orderList = sellOrders[order.pairId][order.price];
        }

        // Remove order from list (simplified)
        for (uint256 i = 0; i < orderList.length; i++) {
            if (orderList[i] == _orderId) {
                orderList[i] = orderList[orderList.length - 1];
                orderList.pop();
                break;
            }
        }
    }

    function _checkArbitrageOpportunities(bytes32 _pairId) internal {
        // Simplified arbitrage detection
        // In production, this would check for triangular arbitrage across multiple pairs
        MarketData memory data = marketData[_pairId];

        // Check for significant spread
        if (data.askPrice > data.bidPrice * 101 / 100) { // >1% spread
            bytes32 opportunityId = keccak256(abi.encodePacked(
                _pairId,
                data.askPrice,
                data.bidPrice,
                block.timestamp
            ));

            ArbitrageOpportunity storage opportunity = arbitrageOpportunities[opportunityId];
            opportunity.opportunityId = opportunityId;
            opportunity.pairs = new bytes32[](1);
            opportunity.pairs[0] = _pairId;
            opportunity.prices = new uint256[](2);
            opportunity.prices[0] = data.bidPrice;
            opportunity.prices[1] = data.askPrice;
            opportunity.profitPercentage = ((data.askPrice - data.bidPrice) * 10000) / data.bidPrice;
            opportunity.isActive = true;
            opportunity.detectedAt = block.timestamp;
            opportunity.expiresAt = block.timestamp + 300; // 5 minutes

            emit ArbitrageDetected(opportunityId, opportunity.profitPercentage);
        }
    }
}
