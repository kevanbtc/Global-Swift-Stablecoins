// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";

/// @title DisclosureRegistry
/// @notice Minimal disclosures/filings registry: map (issuer/instrument, docType) => content hash (e.g., IPFS CID)
///         Writers: ADMIN or AUDITOR. Readers: public. Useful for custody attestations, holdings, policies, prospectus, etc.
contract DisclosureRegistry is AccessControl, Pausable {
    struct Doc {
        string  uri;     // e.g., ipfs://CID or https://...
        uint64  asOf;    // document as-of timestamp
        address signer;  // who wrote it
    }

    // composite key = keccak256(abi.encode(issuerOrVault, instrumentOrCategory, docType))
    mapping(bytes32 => Doc) public docOf;

    event DisclosureSet(bytes32 indexed key, string uri, uint64 asOf, address indexed by);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PolicyRoles.ROLE_ADMIN, admin);
        _grantRole(PolicyRoles.ROLE_AUDITOR, admin);
    }

    // Convenience getters for external systems/tests
    function ROLE_ADMIN_ID() public pure returns (bytes32) { return PolicyRoles.ROLE_ADMIN; }
    function ROLE_AUDITOR_ID() public pure returns (bytes32) { return PolicyRoles.ROLE_AUDITOR; }

    function keyOf(address issuerOrVault, bytes32 instrumentOrCategory, bytes32 docType) public pure returns (bytes32) {
        return keccak256(abi.encode(issuerOrVault, instrumentOrCategory, docType));
    }

    function set(address issuerOrVault, bytes32 instrumentOrCategory, bytes32 docType, string calldata uri, uint64 asOf) public whenNotPaused
    {
        // Allow either ADMIN or AUDITOR to publish disclosures
        require(
            hasRole(PolicyRoles.ROLE_ADMIN, msg.sender) || hasRole(PolicyRoles.ROLE_AUDITOR, msg.sender),
            "not authorized"
        );
        bytes32 k = keyOf(issuerOrVault, instrumentOrCategory, docType);
        docOf[k] = Doc({uri: uri, asOf: asOf, signer: msg.sender});
        emit DisclosureSet(k, uri, asOf, msg.sender);
    }

    function get(bytes32 key) public view returns (string memory uri, uint64 asOf, address signer) {
        Doc memory d = docOf[key];
        return (d.uri, d.asOf, d.signer);
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
