// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @dev Extend your core proxies from this contract.
 * - Role-based upgrade gate (UPGRADER_ROLE).
 * - Guardian approvals (2-of-N) prior to upgrade.
 * - Implementation allowlist to prevent surprise targets.
 */
abstract contract GuardedUUPS is UUPSUpgradeable, PausableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // implementation => allowed
    mapping(address => bool) public allowedImplementation;

    // simple guardian approval nonce -> guardian -> approved
    mapping(uint256 => mapping(address => bool)) public approvals;
    mapping(uint256 => uint256) public approvalCount;

    uint256 public currentUpgradeNonce;
    uint256 public guardianThreshold; // e.g., 2

    event ImplementationAllowed(address impl, bool allowed);
    event GuardianThresholdSet(uint256 n);
    event GuardianApproved(uint256 nonce, address guardian);
    event UpgradeExecuted(uint256 nonce, address impl);

    function __GuardedUUPS_init(address admin, uint256 threshold, address[] memory guardians) internal onlyInitializing {
        __Pausable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        guardianThreshold = threshold;
        for (uint256 i=0;i<guardians.length;i++) {
            _grantRole(GUARDIAN_ROLE, guardians[i]);
        }
        emit GuardianThresholdSet(threshold);
    }

    function setGuardianThreshold(uint256 n) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(n>0, "bad_threshold");
        guardianThreshold = n;
        emit GuardianThresholdSet(n);
    }

    function setImplementationAllowed(address impl, bool ok) public onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedImplementation[impl] = ok;
        emit ImplementationAllowed(impl, ok);
    }

    function guardianApprove(uint256 nonce) public onlyRole(GUARDIAN_ROLE) {
        require(!approvals[nonce][_msgSender()], "already");
        approvals[nonce][_msgSender()] = true;
        approvalCount[nonce] += 1;
        emit GuardianApproved(nonce, _msgSender());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) whenNotPaused {
        require(allowedImplementation[newImplementation], "impl_not_allowlisted");
        require(approvalCount[currentUpgradeNonce] >= guardianThreshold, "guardian_threshold");
        // bump nonce on success
        currentUpgradeNonce += 1;
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    uint256[43] private __gap; // storage gap for future vars
}
