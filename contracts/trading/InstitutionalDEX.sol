// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title InstitutionalDEX
 * @notice Decentralized exchange optimized for institutional trading
 * @dev Supports RFQ, block trading, algorithmic execution, and compliance
 */
contract InstitutionalDEX is Ownable, ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;

    enum OrderType {
        MARKET,
        LIMIT,
        RFQ,
        BLOCK_TRADE
    }

    enum OrderStatus {
        PENDING,
        PARTIAL_FILL,
        FILLED,
        CANCELLED,
        EXPIRED
    }

    enum TradeType {
        BUY,
        SELL
    }

    struct Order {
        bytes32 orderId;
        address trader;
        address baseToken;
        address quoteToken;
        TradeType tradeType;
        OrderType orderType;
        uint256 amount;
        uint256 filledAmount;
        uint256 price;             // For limit orders (18 decimals)
        uint256 slippageTolerance; // BPS
        uint256 expiryTime;
        OrderStatus status;
        uint256 createdAt;
        bytes32 rfqId;            // For RFQ orders
        bool isInstitutional;
    }

    struct RFQQuote {
        bytes32 rfqId;
        address marketMaker;
        uint256 price;
        uint256 availableAmount;
        uint256 expiryTime;
        bytes signature;
        bool isActive;
    }

    struct Trade {
        bytes32 tradeId;
        bytes32 buyOrderId;
        bytes32 sellOrderId;
        address buyer;
        address seller;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 price;
        uint256 fee;
        uint256 executedAt;
        bool isSettled;
    }

    struct TradingPair {
        address baseToken;
        address quoteToken;
        bool isActive;
        uint256 minOrderSize;
        uint256 maxOrderSize;
        uint256 tradingFee;       // BPS
        uint256 lastPrice;
        uint256 dailyVolume;
        uint256 lastVolumeReset;
    }

    // Storage
    mapping(bytes32 => Order) public orders;
    mapping(bytes32 => RFQQuote) public rfqQuotes;
    mapping(bytes32 => Trade) public trades;
    mapping(bytes32 => TradingPair) public tradingPairs;
    mapping(address => mapping(address => uint256)) public balances;

    // Order books (simplified - in production would use more efficient data structures)
    mapping(bytes32 => bytes32[]) public buyOrders;  // pairId => orderIds
    mapping(bytes32 => bytes32[]) public sellOrders; // pairId => orderIds

    // Global parameters
    uint256 public tradingFeeBPS = 10;        // 0.1%
    uint256 public maxSlippageBPS = 100;      // 1%
    uint256 public minOrderSize = 1000 * 1e18; // 1000 units
    uint256 public maxOrderExpiry = 24 hours;
    uint256 public rfqExpiry = 5 minutes;

    // Counters and stats
    uint256 public totalOrders;
    uint256 public totalTrades;
    uint256 public totalVolume;

    // Events
    event OrderPlaced(bytes32 indexed orderId, address indexed trader, OrderType orderType);
    event OrderFilled(bytes32 indexed orderId, uint256 filledAmount);
    event OrderCancelled(bytes32 indexed orderId);
    event TradeExecuted(bytes32 indexed tradeId, address indexed buyer, address indexed seller, uint256 amount);
    event RFQCreated(bytes32 indexed rfqId, address indexed trader, uint256 amount);
    event RFQQuoted(bytes32 indexed rfqId, address indexed marketMaker, uint256 price);
    event TradingPairAdded(bytes32 indexed pairId, address baseToken, address quoteToken);

    modifier validTradingPair(bytes32 _pairId) {
        require(tradingPairs[_pairId].isActive, "Trading pair not active");
        _;
    }

    modifier validOrderSize(bytes32 _pairId, uint256 _amount) {
        TradingPair memory pair = tradingPairs[_pairId];
        require(_amount >= pair.minOrderSize, "Order size too small");
        require(_amount <= pair.maxOrderSize, "Order size too large");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Add a new trading pair
     */
    function addTradingPair(
        address _baseToken,
        address _quoteToken,
        uint256 _minOrderSize,
        uint256 _maxOrderSize,
        uint256 _tradingFee
    ) external onlyOwner returns (bytes32) {
        require(_baseToken != _quoteToken, "Cannot trade token against itself");

        bytes32 pairId = keccak256(abi.encodePacked(_baseToken, _quoteToken));

        tradingPairs[pairId] = TradingPair({
            baseToken: _baseToken,
            quoteToken: _quoteToken,
            isActive: true,
            minOrderSize: _minOrderSize,
            maxOrderSize: _maxOrderSize,
            tradingFee: _tradingFee,
            lastPrice: 0,
            dailyVolume: 0,
            lastVolumeReset: block.timestamp
        });

        emit TradingPairAdded(pairId, _baseToken, _quoteToken);
        return pairId;
    }

    /**
     * @notice Place a limit order
     */
    function placeLimitOrder(
        bytes32 _pairId,
        TradeType _tradeType,
        uint256 _amount,
        uint256 _price,
        uint256 _slippageTolerance
    ) external whenNotPaused validTradingPair(_pairId) validOrderSize(_pairId, _amount)
         returns (bytes32) {

        require(_slippageTolerance <= maxSlippageBPS, "Slippage tolerance too high");

        bytes32 orderId = keccak256(abi.encodePacked(
            msg.sender,
            _pairId,
            _tradeType,
            _amount,
            _price,
            block.timestamp
        ));

        TradingPair memory pair = tradingPairs[_pairId];

        orders[orderId] = Order({
            orderId: orderId,
            trader: msg.sender,
            baseToken: pair.baseToken,
            quoteToken: pair.quoteToken,
            tradeType: _tradeType,
            orderType: OrderType.LIMIT,
            amount: _amount,
            filledAmount: 0,
            price: _price,
            slippageTolerance: _slippageTolerance,
            expiryTime: block.timestamp + maxOrderExpiry,
            status: OrderStatus.PENDING,
            createdAt: block.timestamp,
            rfqId: bytes32(0),
            isInstitutional: true
        });

        // Add to order book
        if (_tradeType == TradeType.BUY) {
            buyOrders[_pairId].push(orderId);
        } else {
            sellOrders[_pairId].push(orderId);
        }

        totalOrders++;

        emit OrderPlaced(orderId, msg.sender, OrderType.LIMIT);

        // Try to match immediately
        _matchOrder(orderId);

        return orderId;
    }

    /**
     * @notice Place a market order
     */
    function placeMarketOrder(
        bytes32 _pairId,
        TradeType _tradeType,
        uint256 _amount,
        uint256 _slippageTolerance
    ) external whenNotPaused validTradingPair(_pairId) validOrderSize(_pairId, _amount)
         returns (bytes32) {

        require(_slippageTolerance <= maxSlippageBPS, "Slippage tolerance too high");

        bytes32 orderId = keccak256(abi.encodePacked(
            msg.sender,
            _pairId,
            _tradeType,
            _amount,
            block.timestamp
        ));

        TradingPair memory pair = tradingPairs[_pairId];

        orders[orderId] = Order({
            orderId: orderId,
            trader: msg.sender,
            baseToken: pair.baseToken,
            quoteToken: pair.quoteToken,
            tradeType: _tradeType,
            orderType: OrderType.MARKET,
            amount: _amount,
            filledAmount: 0,
            price: 0, // Market order
            slippageTolerance: _slippageTolerance,
            expiryTime: block.timestamp + maxOrderExpiry,
            status: OrderStatus.PENDING,
            createdAt: block.timestamp,
            rfqId: bytes32(0),
            isInstitutional: true
        });

        totalOrders++;

        emit OrderPlaced(orderId, msg.sender, OrderType.MARKET);

        // Execute market order immediately
        _executeMarketOrder(orderId);

        return orderId;
    }

    /**
     * @notice Create an RFQ
     */
    function createRFQ(
        bytes32 _pairId,
        TradeType _tradeType,
        uint256 _amount
    ) external whenNotPaused validTradingPair(_pairId) validOrderSize(_pairId, _amount)
         returns (bytes32) {

        bytes32 rfqId = keccak256(abi.encodePacked(
            msg.sender,
            _pairId,
            _tradeType,
            _amount,
            block.timestamp
        ));

        TradingPair memory pair = tradingPairs[_pairId];

        bytes32 orderId = keccak256(abi.encodePacked(rfqId, "ORDER"));

        orders[orderId] = Order({
            orderId: orderId,
            trader: msg.sender,
            baseToken: pair.baseToken,
            quoteToken: pair.quoteToken,
            tradeType: _tradeType,
            orderType: OrderType.RFQ,
            amount: _amount,
            filledAmount: 0,
            price: 0,
            slippageTolerance: 0,
            expiryTime: block.timestamp + rfqExpiry,
            status: OrderStatus.PENDING,
            createdAt: block.timestamp,
            rfqId: rfqId,
            isInstitutional: true
        });

        totalOrders++;

        emit RFQCreated(rfqId, msg.sender, _amount);
        emit OrderPlaced(orderId, msg.sender, OrderType.RFQ);

        return rfqId;
    }

    /**
     * @notice Submit a quote for an RFQ
     */
    function submitRFQQuote(
        bytes32 _rfqId,
        uint256 _price,
        uint256 _availableAmount,
        bytes memory _signature
    ) external whenNotPaused returns (bytes32) {

        require(rfqQuotes[_rfqId].marketMaker == address(0), "RFQ already quoted");

        rfqQuotes[_rfqId] = RFQQuote({
            rfqId: _rfqId,
            marketMaker: msg.sender,
            price: _price,
            availableAmount: _availableAmount,
            expiryTime: block.timestamp + rfqExpiry,
            signature: _signature,
            isActive: true
        });

        emit RFQQuoted(_rfqId, msg.sender, _price);

        return _rfqId;
    }

    /**
     * @notice Accept an RFQ quote
     */
    function acceptRFQQuote(bytes32 _rfqId) external whenNotPaused nonReentrant {
        RFQQuote memory quote = rfqQuotes[_rfqId];
        require(quote.isActive, "Quote not active");
        require(block.timestamp <= quote.expiryTime, "Quote expired");

        // Find the corresponding order
        bytes32 orderId = keccak256(abi.encodePacked(_rfqId, "ORDER"));
        Order storage order = orders[orderId];
        require(order.trader == msg.sender, "Not RFQ owner");
        require(order.status == OrderStatus.PENDING, "Order not pending");

        // Execute the trade
        _executeRFQTrade(orderId, quote);
    }

    /**
     * @notice Cancel an order
     */
    function cancelOrder(bytes32 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.trader == msg.sender, "Not order owner");
        require(order.status == OrderStatus.PENDING, "Order not cancellable");

        order.status = OrderStatus.CANCELLED;

        emit OrderCancelled(_orderId);
    }

    /**
     * @notice Deposit tokens to trading balance
     */
    function deposit(address _token, uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount > 0, "Invalid amount");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        balances[msg.sender][_token] += _amount;
    }

    /**
     * @notice Withdraw tokens from trading balance
     */
    function withdraw(address _token, uint256 _amount) external nonReentrant {
        require(balances[msg.sender][_token] >= _amount, "Insufficient balance");

        balances[msg.sender][_token] -= _amount;
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Get order details
     */
    function getOrder(bytes32 _orderId)
        external
        view
        returns (
            address trader,
            OrderType orderType,
            OrderStatus status,
            uint256 amount,
            uint256 filledAmount,
            uint256 price
        )
    {
        Order memory order = orders[_orderId];
        return (
            order.trader,
            order.orderType,
            order.status,
            order.amount,
            order.filledAmount,
            order.price
        );
    }

    /**
     * @notice Get trading pair info
     */
    function getTradingPair(bytes32 _pairId)
        external
        view
        returns (
            address baseToken,
            address quoteToken,
            uint256 lastPrice,
            uint256 dailyVolume,
            bool isActive
        )
    {
        TradingPair memory pair = tradingPairs[_pairId];
        return (
            pair.baseToken,
            pair.quoteToken,
            pair.lastPrice,
            pair.dailyVolume,
            pair.isActive
        );
    }

    /**
     * @notice Update trading parameters
     */
    function updateParameters(
        uint256 _tradingFeeBPS,
        uint256 _maxSlippageBPS,
        uint256 _minOrderSize,
        uint256 _rfqExpiry
    ) external onlyOwner {
        tradingFeeBPS = _tradingFeeBPS;
        maxSlippageBPS = _maxSlippageBPS;
        minOrderSize = _minOrderSize;
        rfqExpiry = _rfqExpiry;
    }

    /**
     * @notice Emergency pause
     */
    function emergencyPause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause
     */
    function emergencyUnpause() external onlyOwner {
        _unpause();
    }

    // Internal functions

    function _matchOrder(bytes32 _orderId) internal {
        Order storage order = orders[_orderId];
        if (order.orderType != OrderType.LIMIT) return;

        bytes32 pairId = keccak256(abi.encodePacked(order.baseToken, order.quoteToken));
        bytes32[] storage oppositeOrders = order.tradeType == TradeType.BUY ?
            sellOrders[pairId] : buyOrders[pairId];

        // Simple matching logic - in production would use more sophisticated matching engine
        for (uint256 i = 0; i < oppositeOrders.length && order.filledAmount < order.amount; i++) {
            bytes32 oppositeOrderId = oppositeOrders[i];
            Order storage oppositeOrder = orders[oppositeOrderId];

            if (oppositeOrder.status != OrderStatus.PENDING) continue;

            // Check if prices match
            bool priceMatch = order.tradeType == TradeType.BUY ?
                order.price >= oppositeOrder.price :
                order.price <= oppositeOrder.price;

            if (!priceMatch) continue;

            // Calculate fill amount
            uint256 remainingAmount = order.amount - order.filledAmount;
            uint256 oppositeRemaining = oppositeOrder.amount - oppositeOrder.filledAmount;
            uint256 fillAmount = remainingAmount < oppositeRemaining ? remainingAmount : oppositeRemaining;

            // Execute trade
            _executeTrade(_orderId, oppositeOrderId, fillAmount, order.price);
        }
    }

    function _executeMarketOrder(bytes32 _orderId) internal {
        Order storage order = orders[_orderId];
        bytes32 pairId = keccak256(abi.encodePacked(order.baseToken, order.quoteToken));

        // For market orders, match against best available prices
        // Simplified implementation
        uint256 remainingAmount = order.amount;
        uint256 totalFilled = 0;

        // Try to fill from order book
        bytes32[] storage oppositeOrders = order.tradeType == TradeType.BUY ?
            sellOrders[pairId] : buyOrders[pairId];

        for (uint256 i = 0; i < oppositeOrders.length && remainingAmount > 0; i++) {
            bytes32 oppositeOrderId = oppositeOrders[i];
            Order storage oppositeOrder = orders[oppositeOrderId];

            if (oppositeOrder.status != OrderStatus.PENDING) continue;

            uint256 fillAmount = remainingAmount < oppositeOrder.amount ?
                remainingAmount : oppositeOrder.amount;

            _executeTrade(_orderId, oppositeOrderId, fillAmount, oppositeOrder.price);
            remainingAmount -= fillAmount;
            totalFilled += fillAmount;
        }

        if (totalFilled > 0) {
            order.filledAmount = totalFilled;
            if (totalFilled == order.amount) {
                order.status = OrderStatus.FILLED;
            } else {
                order.status = OrderStatus.PARTIAL_FILL;
            }
        }
    }

    function _executeRFQTrade(bytes32 _orderId, RFQQuote memory _quote) internal {
        Order storage order = orders[_orderId];

        uint256 fillAmount = order.amount < _quote.availableAmount ?
            order.amount : _quote.availableAmount;

        _executeTrade(_orderId, bytes32(0), fillAmount, _quote.price);

        // Mark RFQ as inactive
        rfqQuotes[order.rfqId].isActive = false;
    }

    function _executeTrade(
        bytes32 _orderId1,
        bytes32 _orderId2,
        uint256 _amount,
        uint256 _price
    ) internal {
        Order storage order1 = orders[_orderId1];
        Order storage order2 = orders[_orderId2];

        // Calculate trade amounts
        uint256 amountOut = (_amount * _price) / 1e18;
        uint256 fee = (amountOut * tradingFeeBPS) / 10000;

        bytes32 tradeId = keccak256(abi.encodePacked(
            _orderId1,
            _orderId2,
            _amount,
            block.timestamp
        ));

        trades[tradeId] = Trade({
            tradeId: tradeId,
            buyOrderId: order1.tradeType == TradeType.BUY ? _orderId1 : _orderId2,
            sellOrderId: order1.tradeType == TradeType.SELL ? _orderId1 : _orderId2,
            buyer: order1.tradeType == TradeType.BUY ? order1.trader : order2.trader,
            seller: order1.tradeType == TradeType.SELL ? order1.trader : order2.trader,
            tokenIn: order1.tradeType == TradeType.BUY ? order1.quoteToken : order1.baseToken,
            tokenOut: order1.tradeType == TradeType.BUY ? order1.baseToken : order1.quoteToken,
            amountIn: amountOut + fee,
            amountOut: _amount,
            price: _price,
            fee: fee,
            executedAt: block.timestamp,
            isSettled: true
        });

        // Update order fills
        order1.filledAmount += _amount;
        if (order1.filledAmount >= order1.amount) {
            order1.status = OrderStatus.FILLED;
        } else {
            order1.status = OrderStatus.PARTIAL_FILL;
        }

        if (_orderId2 != bytes32(0)) {
            order2.filledAmount += _amount;
            if (order2.filledAmount >= order2.amount) {
                order2.status = OrderStatus.FILLED;
            } else {
                order2.status = OrderStatus.PARTIAL_FILL;
            }
        }

        // Update trading pair stats
        bytes32 pairId = keccak256(abi.encodePacked(order1.baseToken, order1.quoteToken));
        TradingPair storage pair = tradingPairs[pairId];
        pair.lastPrice = _price;
        pair.dailyVolume += amountOut;

        totalTrades++;
        totalVolume += amountOut;

        emit TradeExecuted(tradeId, trades[tradeId].buyer, trades[tradeId].seller, _amount);
        emit OrderFilled(_orderId1, _amount);
        if (_orderId2 != bytes32(0)) {
            emit OrderFilled(_orderId2, _amount);
        }
    }
}
