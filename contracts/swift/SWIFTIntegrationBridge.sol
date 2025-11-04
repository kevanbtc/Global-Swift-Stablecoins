// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title SWIFTIntegrationBridge
 * @notice Direct integration bridge for SWIFT GPI and shared ledger functionality
 * @dev Handles SWIFT message routing, GPI tracking, and shared ledger settlement
 */
contract SWIFTIntegrationBridge is Ownable, ReentrancyGuard, Pausable {

    enum SWIFTMessageType {
        MT_103,     // Single Customer Credit Transfer
        MT_202,     // General Financial Institution Transfer
        MT_205,     // Financial Institution Transfer Execution
        MT_210,     // Notice to Receive
        MT_900,     // Confirmation of Debit
        MT_910,     // Confirmation of Credit
        GPI_STATUS, // GPI Status Update
        SHARED_LEDGER // Shared Ledger Transaction
    }

    enum GPIStatus {
        RECEIVED,
        PENDING,
        COVERED,
        LIQUIDATED,
        CONFIRMED,
        REJECTED
    }

    enum SettlementStatus {
        PENDING,
        CONFIRMED,
        SETTLED,
        FAILED,
        CANCELLED
    }

    struct SWIFTMessage {
        bytes32 messageId;
        SWIFTMessageType msgType;
        GPIStatus gpiStatus;
        SettlementStatus settlementStatus;
        address sender;
        address receiver;
        uint256 amount;
        string currency;
        string senderBIC;
        string receiverBIC;
        string uetr;              // Unique End-to-End Transaction Reference
        bytes32 sharedLedgerTxId; // Shared ledger transaction ID
        uint256 timestamp;
        uint256 expectedSettlementTime;
        uint256 actualSettlementTime;
        bool isSharedLedgerEnabled;
        bytes messageData;
    }

    struct GPITracking {
        bytes32 uetr;
        GPIStatus status;
        uint256 lastUpdate;
        uint256 expectedSettlementTime;
        uint256 actualSettlementTime;
        string trackingInfo;
        address trackedBy;
    }

    struct SharedLedgerEntry {
        bytes32 transactionId;
        address participant;
        uint256 amount;
        string assetType;
        SettlementStatus status;
        uint256 timestamp;
        bytes32 parentUetr;
        bytes settlementProof;
    }

    // Storage
    mapping(bytes32 => SWIFTMessage) public messages;
    mapping(bytes32 => GPITracking) public gpiTracking;
    mapping(bytes32 => SharedLedgerEntry) public sharedLedgerEntries;
    mapping(address => bool) public authorizedSWIFTNodes;
    mapping(string => address) public bicToAddress; // BIC to blockchain address mapping

    // Configuration
    uint256 public maxMessageSize = 50000; // Max SWIFT message size
    uint256 public gpiTimeout = 24 hours;  // GPI status timeout
    uint256 public settlementTimeout = 2 hours; // Settlement timeout
    uint256 public sharedLedgerTimeout = 1 hours;

    // Counters
    uint256 public messageCount;
    uint256 public sharedLedgerTxCount;

    // Events
    event SWIFTMessageReceived(bytes32 indexed messageId, SWIFTMessageType msgType, string uetr);
    event GPIStatusUpdated(bytes32 indexed uetr, GPIStatus status, string trackingInfo);
    event SharedLedgerTransaction(bytes32 indexed txId, address indexed participant, uint256 amount);
    event SettlementConfirmed(bytes32 indexed messageId, uint256 settlementTime);
    event SettlementFailed(bytes32 indexed messageId, string reason);
    event SWIFTNodeAuthorized(address indexed node, bool authorized);
    event BICMapped(string bic, address blockchainAddress);

    modifier onlySWIFTNode() {
        require(authorizedSWIFTNodes[msg.sender], "Not authorized SWIFT node");
        _;
    }

    modifier validMessageSize(bytes memory data) {
        require(data.length <= maxMessageSize, "Message too large");
        _;
    }

    constructor(address[] memory _swiftNodes) Ownable(msg.sender) {
        for (uint256 i = 0; i < _swiftNodes.length; i++) {
            authorizedSWIFTNodes[_swiftNodes[i]] = true;
            emit SWIFTNodeAuthorized(_swiftNodes[i], true);
        }
    }

    /**
     * @notice Receive and process a SWIFT message
     */
    function receiveSWIFTMessage(
        SWIFTMessageType _type,
        address _receiver,
        uint256 _amount,
        string memory _currency,
        string memory _senderBIC,
        string memory _receiverBIC,
        string memory _uetr,
        bytes memory _messageData
    ) external onlySWIFTNode whenNotPaused validMessageSize(_messageData) returns (bytes32) {
        require(_amount > 0, "Invalid amount");
        require(bytes(_currency).length == 3, "Invalid currency");
        require(bytes(_uetr).length == 36, "Invalid UETR format");
        require(bytes(_senderBIC).length == 8 || bytes(_senderBIC).length == 11, "Invalid sender BIC");
        require(bytes(_receiverBIC).length == 8 || bytes(_receiverBIC).length == 11, "Invalid receiver BIC");

        bytes32 messageId = keccak256(abi.encodePacked(
            _type,
            _senderBIC,
            _receiverBIC,
            _uetr,
            block.timestamp,
            _messageData
        ));

        require(messages[messageId].timestamp == 0, "Message already exists");

        // Determine if shared ledger is enabled for this transaction
        bool isSharedLedgerEnabled = _shouldUseSharedLedger(_type, _amount);

        messages[messageId] = SWIFTMessage({
            messageId: messageId,
            msgType: _type,
            gpiStatus: GPIStatus.RECEIVED,
            settlementStatus: SettlementStatus.PENDING,
            sender: bicToAddress[_senderBIC],
            receiver: _receiver,
            amount: _amount,
            currency: _currency,
            senderBIC: _senderBIC,
            receiverBIC: _receiverBIC,
            uetr: _uetr,
            sharedLedgerTxId: bytes32(0),
            timestamp: block.timestamp,
            expectedSettlementTime: block.timestamp + settlementTimeout,
            actualSettlementTime: 0,
            isSharedLedgerEnabled: isSharedLedgerEnabled,
            messageData: _messageData
        });

        // Initialize GPI tracking
        gpiTracking[bytes32(abi.encodePacked(_uetr))] = GPITracking({
            uetr: bytes32(abi.encodePacked(_uetr)),
            status: GPIStatus.RECEIVED,
            lastUpdate: block.timestamp,
            expectedSettlementTime: block.timestamp + settlementTimeout,
            actualSettlementTime: 0,
            trackingInfo: "Message received and acknowledged",
            trackedBy: msg.sender
        });

        messageCount++;

        emit SWIFTMessageReceived(messageId, _type, _uetr);
        emit GPIStatusUpdated(bytes32(abi.encodePacked(_uetr)), GPIStatus.RECEIVED, "Message received and acknowledged");

        // Auto-process certain message types
        if (_type == SWIFTMessageType.MT_900 || _type == SWIFTMessageType.MT_910) {
            _processSettlementConfirmation(messageId);
        }

        return messageId;
    }

    /**
     * @notice Update GPI status for a transaction
     */
    function updateGPIStatus(
        string memory _uetr,
        GPIStatus _status,
        string memory _trackingInfo
    ) external onlySWIFTNode whenNotPaused {
        bytes32 uetrHash = bytes32(abi.encodePacked(_uetr));
        require(gpiTracking[uetrHash].lastUpdate > 0, "UETR not found");

        GPITracking storage tracking = gpiTracking[uetrHash];
        tracking.status = _status;
        tracking.lastUpdate = block.timestamp;
        tracking.trackingInfo = _trackingInfo;
        tracking.trackedBy = msg.sender;

        if (_status == GPIStatus.CONFIRMED) {
            tracking.actualSettlementTime = block.timestamp;
        }

        emit GPIStatusUpdated(uetrHash, _status, _trackingInfo);

        // Update corresponding message status
        _updateMessageFromGPI(uetrHash, _status);
    }

    /**
     * @notice Execute shared ledger transaction
     */
    function executeSharedLedgerTransaction(
        address _participant,
        uint256 _amount,
        string memory _assetType,
        string memory _uetr,
        bytes memory _settlementProof
    ) external onlySWIFTNode whenNotPaused returns (bytes32) {
        require(_amount > 0, "Invalid amount");
        require(_participant != address(0), "Invalid participant");

        bytes32 txId = keccak256(abi.encodePacked(
            _participant,
            _amount,
            _assetType,
            _uetr,
            block.timestamp
        ));

        require(sharedLedgerEntries[txId].timestamp == 0, "Transaction already exists");

        sharedLedgerEntries[txId] = SharedLedgerEntry({
            transactionId: txId,
            participant: _participant,
            amount: _amount,
            assetType: _assetType,
            status: SettlementStatus.CONFIRMED,
            timestamp: block.timestamp,
            parentUetr: bytes32(abi.encodePacked(_uetr)),
            settlementProof: _settlementProof
        });

        sharedLedgerTxCount++;

        emit SharedLedgerTransaction(txId, _participant, _amount);

        // Update parent message if exists
        _updateMessageFromSharedLedger(bytes32(abi.encodePacked(_uetr)), txId);

        return txId;
    }

    /**
     * @notice Confirm settlement for a SWIFT message
     */
    function confirmSettlement(
        bytes32 _messageId,
        bytes memory _proof
    ) external onlySWIFTNode whenNotPaused {
        SWIFTMessage storage message = messages[_messageId];
        require(message.timestamp > 0, "Message not found");
        require(message.settlementStatus == SettlementStatus.PENDING, "Settlement not pending");

        message.settlementStatus = SettlementStatus.CONFIRMED;
        message.actualSettlementTime = block.timestamp;

        // Update GPI status
        bytes32 uetrHash = bytes32(abi.encodePacked(message.uetr));
        if (gpiTracking[uetrHash].lastUpdate > 0) {
            gpiTracking[uetrHash].status = GPIStatus.CONFIRMED;
            gpiTracking[uetrHash].actualSettlementTime = block.timestamp;
            gpiTracking[uetrHash].lastUpdate = block.timestamp;
        }

        emit SettlementConfirmed(_messageId, block.timestamp);
    }

    /**
     * @notice Fail settlement for a SWIFT message
     */
    function failSettlement(
        bytes32 _messageId,
        string memory _reason
    ) external onlySWIFTNode whenNotPaused {
        SWIFTMessage storage message = messages[_messageId];
        require(message.timestamp > 0, "Message not found");
        require(message.settlementStatus == SettlementStatus.PENDING, "Settlement not pending");

        message.settlementStatus = SettlementStatus.FAILED;

        emit SettlementFailed(_messageId, _reason);
    }

    /**
     * @notice Map BIC to blockchain address
     */
    function mapBICToAddress(
        string memory _bic,
        address _blockchainAddress
    ) external onlyOwner {
        require(bytes(_bic).length == 8 || bytes(_bic).length == 11, "Invalid BIC format");
        require(_blockchainAddress != address(0), "Invalid blockchain address");

        bicToAddress[_bic] = _blockchainAddress;
        emit BICMapped(_bic, _blockchainAddress);
    }

    /**
     * @notice Authorize or revoke SWIFT node
     */
    function setSWIFTNodeAuthorization(
        address _node,
        bool _authorized
    ) external onlyOwner {
        authorizedSWIFTNodes[_node] = _authorized;
        emit SWIFTNodeAuthorized(_node, _authorized);
    }

    /**
     * @notice Update configuration parameters
     */
    function updateConfig(
        uint256 _maxMessageSize,
        uint256 _gpiTimeout,
        uint256 _settlementTimeout,
        uint256 _sharedLedgerTimeout
    ) external onlyOwner {
        require(_maxMessageSize > 0, "Invalid max message size");
        require(_gpiTimeout > 0, "Invalid GPI timeout");
        require(_settlementTimeout > 0, "Invalid settlement timeout");
        require(_sharedLedgerTimeout > 0, "Invalid shared ledger timeout");

        maxMessageSize = _maxMessageSize;
        gpiTimeout = _gpiTimeout;
        settlementTimeout = _settlementTimeout;
        sharedLedgerTimeout = _sharedLedgerTimeout;
    }

    /**
     * @notice Get SWIFT message details
     */
    function getSWIFTMessage(bytes32 _messageId)
        external
        view
        returns (
            SWIFTMessageType msgType,
            GPIStatus gpiStatus,
            SettlementStatus settlementStatus,
            address sender,
            address receiver,
            uint256 amount,
            string memory currency,
            string memory uetr,
            uint256 timestamp,
            bool isSharedLedgerEnabled
        )
    {
        SWIFTMessage memory message = messages[_messageId];
        return (
            message.msgType,
            message.gpiStatus,
            message.settlementStatus,
            message.sender,
            message.receiver,
            message.amount,
            message.currency,
            message.uetr,
            message.timestamp,
            message.isSharedLedgerEnabled
        );
    }

    /**
     * @notice Get GPI tracking information
     */
    function getGPITracking(string memory _uetr)
        external
        view
        returns (
            GPIStatus status,
            uint256 lastUpdate,
            uint256 expectedSettlementTime,
            uint256 actualSettlementTime,
            string memory trackingInfo
        )
    {
        GPITracking memory tracking = gpiTracking[bytes32(abi.encodePacked(_uetr))];
        return (
            tracking.status,
            tracking.lastUpdate,
            tracking.expectedSettlementTime,
            tracking.actualSettlementTime,
            tracking.trackingInfo
        );
    }

    /**
     * @notice Get shared ledger entry
     */
    function getSharedLedgerEntry(bytes32 _txId)
        external
        view
        returns (
            address participant,
            uint256 amount,
            string memory assetType,
            SettlementStatus status,
            uint256 timestamp,
            bytes32 parentUetr
        )
    {
        SharedLedgerEntry memory entry = sharedLedgerEntries[_txId];
        return (
            entry.participant,
            entry.amount,
            entry.assetType,
            entry.status,
            entry.timestamp,
            entry.parentUetr
        );
    }

    /**
     * @notice Check if settlement is overdue
     */
    function isSettlementOverdue(bytes32 _messageId) external view returns (bool) {
        SWIFTMessage memory message = messages[_messageId];
        if (message.timestamp == 0 || message.settlementStatus != SettlementStatus.PENDING) {
            return false;
        }
        return block.timestamp > message.expectedSettlementTime;
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

    function _shouldUseSharedLedger(SWIFTMessageType _type, uint256 _amount) internal pure returns (bool) {
        // Use shared ledger for high-value transactions or specific message types
        if (_amount >= 1000000 * 1e18) { // 1M units
            return true;
        }
        if (_type == SWIFTMessageType.MT_202 || _type == SWIFTMessageType.MT_205) {
            return true;
        }
        return false;
    }

    function _processSettlementConfirmation(bytes32 _messageId) internal {
        SWIFTMessage storage message = messages[_messageId];

        // Auto-confirm settlement for confirmation messages
        if (message.msgType == SWIFTMessageType.MT_900 || message.msgType == SWIFTMessageType.MT_910) {
            message.settlementStatus = SettlementStatus.CONFIRMED;
            message.actualSettlementTime = block.timestamp;

            // Update GPI
            bytes32 uetrHash = bytes32(abi.encodePacked(message.uetr));
            if (gpiTracking[uetrHash].lastUpdate > 0) {
                gpiTracking[uetrHash].status = GPIStatus.CONFIRMED;
                gpiTracking[uetrHash].actualSettlementTime = block.timestamp;
            }

            emit SettlementConfirmed(_messageId, block.timestamp);
        }
    }

    function _updateMessageFromGPI(bytes32 _uetrHash, GPIStatus _status) internal {
        // Find and update corresponding message
        for (uint256 i = 0; i < messageCount; i++) {
            bytes32 messageId = keccak256(abi.encodePacked(i)); // Simplified - in practice would need proper indexing
            SWIFTMessage storage message = messages[messageId];
            if (message.timestamp > 0 && bytes32(abi.encodePacked(message.uetr)) == _uetrHash) {
                message.gpiStatus = _status;
                if (_status == GPIStatus.CONFIRMED) {
                    message.settlementStatus = SettlementStatus.CONFIRMED;
                    message.actualSettlementTime = block.timestamp;
                }
                break;
            }
        }
    }

    function _updateMessageFromSharedLedger(bytes32 _uetrHash, bytes32 _sharedLedgerTxId) internal {
        // Find and update corresponding message
        for (uint256 i = 0; i < messageCount; i++) {
            bytes32 messageId = keccak256(abi.encodePacked(i)); // Simplified
            SWIFTMessage storage message = messages[messageId];
            if (message.timestamp > 0 && bytes32(abi.encodePacked(message.uetr)) == _uetrHash) {
                message.sharedLedgerTxId = _sharedLedgerTxId;
                message.settlementStatus = SettlementStatus.CONFIRMED;
                message.actualSettlementTime = block.timestamp;
                break;
            }
        }
    }
}
