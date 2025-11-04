// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title ISO20022MessageHandler
 * @notice Handles processing and validation of ISO 20022 financial messages
 * @dev Supports pacs.008, pacs.009, camt.053, and other ISO 20022 message types
 */
contract ISO20022MessageHandler is Ownable, ReentrancyGuard, Pausable {

    enum MessageType {
        PACS_008,   // FI to FI Customer Credit Transfer
        PACS_009,   // Financial Institution Credit Transfer
        CAMT_053,   // Bank to Customer Statement
        CAMT_054,   // Bank to Customer Debit Credit Notification
        PAIN_001,   // Customer to Bank Credit Transfer
        PAIN_002    // Customer Payment Status Report
    }

    enum MessageStatus {
        RECEIVED,
        VALIDATED,
        PROCESSED,
        REJECTED,
        SETTLED
    }

    struct ISO20022Message {
        bytes32 messageId;
        MessageType msgType;
        MessageStatus status;
        address sender;
        address receiver;
        uint256 amount;
        string currency;
        string messageData;      // Full ISO 20022 XML/JSON
        bytes32 hash;           // Content hash for integrity
        uint256 timestamp;
        uint256 settlementTime;
        bool isSettled;
    }

    struct ValidationResult {
        bool isValid;
        string[] errors;
        bytes32 canonicalHash;
        address validatedBy;
        uint256 validationTime;
    }

    // Message storage
    mapping(bytes32 => ISO20022Message) public messages;
    mapping(bytes32 => ValidationResult) public validations;
    mapping(address => bool) public authorizedValidators;
    mapping(MessageType => bool) public supportedTypes;

    // Configuration
    uint256 public maxMessageSize = 10000; // Max message size in bytes
    uint256 public validationTimeout = 1 hours;
    uint256 public settlementTimeout = 24 hours;

    // Events
    event MessageReceived(bytes32 indexed messageId, MessageType msgType, address indexed sender);
    event MessageValidated(bytes32 indexed messageId, bool isValid, address indexed validator);
    event MessageProcessed(bytes32 indexed messageId, MessageStatus status);
    event MessageSettled(bytes32 indexed messageId, uint256 settlementTime);
    event ValidatorAuthorized(address indexed validator, bool authorized);
    event MessageTypeSupported(MessageType msgType, bool supported);

    modifier onlyValidator() {
        require(authorizedValidators[msg.sender], "Not authorized validator");
        _;
    }

    modifier validMessageType(MessageType _type) {
        require(supportedTypes[_type], "Unsupported message type");
        _;
    }

    constructor(address[] memory _validators) Ownable(msg.sender) {
        // Enable common ISO 20022 message types
        supportedTypes[MessageType.PACS_008] = true;
        supportedTypes[MessageType.PACS_009] = true;
        supportedTypes[MessageType.CAMT_053] = true;
        supportedTypes[MessageType.CAMT_054] = true;
        supportedTypes[MessageType.PAIN_001] = true;
        supportedTypes[MessageType.PAIN_002] = true;

        // Authorize initial validators
        for (uint256 i = 0; i < _validators.length; i++) {
            authorizedValidators[_validators[i]] = true;
            emit ValidatorAuthorized(_validators[i], true);
        }
    }

    /**
     * @notice Receive and process an ISO 20022 message
     */
    function receiveMessage(
        MessageType _type,
        address _receiver,
        uint256 _amount,
        string memory _currency,
        string memory _messageData
    ) external whenNotPaused validMessageType(_type) returns (bytes32) {
        require(bytes(_messageData).length <= maxMessageSize, "Message too large");
        require(_amount > 0, "Invalid amount");
        require(bytes(_currency).length == 3, "Invalid currency code");

        bytes32 messageId = keccak256(abi.encodePacked(
            _type,
            msg.sender,
            _receiver,
            _amount,
            _currency,
            block.timestamp,
            _messageData
        ));

        require(messages[messageId].timestamp == 0, "Message already exists");

        bytes32 contentHash = keccak256(bytes(_messageData));

        messages[messageId] = ISO20022Message({
            messageId: messageId,
            msgType: _type,
            status: MessageStatus.RECEIVED,
            sender: msg.sender,
            receiver: _receiver,
            amount: _amount,
            currency: _currency,
            messageData: _messageData,
            hash: contentHash,
            timestamp: block.timestamp,
            settlementTime: 0,
            isSettled: false
        });

        emit MessageReceived(messageId, _type, msg.sender);
        return messageId;
    }

    /**
     * @notice Validate an ISO 20022 message
     */
    function validateMessage(
        bytes32 _messageId,
        bool _isValid,
        string[] memory _errors
    ) external onlyValidator whenNotPaused {
        ISO20022Message storage message = messages[_messageId];
        require(message.timestamp > 0, "Message not found");
        require(message.status == MessageStatus.RECEIVED, "Message not in validatable state");
        require(
            block.timestamp <= message.timestamp + validationTimeout,
            "Validation timeout exceeded"
        );

        // Prevent double validation
        require(validations[_messageId].validationTime == 0, "Already validated");

        validations[_messageId] = ValidationResult({
            isValid: _isValid,
            errors: _errors,
            canonicalHash: message.hash,
            validatedBy: msg.sender,
            validationTime: block.timestamp
        });

        if (_isValid) {
            message.status = MessageStatus.VALIDATED;
        } else {
            message.status = MessageStatus.REJECTED;
        }

        emit MessageValidated(_messageId, _isValid, msg.sender);
    }

    /**
     * @notice Process a validated message
     */
    function processMessage(bytes32 _messageId) external onlyValidator whenNotPaused {
        ISO20022Message storage message = messages[_messageId];
        ValidationResult memory validation = validations[_messageId];

        require(message.timestamp > 0, "Message not found");
        require(validation.isValid, "Message not validated or invalid");
        require(message.status == MessageStatus.VALIDATED, "Message not validated");

        message.status = MessageStatus.PROCESSED;

        // Process based on message type
        if (message.msgType == MessageType.PACS_008 || message.msgType == MessageType.PACS_009) {
            // Credit transfer - initiate settlement
            _initiateSettlement(_messageId);
        } else if (message.msgType == MessageType.CAMT_053 || message.msgType == MessageType.CAMT_054) {
            // Statement/Notification - mark as processed
            message.status = MessageStatus.SETTLED;
            message.settlementTime = block.timestamp;
            message.isSettled = true;
            emit MessageSettled(_messageId, block.timestamp);
        }

        emit MessageProcessed(_messageId, message.status);
    }

    /**
     * @notice Mark message as settled
     */
    function settleMessage(bytes32 _messageId) external onlyValidator whenNotPaused {
        ISO20022Message storage message = messages[_messageId];
        require(message.timestamp > 0, "Message not found");
        require(message.status == MessageStatus.PROCESSED, "Message not processed");
        require(!message.isSettled, "Already settled");

        message.status = MessageStatus.SETTLED;
        message.settlementTime = block.timestamp;
        message.isSettled = true;

        emit MessageSettled(_messageId, block.timestamp);
    }

    /**
     * @notice Get message details
     */
    function getMessage(bytes32 _messageId)
        external
        view
        returns (
            MessageType msgType,
            MessageStatus status,
            address sender,
            address receiver,
            uint256 amount,
            string memory currency,
            uint256 timestamp,
            bool isSettled
        )
    {
        ISO20022Message memory message = messages[_messageId];
        return (
            message.msgType,
            message.status,
            message.sender,
            message.receiver,
            message.amount,
            message.currency,
            message.timestamp,
            message.isSettled
        );
    }

    /**
     * @notice Get validation result
     */
    function getValidation(bytes32 _messageId)
        external
        view
        returns (
            bool isValid,
            string[] memory errors,
            address validatedBy,
            uint256 validationTime
        )
    {
        ValidationResult memory validation = validations[_messageId];
        return (
            validation.isValid,
            validation.errors,
            validation.validatedBy,
            validation.validationTime
        );
    }

    /**
     * @notice Authorize or revoke validator
     */
    function setValidator(address _validator, bool _authorized) external onlyOwner {
        authorizedValidators[_validator] = _authorized;
        emit ValidatorAuthorized(_validator, _authorized);
    }

    /**
     * @notice Enable or disable message type support
     */
    function setMessageTypeSupport(MessageType _type, bool _supported) external onlyOwner {
        supportedTypes[_type] = _supported;
        emit MessageTypeSupported(_type, _supported);
    }

    /**
     * @notice Update configuration parameters
     */
    function updateConfig(
        uint256 _maxMessageSize,
        uint256 _validationTimeout,
        uint256 _settlementTimeout
    ) external onlyOwner {
        require(_maxMessageSize > 0, "Invalid max message size");
        require(_validationTimeout > 0, "Invalid validation timeout");
        require(_settlementTimeout > 0, "Invalid settlement timeout");

        maxMessageSize = _maxMessageSize;
        validationTimeout = _validationTimeout;
        settlementTimeout = _settlementTimeout;
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

    function _initiateSettlement(bytes32 _messageId) internal {
        // This would integrate with settlement rails
        // For now, just mark as processed
        // In production, this would trigger cross-chain settlement
    }
}
