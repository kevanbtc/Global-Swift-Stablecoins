// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Roles} from "../common/Roles.sol";

/**
 * @title PolicyGuard
 * @notice Central risk/compliance guard:
 *         - freshness windows for attestations
 *         - concentration / allocation caps
 *         - jurisdiction & investor perms
 *         - emergency pause
 *
 * @dev This does NOT claim legal compliance; it provides technical rails to
 *      enforce your policy. Map your Basel/ISO/MiCA rules off-chain to these knobs.
 */
contract PolicyGuard is Initializable, UUPSUpgradeable, PausableUpgradeable, AccessControlUpgradeable {
    // asset classes
    enum AssetClass { CASH, TBILL, NOTE, BOND, ETF, MMF, RWA, OTHER, EXTERNAL_STABLECOIN }

    struct ClassLimits {
        uint16 maxBp;            // max % in basis points, e.g., 9000 = 90%
        uint16 singleIssuerBp;   // per-issuer cap
        uint32 maxTenorDays;     // upper bound tenor (0=ignore)
    }

    // op code -> freshness seconds
    mapping(bytes32 => uint256) public freshnessByOp;  // e.g., keccak256("NAV_ATTEST") => 86400
    // class -> limits
    mapping(AssetClass => ClassLimits) public limitsByClass;

    // Jurisdiction gating: op => countryCode => listed/whitelistMode
    struct JurisdictionRule {
        bool listed;
        bool whitelist;  // if true -> only listed allowed; if false -> listed are blocked
    }
    mapping(bytes32 => mapping(bytes32 => JurisdictionRule)) public jurisdiction; // op -> country -> rule

    // Investor-level toggle (optional simple KYC flag)
    mapping(address => bool) public kycApproved;

    event FreshnessSet(bytes32 indexed op, uint256 secondsValid);
    event ClassLimitsSet(AssetClass indexed cls, ClassLimits lim);
    event JurisdictionSet(bytes32 indexed op, bytes32 indexed country, bool listed, bool whitelistMode);
    event KycSet(address indexed user, bool approved);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address governor, address guardian) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(Roles.GOVERNOR, governor);
        _grantRole(Roles.GUARDIAN, guardian);
        _grantRole(Roles.UPGRADER, governor);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER) {}

    // --- admin controls ---

    function pause() public onlyRole(Roles.GUARDIAN) { _pause(); emit Paused(msg.sender); }
    function unpause() public onlyRole(Roles.GUARDIAN) { _unpause(); emit Unpaused(msg.sender); }

    function setFreshness(bytes32 op, uint256 secsValid) public onlyRole(Roles.GOVERNOR) {
        freshnessByOp[op] = secsValid;
        emit FreshnessSet(op, secsValid);
    }

    function setClassLimits(AssetClass cls, ClassLimits calldata lim) public onlyRole(Roles.GOVERNOR) {
        limitsByClass[cls] = lim;
        emit ClassLimitsSet(cls, lim);
    }

    function setJurisdiction(bytes32 op, bytes32 country, bool listed, bool whitelistMode) public onlyRole(Roles.COMPLIANCE)
    {
        jurisdiction[op][country] = JurisdictionRule({ listed: listed, whitelist: whitelistMode });
        emit JurisdictionSet(op, country, listed, whitelistMode);
    }

    function setKyc(address user, bool ok) public onlyRole(Roles.COMPLIANCE) {
        kycApproved[user] = ok;
        emit KycSet(user, ok);
    }

    // --- checks ---

    /**
     * @notice Validate operation under policy
     * @param op          operation code, e.g., keccak256("MINT"), "REDEEM", "NAV_ATTEST"
     * @param country     ISO-like country bytes32 (e.g., bytes32("US"))
     * @param attAgeSec   age of latest attestation seconds
     * @param classAllocBp total allocation in class after op
     * @param issuerAllocBp issuer concentration after op
     * @param cls         asset class for op context
     * @return ok, reasonString
     */
    function check(
        bytes32 op,
        bytes32 country,
        uint256 attAgeSec,
        uint16 classAllocBp,
        uint16 issuerAllocBp,
        AssetClass cls
    ) public view whenNotPaused returns (bool, string memory) {
        // 1) freshness
        uint256 window = freshnessByOp[op];
        if (window > 0 && attAgeSec > window) {
            return (false, "stale_attestation");
        }

        // 2) class limits
        ClassLimits memory lim = limitsByClass[cls];
        if (lim.maxBp > 0 && classAllocBp > lim.maxBp) {
            return (false, "class_limit_exceeded");
        }
        if (lim.singleIssuerBp > 0 && issuerAllocBp > lim.singleIssuerBp) {
            return (false, "issuer_limit_exceeded");
        }

        // 3) jurisdiction
        JurisdictionRule memory r = jurisdiction[op][country];
        if (r.whitelist && !r.listed) {
            return (false, "jurisdiction_not_whitelisted");
        }
        if (!r.whitelist && r.listed) {
            return (false, "jurisdiction_blacklisted");
        }

        // pass
        return (true, "");
    }
}
