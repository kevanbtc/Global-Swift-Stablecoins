// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RealTimeMessaging
 * @notice Real-time messaging system for financial communications
 * @dev Handles instant messaging, notifications, and event-driven communications
 */
contract RealTimeMessaging is Ownable, ReentrancyGuard {

    enum MessageType {
        NOTIFICATION,
        ALERT,
        TRADE_CONFIRMATION,
        COMPLIANCE_UPDATE,
        REGULATORY_REPORT,
        SYSTEM_MAINTENANCE,
        MARKET_DATA,
        PAYMENT_STATUS,
        SETTLEMENT_UPDATE,
        RISK_WARNING,
        AUDIT_LOG,
        CUSTOM_MESSAGE
    }

    enum MessagePriority {
        LOW,
        NORMAL,
        HIGH,
        URGENT,
        CRITICAL
    }

    enum DeliveryStatus {
        PENDING,
        SENT,
        DELIVERED,
        READ,
        FAILED,
        EXPIRED
    }

    enum ChannelType {
        EMAIL,
        SMS,
        PUSH_NOTIFICATION,
        IN_APP,
        WEBHOOK,
        API_CALLBACK,
        BLOCKCHAIN_EVENT,
        LEGACY_SYSTEM
    }

    struct Message {
        bytes32 messageId;
        MessageType messageType;
        MessagePriority priority;
        address sender;
        address recipient;
        string subject;
        string content;
        bytes32 contentHash;
        uint256 timestamp;
        uint256 expiryTimestamp;
        DeliveryStatus status;
        ChannelType[] channels;
        mapping(ChannelType => DeliveryStatus) channelStatus;
        mapping(bytes32 => bytes32) metadata;
        bool requiresAcknowledgment;
        bool acknowledged;
        uint256 acknowledgmentDeadline;
    }

    struct MessageTemplate {
        bytes32 templateId;
        string name;
        MessageType messageType;
        MessagePriority priority;
        string subjectTemplate;
        string contentTemplate;
        bool isActive;
        uint256 usageCount;
    }

    struct Subscription {
        bytes32 subscriptionId;
        address subscriber;
        MessageType[] messageTypes;
        ChannelType[] preferredChannels;
        bool isActive;
        uint256 subscriptionStart;
        uint256 subscriptionEnd;
        mapping(MessageType => bool) typeEnabled;
    }

    struct MessageQueue {
        bytes32[] pendingMessages;
        uint256 maxQueueSize;
        uint256 processingRate; // messages per block
        bool isActive;
    }

    // Storage
    mapping(bytes32 => Message) public messages;
    mapping(bytes32 => MessageTemplate) public messageTemplates;
    mapping(bytes32 => Subscription) public subscriptions;
    mapping(address => bytes32[]) public userMessages;
    mapping(address => bytes32[]) public userSubscriptions;
    mapping(MessageType => bytes32[]) public messagesByType;
    mapping(ChannelType => address) public channelHandlers;

    MessageQueue public messageQueue;

    // Global statistics
    uint256 public totalMessages;
    uint256 public totalTemplates;
    uint256 public totalSubscriptions;
    uint256 public totalDeliveries;

    // Protocol parameters
    uint256 public defaultExpiry = 7 days;
    uint256 public maxMessageSize = 10000; // characters
    uint256 public maxQueueSize = 1000;
    uint256 public processingRate = 10; // messages per block
    uint256 public acknowledgmentTimeout = 24 hours;

    // Events
    event MessageSent(bytes32 indexed messageId, address indexed sender, address indexed recipient);
    event MessageDelivered(bytes32 indexed messageId, ChannelType channel);
    event MessageAcknowledged(bytes32 indexed messageId, address acknowledger);
    event TemplateCreated(bytes32 indexed templateId, string name);
    event SubscriptionCreated(bytes32 indexed subscriptionId, address subscriber);

    modifier validMessage(bytes32 _messageId) {
        require(messages[_messageId].sender != address(0), "Message not found");
        _;
    }

    modifier validTemplate(bytes32 _templateId) {
        require(messageTemplates[_templateId].isActive, "Template not found or inactive");
        _;
    }

    constructor() Ownable(msg.sender) {
        messageQueue.maxQueueSize = maxQueueSize;
        messageQueue.processingRate = processingRate;
        messageQueue.isActive = true;
    }

    /**
     * @notice Send a message
     */
    function sendMessage(
        address _recipient,
        MessageType _messageType,
        MessagePriority _priority,
        string memory _subject,
        string memory _content,
        ChannelType[] memory _channels,
        bool _requiresAcknowledgment
        ) public returns (bytes32) {
        require(bytes(_subject).length > 0, "Subject required");
        require(bytes(_content).length <= maxMessageSize, "Content too large");
        require(_channels.length > 0, "At least one channel required");

        bytes32 messageId = keccak256(abi.encodePacked(
            msg.sender,
            _recipient,
            _messageType,
            block.timestamp
        ));

        Message storage message = messages[messageId];
        message.messageId = messageId;
        message.messageType = _messageType;
        message.priority = _priority;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.subject = _subject;
        message.content = _content;
        message.contentHash = keccak256(abi.encodePacked(_content));
        message.timestamp = block.timestamp;
        message.expiryTimestamp = block.timestamp + defaultExpiry;
        message.status = DeliveryStatus.PENDING;
        message.channels = _channels;
        message.requiresAcknowledgment = _requiresAcknowledgment;

        if (_requiresAcknowledgment) {
            message.acknowledgmentDeadline = block.timestamp + acknowledgmentTimeout;
        }

        userMessages[_recipient].push(messageId);
        messagesByType[_messageType].push(messageId);
        totalMessages++;

        // Add to processing queue
        if (messageQueue.pendingMessages.length < messageQueue.maxQueueSize) {
            messageQueue.pendingMessages.push(messageId);
        }

        emit MessageSent(messageId, msg.sender, _recipient);
        return messageId;
    }

    /**
     * @notice Send message using template
     */
    function sendTemplatedMessage(
        bytes32 _templateId,
        address _recipient,
        string[] memory _placeholders,
        ChannelType[] memory _channels
    ) public validTemplate(_templateId) returns (bytes32) {
        MessageTemplate memory template = messageTemplates[_templateId];

        // Apply placeholders to template (simplified)
        string memory subject = template.subjectTemplate;
        string memory content = template.contentTemplate;

        // In production, would replace placeholders with actual values
        for (uint256 i = 0; i < _placeholders.length; i++) {
            // Placeholder replacement logic would go here
        }

        template.usageCount++;

        return sendMessage(
            _recipient,
            template.messageType,
            template.priority,
            subject,
            content,
            _channels,
            false
        );
    }

    /**
     * @notice Create message template
     */
    function createTemplate(
        string memory _name,
        MessageType _messageType,
        MessagePriority _priority,
        string memory _subjectTemplate,
        string memory _contentTemplate
    ) public onlyOwner returns (bytes32) {
        bytes32 templateId = keccak256(abi.encodePacked(
            _name,
            _messageType,
            block.timestamp
        ));

        MessageTemplate storage template = messageTemplates[templateId];
        template.templateId = templateId;
        template.name = _name;
        template.messageType = _messageType;
        template.priority = _priority;
        template.subjectTemplate = _subjectTemplate;
        template.contentTemplate = _contentTemplate;
        template.isActive = true;

        totalTemplates++;

        emit TemplateCreated(templateId, _name);
        return templateId;
    }

    /**
     * @notice Subscribe to message types
     */
    function subscribeToMessages(
        MessageType[] memory _messageTypes,
        ChannelType[] memory _preferredChannels
    ) public returns (bytes32) {
        bytes32 subscriptionId = keccak256(abi.encodePacked(
            msg.sender,
            block.timestamp
        ));

        Subscription storage subscription = subscriptions[subscriptionId];
        subscription.subscriptionId = subscriptionId;
        subscription.subscriber = msg.sender;
        subscription.messageTypes = _messageTypes;
        subscription.preferredChannels = _preferredChannels;
        subscription.isActive = true;
        subscription.subscriptionStart = block.timestamp;
        subscription.subscriptionEnd = block.timestamp + 365 days; // 1 year

        for (uint256 i = 0; i < _messageTypes.length; i++) {
            subscription.typeEnabled[_messageTypes[i]] = true;
        }

        userSubscriptions[msg.sender].push(subscriptionId);
        totalSubscriptions++;

        emit SubscriptionCreated(subscriptionId, msg.sender);
        return subscriptionId;
    }

    /**
     * @notice Acknowledge message receipt
     */
    function acknowledgeMessage(bytes32 _messageId) public validMessage(_messageId) {
        Message storage message = messages[_messageId];
        require(message.recipient == msg.sender, "Not message recipient");
        require(message.requiresAcknowledgment, "Acknowledgment not required");
        require(!message.acknowledged, "Already acknowledged");
        require(block.timestamp <= message.acknowledgmentDeadline, "Acknowledgment deadline passed");

        message.acknowledged = true;

        emit MessageAcknowledged(_messageId, msg.sender);
    }

    /**
     * @notice Update message delivery status
     */
    function updateDeliveryStatus(
        bytes32 _messageId,
        ChannelType _channel,
        DeliveryStatus _status
    ) public validMessage(_messageId) {
        Message storage message = messages[_messageId];
        require(channelHandlers[_channel] == msg.sender, "Not authorized channel handler");

        message.channelStatus[_channel] = _status;

        // Update overall message status
        if (_status == DeliveryStatus.DELIVERED && message.status != DeliveryStatus.READ) {
            message.status = DeliveryStatus.DELIVERED;
            totalDeliveries++;
            emit MessageDelivered(_messageId, _channel);
        } else if (_status == DeliveryStatus.READ) {
            message.status = DeliveryStatus.READ;
        } else if (_status == DeliveryStatus.FAILED && message.status != DeliveryStatus.DELIVERED) {
            message.status = DeliveryStatus.FAILED;
        }
    }

    /**
     * @notice Register channel handler
     */
    function registerChannelHandler(ChannelType _channel, address _handler) public onlyOwner {
        channelHandlers[_channel] = _handler;
    }

    /**
     * @notice Process message queue
     */
    function processMessageQueue(uint256 _maxMessages) public {
        require(messageQueue.isActive, "Queue not active");

        uint256 messagesToProcess = _maxMessages < messageQueue.processingRate ?
            _maxMessages : messageQueue.processingRate;

        for (uint256 i = 0; i < messagesToProcess && messageQueue.pendingMessages.length > 0; i++) {
            bytes32 messageId = messageQueue.pendingMessages[0];
            messageQueue.pendingMessages[0] = messageQueue.pendingMessages[messageQueue.pendingMessages.length - 1];
            messageQueue.pendingMessages.pop();

            // Process message (send to channels)
            _processMessage(messageId);
        }
    }

    /**
     * @notice Get message details
     */
    function getMessage(bytes32 _messageId) public view
        returns (
            MessageType messageType,
            MessagePriority priority,
            address sender,
            address recipient,
            string memory subject,
            uint256 timestamp,
            DeliveryStatus status,
            bool requiresAcknowledgment,
            bool acknowledged
        )
    {
        Message storage message = messages[_messageId];
        return (
            message.messageType,
            message.priority,
            message.sender,
            message.recipient,
            message.subject,
            message.timestamp,
            message.status,
            message.requiresAcknowledgment,
            message.acknowledged
        );
    }

    /**
     * @notice Get message content
     */
    function getMessageContent(bytes32 _messageId) public view
        validMessage(_messageId)
        returns (string memory content, bytes32 contentHash)
    {
        Message storage message = messages[_messageId];
        // In production, would check access permissions
        return (message.content, message.contentHash);
    }

    /**
     * @notice Get message channels
     */
    function getMessageChannels(bytes32 _messageId) public view
        returns (ChannelType[] memory channels, DeliveryStatus[] memory statuses)
    {
        Message storage message = messages[_messageId];
        DeliveryStatus[] memory channelStatuses = new DeliveryStatus[](message.channels.length);

        for (uint256 i = 0; i < message.channels.length; i++) {
            channelStatuses[i] = message.channelStatus[message.channels[i]];
        }

        return (message.channels, channelStatuses);
    }

    /**
     * @notice Get subscription details
     */
    function getSubscription(bytes32 _subscriptionId) public view
        returns (
            address subscriber,
            MessageType[] memory messageTypes,
            ChannelType[] memory preferredChannels,
            bool isActive,
            uint256 subscriptionEnd
        )
    {
        Subscription storage subscription = subscriptions[_subscriptionId];
        return (
            subscription.subscriber,
            subscription.messageTypes,
            subscription.preferredChannels,
            subscription.isActive,
            subscription.subscriptionEnd
        );
    }

    /**
     * @notice Get user messages
     */
    function getUserMessages(address _user, uint256 _offset, uint256 _limit) public view
        returns (bytes32[] memory messageIds)
    {
        bytes32[] memory allMessages = userMessages[_user];
        uint256 start = _offset;
        uint256 end = _offset + _limit > allMessages.length ? allMessages.length : _offset + _limit;

        bytes32[] memory result = new bytes32[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = allMessages[i];
        }

        return result;
    }

    /**
     * @notice Check if user is subscribed to message type
     */
    function isSubscribedToType(address _user, MessageType _messageType) public view returns (bool) {
        bytes32[] memory userSubs = userSubscriptions[_user];
        for (uint256 i = 0; i < userSubs.length; i++) {
            Subscription storage subscription = subscriptions[userSubs[i]];
            if (subscription.isActive && subscription.typeEnabled[_messageType]) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _defaultExpiry,
        uint256 _maxMessageSize,
        uint256 _maxQueueSize,
        uint256 _processingRate,
        uint256 _acknowledgmentTimeout
    ) public onlyOwner {
        defaultExpiry = _defaultExpiry;
        maxMessageSize = _maxMessageSize;
        maxQueueSize = _maxQueueSize;
        processingRate = _processingRate;
        acknowledgmentTimeout = _acknowledgmentTimeout;

        messageQueue.maxQueueSize = _maxQueueSize;
        messageQueue.processingRate = _processingRate;
    }

    /**
     * @notice Get global messaging statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalMessages,
            uint256 _totalTemplates,
            uint256 _totalSubscriptions,
            uint256 _totalDeliveries,
            uint256 _queueLength
        )
    {
        return (
            totalMessages,
            totalTemplates,
            totalSubscriptions,
            totalDeliveries,
            messageQueue.pendingMessages.length
        );
    }

    // Internal functions
    function _processMessage(bytes32 _messageId) internal {
        Message storage message = messages[_messageId];

        // Send to all specified channels
        for (uint256 i = 0; i < message.channels.length; i++) {
            ChannelType channel = message.channels[i];
            address handler = channelHandlers[channel];

            if (handler != address(0)) {
                // In production, would call handler contract
                // For now, mark as sent
                message.channelStatus[channel] = DeliveryStatus.SENT;
            }
        }

        message.status = DeliveryStatus.SENT;
    }
}
