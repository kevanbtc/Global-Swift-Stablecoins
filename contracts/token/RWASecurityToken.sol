// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";
import {IComplianceRegistry} from "../interfaces/IComplianceRegistry.sol";

/// @title RWASecurityToken
/// @notice ERC20-based security token with transfer restrictions, compliance checks, and permit
contract RWASecurityToken is ERC20, AccessControl {
    IComplianceRegistry public compliance;
    bytes32 public policyPartition;  // e.g. REG_D / PRO_ONLY / etc.

    event ComplianceSet(address indexed reg);
    event PolicyPartitionSet(bytes32 partition);

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        IComplianceRegistry reg,
        bytes32 partition
    ) ERC20(name_, symbol_) {
        _grantRole(PolicyRoles.ROLE_ADMIN, admin);
        _grantRole(PolicyRoles.ROLE_ISSUER, admin);
        compliance = reg;
        policyPartition = partition;
        emit ComplianceSet(address(reg));
        emit PolicyPartitionSet(partition);
    }

    // --- Admin
    function setCompliance(IComplianceRegistry reg) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        compliance = reg; emit ComplianceSet(address(reg));
    }

    function setPolicyPartition(bytes32 partition) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        policyPartition = partition; emit PolicyPartitionSet(partition);
    }

    // --- Mint/Burn
    function mint(address to, uint256 amount) public onlyRole(PolicyRoles.ROLE_ISSUER) {
        require(compliance.isCompliant(to), "non-compliant");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyRole(PolicyRoles.ROLE_ISSUER) {
        require(compliance.isCompliant(from), "non-compliant");
        _burn(from, amount);
    }

    // --- Transfer hook
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) { require(compliance.isCompliant(from), "from blocked"); }
        if (to != address(0)) { require(compliance.isCompliant(to), "to blocked"); }
        super._update(from, to, value);
    }
}
