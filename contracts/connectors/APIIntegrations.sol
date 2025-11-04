// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title APIIntegrations
 * @notice REST API and webhook integrations for external services
 * @dev Handles API calls, webhooks, and external service integrations
 */
contract APIIntegrations is Ownable, ReentrancyGuard {

    enum APIType {
        REST_API,
        GRAPHQL_API,
        WEBHOOK,
        WEBSOCKET,
        SOAP_API,
        GRPC_API
    }

    enum HTTPMethod {
        GET,
        POST,
        PUT,
        DELETE,
        PATCH,
        HEAD,
        OPTIONS
    }

    enum IntegrationStatus {
        INACTIVE,
        ACTIVE,
        SUSPENDED,
        ERROR,
        MAINTENANCE
    }

    struct APIEndpoint {
        bytes32 endpointId;
        string name;
        string url;
        APIType apiType;
        HTTPMethod method;
        address authorizedCaller;
        uint256 rateLimit;           // requests per minute
        uint256 lastCall;
        uint256 callCount;
        IntegrationStatus status;
        bool requiresAuth;
        bytes32 authToken;
        mapping(bytes32 => bytes32) responseCache; // requestHash => responseHash
    }

    struct WebhookSubscription {
        bytes32 subscriptionId;
        string webhookUrl;
        address subscriber;
        bytes32[] eventTypes;
        bool isActive;
        uint256 retryCount;
        uint256 lastDelivery;
        bytes32 authToken;
    }

    struct APIRequest {
        bytes32 requestId;
        bytes32 endpointId;
        address requester;
        bytes32 requestHash;
        uint256 timestamp;
        uint256 gasLimit;
        bool isAsync;
        bytes32 responseHash;
        bool fulfilled;
    }

    struct APIResponse {
        bytes32 responseId;
        bytes32 requestId;
        uint256 statusCode;
        bytes32 dataHash;
        uint256 responseTime;
        bool success;
        bytes32 errorMessage;
    }

    // Storage
    mapping(bytes32 => APIEndpoint) public apiEndpoints;
    mapping(bytes32 => WebhookSubscription) public webhookSubscriptions;
    mapping(bytes32 => APIRequest) public apiRequests;
    mapping(bytes32 => APIResponse) public apiResponses;
    mapping(address => bytes32[]) public endpointsByCaller;
    mapping(address => bytes32[]) public subscriptionsBySubscriber;

    // Global statistics
    uint256 public totalEndpoints;
    uint256 public totalSubscriptions;
    uint256 public totalRequests;
    uint256 public totalResponses;

    // Protocol parameters
    uint256 public defaultRateLimit = 60;      // requests per minute
    uint256 public maxGasLimit = 500000;       // gas limit for API calls
    uint256 public cacheExpiry = 300;          // 5 minutes
    uint256 public maxRetries = 3;

    // Events
    event APIEndpointRegistered(bytes32 indexed endpointId, string name, string url);
    event WebhookSubscribed(bytes32 indexed subscriptionId, address subscriber, string webhookUrl);
    event APIRequestMade(bytes32 indexed requestId, bytes32 indexed endpointId, address requester);
    event APIResponseReceived(bytes32 indexed responseId, bytes32 indexed requestId, bool success);
    event WebhookDelivered(bytes32 indexed subscriptionId, bytes32 eventId);

    modifier validEndpoint(bytes32 _endpointId) {
        require(apiEndpoints[_endpointId].authorizedCaller != address(0), "Endpoint not found");
        _;
    }

    modifier authorizedCaller(bytes32 _endpointId) {
        require(apiEndpoints[_endpointId].authorizedCaller == msg.sender, "Not authorized");
        _;
    }

    modifier activeEndpoint(bytes32 _endpointId) {
        require(apiEndpoints[_endpointId].status == IntegrationStatus.ACTIVE, "Endpoint not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new API endpoint
     */
    function registerEndpoint(
        string memory _name,
        string memory _url,
        APIType _apiType,
        HTTPMethod _method,
        uint256 _rateLimit,
        bool _requiresAuth,
        bytes32 _authToken
    ) external returns (bytes32) {
        bytes32 endpointId = keccak256(abi.encodePacked(
            _name,
            _url,
            msg.sender,
            block.timestamp
        ));

        require(apiEndpoints[endpointId].authorizedCaller == address(0), "Endpoint already exists");

        APIEndpoint storage endpoint = apiEndpoints[endpointId];
        endpoint.endpointId = endpointId;
        endpoint.name = _name;
        endpoint.url = _url;
        endpoint.apiType = _apiType;
        endpoint.method = _method;
        endpoint.authorizedCaller = msg.sender;
        endpoint.rateLimit = _rateLimit > 0 ? _rateLimit : defaultRateLimit;
        endpoint.status = IntegrationStatus.ACTIVE;
        endpoint.requiresAuth = _requiresAuth;
        endpoint.authToken = _authToken;

        endpointsByCaller[msg.sender].push(endpointId);
        totalEndpoints++;

        emit APIEndpointRegistered(endpointId, _name, _url);
        return endpointId;
    }

    /**
     * @notice Subscribe to webhooks
     */
    function subscribeWebhook(
        string memory _webhookUrl,
        bytes32[] memory _eventTypes,
        bytes32 _authToken
    ) external returns (bytes32) {
        bytes32 subscriptionId = keccak256(abi.encodePacked(
            _webhookUrl,
            msg.sender,
            block.timestamp
        ));

        WebhookSubscription storage subscription = webhookSubscriptions[subscriptionId];
        subscription.subscriptionId = subscriptionId;
        subscription.webhookUrl = _webhookUrl;
        subscription.subscriber = msg.sender;
        subscription.eventTypes = _eventTypes;
        subscription.isActive = true;
        subscription.authToken = _authToken;

        subscriptionsBySubscriber[msg.sender].push(subscriptionId);
        totalSubscriptions++;

        emit WebhookSubscribed(subscriptionId, msg.sender, _webhookUrl);
        return subscriptionId;
    }

    /**
     * @notice Make an API request
     */
    function makeAPIRequest(
        bytes32 _endpointId,
        bytes32 _requestHash,
        uint256 _gasLimit,
        bool _isAsync
    ) external validEndpoint(_endpointId) activeEndpoint(_endpointId) returns (bytes32) {
        APIEndpoint storage endpoint = apiEndpoints[_endpointId];

        // Check rate limit
        require(_checkRateLimit(endpoint), "Rate limit exceeded");

        // Check gas limit
        uint256 gasLimit = _gasLimit > 0 ? _gasLimit : maxGasLimit;
        require(gasLimit <= maxGasLimit, "Gas limit too high");

        bytes32 requestId = keccak256(abi.encodePacked(
            _endpointId,
            _requestHash,
            msg.sender,
            block.timestamp
        ));

        APIRequest storage request = apiRequests[requestId];
        request.requestId = requestId;
        request.endpointId = _endpointId;
        request.requester = msg.sender;
        request.requestHash = _requestHash;
        request.timestamp = block.timestamp;
        request.gasLimit = gasLimit;
        request.isAsync = _isAsync;

        endpoint.lastCall = block.timestamp;
        endpoint.callCount++;
        totalRequests++;

        emit APIRequestMade(requestId, _endpointId, msg.sender);
        return requestId;
    }

    /**
     * @notice Submit API response
     */
    function submitAPIResponse(
        bytes32 _requestId,
        uint256 _statusCode,
        bytes32 _dataHash,
        bytes32 _errorMessage
    ) external returns (bytes32) {
        APIRequest storage request = apiRequests[_requestId];
        require(request.requester != address(0), "Request not found");
        require(!request.fulfilled, "Request already fulfilled");

        bytes32 responseId = keccak256(abi.encodePacked(
            _requestId,
            _statusCode,
            _dataHash,
            block.timestamp
        ));

        APIResponse storage response = apiResponses[responseId];
        response.responseId = responseId;
        response.requestId = _requestId;
        response.statusCode = _statusCode;
        response.dataHash = _dataHash;
        response.responseTime = block.timestamp - request.timestamp;
        response.success = _statusCode >= 200 && _statusCode < 300;
        response.errorMessage = _errorMessage;

        request.responseHash = _dataHash;
        request.fulfilled = true;

        // Cache response
        APIEndpoint storage endpoint = apiEndpoints[request.endpointId];
        endpoint.responseCache[request.requestHash] = _dataHash;

        totalResponses++;

        emit APIResponseReceived(responseId, _requestId, response.success);
        return responseId;
    }

    /**
     * @notice Deliver webhook
     */
    function deliverWebhook(
        bytes32 _subscriptionId,
        bytes32 _eventId,
        bytes32 _eventData
    ) external {
        WebhookSubscription storage subscription = webhookSubscriptions[_subscriptionId];
        require(subscription.subscriber != address(0), "Subscription not found");
        require(subscription.isActive, "Subscription not active");

        // Check if event type is subscribed to
        bool isSubscribed = false;
        for (uint256 i = 0; i < subscription.eventTypes.length; i++) {
            if (subscription.eventTypes[i] == _eventId) {
                isSubscribed = true;
                break;
            }
        }
        require(isSubscribed, "Event type not subscribed");

        subscription.lastDelivery = block.timestamp;

        emit WebhookDelivered(_subscriptionId, _eventId);
    }

    /**
     * @notice Update endpoint status
     */
    function updateEndpointStatus(
        bytes32 _endpointId,
        IntegrationStatus _status
    ) external validEndpoint(_endpointId) authorizedCaller(_endpointId) {
        apiEndpoints[_endpointId].status = _status;
    }

    /**
     * @notice Update subscription status
     */
    function updateSubscriptionStatus(
        bytes32 _subscriptionId,
        bool _isActive
    ) external {
        WebhookSubscription storage subscription = webhookSubscriptions[_subscriptionId];
        require(subscription.subscriber == msg.sender, "Not subscriber");

        subscription.isActive = _isActive;
    }

    /**
     * @notice Get cached response
     */
    function getCachedResponse(bytes32 _endpointId, bytes32 _requestHash)
        external
        view
        returns (bytes32 responseHash, bool isCached)
    {
        APIEndpoint storage endpoint = apiEndpoints[_endpointId];
        responseHash = endpoint.responseCache[_requestHash];
        isCached = responseHash != bytes32(0);
    }

    /**
     * @notice Get endpoint details
     */
    function getEndpoint(bytes32 _endpointId)
        external
        view
        returns (
            string memory name,
            string memory url,
            APIType apiType,
            HTTPMethod method,
            uint256 rateLimit,
            IntegrationStatus status,
            bool requiresAuth
        )
    {
        APIEndpoint memory endpoint = apiEndpoints[_endpointId];
        return (
            endpoint.name,
            endpoint.url,
            endpoint.apiType,
            endpoint.method,
            endpoint.rateLimit,
            endpoint.status,
            endpoint.requiresAuth
        );
    }

    /**
     * @notice Get webhook subscription details
     */
    function getWebhookSubscription(bytes32 _subscriptionId)
        external
        view
        returns (
            string memory webhookUrl,
            address subscriber,
            bytes32[] memory eventTypes,
            bool isActive,
            uint256 lastDelivery
        )
    {
        WebhookSubscription memory subscription = webhookSubscriptions[_subscriptionId];
        return (
            subscription.webhookUrl,
            subscription.subscriber,
            subscription.eventTypes,
            subscription.isActive,
            subscription.lastDelivery
        );
    }

    /**
     * @notice Get API request details
     */
    function getAPIRequest(bytes32 _requestId)
        external
        view
        returns (
            bytes32 endpointId,
            address requester,
            uint256 timestamp,
            bool isAsync,
            bool fulfilled
        )
    {
        APIRequest memory request = apiRequests[_requestId];
        return (
            request.endpointId,
            request.requester,
            request.timestamp,
            request.isAsync,
            request.fulfilled
        );
    }

    /**
     * @notice Get API response details
     */
    function getAPIResponse(bytes32 _responseId)
        external
        view
        returns (
            bytes32 requestId,
            uint256 statusCode,
            bytes32 dataHash,
            bool success,
            bytes32 errorMessage
        )
    {
        APIResponse memory response = apiResponses[_responseId];
        return (
            response.requestId,
            response.statusCode,
            response.dataHash,
            response.success,
            response.errorMessage
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _defaultRateLimit,
        uint256 _maxGasLimit,
        uint256 _cacheExpiry,
        uint256 _maxRetries
    ) external onlyOwner {
        defaultRateLimit = _defaultRateLimit;
        maxGasLimit = _maxGasLimit;
        cacheExpiry = _cacheExpiry;
        maxRetries = _maxRetries;
    }

    /**
     * @notice Get global API integration statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalEndpoints,
            uint256 _totalSubscriptions,
            uint256 _totalRequests,
            uint256 _totalResponses
        )
    {
        return (totalEndpoints, totalSubscriptions, totalRequests, totalResponses);
    }

    // Internal functions
    function _checkRateLimit(APIEndpoint storage _endpoint) internal view returns (bool) {
        if (_endpoint.callCount == 0) return true;

        uint256 timeSinceLastCall = block.timestamp - _endpoint.lastCall;
        uint256 callsPerSecond = _endpoint.rateLimit / 60;

        // Simplified rate limiting - in production would use more sophisticated algorithm
        return timeSinceLastCall >= (60 / callsPerSecond);
    }
}
