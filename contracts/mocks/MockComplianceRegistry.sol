// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockComplianceRegistry {
    mapping(address => bool) private _compliant;

    function setCompliant(address account, bool status) external {
        _compliant[account] = status;
    }

    function isCompliant(address account) external view returns (bool) {
        return _compliant[account];
    }
}
