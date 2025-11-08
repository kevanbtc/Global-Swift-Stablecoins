// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Types} from "../common/Types.sol";
import {IRail} from "../settlement/rails/IRail.sol";
import {ExternalRail} from "../settlement/rails/ExternalRail.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SWIFTGPIAdapter
/// @notice SR-level adapter for SWIFT Global Payments Innovation (GPI) integration.
/// Handles payment tracking, status updates, and off-chain SWIFT receipt verification.
/// Integrates with ExternalRail for SWIFT leg confirmations.
contract SWIFTGPIAdapter is Ownable, ReentrancyGuard {
    
    // SWIFT GPI tracking
    mapping(string => Types.SWIFTTracking) public gpiTracking; // UETR => tracking
    mapping(bytes32 => string) public settlementToUETR; // settlement ID => UETR
    
    // Trusted SWIFT executors (banks, FIs)
    mapping(address => bool) public trustedExecutors;
    
    // External rail for SWIFT legs
    ExternalRail public immutable externalRail;
    
    // Events
    event GPIPaymentInitiated(string indexed uetr, bytes32 indexed settlementId, address indexed initiator);
    event GPIStatusUpdated(string indexed uetr, Types.SWIFTStatus status, uint256 timestamp);
    event GPIPaymentCompleted(string indexed uetr, bytes32 indexed settlementId);
    event GPIPaymentRejected(string indexed uetr, bytes32 indexed settlementId, string reason);
    event TrustedExecutorSet(address indexed executor, bool trusted);
    
    constructor(address _externalRail) Ownable(msg.sender) {
        require(_externalRail != address(0), "SGPI: 0");
        externalRail = ExternalRail(_externalRail);
    }
    
    /// @notice Set trusted SWIFT executor (bank, FI)
    function setTrustedExecutor(address executor, bool trusted) public onlyOwner {
        trustedExecutors[executor] = trusted;
        emit TrustedExecutorSet(executor, trusted);
    }
    
    /// @notice Initiate SWIFT GPI payment
    /// @param uetr Unique End-to-End Transaction Reference (ISO 20022)
    /// @param settlementId On-chain settlement ID
    function initiateGPIPayment(
        string calldata uetr,
        bytes32 settlementId
    ) public nonReentrant {
        require(bytes(uetr).length > 0, "SGPI: Empty UETR");
        require(gpiTracking[uetr].timestamp == 0, "SGPI: UETR exists");
        
        gpiTracking[uetr] = Types.SWIFTTracking({
            uetr: uetr,
            status: Types.SWIFTStatus.PENDING,
            timestamp: block.timestamp
        });
        
        settlementToUETR[settlementId] = uetr;
        
        emit GPIPaymentInitiated(uetr, settlementId, msg.sender);
    }
    
    /// @notice Update SWIFT GPI payment status (called by trusted executor)
    /// @param uetr Unique End-to-End Transaction Reference
    /// @param status New status (ACCEPTED, REJECTED, COMPLETED)
    function updateGPIStatus(
        string calldata uetr,
        Types.SWIFTStatus status
    ) public nonReentrant {
        require(trustedExecutors[msg.sender], "SGPI: Not trusted");
        require(gpiTracking[uetr].timestamp > 0, "SGPI: UETR not found");
        require(status != Types.SWIFTStatus.PENDING, "SGPI: Invalid status");
        
        gpiTracking[uetr].status = status;
        gpiTracking[uetr].timestamp = block.timestamp;
        
        emit GPIStatusUpdated(uetr, status, block.timestamp);
        
        // If completed, mark external rail as released
        if (status == Types.SWIFTStatus.COMPLETED) {
            bytes32 settlementId = keccak256(abi.encodePacked(uetr));
            emit GPIPaymentCompleted(uetr, settlementId);
        }
    }
    
    /// @notice Complete SWIFT GPI payment and mark external rail as released
    /// @param uetr Unique End-to-End Transaction Reference
    /// @param settlementId On-chain settlement ID
    /// @param receiptHash Hash of off-chain SWIFT receipt
    function completeGPIPayment(
        string calldata uetr,
        bytes32 settlementId,
        bytes32 receiptHash
    ) public nonReentrant {
        require(trustedExecutors[msg.sender], "SGPI: Not trusted");
        require(gpiTracking[uetr].status == Types.SWIFTStatus.ACCEPTED, "SGPI: Not accepted");
        
        // Update status to completed
        gpiTracking[uetr].status = Types.SWIFTStatus.COMPLETED;
        gpiTracking[uetr].timestamp = block.timestamp;
        
        // Mark external rail as released (SWIFT leg confirmed)
        // Create dummy transfer for ExternalRail compatibility
        IRail.Transfer memory dummyTransfer = IRail.Transfer({
            asset: address(0),
            from: address(0),
            to: address(0),
            amount: 0,
            metadata: abi.encode(receiptHash)
        });
        externalRail.markReleased(settlementId, dummyTransfer);
        
        emit GPIPaymentCompleted(uetr, settlementId);
    }
    
    /// @notice Reject SWIFT GPI payment and mark external rail as refunded
    /// @param uetr Unique End-to-End Transaction Reference
    /// @param settlementId On-chain settlement ID
    /// @param reason Rejection reason
    function rejectGPIPayment(
        string calldata uetr,
        bytes32 settlementId,
        string calldata reason
    ) public nonReentrant {
        require(trustedExecutors[msg.sender], "SGPI: Not trusted");
        require(gpiTracking[uetr].timestamp > 0, "SGPI: UETR not found");
        
        // Update status to rejected
        gpiTracking[uetr].status = Types.SWIFTStatus.REJECTED;
        gpiTracking[uetr].timestamp = block.timestamp;
        
        // Mark external rail as refunded (SWIFT leg failed)
        // Create dummy transfer for ExternalRail compatibility
        IRail.Transfer memory dummyTransfer = IRail.Transfer({
            asset: address(0),
            from: address(0),
            to: address(0),
            amount: 0,
            metadata: ""
        });
        externalRail.markRefunded(settlementId, dummyTransfer);
        
        emit GPIPaymentRejected(uetr, settlementId, reason);
    }
    
    /// @notice Get SWIFT GPI tracking info
    function getGPITracking(string calldata uetr) public view returns (Types.SWIFTTracking memory) {
        return gpiTracking[uetr];
    }
    
    /// @notice Get UETR for settlement ID
    function getUETRForSettlement(bytes32 settlementId) public view returns (string memory) {
        return settlementToUETR[settlementId];
    }
}
