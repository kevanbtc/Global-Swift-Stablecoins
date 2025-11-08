// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title ReserveProofRegistry (UUPS, role-gated, EIP-712 attested)
 * @notice Anchors reserve attestations for stablecoins/RWAs: assets, liabilities, time window, and IPFS CID.
 *         - Upgrade-safe via UUPS
 *         - Operational controls: pause/unpause
 *         - Roles: ADMIN, GOVERNOR (upgrades), REPORTER (submits), AUDITOR (signs)
 *         - EIP-712 typed attestation; on-chain signature verification
 *         - Latest-per-reserve read with full struct + digest + block/time metadata
 *
 * @dev Designed for production deployments and auditability. Emits fine-grained events for off-chain indexing.
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ReserveProofRegistry is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    // --------------------------
    // Roles
    // --------------------------
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE"); // upgrades + parameters + pause
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE"); // may submit a signed attestation
    bytes32 public constant AUDITOR_ROLE  = keccak256("AUDITOR_ROLE");  // permitted as attestation signer

    // --------------------------
    // EIP-712
    // --------------------------
    // ReserveAttestation(bytes32 reserveId,address auditor,uint64 start,uint64 end,uint64 validUntil,uint256 totalAssets,uint256 totalLiabilities,bytes32 cid,uint64 nonce)
    bytes32 public constant ATTESTATION_TYPEHASH = keccak256(
        "ReserveAttestation(bytes32 reserveId,address auditor,uint64 start,uint64 end,uint64 validUntil,uint256 totalAssets,uint256 totalLiabilities,bytes32 cid,uint64 nonce)"
    );

    string private constant _NAME    = "ReserveProofRegistry";
    string private constant _VERSION = "1";

    // --------------------------
    // Data structures
    // --------------------------
    struct ReserveAttestation {
        bytes32  reserveId;        // e.g., keccak256("USDC_RESERVE_US_TBILLS")
        address  auditor;          // address with AUDITOR_ROLE who signed the EIP-712 payload
        uint64   start;            // inclusive unix seconds
        uint64   end;             // inclusive unix seconds
        uint64   validUntil;       // timestamp after which attestation is stale
        uint256  totalAssets;      // base units (e.g., cents or 6/18 decimals, off-chain documented)
        uint256  totalLiabilities; // base units
        bytes32  cid;             // IPFS CIDv1 digest (32 bytes; store multihash digest)
        uint64   nonce;           // strictly increasing per-reserve (anti-replay)
    }

    struct StoredAttestation {
        // mirrored fields for easy reads
        address  auditor;
        uint64   start;
        uint64   end;
        uint64   validUntil;
        uint64   nonce;
        uint256  totalAssets;
        uint256  totalLiabilities;
        bytes32  cid;
        // metadata
        bytes32  digest;           // EIP-712 digest
        uint64   storedAt;         // block timestamp
        uint64   storedAtBlock;    // block.number (downcast OK)
    }

    // Latest attestation per reserve
    mapping(bytes32 => StoredAttestation) private _latest;

    // last accepted nonce per reserve
    mapping(bytes32 => uint64) public lastNonce;

    // Optional auditor freeze per reserve (to pin a specific auditor)
    mapping(bytes32 => address) public pinnedAuditor; // 0 = any AUDITOR_ROLE; else must match

    // --------------------------
    // Events
    // --------------------------
    event AttestationSubmitted(
        bytes32 indexed reserveId,
        bytes32 digest,
        address indexed auditor,
        uint64 start,
        uint64 end,
        uint64 validUntil,
        uint256 totalAssets,
        uint256 totalLiabilities,
        bytes32 cid,
        uint64 nonce
    );

    event AuditorPinned(bytes32 indexed reserveId, address indexed auditor);
    event AuditorUnpinned(bytes32 indexed reserveId);
    event RegistryPaused(address indexed by);
    event RegistryUnpaused(address indexed by);

    // --------------------------
    // Init / Upgrade
    // --------------------------
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address governor) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __EIP712_init(_NAME, _VERSION);

        // roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
    }

    function _authorizeUpgrade(address newImpl) internal override onlyRole(GOVERNOR_ROLE) {}

    // --------------------------
    // Admin / Ops
    // --------------------------
    function pause() public onlyRole(GOVERNOR_ROLE) {
        _pause();
        emit RegistryPaused(msg.sender);
    }

    function unpause() public onlyRole(GOVERNOR_ROLE) {
        _unpause();
        emit RegistryUnpaused(msg.sender);
    }

    /// @notice pin a specific auditor address for a given reserveId (optional stronger control)
    function pinAuditor(bytes32 reserveId, address auditor) public onlyRole(GOVERNOR_ROLE) {
        require(auditor != address(0), "bad auditor");
        pinnedAuditor[reserveId] = auditor;
        emit AuditorPinned(reserveId, auditor);
    }

    function unpinAuditor(bytes32 reserveId) public onlyRole(GOVERNOR_ROLE) {
        delete pinnedAuditor[reserveId];
        emit AuditorUnpinned(reserveId);
    }

    // --------------------------
    // Submit (primary entry)
    // --------------------------
    /**
     * @notice Submit a signed reserve attestation. Caller must hold REPORTER_ROLE.
     *         The signature must come from an account with AUDITOR_ROLE (and, if pinned, equal pinnedAuditor[reserveId]).
     */
    function submitReserveAttestation(ReserveAttestation calldata att, bytes calldata signature) public nonReentrant
        whenNotPaused
        onlyRole(REPORTER_ROLE)
    {
        _validateAttestation(att);

        // EIP-712 digest creation
        bytes32 structHash = keccak256(
            abi.encode(
                ATTESTATION_TYPEHASH,
                att.reserveId,
                att.auditor,
                att.start,
                att.end,
                att.validUntil,
                att.totalAssets,
                att.totalLiabilities,
                att.cid,
                att.nonce
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        // Recover signer and validate
    address signer = ECDSA.recover(digest, signature);
        require(signer == att.auditor, "signer != auditor");
        require(hasRole(AUDITOR_ROLE, signer), "auditor not allowed");

        // If a pinned auditor is set for this reserve, enforce it
        address pinned = pinnedAuditor[att.reserveId];
        if (pinned != address(0)) {
            require(signer == pinned, "auditor not pinned");
        }

        // Nonce enforcement (strictly increasing)
        uint64 last = lastNonce[att.reserveId];
        require(att.nonce == last + 1, "bad nonce");
        lastNonce[att.reserveId] = att.nonce;

        // Persist
        _latest[att.reserveId] = StoredAttestation({
            auditor: att.auditor,
            start: att.start,
            end: att.end,
            validUntil: att.validUntil,
            nonce: att.nonce,
            totalAssets: att.totalAssets,
            totalLiabilities: att.totalLiabilities,
            cid: att.cid,
            digest: digest,
            storedAt: uint64(block.timestamp),
            storedAtBlock: uint64(block.number)
        });

        emit AttestationSubmitted(
            att.reserveId,
            digest,
            att.auditor,
            att.start,
            att.end,
            att.validUntil,
            att.totalAssets,
            att.totalLiabilities,
            att.cid,
            att.nonce
        );
    }

    // --------------------------
    // Views
    // --------------------------
    function latest(bytes32 reserveId) public view returns (StoredAttestation memory) {
        return _latest[reserveId];
    }

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // --------------------------
    // Internal validation
    // --------------------------
    function _validateAttestation(ReserveAttestation calldata att) internal view {
        require(att.reserveId != bytes32(0), "reserveId=0");
        require(att.auditor != address(0), "auditor=0");
        require(att.start < att.end, "time window");
        require(att.validUntil >= block.timestamp, "stale");
        require(att.cid != bytes32(0), "cid=0");
        // assets/liabilities can be 0 (e.g., bootstrap) but typically > 0
    }
}
