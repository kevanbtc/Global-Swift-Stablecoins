// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AtomicCrossAssetSettlement
 * @notice Instant atomic settlement across multiple asset classes
 * @dev Supports ERC20 (stablecoins, CBDC), ERC721 (RWA), and external rails
 */
contract AtomicCrossAssetSettlement is ReentrancyGuard, Ownable {
    
    enum AssetType { ERC20, ERC721, EXTERNAL_RAIL, AGORA, RLN, FNALITY }
    
    struct Asset {
        AssetType assetType;
        address assetAddress;           // Token contract or rail address
        uint256 amountOrTokenId;        // Amount for ERC20, tokenId for ERC721
        address owner;
        bytes32 externalRef;            // For external rails (SWIFT UETR, etc.)
    }
    
    struct AtomicSettlement {
        bytes32 settlementId;
        Asset[] assetsIn;               // Assets being exchanged
        Asset[] assetsOut;              // Assets being received
        address[] participants;
        bool isCompleted;
        bool isCancelled;
        uint256 timestamp;
        uint256 expiryTime;
    }
    
    mapping(bytes32 => AtomicSettlement) public settlements;
    
    event SettlementInitiated(bytes32 indexed settlementId, address[] participants);
    event SettlementCompleted(bytes32 indexed settlementId);
    event SettlementCancelled(bytes32 indexed settlementId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Initiate atomic cross-asset settlement
     */
    function initiateAtomicSettlement(
        bytes32 settlementId,
        Asset[] memory assetsIn,
        Asset[] memory assetsOut,
        address[] memory participants,
        uint256 expiryTime
    ) external nonReentrant returns (bool) {
        require(assetsIn.length > 0 && assetsOut.length > 0, "Empty assets");
        require(participants.length >= 2, "Need at least 2 participants");
        require(expiryTime > block.timestamp, "Invalid expiry");
        
        // Store settlement
        AtomicSettlement storage settlement = settlements[settlementId];
        settlement.settlementId = settlementId;
        settlement.timestamp = block.timestamp;
        settlement.expiryTime = expiryTime;
        settlement.participants = participants;
        
        // Copy assets
        for (uint i = 0; i < assetsIn.length; i++) {
            settlement.assetsIn.push(assetsIn[i]);
        }
        for (uint i = 0; i < assetsOut.length; i++) {
            settlement.assetsOut.push(assetsOut[i]);
        }
        
        emit SettlementInitiated(settlementId, participants);
        return true;
    }
    
    /**
     * @notice Execute atomic settlement (all-or-nothing)
     */
    function executeAtomicSettlement(bytes32 settlementId) external nonReentrant onlyOwner {
        AtomicSettlement storage settlement = settlements[settlementId];
        require(!settlement.isCompleted, "Already completed");
        require(!settlement.isCancelled, "Cancelled");
        require(block.timestamp <= settlement.expiryTime, "Expired");
        
        // Execute all asset transfers atomically
        for (uint i = 0; i < settlement.assetsIn.length; i++) {
            _transferAsset(settlement.assetsIn[i], address(this));
        }
        
        for (uint i = 0; i < settlement.assetsOut.length; i++) {
            _transferAsset(settlement.assetsOut[i], settlement.assetsOut[i].owner);
        }
        
        settlement.isCompleted = true;
        emit SettlementCompleted(settlementId);
    }
    
    /**
     * @notice Cancel settlement (if expired or by participant)
     */
    function cancelSettlement(bytes32 settlementId) external {
        AtomicSettlement storage settlement = settlements[settlementId];
        require(!settlement.isCompleted, "Already completed");
        require(!settlement.isCancelled, "Already cancelled");
        
        // Allow any participant or owner to cancel if expired
        bool isParticipant = false;
        for (uint i = 0; i < settlement.participants.length; i++) {
            if (settlement.participants[i] == msg.sender) {
                isParticipant = true;
                break;
            }
        }
        
        require(
            msg.sender == owner() || isParticipant || block.timestamp > settlement.expiryTime,
            "Not authorized"
        );
        
        settlement.isCancelled = true;
        emit SettlementCancelled(settlementId);
    }
    
    /**
     * @dev Internal function to transfer assets based on type
     */
    function _transferAsset(Asset memory asset, address to) internal {
        if (asset.assetType == AssetType.ERC20) {
            IERC20(asset.assetAddress).transferFrom(asset.owner, to, asset.amountOrTokenId);
        } else if (asset.assetType == AssetType.ERC721) {
            IERC721(asset.assetAddress).transferFrom(asset.owner, to, asset.amountOrTokenId);
        }
        // External rails handled off-chain with receipts
    }
    
    /**
     * @notice Get settlement information
     */
    function getSettlement(bytes32 settlementId) external view returns (AtomicSettlement memory) {
        return settlements[settlementId];
    }
    
    /**
     * @notice Get asset count for settlement
     */
    function getAssetCount(bytes32 settlementId, bool isInput) external view returns (uint256) {
        AtomicSettlement storage settlement = settlements[settlementId];
        return isInput ? settlement.assetsIn.length : settlement.assetsOut.length;
    }
}
