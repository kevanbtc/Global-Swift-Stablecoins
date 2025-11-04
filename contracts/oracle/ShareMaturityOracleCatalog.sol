// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IShareMaturityOracle} from "../interfaces/IShareMaturityOracle.sol";

/// @title ShareMaturityOracleCatalog
/// @notice Registry of instrument lots with maturities and weights (assets).
///         Computes weighted average remaining days (floor at zero).
contract ShareMaturityOracleCatalog is IShareMaturityOracle, AccessControl {
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant WRITER = keccak256("WRITER");

    struct LotInfo {
        uint64 maturity; // unix seconds
        uint128 weight;  // asset units (e.g., face/NAV units)
    }

    // instrument => lots
    mapping(address => LotInfo[]) internal _lots;

    event LotsSet(address indexed instrument, uint256 lotCount, uint64 asOf);
    event LotPushed(address indexed instrument, uint64 maturity, uint128 weight);
    event Cleared(address indexed instrument);

    constructor(address governor) {
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(ADMIN, governor);
        _grantRole(WRITER, governor);
    }

    function clear(address instrument) external onlyRole(ADMIN) {
        delete _lots[instrument];
        emit Cleared(instrument);
    }

    function setLots(address instrument, LotInfo[] calldata lotInfos) external onlyRole(WRITER) {
        delete _lots[instrument];
        for (uint256 i; i < lotInfos.length; ++i) {
            require(lotInfos[i].maturity > 0 && lotInfos[i].weight > 0, "bad_lot");
            _lots[instrument].push(lotInfos[i]);
        }
        emit LotsSet(instrument, lotInfos.length, uint64(block.timestamp));
    }

    function pushLot(address instrument, uint64 maturity, uint128 weight) external onlyRole(WRITER) {
        require(maturity > 0 && weight > 0, "bad_lot");
        _lots[instrument].push(LotInfo(maturity, weight));
        emit LotPushed(instrument, maturity, weight);
    }

    function lots(address instrument) external view returns (LotInfo[] memory) {
        return _lots[instrument];
    }

    /// @inheritdoc IShareMaturityOracle
    function daysToMaturity(address instrument) external view returns (uint16) {
        LotInfo[] memory L = _lots[instrument];
        if (L.length == 0) return 0;

        uint256 nowTs = block.timestamp;
        uint256 wsum;
        uint256 acc;
        for (uint256 i; i < L.length; ++i) {
            uint256 rem = (L[i].maturity > nowTs) ? (L[i].maturity - nowTs) : 0;
            // convert seconds → days (rounded down)
            uint256 daysRem = rem / 1 days;
            acc += uint256(L[i].weight) * daysRem;
            wsum += L[i].weight;
        }
        if (wsum == 0) return 0;
        uint256 wavg = acc / wsum;
        if (wavg > type(uint16).max) return type(uint16).max;
        return uint16(wavg);
    }
}
