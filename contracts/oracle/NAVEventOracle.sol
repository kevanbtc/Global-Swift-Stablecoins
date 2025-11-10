// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title NAVEventOracle
 * @notice Event-sourced positions ledger for NAV calc with adapter-based pricing.
 *         Supports ETF fallback (e.g., SGOV/SHV) via Chainlink-style aggregators.
 */
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IPriceAdapter {
    /// @return price 1e18 (settlement token units per 1 unit of asset)
    function price1e18(bytes32 assetId) external view returns (uint256 price, uint64 ts);
}

interface IAggregatorV3 {
  function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80);
  function decimals() external view returns (uint8);
}

contract NAVEventOracle is AccessControl {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant UPDATER_ROLE  = keccak256("UPDATER_ROLE");

    struct Position { bytes32 assetId; int256 qty; address adapter; }
    mapping(bytes32 => Position) public positions;  // posId => Position
    bytes32[] public ids;

    address public etfFallback; // Chainlink Aggregator (price 1e8 or other)
    uint8   public etfDecimals; // cached

    event PositionSet(bytes32 indexed id, bytes32 assetId, int256 qty, address adapter);
    event PositionDelta(bytes32 indexed id, int256 delta);
    event FallbackSet(address agg, uint8 decimals);

    constructor(address admin, address governor) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
    }

    function setFallback(address agg) public onlyRole(GOVERNOR_ROLE) {
        etfFallback = agg;
        etfDecimals = IAggregatorV3(agg).decimals();
        emit FallbackSet(agg, etfDecimals);
    }

    function setPosition(bytes32 id, bytes32 assetId, int256 qty, address adapter) public onlyRole(UPDATER_ROLE)
    {
        if (positions[id].assetId == 0) ids.push(id);
        positions[id] = Position({assetId: assetId, qty: qty, adapter: adapter});
        emit PositionSet(id, assetId, qty, adapter);
    }

    function applyDelta(bytes32 id, int256 delta) public onlyRole(UPDATER_ROLE) {
        Position storage p = positions[id];
        require(p.assetId != 0, "pos");
        p.qty += delta;
        emit PositionDelta(id, delta);
    }

    function nav1e18() public view returns (uint256 nav, uint64 asOf) {
        uint64 minTs = type(uint64).max;
        for (uint256 i = 0; i < ids.length; i++) {
            Position memory p = positions[ids[i]];
            (uint256 px, uint64 ts) = IPriceAdapter(p.adapter).price1e18(p.assetId);
            int256 contrib = (int256(px) * p.qty) / int256(1e18);
            if (contrib >= 0) nav += uint256(contrib);
            else nav -= uint256(-contrib);
            if (ts < minTs) minTs = ts;
        }
        if (nav == 0 && etfFallback != address(0)) {
            (,int256 ans,,uint256 updated,) = IAggregatorV3(etfFallback).latestRoundData();
            uint256 px = uint256(ans);
            if (etfDecimals < 18) px *= 10 ** (18 - etfDecimals);
            else if (etfDecimals > 18) px /= 10 ** (etfDecimals - 18);
            nav = px; // interpret 1 unit; caller can scale
            minTs = uint64(updated);
        }
        asOf = minTs == type(uint64).max ? uint64(block.timestamp) : minTs;
    }
}
