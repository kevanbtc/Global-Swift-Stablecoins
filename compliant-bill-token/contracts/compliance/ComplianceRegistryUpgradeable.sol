// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ComplianceRegistryUpgradeable is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    struct Policy { bool allowUS; bool allowEU; bool allowSG; bool allowUK; bool regD506c; bool regS; bool micaART; bool micaEMT; bool proOnly; bool travelRuleRequired; }
    struct Profile { bool kyc; bool accredited; uint64 kycAsOf; uint64 kycExpiry; bytes2 isoCountry; bool frozen; }

    mapping(bytes32 => Policy) public policies; // id => policy
    mapping(address => Profile) public profiles; // user => profile
    mapping(address => bool) public allowlist;

    event PolicySet(bytes32 indexed id, Policy p);
    event ProfileSet(address indexed user, Profile prof);
    event AllowlistSet(address indexed user, bool ok);

    function initialize(address admin) public initializer {
        __AccessControl_init(); __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin); _grantRole(ADMIN_ROLE, admin);
    }
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setPolicy(bytes32 id, Policy calldata p) external onlyRole(ADMIN_ROLE) { policies[id] = p; emit PolicySet(id, p); }
    function setProfile(address user, Profile calldata prof) external onlyRole(ATTESTOR_ROLE) { profiles[user] = prof; emit ProfileSet(user, prof); }
    function setAllowlist(address user, bool ok) external onlyRole(ADMIN_ROLE) { allowlist[user] = ok; emit AllowlistSet(user, ok); }

    function canHold(address user, bytes32 policyId) external view returns (bool) {
        if (allowlist[user]) return true; Policy memory p = policies[policyId]; Profile memory u = profiles[user];
        if (u.frozen || !u.kyc) return false; if (u.kycExpiry != 0 && block.timestamp > u.kycExpiry) return false;
        if (u.isoCountry == bytes2("US")) { if (!p.allowUS) return false; }
        if (u.isoCountry == bytes2("GB")) { if (!p.allowUK) return false; }
        if (u.isoCountry == bytes2("SG")) { if (!p.allowSG) return false; }
        if (p.proOnly && !u.accredited) return false; return true;
    }
}
