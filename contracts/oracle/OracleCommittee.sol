// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Roles} from "../common/Roles.sol";

/**
 * @title OracleCommittee
 * @notice NAV/price quorum with staleness and min-signers.
 */
contract OracleCommittee is Initializable, UUPSUpgradeable, AccessControlUpgradeable, EIP712Upgradeable {

    struct Quote {
        bytes32 symbol;    // e.g., bytes32("TBILL_1M") or bytes32("SGOV")
        uint128 pxMinor;   // price scaled (e.g. 1e6)
        uint64  asOf;      // unix sec
        string  source;    // "fiscaldata", "ibkr", "etf_nav", "besu_oracle"
        bytes32 besuGroup; // For Besu privacy group attestation
    }

    struct Config {
        uint8 minSigners;      // M-of-N
        uint32 maxAge;         // seconds
        uint32 disputeWindow;  // optional
    }

    Config public config;
    mapping(address => bool) public signers; // ROLE: PRICE_FEED
    mapping(bytes32 => Quote) public latestBySymbol;

    event SignerSet(address indexed who, bool allowed);
    event ConfigSet(Config cfg);
    event QuotePosted(bytes32 indexed symbol, uint128 pxMinor, uint64 asOf, string source, uint8 uniqueSigners);

    bytes32 private constant TYPEHASH =
        keccak256("PriceQuote(bytes32 symbol,uint128 pxMinor,uint64 asOf,string source,bytes32 besuGroup)");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address governor, uint8 minSigners, uint32 maxAgeSec) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __EIP712_init("OracleCommittee", "1");
        _grantRole(Roles.GOVERNOR, governor);
        _grantRole(Roles.UPGRADER, governor);
        config = Config({ minSigners: minSigners, maxAge: maxAgeSec, disputeWindow: 0 });
        emit ConfigSet(config);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER) {}

    function setSigner(address who, bool allowed) external onlyRole(Roles.GOVERNOR) {
        signers[who] = allowed;
        emit SignerSet(who, allowed);
    }

    function setConfig(Config calldata cfg) external onlyRole(Roles.GOVERNOR) {
        require(cfg.minSigners >= 1 && cfg.maxAge > 0, "bad_cfg");
        config = cfg;
        emit ConfigSet(cfg);
    }

    function postAggregate(Quote calldata q, bytes[] calldata sigs) external {
        require(block.timestamp >= q.asOf && (block.timestamp - q.asOf) <= config.maxAge, "stale_quote");
        // verify unique signer quorum
        uint256 n = sigs.length;
        uint256 uniq = 0;
        address[] memory seen = new address[](n);
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(TYPEHASH, q.symbol, q.pxMinor, q.asOf, keccak256(bytes(q.source)), q.besuGroup)));
        for (uint256 i; i < n; i++) {
            address s = ECDSA.recover(digest, sigs[i]);
            if (!signers[s]) continue;
            bool dupe = false;
            for (uint256 j; j < uniq; j++) if (seen[j] == s) { dupe = true; break; }
            if (dupe) continue;
            seen[uniq++] = s;
        }
        require(uniq >= config.minSigners, "quorum_not_met");

        latestBySymbol[q.symbol] = q;
        emit QuotePosted(q.symbol, q.pxMinor, q.asOf, q.source, uint8(uniq));
    }
}
