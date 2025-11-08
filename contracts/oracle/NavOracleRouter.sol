// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";

/// @title NavOracleRouter
/// @notice Stores per-instrument NAV per share (scaled 1e18) with timestamps. Writers must hold ROLE_ORACLE.
contract NavOracleRouter is AccessControl, Pausable {
    struct Nav {
        uint256 navPerShare18; // e.g., $1.000123 in 1e18
        uint64  asOf;          // unix seconds of price/NAV time
        address signer;        // who last set the NAV
    }

    // instrument key => latest NAV
    mapping(bytes32 => Nav) public navOf;

    event NavSet(bytes32 indexed instrument, uint256 navPerShare18, uint64 asOf, address indexed by);

    constructor(address admin, address oracle) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        if (oracle != address(0)) _grantRole(PolicyRoles.ROLE_ORACLE, oracle);
    }

    function set(bytes32 instrument, uint256 navPerShare18, uint64 asOf) public onlyRole(PolicyRoles.ROLE_ORACLE)
        whenNotPaused
    {
        navOf[instrument] = Nav({navPerShare18: navPerShare18, asOf: asOf, signer: msg.sender});
        emit NavSet(instrument, navPerShare18, asOf, msg.sender);
    }

    function get(bytes32 instrument) public view returns (uint256 navPerShare18, uint64 asOf, address signer) {
        Nav memory n = navOf[instrument];
        return (n.navPerShare18, n.asOf, n.signer);
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
