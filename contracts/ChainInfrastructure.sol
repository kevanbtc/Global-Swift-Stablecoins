// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title ChainInfrastructure
 * @notice Core infrastructure contract for chain management
 * @dev Manages chain configurations, state transitions and cross-chain messaging
 */
contract ChainInfrastructure is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    // Chain configuration
    struct ChainConfig {
        uint256 chainId;
        string name;
        string networkType;
        uint256 blockTime;
        uint256 gasLimit;
        bool active;
        mapping(bytes32 => bool) supportedProtocols;
    }
    
    // State management
    struct ChainState {
        uint256 lastBlockHeight;
        bytes32 lastBlockHash;
        uint256 totalTransactions;
        uint256 lastUpdateTime;
        bytes32 networkState;
    }
    
    // Protocol configuration
    struct Protocol {
        string name;
        address bridge;
        bool active;
        uint256 minConfirmations;
        uint256 maxMessageSize;
    }
    
    // Message tracking
    struct CrossChainMessage {
        bytes32 messageId;
        uint256 sourceChain;
        uint256 destinationChain;
        address sender;
        address recipient;
        bytes data;
        uint256 timestamp;
        bool processed;
    }

    // Mappings
    mapping(uint256 => ChainConfig) public chainConfigs;
    mapping(uint256 => ChainState) public chainStates;
    mapping(bytes32 => Protocol) public protocols;
    mapping(bytes32 => CrossChainMessage) public messages;
    mapping(uint256 => uint256) public messageCount;
    
    // Events
    event ChainRegistered(uint256 indexed chainId, string name);
    event ChainStateUpdated(uint256 indexed chainId, bytes32 state);
    event ProtocolRegistered(bytes32 indexed protocolId, string name);
    event MessageSent(
        bytes32 indexed messageId,
        uint256 indexed sourceChain,
        uint256 indexed destinationChain
    );
    event MessageProcessed(
        bytes32 indexed messageId,
        bool success
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);
    }

    /**
     * @notice Register a new chain
     * @param chainId Chain identifier
     * @param name Chain name
     * @param networkType Network type (e.g., "mainnet", "testnet")
     * @param blockTime Average block time
     * @param gasLimit Block gas limit
     */
    function registerChain(
        uint256 chainId,
        string memory name,
        string memory networkType,
        uint256 blockTime,
        uint256 gasLimit
    )
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        require(chainConfigs[chainId].chainId == 0, "Chain exists");
        
        ChainConfig storage config = chainConfigs[chainId];
        config.chainId = chainId;
        config.name = name;
        config.networkType = networkType;
        config.blockTime = blockTime;
        config.gasLimit = gasLimit;
        config.active = true;
        
        emit ChainRegistered(chainId, name);
    }

    /**
     * @notice Update chain state
     * @param chainId Chain identifier
     * @param blockHeight Current block height
     * @param blockHash Latest block hash
     * @param networkState Current network state
     */
    function updateChainState(
        uint256 chainId,
        uint256 blockHeight,
        bytes32 blockHash,
        bytes32 networkState
    )
        external
        onlyRole(VALIDATOR_ROLE)
        whenNotPaused
    {
        require(chainConfigs[chainId].active, "Chain not active");
        
        ChainState storage state = chainStates[chainId];
        require(blockHeight > state.lastBlockHeight, "Invalid block height");
        
        state.lastBlockHeight = blockHeight;
        state.lastBlockHash = blockHash;
        state.lastUpdateTime = block.timestamp;
        state.networkState = networkState;
        state.totalTransactions++;
        
        emit ChainStateUpdated(chainId, networkState);
    }

    /**
     * @notice Register a new protocol
     * @param name Protocol name
     * @param bridge Bridge contract address
     * @param minConfirmations Minimum confirmations required
     * @param maxMessageSize Maximum message size
     */
    function registerProtocol(
        string memory name,
        address bridge,
        uint256 minConfirmations,
        uint256 maxMessageSize
    )
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
        returns (bytes32)
    {
        bytes32 protocolId = keccak256(abi.encodePacked(name));
        require(!protocols[protocolId].active, "Protocol exists");
        
        Protocol storage protocol = protocols[protocolId];
        protocol.name = name;
        protocol.bridge = bridge;
        protocol.active = true;
        protocol.minConfirmations = minConfirmations;
        protocol.maxMessageSize = maxMessageSize;
        
        emit ProtocolRegistered(protocolId, name);
        return protocolId;
    }

    /**
     * @notice Send cross-chain message
     * @param destinationChain Destination chain ID
     * @param recipient Recipient address
     * @param protocolId Protocol to use
     * @param data Message data
     */
    function sendMessage(
        uint256 destinationChain,
        address recipient,
        bytes32 protocolId,
        bytes memory data
    )
        external
        whenNotPaused
        nonReentrant
        returns (bytes32)
    {
        require(chainConfigs[destinationChain].active, "Invalid destination");
        require(protocols[protocolId].active, "Invalid protocol");
        require(data.length <= protocols[protocolId].maxMessageSize,
            "Message too large");
        
        bytes32 messageId = keccak256(abi.encodePacked(
            block.chainid,
            destinationChain,
            msg.sender,
            recipient,
            messageCount[destinationChain],
            block.timestamp
        ));
        
        CrossChainMessage storage message = messages[messageId];
        message.messageId = messageId;
        message.sourceChain = block.chainid;
        message.destinationChain = destinationChain;
        message.sender = msg.sender;
        message.recipient = recipient;
        message.data = data;
        message.timestamp = block.timestamp;
        message.processed = false;
        
        messageCount[destinationChain]++;
        
        emit MessageSent(messageId, block.chainid, destinationChain);
        
        return messageId;
    }

    /**
     * @notice Process received message
     * @param messageId Message identifier
     */
    function processMessage(bytes32 messageId)
        external
        onlyRole(VALIDATOR_ROLE)
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        CrossChainMessage storage message = messages[messageId];
        require(message.timestamp > 0, "Message not found");
        require(!message.processed, "Already processed");
        require(message.destinationChain == block.chainid,
            "Wrong destination");
        
        message.processed = true;
        
        // Execute message
        (bool success,) = message.recipient.call(message.data);
        
        emit MessageProcessed(messageId, success);
        
        return success;
    }

    /**
     * @notice Get chain configuration
     * @param chainId Chain identifier
     */
    function getChainConfig(uint256 chainId)
        external
        view
        returns (
            string memory name,
            string memory networkType,
            uint256 blockTime,
            uint256 gasLimit,
            bool active
        )
    {
        ChainConfig storage config = chainConfigs[chainId];
        require(config.chainId > 0, "Chain not found");
        
        return (
            config.name,
            config.networkType,
            config.blockTime,
            config.gasLimit,
            config.active
        );
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}