// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable as AC} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IPriceAdapter {
    function price1e18(bytes32 assetId) external view returns (uint256 price, uint64 ts);
}
interface IAggregatorV3 {
  function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80);
  function decimals() external view returns (uint8);
}

/**
 * @notice Event-sourced positions + adapter-based pricing w/ ETF fallback.
 */
contract NAVEventOracleUpgradeable is Initializable, AC {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant UPDATER_ROLE  = keccak256("UPDATER_ROLE");

    struct Position { bytes32 assetId; int256 qty; address adapter; }
    mapping(bytes32 => Position) public positions;
    bytes32[] public ids;

    address public etfFallback;
    uint8   public etfDecimals;

    event PositionSet(bytes32 indexed id, bytes32 assetId, int256 qty, address adapter);
    event PositionDelta(bytes32 indexed id, int256 delta);
    event FallbackSet(address agg, uint8 decimals);

    function initialize(address admin, address governor) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
    }

    function setFallback(address agg) external onlyRole(GOVERNOR_ROLE) {
        etfFallback = agg;
        etfDecimals = IAggregatorV3(agg).decimals();
        emit FallbackSet(agg, etfDecimals);
    }

    function setPosition(bytes32 id, bytes32 assetId, int256 qty, address adapter)
        external onlyRole(UPDATER_ROLE)
    {
        if (positions[id].assetId == 0) ids.push(id);
        positions[id] = Position({assetId: assetId, qty: qty, adapter: adapter});
        emit PositionSet(id, assetId, qty, adapter);
    }

    function applyDelta(bytes32 id, int256 delta) external onlyRole(UPDATER_ROLE) {
        Position storage p = positions[id];
        require(p.assetId != 0, "pos");
        p.qty += delta;
        emit PositionDelta(id, delta);
    }

    function nav1e18() external view returns (uint256 nav, uint64 asOf) {
        uint64 minTs = type(uint64).max;
        for (uint256 i = 0; i < ids.length; i++) {
            Position memory p = positions[ids[i]];
            (uint256 px, uint64 ts) = IPriceAdapter(p.adapter).price1e18(p.assetId);
            int256 contrib = (int256(px) * p.qty) / int256(1e18);
            nav = contrib >= 0 ? nav + uint256(contrib) : nav - uint256(-contrib);
            if (ts < minTs) minTs = ts;
        }
        if (nav == 0 && etfFallback != address(0)) {
            (,int256 ans,,uint256 updated,) = IAggregatorV3(etfFallback).latestRoundData();
            uint256 px = uint256(ans);
            if (etfDecimals < 18) px *= 10 ** (18 - etfDecimals);
            else if (etfDecimals > 18) px /= 10 ** (etfDecimals - 18);
            nav = px;
            minTs = uint64(updated);
        }
        asOf = minTs == type(uint64).max ? uint64(block.timestamp) : minTs;
    }
}
