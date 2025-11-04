// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title LegacySystemAdapters
 * @notice Adapters for connecting to legacy financial systems
 * @dev Bridges traditional banking systems with blockchain infrastructure
 */
contract LegacySystemAdapters is Ownable, ReentrancyGuard {

    enum LegacySystem {
        SWIFT_NETWORK,
        FEDWIRE,
        CHIPS,
        TARGET2,
        CHAPS,
        CLS_GROUP,
        DTCC,
        EURO_CLEAR,
        CLEARSTREAM,
        BOJ_NET,
        BACS,
        SEPA,
        ACH,
        WIRE_TRANSFER,
        CHECK_CLEARING,
        CARD_NETWORKS
    }

    enum MessageType {
        PAYMENT_INSTRUCTION,
        PAYMENT_STATUS,
        ACCOUNT_STATEMENT,
        BALANCE_INQUIRY,
        COMPLIANCE_CHECK,
        REGULATORY_REPORT,
        SETTLEMENT_CONFIRMATION,
        DISPUTE_RESOLUTION,
        ACCOUNT_MAINTENANCE,
        CUSTOM_MESSAGE
    }

    enum ConnectionStatus {
        DISCONNECTED,
        CONNECTING,
        CONNECTED,
        AUTHENTICATING,
        ACTIVE,
        ERROR,
        MAINTENANCE
    }

    struct SystemAdapter {
        bytes32 adapterId;
        LegacySystem systemType;
        string systemName;
        address adapterAddress;
        ConnectionStatus status;
        uint256 lastHeartbeat;
        uint256 messageCount;
        uint256 errorCount;
        bytes32 authenticationToken;
        uint256 connectionTimeout;    // seconds
        bool isActive;
        mapping(MessageType => bool) supportedMessages;
        mapping(bytes32 => bytes32) pendingMessages; // messageId => responseId
    }

    struct LegacyMessage {
        bytes32 messageId;
        bytes32 adapterId;
        MessageType messageType;
        address sender;
        address recipient;
        uint256 timestamp;
        bytes32 contentHash;
        bytes32 correlationId;
        bool isProcessed;
        bytes32 responseHash;
        uint256 processingTime;
    }

    struct MessageMapping {
        bytes32 legacyMessageId;
        bytes32 blockchainMessageId;
        LegacySystem sourceSystem;
        uint256 mappingTimestamp;
        bool isActive;
    }

    // Storage
    mapping(bytes32 => SystemAdapter) public systemAdapters;
    mapping(bytes32 => LegacyMessage) public legacyMessages;
    mapping(bytes32 => MessageMapping) public messageMappings;
    mapping(LegacySystem => bytes32[]) public systemAdaptersByType;
    mapping(address => bytes32[]) public adaptersByAddress;

    // Global statistics
    uint256 public totalAdapters;
    uint256 public totalMessages;
    uint256 public totalMappings;
    uint256 public activeConnections;

    // Protocol parameters
    uint256 public heartbeatInterval = 300;     // 5 minutes
    uint256 public connectionTimeout = 3600;    // 1 hour
    uint256 public maxMessageSize = 1024;       // bytes
    uint256 public processingTimeout = 600;     // 10 minutes

    // Events
    event AdapterRegistered(bytes32 indexed adapterId, LegacySystem systemType, string systemName);
    event ConnectionStatusChanged(bytes32 indexed adapterId, ConnectionStatus status);
    event MessageSent(bytes32 indexed messageId, bytes32 indexed adapterId, MessageType messageType);
    event MessageReceived(bytes32 indexed messageId, bytes32 indexed adapterId, MessageType messageType);
    event MessageMapped(bytes32 indexed legacyMessageId, bytes32 indexed blockchainMessageId);

    modifier validAdapter(bytes32 _adapterId) {
        require(systemAdapters[_adapterId].adapterAddress != address(0), "Adapter not found");
        _;
    }

    modifier onlyAdapter(bytes32 _adapterId) {
        require(systemAdapters[_adapterId].adapterAddress == msg.sender, "Not adapter");
        _;
    }

    modifier activeAdapter(bytes32 _adapterId) {
        require(systemAdapters[_adapterId].isActive, "Adapter not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new legacy system adapter
     */
    function registerAdapter(
        LegacySystem _systemType,
        string memory _systemName,
        bytes32 _authenticationToken,
        uint256 _connectionTimeout
    ) external returns (bytes32) {
        bytes32 adapterId = keccak256(abi.encodePacked(
            _systemType,
            _systemName,
            msg.sender,
            block.timestamp
        ));

        require(systemAdapters[adapterId].adapterAddress == address(0), "Adapter already exists");

        SystemAdapter storage adapter = systemAdapters[adapterId];
        adapter.adapterId = adapterId;
        adapter.systemType = _systemType;
        adapter.systemName = _systemName;
        adapter.adapterAddress = msg.sender;
        adapter.status = ConnectionStatus.DISCONNECTED;
        adapter.authenticationToken = _authenticationToken;
        adapter.connectionTimeout = _connectionTimeout;
        adapter.isActive = true;

        systemAdaptersByType[_systemType].push(adapterId);
        adaptersByAddress[msg.sender].push(adapterId);
        totalAdapters++;

        emit AdapterRegistered(adapterId, _systemType, _systemName);
        return adapterId;
    }

    /**
     * @notice Update adapter connection status
     */
    function updateConnectionStatus(
        bytes32 _adapterId,
        ConnectionStatus _status
    ) external validAdapter(_adapterId) onlyAdapter(_adapterId) {
        SystemAdapter storage adapter = systemAdapters[_adapterId];
        ConnectionStatus oldStatus = adapter.status;

        adapter.status = _status;
        adapter.lastHeartbeat = block.timestamp;

        // Update active connections count
        if (oldStatus != ConnectionStatus.ACTIVE && _status == ConnectionStatus.ACTIVE) {
            activeConnections++;
        } else if (oldStatus == ConnectionStatus.ACTIVE && _status != ConnectionStatus.ACTIVE) {
            activeConnections--;
        }

        emit ConnectionStatusChanged(_adapterId, _status);
    }

    /**
     * @notice Send message to legacy system
     */
    function sendMessage(
        bytes32 _adapterId,
        MessageType _messageType,
        address _recipient,
        bytes32 _contentHash,
        bytes32 _correlationId
    ) external validAdapter(_adapterId) activeAdapter(_adapterId) returns (bytes32) {
        SystemAdapter storage adapter = systemAdapters[_adapterId];
        require(adapter.supportedMessages[_messageType], "Message type not supported");
        require(adapter.status == ConnectionStatus.ACTIVE, "Adapter not connected");

        bytes32 messageId = keccak256(abi.encodePacked(
            _adapterId,
            _messageType,
            msg.sender,
            _recipient,
            block.timestamp
        ));

        LegacyMessage storage message = legacyMessages[messageId];
        message.messageId = messageId;
        message.adapterId = _adapterId;
        message.messageType = _messageType;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.timestamp = block.timestamp;
        message.contentHash = _contentHash;
        message.correlationId = _correlationId;

        adapter.pendingMessages[messageId] = bytes32(0); // Placeholder for response
        adapter.messageCount++;
        totalMessages++;

        emit MessageSent(messageId, _adapterId, _messageType);
        return messageId;
    }

    /**
     * @notice Receive message from legacy system
     */
    function receiveMessage(
        bytes32 _messageId,
        bytes32 _correlationId,
        bytes32 _responseHash
    ) external validAdapter(_getAdapterId(msg.sender)) {
        bytes32 adapterId = _getAdapterId(msg.sender);
        SystemAdapter storage adapter = systemAdapters[adapterId];

        LegacyMessage storage message = legacyMessages[_messageId];
        require(message.adapterId == adapterId, "Message not for this adapter");
        require(!message.isProcessed, "Message already processed");

        message.responseHash = _responseHash;
        message.isProcessed = true;
        message.processingTime = block.timestamp - message.timestamp;

        // Remove from pending messages
        delete adapter.pendingMessages[_messageId];

        emit MessageReceived(_messageId, adapterId, message.messageType);
    }

    /**
     * @notice Map legacy message to blockchain message
     */
    function mapMessage(
        bytes32 _legacyMessageId,
        bytes32 _blockchainMessageId,
        LegacySystem _sourceSystem
    ) external onlyOwner returns (bytes32) {
        bytes32 mappingId = keccak256(abi.encodePacked(
            _legacyMessageId,
            _blockchainMessageId,
            block.timestamp
        ));

        MessageMapping storage messageMapping = messageMappings[mappingId];
        messageMapping.legacyMessageId = _legacyMessageId;
        messageMapping.blockchainMessageId = _blockchainMessageId;
        messageMapping.sourceSystem = _sourceSystem;
        messageMapping.mappingTimestamp = block.timestamp;
        messageMapping.isActive = true;

        totalMappings++;

        emit MessageMapped(_legacyMessageId, _blockchainMessageId);
        return mappingId;
    }

    /**
     * @notice Configure supported message types for adapter
     */
    function configureMessageTypes(
        bytes32 _adapterId,
        MessageType[] memory _messageTypes,
        bool[] memory _supported
    ) external validAdapter(_adapterId) onlyAdapter(_adapterId) {
        require(_messageTypes.length == _supported.length, "Array length mismatch");

        SystemAdapter storage adapter = systemAdapters[_adapterId];
        for (uint256 i = 0; i < _messageTypes.length; i++) {
            adapter.supportedMessages[_messageTypes[i]] = _supported[i];
        }
    }

    /**
     * @notice Send heartbeat to maintain connection
     */
    function sendHeartbeat(bytes32 _adapterId) external validAdapter(_adapterId) onlyAdapter(_adapterId) {
        SystemAdapter storage adapter = systemAdapters[_adapterId];
        adapter.lastHeartbeat = block.timestamp;

        if (adapter.status == ConnectionStatus.ACTIVE) {
            // Check for timeout
            if (block.timestamp - adapter.lastHeartbeat > adapter.connectionTimeout) {
                adapter.status = ConnectionStatus.ERROR;
                activeConnections--;
                emit ConnectionStatusChanged(_adapterId, ConnectionStatus.ERROR);
            }
        }
    }

    /**
     * @notice Get adapter details
     */
    function getAdapter(bytes32 _adapterId)
        external
        view
        returns (
            LegacySystem systemType,
            string memory systemName,
            ConnectionStatus status,
            uint256 messageCount,
            uint256 errorCount,
            bool isActive
        )
    {
        SystemAdapter memory adapter = systemAdapters[_adapterId];
        return (
            adapter.systemType,
            adapter.systemName,
            adapter.status,
            adapter.messageCount,
            adapter.errorCount,
            adapter.isActive
        );
    }

    /**
     * @notice Get message details
     */
    function getMessage(bytes32 _messageId)
        external
        view
        returns (
            bytes32 adapterId,
            MessageType messageType,
            address sender,
            address recipient,
            uint256 timestamp,
            bool isProcessed,
            uint256 processingTime
        )
    {
        LegacyMessage memory message = legacyMessages[_messageId];
        return (
            message.adapterId,
            message.messageType,
            message.sender,
            message.recipient,
            message.timestamp,
            message.isProcessed,
            message.processingTime
        );
    }

    /**
     * @notice Get message mapping
     */
    function getMessageMapping(bytes32 _mappingId)
        external
        view
        returns (
            bytes32 legacyMessageId,
            bytes32 blockchainMessageId,
            LegacySystem sourceSystem,
            uint256 mappingTimestamp,
            bool isActive
        )
    {
        MessageMapping memory msgMapping = messageMappings[_mappingId];
        return (
            msgMapping.legacyMessageId,
            msgMapping.blockchainMessageId,
            msgMapping.sourceSystem,
            msgMapping.mappingTimestamp,
            msgMapping.isActive
        );
    }

    /**
     * @notice Get adapters by system type
     */
    function getAdaptersByType(LegacySystem _systemType)
        external
        view
        returns (bytes32[] memory)
    {
        return systemAdaptersByType[_systemType];
    }

    /**
     * @notice Check if message type is supported
     */
    function isMessageTypeSupported(bytes32 _adapterId, MessageType _messageType)
        external
        view
        returns (bool)
    {
        return systemAdapters[_adapterId].supportedMessages[_messageType];
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _heartbeatInterval,
        uint256 _connectionTimeout,
        uint256 _maxMessageSize,
        uint256 _processingTimeout
    ) external onlyOwner {
        heartbeatInterval = _heartbeatInterval;
        connectionTimeout = _connectionTimeout;
        maxMessageSize = _maxMessageSize;
        processingTimeout = _processingTimeout;
    }

    /**
     * @notice Get global adapter statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalAdapters,
            uint256 _totalMessages,
            uint256 _totalMappings,
            uint256 _activeConnections
        )
    {
        return (totalAdapters, totalMessages, totalMappings, activeConnections);
    }

    // Internal functions
    function _getAdapterId(address _adapterAddress) internal view returns (bytes32) {
        bytes32[] memory adapterIds = adaptersByAddress[_adapterAddress];
        require(adapterIds.length > 0, "Not a registered adapter");
        return adapterIds[0]; // Return first adapter ID
    }
}
