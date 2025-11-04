// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReserveVault} from "../ReserveVault.sol";
import {PolicyGuard} from "../../policy/PolicyGuard.sol";

/// @title TBillInventoryAdapter
/// @notice Tracks CUSIP-based T-Bill lots and verifies signed price marks. Can sync summarized positions into ReserveManager.
contract TBillInventoryAdapter is AccessControl, EIP712 {
    bytes32 public constant ROLE_ADMIN     = keccak256("ROLE_ADMIN");
    bytes32 public constant ROLE_FEED      = keccak256("ROLE_FEED");      // allowed to submit signed marks
    bytes32 public constant ROLE_TREASURER = keccak256("ROLE_TREASURER"); // can sync to ReserveManager

    struct Lot {
        bool    active;
        bytes9  cusip;         // 9-char CUSIP packed (use bytes9 to save)
        uint64  issueDate;     // yyyy-mm-dd
        uint64  maturityDate;  // yyyy-mm-dd
        uint128 faceMinor;     // face value in minor units (e.g., cents)
        string  brokerRef;     // optional account id / clearing id
        string  meta;          // json pointer / uri (auction id, docs)
    }

    struct Mark {
        uint64  asOf;          // timestamp of mark
        uint128 pricePer100;   // price per 100 face (minor units: e.g., $99.125000 -> 99125000 if 6 decimals)
        string  source;        // "IBKR", "Bloomberg BVAL", etc.
        address signer;        // recovered signer
    }

    // id → lot / mark history
    uint256 public lastLotId;
    mapping(uint256 => Lot) public lots;
    mapping(uint256 => mapping(uint64 => Mark)) public marksByTime; // lotId => asOf => Mark
    mapping(uint256 => uint64[]) public markTimes;                   // lotId timeline

    // reference to ReserveVault + scales
    ReserveVault public reserveVault;
    uint256 public immutable USD_SCALE; // must match ReserveManager.USD_SCALE

    event LotAdded(uint256 indexed id, bytes9 cusip, uint64 issueDate, uint64 maturityDate, uint128 faceMinor, string brokerRef);
    event LotUpdated(uint256 indexed id, bool active, uint128 faceMinor, string brokerRef, string meta);
    event MarkAccepted(uint256 indexed id, uint64 asOf, uint128 pricePer100, string source, address signer);
    event SyncedToReserves(uint256 indexed positionId, uint256 totalNAV);
    event FeedSet(address indexed feed, bool allowed);
    event ReserveManagerSet(address indexed rm);

    bytes32 private constant _MARK_TYPEHASH = keccak256(
        "TBillMark(uint256 lotId,bytes9 cusip,uint64 maturityDate,uint64 asOf,uint128 pricePer100,string source)"
    );

    constructor(address admin, uint256 usdScale)
        EIP712("TBillInventoryAdapter","1")
    {
        USD_SCALE = usdScale;
        _grantRole(ROLE_ADMIN, admin);
        _grantRole(ROLE_FEED, admin);
        _grantRole(ROLE_TREASURER, admin);
    }

    // ---------- wiring ----------
    function setReserveManager(ReserveVault rm) external onlyRole(ROLE_ADMIN) {
        reserveVault = rm;
        emit ReserveManagerSet(address(rm));
    }

    function setFeed(address feed, bool allowed) external onlyRole(ROLE_ADMIN) {
        if (allowed) _grantRole(ROLE_FEED, feed);
        else _revokeRole(ROLE_FEED, feed);
        emit FeedSet(feed, allowed);
    }

    // ---------- lots ----------
    function addLot(
        bytes9 cusip,
        uint64 issueDate,
        uint64 maturityDate,
        uint128 faceMinor,
        string calldata brokerRef,
        string calldata meta
    ) external onlyRole(ROLE_TREASURER) returns (uint256 id) {
        require(maturityDate >= issueDate, "bad dates");
        id = ++lastLotId;
        lots[id] = Lot({
            active: true,
            cusip: cusip,
            issueDate: issueDate,
            maturityDate: maturityDate,
            faceMinor: faceMinor,
            brokerRef: brokerRef,
            meta: meta
        });
        emit LotAdded(id, cusip, issueDate, maturityDate, faceMinor, brokerRef);
    }

    function updateLot(
        uint256 id,
        bool active,
        uint128 faceMinor,
        string calldata brokerRef,
        string calldata meta
    ) external onlyRole(ROLE_TREASURER) {
        Lot storage L = lots[id];
        require(L.cusip != bytes9(0), "no lot");
        L.active = active;
        L.faceMinor = faceMinor;
        L.brokerRef = brokerRef;
        L.meta = meta;
        emit LotUpdated(id, active, faceMinor, brokerRef, meta);
    }

    // ---------- marks ----------
    function _hashMark(
        uint256 lotId,
        bytes9 cusip,
        uint64 maturityDate,
        uint64 asOf,
        uint128 pricePer100,
        string memory source
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            _MARK_TYPEHASH,
            lotId,
            cusip,
            maturityDate,
            asOf,
            pricePer100,
            keccak256(bytes(source))
        )));
    }

    /// @notice Accept a signed price mark for a lot.
    function submitMark(
        uint256 lotId,
        uint64 asOf,
        uint128 pricePer100,
        string calldata source,
        bytes calldata signature
    ) external returns (address signer) {
        Lot storage L = lots[lotId];
        require(L.active, "inactive lot");

        bytes32 digest = _hashMark(lotId, L.cusip, L.maturityDate, asOf, pricePer100, source);
        signer = ECDSA.recover(digest, signature);
        require(hasRole(ROLE_FEED, signer), "unauthorized feed");

        // record
        marksByTime[lotId][asOf] = Mark({
            asOf: asOf,
            pricePer100: pricePer100,
            source: source,
            signer: signer
        });
        markTimes[lotId].push(asOf);

        emit MarkAccepted(lotId, asOf, pricePer100, source, signer);
    }

    // ---------- reserve sync ----------
    /// @notice Push aggregated TBILL exposure into ReserveVault as one position (or update existing one).
    /// @dev If you prefer 1:1 CUSIP positions, loop and call ReserveVault.addPosition() yourself externally.
    function syncAllToReserve(bytes32 refKey, uint256 positionIdIfExists, uint64 asOf) external onlyRole(ROLE_TREASURER) {
        require(address(reserveVault) != address(0), "no RM");
        // Sum face * pricePer100
        uint256 totalNAV; // USD scaled
        for (uint256 i = 1; i <= lastLotId; i++) {
            Lot storage L = lots[i];
            if (!L.active) continue;
            Mark storage M = marksByTime[i][asOf];
            // require a mark at asOf to include; or choose latest fallback (omitted for determinism)
            if (M.asOf == 0) continue;

            // pricePer100 (minor scale) applied to faceMinor (minor)
            // valuation = faceMinor * pricePer100 / (100 * scale)
            // Here assume both faceMinor and pricePer100 scaled by USD_SCALE.
            // Then: value = faceMinor * pricePer100 / (100 * USD_SCALE)
            uint256 value = (uint256(L.faceMinor) * uint256(M.pricePer100)) / (100 * USD_SCALE);
            totalNAV += value;
        }

        // If position exists: update qty=totalNAV, px=USD_SCALE (1.000000)
        // Else: add a new TBILL position with qty=totalNAV, px=USD_SCALE (1.000000)
        if (positionIdIfExists == 0) {
            uint256 posId = reserveVault.addPosition(
                refKey,                                  // symbol
                refKey,                                  // issuer (reuse key)
                uint128(totalNAV),                       // qty in minor units
                uint128(USD_SCALE),                      // px = 1.000000
                PolicyGuard.AssetClass.TBILL
            );
            emit SyncedToReserves(posId, totalNAV);
        } else {
            reserveVault.updatePosition(
                positionIdIfExists,
                uint128(totalNAV),
                uint128(USD_SCALE),
                asOf
            );
            emit SyncedToReserves(positionIdIfExists, totalNAV);
        }
    }

    function _u64(uint64 x) private pure returns (string memory) {
        if (x == 0) return "0";
        uint64 y = x; uint256 len;
        while (y != 0) { len++; y/=10; }
        bytes memory b = new bytes(len);
        while (x != 0) { b[--len] = bytes1(uint8(48 + x%10)); x/=10; }
        return string(b);
    }
}
