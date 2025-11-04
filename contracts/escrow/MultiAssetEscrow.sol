// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../erc1400/interfaces/IERC1400.sol";

/// @title Multi-Asset Escrow for DvP/RvP Settlement
/// @notice Handles atomic settlement of security tokens and payment tokens
contract MultiAssetEscrow is ReentrancyGuard, AccessControl {
    bytes32 public constant ESCROW_ADMIN_ROLE = keccak256("ESCROW_ADMIN_ROLE");
    bytes32 public constant SETTLEMENT_OPERATOR_ROLE = keccak256("SETTLEMENT_OPERATOR_ROLE");

    struct Settlement {
        address securityToken;     // ERC-1400 security token
        address paymentToken;      // ERC-20 payment token
        address seller;           // Security token holder
        address buyer;            // Payment token holder
        uint256 securityAmount;   // Amount of security tokens
        uint256 paymentAmount;    // Amount of payment tokens
        bytes32 partition;        // Security token partition
        uint256 deadline;         // Settlement deadline
        bool isSettled;          // Settlement status
    }

    // Settlement ID => Settlement details
    mapping(bytes32 => Settlement) public settlements;

    event SettlementCreated(
        bytes32 indexed settlementId,
        address indexed securityToken,
        address indexed paymentToken,
        address seller,
        address buyer,
        uint256 securityAmount,
        uint256 paymentAmount,
        bytes32 partition,
        uint256 deadline
    );

    event SettlementExecuted(bytes32 indexed settlementId);
    event SettlementCancelled(bytes32 indexed settlementId);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ESCROW_ADMIN_ROLE, msg.sender);
    }

    function createSettlement(
        address securityToken,
        address paymentToken,
        address seller,
        address buyer,
        uint256 securityAmount,
        uint256 paymentAmount,
        bytes32 partition,
        uint256 deadline
    ) external onlyRole(SETTLEMENT_OPERATOR_ROLE) returns (bytes32) {
        require(securityToken != address(0), "Invalid security token");
        require(paymentToken != address(0), "Invalid payment token");
        require(seller != address(0), "Invalid seller");
        require(buyer != address(0), "Invalid buyer");
        require(securityAmount > 0, "Invalid security amount");
        require(paymentAmount > 0, "Invalid payment amount");
        require(deadline > block.timestamp, "Invalid deadline");

        bytes32 settlementId = keccak256(
            abi.encodePacked(
                securityToken,
                paymentToken,
                seller,
                buyer,
                securityAmount,
                paymentAmount,
                partition,
                deadline,
                block.timestamp
            )
        );

        require(settlements[settlementId].securityToken == address(0), "Settlement exists");

        settlements[settlementId] = Settlement({
            securityToken: securityToken,
            paymentToken: paymentToken,
            seller: seller,
            buyer: buyer,
            securityAmount: securityAmount,
            paymentAmount: paymentAmount,
            partition: partition,
            deadline: deadline,
            isSettled: false
        });

        emit SettlementCreated(
            settlementId,
            securityToken,
            paymentToken,
            seller,
            buyer,
            securityAmount,
            paymentAmount,
            partition,
            deadline
        );

        return settlementId;
    }

    function executeSettlement(bytes32 settlementId) external nonReentrant {
        Settlement storage settlement = settlements[settlementId];
        require(!settlement.isSettled, "Already settled");
        require(block.timestamp <= settlement.deadline, "Settlement expired");

        IERC1400 securityToken = IERC1400(settlement.securityToken);
        IERC20 paymentToken = IERC20(settlement.paymentToken);

        // Verify and execute security token transfer
        bytes1 partitionCheck;
        bytes32 memo1;
        bytes32 memo2;
        (partitionCheck, memo1, memo2) = securityToken.canTransfer(
            settlement.buyer,
            settlement.securityAmount,
            ""
        );
        require(partitionCheck == 0x51, "Security transfer not possible"); // 0x51 = transfer valid

        // Transfer payment tokens from buyer to seller
        require(
            paymentToken.transferFrom(settlement.buyer, settlement.seller, settlement.paymentAmount),
            "Payment transfer failed"
        );

        // Transfer security tokens from seller to buyer
        securityToken.operatorTransferByPartition(
            settlement.partition,
            settlement.seller,
            settlement.buyer,
            settlement.securityAmount,
            "",
            ""
        );

        settlement.isSettled = true;
        emit SettlementExecuted(settlementId);
    }

    function cancelSettlement(bytes32 settlementId) external {
        Settlement storage settlement = settlements[settlementId];
        require(!settlement.isSettled, "Already settled");
        require(
            msg.sender == settlement.seller ||
            msg.sender == settlement.buyer ||
            hasRole(ESCROW_ADMIN_ROLE, msg.sender),
            "Not authorized"
        );

        delete settlements[settlementId];
        emit SettlementCancelled(settlementId);
    }
}
