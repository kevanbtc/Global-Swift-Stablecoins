// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IMidnightBridge
 * @notice Interface for Midnight network bridge interactions
 * @dev Used by MidnightSettlementAdapter to verify cross-chain transactions
 */
interface IMidnightBridge {
    /**
     * @notice Verify a Midnight network transaction
     * @param txHash Transaction hash on Midnight network
     * @param proof Cryptographic proof of transaction inclusion
     * @return bool True if transaction is valid and confirmed
     */
    function verifyTransaction(
        bytes32 txHash,
        bytes calldata proof
    ) external view returns (bool);

    /**
     * @notice Submit a cross-chain message to Midnight network
     * @param recipient Recipient address on Midnight network
     * @param payload Message payload
     * @return bytes32 Message ID
     */
    function sendMessage(
        bytes32 recipient,
        bytes calldata payload
    ) external payable returns (bytes32);

    /**
     * @notice Get Midnight network chain ID
     * @return bytes32 Midnight network identifier
     */
    function getMidnightChainId() external view returns (bytes32);

    /**
     * @notice Check if bridge is operational
     * @return bool True if bridge is active
     */
    function isOperational() external view returns (bool);

    /**
     * @notice Event emitted when message is sent to Midnight
     */
    event MessageSent(
        bytes32 indexed messageId,
        bytes32 indexed recipient,
        bytes payload,
        uint256 timestamp
    );

    /**
     * @notice Event emitted when transaction is verified
     */
    event TransactionVerified(
        bytes32 indexed txHash,
        address indexed verifier,
        uint256 timestamp
    );
}
