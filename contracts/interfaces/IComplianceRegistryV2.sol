// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Public interface for ComplianceRegistryV2 used by gates/routers/escrows.
interface IComplianceRegistryV2 {
    /// @return tier 0..255, accredited, sanctioned, country ISO3166-1 alpha2 encoded as two bytes in uint16
    function getProfile(address user) external view returns (uint8 tier, bool accredited, bool sanctioned, uint16 countryCode2);
    function assertCompliantProfile(address user) external view;
    function assertPartitionAllowed(address user, bytes32 partition) external view;

    // Admin ops
    function setProfile(address user, uint8 tier, bool accredited, bool sanctioned, uint16 countryCode2) external;
    function setPartitionPolicy(bytes32 partition, bool enabled) external;
    function setUserPartitionOverride(address user, bytes32 partition, bool allowed) external;
}
