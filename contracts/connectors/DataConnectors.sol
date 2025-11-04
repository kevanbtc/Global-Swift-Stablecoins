// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title DataConnectors
 * @notice Real-time data integration from traditional financial systems
 * @dev Connects to Bloomberg, Reuters, SWIFT, central banks, exchanges
 */
contract DataConnectors is Ownable, ReentrancyGuard {

    enum DataSource {
        BLOOMBERG,
        REUTERS,
        SWIFT,
        CENTRAL_BANK,
        EXCHANGE,
        REGULATOR,
        CREDIT_RATING,
        NEWS_WIRE,
        SOCIAL_MEDIA,
        SATELLITE,
        IoT_SENSORS,
        BLOCKCHAIN_ORACLE,
        CUSTOM_API
    }

    enum DataType {
        PRICE_FEED,
        MARKET_DATA,
        ECONOMIC_INDICATOR,
        REGULATORY_REPORT,
        CREDIT_SCORE,
        NEWS_SENTIMENT,
        WEATHER_DATA,
        SUPPLY_CHAIN,
        ESG_METRICS,
        RISK_METRICS,
        COMPLIANCE_DATA,
        IDENTITY_DATA
    }

    enum DataQuality {
        RAW,
        VALIDATED,
        CERTIFIED,
        REGULATORY_APPROVED
    }

    struct DataFeed {
        bytes32 feedId;
        DataSource source;
        DataType dataType;
        address provider;
        uint256 updateFrequency;     // seconds
        uint256 lastUpdate;
        uint256 dataPoints;          // total data points provided
        DataQuality quality;
        bool isActive;
        bytes32 dataHash;
        uint256 feePerQuery;         // wei
        mapping(bytes32 => bytes32) dataStore; // key => value hash
    }

    struct DataSubscription {
        bytes32 subscriptionId;
        address subscriber;
        bytes32 feedId;
        uint256 subscriptionStart;
        uint256 subscriptionEnd;
        uint256 paymentAmount;
        bool autoRenew;
        uint256 queryCount;
        uint256 maxQueries;
    }

    struct DataQuery {
        bytes32 queryId;
        bytes32 feedId;
        address requester;
        bytes32 dataKey;
        uint256 queryTimestamp;
        uint256 responseTimestamp;
        bytes32 responseHash;
        bool fulfilled;
        uint256 feePaid;
    }

    // Storage
    mapping(bytes32 => DataFeed) public dataFeeds;
    mapping(bytes32 => DataSubscription) public dataSubscriptions;
    mapping(bytes32 => DataQuery) public dataQueries;
    mapping(address => bytes32[]) public providerFeeds;
    mapping(address => bytes32[]) public subscriberQueries;
    mapping(DataSource => bytes32[]) public sourceFeeds;
    mapping(DataType => bytes32[]) public typeFeeds;

    // Global statistics
    uint256 public totalFeeds;
    uint256 public totalSubscriptions;
    uint256 public totalQueries;
    uint256 public totalDataPoints;

    // Protocol parameters
    uint256 public minUpdateFrequency = 60;     // 1 minute
    uint256 public maxUpdateFrequency = 86400;  // 24 hours
    uint256 public subscriptionFee = 0.1 ether; // 0.1 ETH per month
    uint256 public queryFee = 0.001 ether;      // 0.001 ETH per query

    // Events
    event DataFeedCreated(bytes32 indexed feedId, DataSource source, DataType dataType);
    event DataUpdated(bytes32 indexed feedId, bytes32 dataKey, bytes32 dataHash);
    event SubscriptionCreated(bytes32 indexed subscriptionId, address subscriber, bytes32 feedId);
    event DataQueried(bytes32 indexed queryId, address requester, bytes32 feedId);
    event FeedQualityUpdated(bytes32 indexed feedId, DataQuality quality);

    modifier validFeed(bytes32 _feedId) {
        require(dataFeeds[_feedId].provider != address(0), "Feed not found");
        _;
    }

    modifier onlyProvider(bytes32 _feedId) {
        require(dataFeeds[_feedId].provider == msg.sender, "Not feed provider");
        _;
    }

    modifier activeFeed(bytes32 _feedId) {
        require(dataFeeds[_feedId].isActive, "Feed not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new data feed
     */
    function createDataFeed(
        DataSource _source,
        DataType _dataType,
        uint256 _updateFrequency,
        DataQuality _quality,
        uint256 _feePerQuery
    ) external returns (bytes32) {
        require(_updateFrequency >= minUpdateFrequency, "Update frequency too low");
        require(_updateFrequency <= maxUpdateFrequency, "Update frequency too high");

        bytes32 feedId = keccak256(abi.encodePacked(
            _source,
            _dataType,
            msg.sender,
            block.timestamp
        ));

        require(dataFeeds[feedId].provider == address(0), "Feed already exists");

        DataFeed storage feed = dataFeeds[feedId];
        feed.feedId = feedId;
        feed.source = _source;
        feed.dataType = _dataType;
        feed.provider = msg.sender;
        feed.updateFrequency = _updateFrequency;
        feed.quality = _quality;
        feed.feePerQuery = _feePerQuery;
        feed.isActive = true;
        feed.lastUpdate = block.timestamp;

        providerFeeds[msg.sender].push(feedId);
        sourceFeeds[_source].push(feedId);
        typeFeeds[_dataType].push(feedId);
        totalFeeds++;

        emit DataFeedCreated(feedId, _source, _dataType);
        return feedId;
    }

    /**
     * @notice Update data in a feed
     */
    function updateData(
        bytes32 _feedId,
        bytes32 _dataKey,
        bytes32 _dataHash
    ) external validFeed(_feedId) onlyProvider(_feedId) activeFeed(_feedId) {
        DataFeed storage feed = dataFeeds[_feedId];
        feed.dataStore[_dataKey] = _dataHash;
        feed.lastUpdate = block.timestamp;
        feed.dataPoints++;
        totalDataPoints++;

        emit DataUpdated(_feedId, _dataKey, _dataHash);
    }

    /**
     * @notice Subscribe to a data feed
     */
    function subscribeToFeed(
        bytes32 _feedId,
        uint256 _duration,
        bool _autoRenew
    ) external payable validFeed(_feedId) activeFeed(_feedId) returns (bytes32) {
        uint256 requiredPayment = subscriptionFee * (_duration / 30 days);
        require(msg.value >= requiredPayment, "Insufficient payment");

        bytes32 subscriptionId = keccak256(abi.encodePacked(
            _feedId,
            msg.sender,
            block.timestamp
        ));

        DataSubscription storage subscription = dataSubscriptions[subscriptionId];
        subscription.subscriptionId = subscriptionId;
        subscription.subscriber = msg.sender;
        subscription.feedId = _feedId;
        subscription.subscriptionStart = block.timestamp;
        subscription.subscriptionEnd = block.timestamp + _duration;
        subscription.paymentAmount = msg.value;
        subscription.autoRenew = _autoRenew;
        subscription.maxQueries = _duration / 1 hours; // 1 query per hour

        totalSubscriptions++;

        emit SubscriptionCreated(subscriptionId, msg.sender, _feedId);
        return subscriptionId;
    }

    /**
     * @notice Query data from a feed
     */
    function queryData(
        bytes32 _feedId,
        bytes32 _dataKey
    ) external payable validFeed(_feedId) activeFeed(_feedId) returns (bytes32) {
        DataFeed memory feed = dataFeeds[_feedId];
        require(msg.value >= feed.feePerQuery, "Insufficient query fee");

        // Check subscription or pay per query
        bytes32 subscriptionId = _getActiveSubscription(msg.sender, _feedId);
        if (subscriptionId != bytes32(0)) {
            DataSubscription storage subscription = dataSubscriptions[subscriptionId];
            require(subscription.queryCount < subscription.maxQueries, "Query limit reached");
            subscription.queryCount++;
        } else {
            require(msg.value >= queryFee, "Minimum query fee required");
        }

        bytes32 queryId = keccak256(abi.encodePacked(
            _feedId,
            _dataKey,
            msg.sender,
            block.timestamp
        ));

        DataQuery storage query = dataQueries[queryId];
        query.queryId = queryId;
        query.feedId = _feedId;
        query.requester = msg.sender;
        query.dataKey = _dataKey;
        query.queryTimestamp = block.timestamp;
        query.feePaid = msg.value;

        subscriberQueries[msg.sender].push(queryId);
        totalQueries++;

        // Fulfill query immediately (in production, this might be asynchronous)
        _fulfillQuery(queryId, _dataKey);

        emit DataQueried(queryId, msg.sender, _feedId);
        return queryId;
    }

    /**
     * @notice Update feed quality certification
     */
    function updateFeedQuality(
        bytes32 _feedId,
        DataQuality _quality
    ) external onlyOwner validFeed(_feedId) {
        dataFeeds[_feedId].quality = _quality;
        emit FeedQualityUpdated(_feedId, _quality);
    }

    /**
     * @notice Get data from a feed
     */
    function getData(bytes32 _feedId, bytes32 _dataKey)
        external
        view
        returns (bytes32 dataHash, uint256 lastUpdate, DataQuality quality)
    {
        DataFeed memory feed = dataFeeds[_feedId];
        return (feed.dataStore[_dataKey], feed.lastUpdate, feed.quality);
    }

    /**
     * @notice Get feed details
     */
    function getFeedDetails(bytes32 _feedId)
        external
        view
        returns (
            DataSource source,
            DataType dataType,
            address provider,
            uint256 updateFrequency,
            uint256 dataPoints,
            DataQuality quality,
            bool isActive
        )
    {
        DataFeed memory feed = dataFeeds[_feedId];
        return (
            feed.source,
            feed.dataType,
            feed.provider,
            feed.updateFrequency,
            feed.dataPoints,
            feed.quality,
            feed.isActive
        );
    }

    /**
     * @notice Get subscription details
     */
    function getSubscription(bytes32 _subscriptionId)
        external
        view
        returns (
            address subscriber,
            bytes32 feedId,
            uint256 subscriptionEnd,
            uint256 queryCount,
            uint256 maxQueries,
            bool autoRenew
        )
    {
        DataSubscription memory subscription = dataSubscriptions[_subscriptionId];
        return (
            subscription.subscriber,
            subscription.feedId,
            subscription.subscriptionEnd,
            subscription.queryCount,
            subscription.maxQueries,
            subscription.autoRenew
        );
    }

    /**
     * @notice Get query response
     */
    function getQueryResponse(bytes32 _queryId)
        external
        view
        returns (
            bytes32 responseHash,
            uint256 responseTimestamp,
            bool fulfilled
        )
    {
        DataQuery memory query = dataQueries[_queryId];
        return (
            query.responseHash,
            query.responseTimestamp,
            query.fulfilled
        );
    }

    /**
     * @notice Get feeds by source
     */
    function getFeedsBySource(DataSource _source)
        external
        view
        returns (bytes32[] memory)
    {
        return sourceFeeds[_source];
    }

    /**
     * @notice Get feeds by type
     */
    function getFeedsByType(DataType _type)
        external
        view
        returns (bytes32[] memory)
    {
        return typeFeeds[_type];
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _minUpdateFrequency,
        uint256 _maxUpdateFrequency,
        uint256 _subscriptionFee,
        uint256 _queryFee
    ) external onlyOwner {
        minUpdateFrequency = _minUpdateFrequency;
        maxUpdateFrequency = _maxUpdateFrequency;
        subscriptionFee = _subscriptionFee;
        queryFee = _queryFee;
    }

    /**
     * @notice Get global data connector statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalFeeds,
            uint256 _totalSubscriptions,
            uint256 _totalQueries,
            uint256 _totalDataPoints
        )
    {
        return (totalFeeds, totalSubscriptions, totalQueries, totalDataPoints);
    }

    // Internal functions
    function _getActiveSubscription(address _subscriber, bytes32 _feedId)
        internal
        view
        returns (bytes32)
    {
        // Simplified - in production would check all subscriptions
        // This is a placeholder implementation
        return bytes32(0);
    }

    function _fulfillQuery(bytes32 _queryId, bytes32 _dataKey) internal {
        DataQuery storage query = dataQueries[_queryId];
        DataFeed storage feed = dataFeeds[query.feedId];

        query.responseHash = feed.dataStore[_dataKey];
        query.responseTimestamp = block.timestamp;
        query.fulfilled = true;
    }
}
