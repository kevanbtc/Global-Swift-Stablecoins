// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title KYCRegistry
 * @notice Minimal, on-chain KYC attestation directory for gating flows.
 * - Admin can approve/revoke parties and set metadata (jurisdiction, riskTier).
 */
contract KYCRegistry {
    address public admin;

    struct KYCRecord {
        bool approved;
        bytes32 jurisdiction;   // e.g., keccak256("US-CA"), "AE-DIFC"
        bytes32 riskTier;       // e.g., keccak256("LOW"|"MED"|"HIGH")
        uint64 updatedAt;
    }

    mapping(address => KYCRecord) public records;

    event AdminTransferred(address indexed from, address indexed to);
    event KYCSet(address indexed party, bool approved, bytes32 jurisdiction, bytes32 riskTier);

    modifier onlyAdmin() { require(msg.sender == admin, "KYC: not admin"); _; }

    constructor(address _admin) { require(_admin != address(0), "KYC: admin 0"); admin = _admin; }

    function transferAdmin(address to) external onlyAdmin { require(to != address(0), "KYC: 0"); emit AdminTransferred(admin, to); admin = to; }

    function set(address party, bool approved, bytes32 jurisdiction, bytes32 riskTier) external onlyAdmin {
        records[party] = KYCRecord({approved: approved, jurisdiction: jurisdiction, riskTier: riskTier, updatedAt: uint64(block.timestamp)});
        emit KYCSet(party, approved, jurisdiction, riskTier);
    }
}
