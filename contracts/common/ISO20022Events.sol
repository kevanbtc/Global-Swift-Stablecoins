// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title ISO20022Events
 * @notice Canonical on-chain anchors for ISO 20022 semantics. These events DO NOT enforce logic;
 *         they exist for audit analytics, off-chain reconciliation, and regulator tooling.
 *
 *         Key refs:
 *           - pacs.008 (FIToFICustomerCreditTransfer)
 *           - secu.001/002 (Securities messages)
 *           - camt.xxx (Cash management)
 */
library ISO20022Events {
    /// @dev Emitted when primary subscription is completed (akin to secu.001 issuance legs)
    event SEC_Mint(
        bytes32 indexed instrumentId,
        address indexed subscriber,
        uint256 grossPaid,    // settlement token units
        uint16  feeBps,
        uint256 sharesOut,    // ERC20 units (1e18)
        bytes32 nonce,
        uint64  ts
    );

    /// @dev Emitted when redemption is settled (akin to secu.002 redemption/cash payout)
    event SEC_Redeem(
        bytes32 indexed instrumentId,
        address indexed redeemer,
        uint256 sharesIn,
        uint16  feeBps,
        uint256 netPayout,    // settlement token units
        bytes32 nonce,
        uint64  ts
    );

    /// @dev Cash leg settlement anchor (pacs.008 style)
    event PACS_008_Payment(
        address indexed payer,
        address indexed payee,
        bytes32 indexed messageId, // internal payment reference
        uint256 amount,
        address currencyToken,     // ERC20 settlement token
        uint64  valueDate,         // unix ts (T+0/T+1)
        string  debtorIban,        // optional metadata
        string  creditorIban,      // optional metadata
        string  purposeCode         // ISO purpose (e.g., "SALA","TREA","DIVI")
    );

    /// @dev Balance snapshot/statement (camt.052/053 style)
    event CAMT_Statement(
        bytes32 indexed accountId,
        int256  delta,          // signed
        uint256 newBalance,
        string  statementRef,
        uint64  ts
    );
}
