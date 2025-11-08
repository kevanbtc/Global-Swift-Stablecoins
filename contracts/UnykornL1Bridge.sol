// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./common/Types.sol";
import "./common/Roles.sol";
import "./common/Errors.sol";
import "./ai/AIAgentRegistry.sol";

/**
 * @title UnykornL1Bridge
 * @notice Cross-chain bridge for Layer 1 to Layer 2 transfers
 * @dev Manages token transfers and message passing between chains
 */
contract UnykornL1Bridge is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // Supported L2 chains
    mapping(uint256 => bool) public supportedChains;
    
    // Bridge state variables
    mapping(bytes32 => bool) public processedMessages;
    mapping(uint256 => uint256) public minimumTransferAmount;
    mapping(uint256 => uint256) public maximumTransferAmount;
    
    // Bridge fees
    mapping(uint256 => uint256) public bridgeFees;
    
    // Message queues
    mapping(uint256 => bytes32[]) public pendingMessages;
    
    // Events
    event ChainAdded(uint256 indexed chainId);
    event ChainRemoved(uint256 indexed chainId);
    event MessageProcessed(bytes32 indexed messageId, uint256 indexed chainId);
    event TokensBridged(
        address indexed token,
        address indexed from,
        uint256 indexed toChainId,
        address to,
        uint256 amount
    );
    event FeesUpdated(uint256 indexed chainId, uint256 newFee);
    event LimitsUpdated(
        uint256 indexed chainId,
        uint256 newMinimum,
        uint256 newMaximum
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);
    }

    /**
     * @notice Add support for a new L2 chain
     * @param chainId Chain ID of the L2 network
     * @param minimumAmount Minimum transfer amount
     * @param maximumAmount Maximum transfer amount
     * @param fee Bridge fee for this chain
     */
    function addChain(
        uint256 chainId,
        uint256 minimumAmount,
        uint256 maximumAmount,
        uint256 fee
    ) public onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused 
    {
        require(!supportedChains[chainId], "Chain already supported");
        require(minimumAmount < maximumAmount, "Invalid limits");
        
        supportedChains[chainId] = true;
        minimumTransferAmount[chainId] = minimumAmount;
        maximumTransferAmount[chainId] = maximumAmount;
        bridgeFees[chainId] = fee;
        
        emit ChainAdded(chainId);
        emit LimitsUpdated(chainId, minimumAmount, maximumAmount);
        emit FeesUpdated(chainId, fee);
    }

    /**
     * @notice Remove support for an L2 chain
     * @param chainId Chain ID to remove
     */
    function removeChain(uint256 chainId) public onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
    {
        require(supportedChains[chainId], "Chain not supported");
        supportedChains[chainId] = false;
        emit ChainRemoved(chainId);
    }

    /**
     * @notice Bridge tokens to L2
     * @param token Token address
     * @param to Recipient address on L2
     * @param amount Amount to bridge
     * @param toChainId Destination chain ID
     */
    function bridgeTokens(
        address token,
        address to,
        uint256 amount,
        uint256 toChainId
    ) public payable
        whenNotPaused
        nonReentrant
    {
        require(supportedChains[toChainId], "Unsupported chain");
        require(amount >= minimumTransferAmount[toChainId], "Below minimum");
        require(amount <= maximumTransferAmount[toChainId], "Exceeds maximum");
        require(msg.value >= bridgeFees[toChainId], "Insufficient fee");
        
        // Lock tokens in bridge
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        // Generate message for L2
        bytes32 messageId = _generateMessageId(
            token,
            msg.sender,
            to,
            amount,
            toChainId
        );
        
        // Queue message for processing
        pendingMessages[toChainId].push(messageId);
        
        emit TokensBridged(token, msg.sender, toChainId, to, amount);
    }

    /**
     * @notice Process queued messages
     * @param chainId Chain ID to process
     * @param maxMessages Maximum messages to process
     */
    function processMessages(uint256 chainId, uint256 maxMessages) public onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        require(supportedChains[chainId], "Chain not supported");
        
        bytes32[] storage queue = pendingMessages[chainId];
        uint256 messagesToProcess = queue.length < maxMessages ? 
            queue.length : maxMessages;
            
        for (uint256 i = 0; i < messagesToProcess; i++) {
            bytes32 messageId = queue[i];
            if (!processedMessages[messageId]) {
                processedMessages[messageId] = true;
                emit MessageProcessed(messageId, chainId);
            }
        }
        
        // Remove processed messages
        if (messagesToProcess > 0) {
            for (uint256 i = messagesToProcess; i < queue.length; i++) {
                queue[i - messagesToProcess] = queue[i];
            }
            for (uint256 i = 0; i < messagesToProcess; i++) {
                queue.pop();
            }
        }
    }

    /**
     * @notice Update bridge fees
     * @param chainId Chain ID
     * @param newFee New fee amount
     */
    function updateFee(uint256 chainId, uint256 newFee) public onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
    {
        require(supportedChains[chainId], "Chain not supported");
        bridgeFees[chainId] = newFee;
        emit FeesUpdated(chainId, newFee);
    }

    /**
     * @notice Update transfer limits
     * @param chainId Chain ID
     * @param newMinimum New minimum amount
     * @param newMaximum New maximum amount
     */
    function updateLimits(
        uint256 chainId,
        uint256 newMinimum,
        uint256 newMaximum
    ) public onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
    {
        require(supportedChains[chainId], "Chain not supported");
        require(newMinimum < newMaximum, "Invalid limits");
        
        minimumTransferAmount[chainId] = newMinimum;
        maximumTransferAmount[chainId] = newMaximum;
        
        emit LimitsUpdated(chainId, newMinimum, newMaximum);
    }

    /**
     * @notice Generate unique message ID
     */
    function _generateMessageId(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 chainId
    )
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                token,
                from,
                to,
                amount,
                chainId,
                block.timestamp
            )
        );
    }

    // Emergency controls
    function pause() public onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    // Withdraw bridge fees
    function withdrawFees(address payable recipient) public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 balance = address(this).balance;
        (bool success, ) = recipient.call{value: balance}("");
        require(success, "Fee withdrawal failed");
    }
}