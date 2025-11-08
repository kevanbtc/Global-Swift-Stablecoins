// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";

/// @title PorAggregator
/// @notice Aggregates on-chain Proof-of-Reserve statuses for reserves identified by a bytes32 key (e.g., LEI+currency).
///         Writers must hold ROLE_ORACLE. Consumers can read statuses and timestamps.
contract PorAggregator is AccessControl, Pausable {
    struct Status {
        bool ok;        // true if reserve proof is valid as-of timestamp
        uint64 asOf;    // unix seconds of last attested state
        address signer; // who last updated (oracle we trust)
    }

    // reserveId => latest status
    mapping(bytes32 => Status) public statusOf;

    event PorUpdated(bytes32 indexed reserveId, bool ok, uint64 asOf, address indexed by);

    constructor(address admin, address oracle) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        if (oracle != address(0)) _grantRole(PolicyRoles.ROLE_ORACLE, oracle);
    }

    function set(bytes32 reserveId, bool ok, uint64 asOf) public onlyRole(PolicyRoles.ROLE_ORACLE) whenNotPaused {
        statusOf[reserveId] = Status({ok: ok, asOf: asOf, signer: msg.sender});
        emit PorUpdated(reserveId, ok, asOf, msg.sender);
    }

    function get(bytes32 reserveId) public view returns (bool ok, uint64 asOf, address signer) {
        Status memory s = statusOf[reserveId];
        return (s.ok, s.asOf, s.signer);
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
