// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @notice Stable role ids usable across registries, routers, and share classes
library RoleIds {
    bytes32 public constant GOVERNOR_ROLE   = keccak256("GOVERNOR_ROLE");
    bytes32 public constant OPERATOR_ROLE   = keccak256("OPERATOR_ROLE");
    bytes32 public constant SIGNER_ROLE     = keccak256("SIGNER_ROLE");       // off-chain KYC/KYB/Accred attest
    bytes32 public constant AP_ROLE         = keccak256("AP_ROLE");           // Authorized Participant
    bytes32 public constant CASHIER_ROLE    = keccak256("CASHIER_ROLE");      // payout ops
    bytes32 public constant AUDITOR_ROLE    = keccak256("AUDITOR_ROLE");
    bytes32 public constant READER_ROLE     = keccak256("READER_ROLE");
}
