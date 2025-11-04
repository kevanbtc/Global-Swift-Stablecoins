// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FeeRouter
 * @notice Routes and distributes fees for stablecoin operations
 * @dev Handles fee collection, distribution, and treasury management
 */
contract FeeRouter is Ownable {
    using SafeERC20 for IERC20;

    struct FeeRecipient {
        address recipient;
        uint256 share;              // Basis points (e.g., 500 = 5%)
        bool isActive;
        string description;
    }

    struct FeeConfig {
        address token;              // Fee token (address(0) for native)
        uint256 totalCollected;
        FeeRecipient[] recipients;
        uint256 lastDistribution;
        uint256 distributionCooldown;
    }

    // Fee configurations by token
    mapping(address => FeeConfig) public feeConfigs;

    // Supported fee tokens
    address[] public supportedTokens;

    // Global settings
    uint256 public constant MAX_SHARE = 10000; // 100%
    uint256 public distributionCooldown = 7 days;
    address public treasury;

    // Events
    event FeeCollected(address indexed token, uint256 amount, address indexed collector);
    event FeeDistributed(address indexed token, uint256 totalAmount, uint256 recipientCount);
    event FeeRecipientAdded(address indexed token, address indexed recipient, uint256 share);
    event FeeRecipientRemoved(address indexed token, address indexed recipient);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    constructor(address _treasury) {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
        _transferOwnership(msg.sender);
    }

    /**
     * @notice Collect fees from stablecoin operations
     */
    function collectFee(address token, uint256 amount) external payable {
        require(amount > 0, "Amount must be greater than 0");

        if (token == address(0)) {
            // Native token
            require(msg.value >= amount, "Insufficient native payment");
        } else {
            // ERC20 token
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Initialize fee config if not exists
        if (feeConfigs[token].token == address(0)) {
            _initializeFeeConfig(token);
        }

        feeConfigs[token].totalCollected += amount;

        emit FeeCollected(token, amount, msg.sender);
    }

    /**
     * @notice Distribute collected fees to recipients
     */
    function distributeFees(address token) external {
        FeeConfig storage config = feeConfigs[token];
        require(config.token != address(0), "Fee config not initialized");
        require(config.recipients.length > 0, "No recipients configured");

        uint256 timeSinceLastDistribution = block.timestamp - config.lastDistribution;
        require(timeSinceLastDistribution >= config.distributionCooldown, "Distribution cooldown active");

        uint256 totalToDistribute = config.totalCollected;
        require(totalToDistribute > 0, "No fees to distribute");

        uint256 distributed = 0;
        uint256 activeRecipients = 0;

        // Count active recipients
        for (uint256 i = 0; i < config.recipients.length; i++) {
            if (config.recipients[i].isActive) {
                activeRecipients++;
            }
        }

        require(activeRecipients > 0, "No active recipients");

        // Distribute to each active recipient
        for (uint256 i = 0; i < config.recipients.length; i++) {
            FeeRecipient memory recipient = config.recipients[i];
            if (!recipient.isActive) continue;

            uint256 recipientShare = (totalToDistribute * recipient.share) / MAX_SHARE;
            if (recipientShare > 0) {
                if (token == address(0)) {
                    // Native token
                    payable(recipient.recipient).transfer(recipientShare);
                } else {
                    // ERC20 token
                    IERC20(token).safeTransfer(recipient.recipient, recipientShare);
                }
                distributed += recipientShare;
            }
        }

        // Reset collected amount and update timestamp
        config.totalCollected = 0;
        config.lastDistribution = block.timestamp;

        emit FeeDistributed(token, distributed, activeRecipients);
    }

    /**
     * @notice Add fee recipient for a token
     */
    function addFeeRecipient(
        address token,
        address recipient,
        uint256 share,
        string memory description
    ) external onlyOwner {
        require(recipient != address(0), "Invalid recipient address");
        require(share > 0 && share <= MAX_SHARE, "Invalid share amount");

        FeeConfig storage config = feeConfigs[token];
        if (config.token == address(0)) {
            _initializeFeeConfig(token);
        }

        // Check total share doesn't exceed 100%
        uint256 totalShare = share;
        for (uint256 i = 0; i < config.recipients.length; i++) {
            if (config.recipients[i].isActive) {
                totalShare += config.recipients[i].share;
            }
        }
        require(totalShare <= MAX_SHARE, "Total share exceeds 100%");

        config.recipients.push(FeeRecipient({
            recipient: recipient,
            share: share,
            isActive: true,
            description: description
        }));

        emit FeeRecipientAdded(token, recipient, share);
    }

    /**
     * @notice Remove fee recipient
     */
    function removeFeeRecipient(address token, uint256 index) external onlyOwner {
        FeeConfig storage config = feeConfigs[token];
        require(index < config.recipients.length, "Invalid recipient index");

        address recipient = config.recipients[index].recipient;
        config.recipients[index].isActive = false;

        emit FeeRecipientRemoved(token, recipient);
    }

    /**
     * @notice Update fee recipient share
     */
    function updateFeeRecipientShare(
        address token,
        uint256 index,
        uint256 newShare
    ) external onlyOwner {
        require(newShare > 0 && newShare <= MAX_SHARE, "Invalid share amount");

        FeeConfig storage config = feeConfigs[token];
        require(index < config.recipients.length, "Invalid recipient index");

        // Check total share doesn't exceed 100%
        uint256 totalShare = newShare;
        for (uint256 i = 0; i < config.recipients.length; i++) {
            if (config.recipients[i].isActive && i != index) {
                totalShare += config.recipients[i].share;
            }
        }
        require(totalShare <= MAX_SHARE, "Total share exceeds 100%");

        config.recipients[index].share = newShare;
    }

    /**
     * @notice Set distribution cooldown for a token
     */
    function setDistributionCooldown(address token, uint256 cooldown) external onlyOwner {
        feeConfigs[token].distributionCooldown = cooldown;
    }

    /**
     * @notice Update treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Emergency withdraw stuck tokens
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(treasury).transfer(amount);
        } else {
            IERC20(token).safeTransfer(treasury, amount);
        }
    }

    /**
     * @notice Get fee configuration
     */
    function getFeeConfig(address token) external view returns (
        address tokenAddress,
        uint256 totalCollected,
        uint256 recipientCount,
        uint256 lastDistribution
    ) {
        FeeConfig memory config = feeConfigs[token];
        return (
            config.token,
            config.totalCollected,
            config.recipients.length,
            config.lastDistribution
        );
    }

    /**
     * @notice Get fee recipient details
     */
    function getFeeRecipient(address token, uint256 index) external view returns (
        address recipient,
        uint256 share,
        bool isActive,
        string memory description
    ) {
        FeeRecipient memory recipientData = feeConfigs[token].recipients[index];
        return (
            recipientData.recipient,
            recipientData.share,
            recipientData.isActive,
            recipientData.description
        );
    }

    /**
     * @notice Get total active recipients for a token
     */
    function getActiveRecipientCount(address token) external view returns (uint256) {
        FeeRecipient[] memory recipients = feeConfigs[token].recipients;
        uint256 activeCount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].isActive) {
                activeCount++;
            }
        }
        return activeCount;
    }

    /**
     * @notice Check if distribution is ready for a token
     */
    function canDistribute(address token) external view returns (bool) {
        FeeConfig memory config = feeConfigs[token];
        if (config.token == address(0) || config.totalCollected == 0) {
            return false;
        }

        uint256 timeSinceLastDistribution = block.timestamp - config.lastDistribution;
        return timeSinceLastDistribution >= config.distributionCooldown;
    }

    /**
     * @dev Initialize fee configuration for a token
     */
    function _initializeFeeConfig(address token) internal {
        feeConfigs[token] = FeeConfig({
            token: token,
            totalCollected: 0,
            recipients: new FeeRecipient[](0),
            lastDistribution: 0,
            distributionCooldown: distributionCooldown
        });

        // Add to supported tokens if not already present
        bool alreadySupported = false;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                alreadySupported = true;
                break;
            }
        }
        if (!alreadySupported) {
            supportedTokens.push(token);
        }
    }

    /**
     * @notice Get supported tokens count
     */
    function getSupportedTokensCount() external view returns (uint256) {
        return supportedTokens.length;
    }

    /**
     * @notice Get supported token by index
     */
    function getSupportedToken(uint256 index) external view returns (address) {
        return supportedTokens[index];
    }

    // Receive native tokens
    receive() external payable {}
}
