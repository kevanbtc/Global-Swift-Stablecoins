// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IRail} from "../settlement/rails/IRail.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SWIFTSharedLedgerRail
/// @notice SR-level rail for SWIFT shared ledger integration with Besu privacy groups.
/// Handles prepare/release for SWIFT shared ledger legs with trusted executor pattern.
contract SWIFTSharedLedgerRail is IRail, Ownable, ReentrancyGuard {
    
    // Besu privacy groups
    mapping(bytes32 => bool) public activePrivacyGroups;
    
    // Trusted executors (banks, FIs)
    mapping(address => bool) public trustedExecutors;
    
    // Transfer tracking
    mapping(bytes32 => Transfer) public transfers;
    mapping(bytes32 => Status) public transferStatus;
    mapping(bytes32 => bytes32) public receiptHashes;
    
    // Events
    event PrivacyGroupActivated(bytes32 indexed groupId);
    event TrustedExecutorSet(address indexed executor, bool trusted);
    event ReceiptPosted(bytes32 indexed transferId, bytes32 receiptHash);
    
    constructor() Ownable(msg.sender) {}
    
    /// @notice Activate Besu privacy group
    function activatePrivacyGroup(bytes32 groupId) public onlyOwner {
        activePrivacyGroups[groupId] = true;
        emit PrivacyGroupActivated(groupId);
    }
    
    /// @notice Set trusted executor
    function setTrustedExecutor(address executor, bool trusted) public onlyOwner {
        trustedExecutors[executor] = trusted;
        emit TrustedExecutorSet(executor, trusted);
    }
    
    /// @notice Returns the rail kind
    function kind() public pure override returns (Kind) {
        return Kind.EXTERNAL;
    }
    
    /// @notice Generate transfer ID
    function transferId(Transfer calldata t) public pure override returns (bytes32) {
        return keccak256(abi.encode(t.asset, t.from, t.to, t.amount, t.metadata));
    }
    
    /// @notice Prepare SWIFT shared ledger transfer
    function prepare(Transfer calldata xfer) public payable override nonReentrant {
        bytes32 id = keccak256(abi.encode(xfer.asset, xfer.from, xfer.to, xfer.amount, xfer.metadata));
        require(transferStatus[id] == Status.NONE, "SSL: Already prepared");
        
        // Decode privacy group from metadata
        bytes32 privacyGroup;
        if (xfer.metadata.length >= 32) {
            privacyGroup = abi.decode(xfer.metadata, (bytes32));
            if (privacyGroup != bytes32(0)) {
                require(activePrivacyGroups[privacyGroup], "SSL: Invalid privacy group");
            }
        }
        
        transfers[id] = xfer;
        transferStatus[id] = Status.PREPARED;
        emit RailPrepared(id, xfer.from, xfer.to, xfer.asset, xfer.amount);
    }
    
    /// @notice Release transfer after receipt verification
    function release(bytes32 id, Transfer calldata t) public override nonReentrant {
        require(trustedExecutors[msg.sender], "SSL: Not trusted executor");
        require(transferStatus[id] == Status.PREPARED, "SSL: Not prepared");
        
        Transfer memory xfer = transfers[id];
        
        // Store receipt hash from metadata
        if (t.metadata.length >= 32) {
            bytes32 receiptHash = abi.decode(t.metadata, (bytes32));
            receiptHashes[id] = receiptHash;
            emit ReceiptPosted(id, receiptHash);
        }
        
        transferStatus[id] = Status.RELEASED;
        emit RailReleased(id, xfer.to, xfer.asset, xfer.amount);
    }
    
    /// @notice Refund transfer
    function refund(bytes32 id, Transfer calldata t) public override nonReentrant {
        require(trustedExecutors[msg.sender], "SSL: Not trusted executor");
        require(transferStatus[id] == Status.PREPARED, "SSL: Not prepared");
        
        Transfer memory xfer = transfers[id];
        
        transferStatus[id] = Status.REFUNDED;
        emit RailRefunded(id, xfer.from, xfer.asset, xfer.amount);
    }
    
    /// @notice Get transfer status
    function status(bytes32 id) public view override returns (Status) {
        return transferStatus[id];
    }
}
