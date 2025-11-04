// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PolicyRoles
/// @notice Canonical role IDs for access control across the suite
library PolicyRoles {
    bytes32 public constant ROLE_ADMIN            = keccak256("ADMIN");
    bytes32 public constant ROLE_GUARDIAN         = keccak256("GUARDIAN");       // circuit breaker
    bytes32 public constant ROLE_COMPLIANCE       = keccak256("COMPLIANCE");     // KYC/AML attestors & list mgmt
    bytes32 public constant ROLE_ISSUER           = keccak256("ISSUER");         // mint RWA / stablecoin
    bytes32 public constant ROLE_TREASURER        = keccak256("TREASURER");      // move reserves, rebalance
    bytes32 public constant ROLE_ORACLE           = keccak256("ORACLE");         // PoR & market data pushers
    bytes32 public constant ROLE_AUDITOR          = keccak256("AUDITOR");        // read privileged proofs
    bytes32 public constant ROLE_UPGRADER         = keccak256("UPGRADER");       // UUPS upgrades
}
