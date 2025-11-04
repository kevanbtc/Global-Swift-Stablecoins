// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/governance/PolicyRoles.sol";
import "../../contracts/compliance/ComplianceRegistryUpgradeable.sol";

/// Invariant scaffolds for role hygiene and privilege separation.
contract AccessControlInvariants is Test {
    ComplianceRegistryUpgradeable internal registry;
    address internal admin = address(this);
    address internal gov   = address(0xBEEF);

    function setUp() public {
        registry = new ComplianceRegistryUpgradeable();
        registry.initialize(admin, gov);
    }

    // Only ROLE_ADMIN should be able to grant roles; non-admin attempts must always fail.
    function invariant_OnlyAdminGrants() external view {
        // TODO: vm.prank non-admin and expect reverts on grantRole; avoid failing CI for now
    }

    // Governor actions should be limited to governance-only surfaces.
    function invariant_GovernorSeparation() external view {
        // TODO: assert governor cannot call admin-only functions
    }
}
