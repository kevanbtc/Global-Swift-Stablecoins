// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {CustomErrors} from "../common/Errors.sol";
import {RoleIds} from "./RoleIds.sol";

/// @notice Token-Based Access Control (TBAC) + jurisdiction & sanction gating + EIP-712 attestations
contract AccessRegistryUpgradeable is Initializable, UUPSUpgradeable, AccessControlUpgradeable, EIP712Upgradeable {
    // using ECDSA for bytes32; // direct call style used

    struct Status {
        bool kyc;             // individual KYC pass
        bool kyb;             // business KYB pass
        bool accredited;      // Reg D 506(c) pass flag (attested)
        bool pep;             // politically exposed person flag
        bool sanctioned;      // sanction list hit (OFAC etc.)
        uint8 riskTier;       // 0-9 internal risk scale
        uint16 countryISO;    // ISO-3166 numeric code (e.g., US=840, AE=784)
        uint64 expiresAt;     // when the KYC/KYB accreditation expires (epoch)
        bytes32 metadataCid;  // IPFS/Arweave CID hash for docs
    }

    // subject => status
    mapping(address => Status) public statusOf;
    // subject => EIP-712 nonce (replay protection)
    mapping(address => uint256) public nonces;
    // blocklist by ISO code (jurisdiction blocking)
    mapping(uint16 => bool) public isoBlocked;
    // global pause
    bool public paused;

    event StatusSet(address indexed subject, Status s);
    event StatusRevoked(address indexed subject);
    event JurisdictionBlocked(uint16 iso, bool blocked);
    event Paused(bool p);

    /// EIP-712 typed struct
    struct StatusAttestation {
        address subject;
        Status  s;
        uint256 nonce;
        uint64  issuedAt;
        uint64  expiresAt; // of the attestation itself (signature expiry)
    }

    // ---- INITIALIZER / UUPS ----
    function initialize(address admin, address governor, string memory name_) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        __EIP712_init(name_, "1");
        // Allow governor to manage operator/signer roles directly
        _setRoleAdmin(RoleIds.OPERATOR_ROLE, RoleIds.GOVERNOR_ROLE);
        _setRoleAdmin(RoleIds.SIGNER_ROLE, RoleIds.GOVERNOR_ROLE);
        _grantRole(RoleIds.GOVERNOR_ROLE, governor);
        _grantRole(RoleIds.OPERATOR_ROLE, governor);
        _grantRole(RoleIds.SIGNER_ROLE, governor);
        paused = false;
    }
    function _authorizeUpgrade(address) internal override onlyRole(RoleIds.GOVERNOR_ROLE) {}

    // Expose the EIP-712 domain for off-chain signing helpers/tests
    function DOMAIN_SEPARATOR() public view returns (bytes32) { return _domainSeparatorV4(); }

    // ---- GOVERNANCE ----
    function setPaused(bool p) public onlyRole(RoleIds.GOVERNOR_ROLE) {
        paused = p; emit Paused(p);
    }

    function setJurisdictionBlocked(uint16 iso, bool blocked) public onlyRole(RoleIds.OPERATOR_ROLE) {
        isoBlocked[iso] = blocked; emit JurisdictionBlocked(iso, blocked);
    }

    // ---- DIRECT SET/REVOKE (ops/manual) ----
    function setStatus(address subject, Status calldata s) public onlyRole(RoleIds.OPERATOR_ROLE) {
        if (subject == address(0)) revert CustomErrors.InvalidParam();
        statusOf[subject] = s; emit StatusSet(subject, s);
    }

    function revoke(address subject) public onlyRole(RoleIds.OPERATOR_ROLE) {
        delete statusOf[subject]; emit StatusRevoked(subject);
    }

    // ---- EIP-712 ATTESTATION PATH ----
    bytes32 private constant STATUS_TYPEHASH =
        keccak256(
            "StatusAttestation(address subject,(bool kyc,bool kyb,bool accredited,bool pep,bool sanctioned,uint8 riskTier,uint16 countryISO,uint64 expiresAt,bytes32 metadataCid) s,uint256 nonce,uint64 issuedAt,uint64 expiresAt)"
        );

    bytes32 private constant STATUS_STRUCTHASH =
        keccak256("Status(bool kyc,bool kyb,bool accredited,bool pep,bool sanctioned,uint8 riskTier,uint16 countryISO,uint64 expiresAt,bytes32 metadataCid)");

    function _hashStatus(Status memory s) internal pure returns (bytes32) {
        return keccak256(abi.encode(STATUS_STRUCTHASH, s.kyc, s.kyb, s.accredited, s.pep, s.sanctioned, s.riskTier, s.countryISO, s.expiresAt, s.metadataCid));
    }

    function _hashAttestation(StatusAttestation memory a) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(STATUS_TYPEHASH, a.subject, _hashStatus(a.s), a.nonce, a.issuedAt, a.expiresAt))
        );
    }

    function attestBySig(StatusAttestation calldata a, bytes calldata sig) public {
        if (paused) revert CustomErrors.Paused();
        if (a.subject == address(0)) revert CustomErrors.InvalidParam();
        if (a.expiresAt < block.timestamp) revert CustomErrors.Expired();
        if (a.nonce != nonces[a.subject]) revert CustomErrors.Replay();

    address signer = ECDSA.recover(_hashAttestation(a), sig);
        if (!hasRole(RoleIds.SIGNER_ROLE, signer)) revert CustomErrors.Signature();

        nonces[a.subject] = a.nonce + 1;
        statusOf[a.subject] = a.s;
        emit StatusSet(a.subject, a.s);
    }

    // ---- GATING HELPERS ----
    enum Gate {
        VIEW,               // read-only endpoints
        SECONDARY_MARKET,   // retail trading (KYC only)
        PRIMARY_AP,         // AP actions (KYC+Accred)
        INSTITUTION,        // KYB (entity) + risk tier check
        CASHIER             // payouts
    }

    /// @notice returns true if subject passes the gate, reverts on soft violations (sanctions/geo)
    function check(address subject, Gate gate) public view returns (bool) {
        Status memory s = statusOf[subject];

        if (s.sanctioned) revert CustomErrors.Sanctioned();
        if (isoBlocked[s.countryISO]) revert CustomErrors.JurisdictionBlocked();
        if (s.expiresAt < block.timestamp) revert CustomErrors.Expired();

        if (gate == Gate.VIEW) return true;
        if (gate == Gate.SECONDARY_MARKET) return s.kyc;
        if (gate == Gate.PRIMARY_AP) return (s.kyc && s.accredited);
        if (gate == Gate.INSTITUTION) return (s.kyb && s.riskTier <= 5);
        if (gate == Gate.CASHIER) return (s.kyc || s.kyb);
        return false;
    }
}
