// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";
import "../ai/AIAgentRegistry.sol";

/**
 * @title SWIFTGPIAdapter
 * @notice SWIFT GPI adapter for banking integration
 * @dev Manages SWIFT payment message processing and ISO20022 compliance
 */
contract SWIFTGPIAdapter is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant SWIFT_OPERATOR_ROLE = keccak256("SWIFT_OPERATOR_ROLE");
    bytes32 public constant BANK_ROLE = keccak256("BANK_ROLE");

    // Message types
    bytes32 public constant PACS_008 = keccak256("pacs.008"); // FIToFICustomerCreditTransfer
    bytes32 public constant PACS_009 = keccak256("pacs.009"); // FinancialInstitutionCreditTransfer
    bytes32 public constant CAMT_056 = keccak256("camt.056"); // FIToFIPaymentCancellationRequest
    
    struct SWIFTMessage {
        bytes32 messageType;
        string messageId;
        address sender;
        address receiver;
        uint256 amount;
        uint256 timestamp;
        bool processed;
        bytes32 status;
        bytes data;
    }

    // Message tracking
    mapping(bytes32 => SWIFTMessage) public messages;
    mapping(address => bool) public authorizedBanks;
    mapping(bytes32 => bool) public supportedMessageTypes;
    
    // Events
    event MessageReceived(
        bytes32 indexed messageId,
        bytes32 indexed messageType,
        address indexed sender
    );
    event MessageProcessed(
        bytes32 indexed messageId,
        bytes32 indexed status
    );
    event BankAuthorized(address indexed bank);
    event BankDeauthorized(address indexed bank);
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SWIFT_OPERATOR_ROLE, msg.sender);
        
        // Initialize supported message types
        supportedMessageTypes[PACS_008] = true;
        supportedMessageTypes[PACS_009] = true;
        supportedMessageTypes[CAMT_056] = true;
    }

    /**
     * @notice Submit a SWIFT message
     * @param messageType Type of SWIFT message
     * @param messageId Unique message identifier
     * @param receiver Receiving bank's address
     * @param amount Transaction amount
     * @param data Additional message data
     */
    function submitMessage(
        bytes32 messageType,
        string memory messageId,
        address receiver,
        uint256 amount,
        bytes memory data
    ) public whenNotPaused
        onlyRole(BANK_ROLE)
        returns (bytes32)
    {
        require(supportedMessageTypes[messageType], "Unsupported message type");
        require(authorizedBanks[receiver], "Receiver not authorized");
        
        bytes32 id = keccak256(abi.encodePacked(messageId, block.timestamp));
        
        SWIFTMessage memory message = SWIFTMessage({
            messageType: messageType,
            messageId: messageId,
            sender: msg.sender,
            receiver: receiver,
            amount: amount,
            timestamp: block.timestamp,
            processed: false,
            status: bytes32(0),
            data: data
        });
        
        messages[id] = message;
        
        emit MessageReceived(id, messageType, msg.sender);
        
        return id;
    }

    /**
     * @notice Process a SWIFT message
     * @param messageId Message identifier
     * @param status Processing status
     */
    function processMessage(bytes32 messageId, bytes32 status) public whenNotPaused
        onlyRole(SWIFT_OPERATOR_ROLE)
    {
        require(messages[messageId].timestamp > 0, "Message not found");
        require(!messages[messageId].processed, "Already processed");
        
        messages[messageId].processed = true;
        messages[messageId].status = status;
        
        emit MessageProcessed(messageId, status);
    }

    /**
     * @notice Authorize a bank
     * @param bank Bank's address
     */
    function authorizeBank(address bank) public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(!authorizedBanks[bank], "Already authorized");
        authorizedBanks[bank] = true;
        _grantRole(BANK_ROLE, bank);
        
        emit BankAuthorized(bank);
    }

    /**
     * @notice Deauthorize a bank
     * @param bank Bank's address
     */
    function deauthorizeBank(address bank) public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(authorizedBanks[bank], "Not authorized");
        authorizedBanks[bank] = false;
        _revokeRole(BANK_ROLE, bank);
        
        emit BankDeauthorized(bank);
    }

    /**
     * @notice Get message details
     * @param messageId Message identifier
     */
    function getMessage(bytes32 messageId) public view
        returns (
            bytes32 messageType,
            string memory id,
            address sender,
            address receiver,
            uint256 amount,
            uint256 timestamp,
            bool processed,
            bytes32 status
        )
    {
        SWIFTMessage memory message = messages[messageId];
        require(message.timestamp > 0, "Message not found");
        
        return (
            message.messageType,
            message.messageId,
            message.sender,
            message.receiver,
            message.amount,
            message.timestamp,
            message.processed,
            message.status
        );
    }

    /**
     * @notice Add a new supported message type
     * @param messageType Type of message to support
     */
    function addMessageType(bytes32 messageType) public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(!supportedMessageTypes[messageType], "Already supported");
        supportedMessageTypes[messageType] = true;
    }

    /**
     * @notice Remove a supported message type
     * @param messageType Type of message to remove
     */
    function removeMessageType(bytes32 messageType) public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(messageType != PACS_008 && messageType != PACS_009,
            "Cannot remove core types");
        require(supportedMessageTypes[messageType], "Not supported");
        supportedMessageTypes[messageType] = false;
    }

    // Emergency controls
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}