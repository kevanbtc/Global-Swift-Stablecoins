// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title ComplianceRegistryUpgradeable
/// @notice Stores jurisdictional/policy flags and investor profiles for transfer gating.
contract ComplianceRegistryUpgradeable is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    struct Policy {
        bool allowUS;
        bool allowEU;
        bool allowSG;
        bool allowUK;
        bool regD506c;
        bool regS;
        bool micaART;   // Asset-Referenced Token
        bool micaEMT;   // E-Money Token
        bool proOnly;   // Professional/Accredited only
        bool travelRuleRequired;
    }

    struct Profile {
        bool kyc;         // passed KYC
        bool accredited;  // meets professional investor criteria
        uint64 kycAsOf;   // unix seconds
        uint64 kycExpiry; // unix seconds
        bytes2 isoCountry; // e.g., "US","SG"
        bool frozen;      // administrative freeze
    }

    mapping(bytes32 => Policy) public policies;      // policyId => Policy
    mapping(address => Profile) public profiles;     // user => Profile
    mapping(address => bool) public allowlist;       // optional direct allow

    event PolicySet(bytes32 indexed policyId, Policy policy);
    event ProfileSet(address indexed user, Profile profile);
    event AllowlistSet(address indexed user, bool allowed);

    function initialize(address admin) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function _authorizeUpgrade(address newImpl) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setPolicy(bytes32 id, Policy calldata p) public onlyRole(ADMIN_ROLE) {
        policies[id] = p;
        emit PolicySet(id, p);
    }

    function setProfile(address user, Profile calldata prof) public onlyRole(ATTESTOR_ROLE) {
        profiles[user] = prof;
        emit ProfileSet(user, prof);
    }

    function setAllowlist(address user, bool ok) public onlyRole(ADMIN_ROLE) {
        allowlist[user] = ok;
        emit AllowlistSet(user, ok);
    }

    function canHold(address user, bytes32 policyId) public view returns (bool) {
        // Allowlist override
        if (allowlist[user]) return true;

        Policy memory p = policies[policyId];
        Profile memory u = profiles[user];

        if (u.frozen || !u.kyc) return false;
        if (u.kycExpiry != 0 && block.timestamp > u.kycExpiry) return false;

        // Jurisdictional flags (very simplified — extend as needed)
        if (u.isoCountry == "US") { if (!p.allowUS) return false; }
        if (u.isoCountry == "GB") { if (!p.allowUK) return false; }
        if (u.isoCountry == "SG") { if (!p.allowSG) return false; }
        // Treat EU as set of member countries — omitted for brevity

        if (p.proOnly && !u.accredited) return false;

        return true;
    }
}
