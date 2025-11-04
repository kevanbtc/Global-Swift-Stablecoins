// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IComplianceRegistry {
    /// @notice Returns whether an account is allowed to hold & transfer
    function isCompliant(address account) external view returns (bool);

    /// @notice Returns whether two parties can settle peer-to-peer (jurisdictional checks)
    function isPairCompliant(address from, address to) external view returns (bool);

    /// @notice Optional: country code or legal profile id for account
    function profileOf(address account) external view returns (bytes32 profileId);

    /// @notice Optional: returns true if account is sanctioned/blocked
    function isSanctioned(address account) external view returns (bool);
}
