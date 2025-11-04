// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract StableRoles is AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant CASHIER_ROLE = keccak256("CASHIER_ROLE");
    bytes32 public constant GUARD_ROLE   = keccak256("GUARD_ROLE");

    function __stableRoles_init(address admin) internal onlyInitializing {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }
}
