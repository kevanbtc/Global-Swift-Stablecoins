// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Roles
 * @notice Canonical role identifiers shared across the system.
 * @dev Keep this small and stable for off-chain ACL mapping.
 */
library Roles {
    // Platform authority
    bytes32 public constant GOVERNOR          = keccak256("GOVERNOR");          // Owns upgrades & global params
    bytes32 public constant GUARDIAN          = keccak256("GUARDIAN");          // Emergency pause / risk locks

    // Treasury / reserves
    bytes32 public constant TREASURER         = keccak256("TREASURER");         // Books/reserve ops, rebal, settlements
    bytes32 public constant AUDITOR           = keccak256("AUDITOR");           // Can post attestations / run checks
    bytes32 public constant COMPLIANCE        = keccak256("COMPLIANCE");        // KYC/allowlists/sanctions switches

    // Feeds & oracles
    bytes32 public constant PRICE_FEED        = keccak256("PRICE_FEED");        // Price/NAV signers
    bytes32 public constant PROOF_PROVIDER    = keccak256("PROOF_PROVIDER");    // Reserve proof attestations

    // Token
    bytes32 public constant MINTER            = keccak256("MINTER");            // Stablecoin mint
    bytes32 public constant BURNER            = keccak256("BURNER");            // Stablecoin burn (redemptions)

    // System
    bytes32 public constant UPGRADER          = keccak256("UPGRADER");          // UUPS upgrade authority
}
