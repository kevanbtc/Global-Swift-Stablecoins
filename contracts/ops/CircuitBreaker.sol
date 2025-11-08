// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IPorAggregator { function get(bytes32 reserveId) external view returns (bool ok, uint64 asOf, address signer); }
interface INavOracleRouter { function get(bytes32 instrument) external view returns (uint256 navPerShare18, uint64 asOf, address signer); }

/// @title CircuitBreaker
/// @notice Halts operations if PoR is false, NAV is stale, or NAV deviates over threshold.
contract CircuitBreaker is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IPorAggregator public por;
    INavOracleRouter public nav;
    bytes32 public reserveId;
    bytes32 public instrument;

    uint64  public maxNavAge;          // seconds
    uint256 public maxNavDriftBps;     // e.g., 100 = 1%
    uint256 public referenceNav18;     // optional reference

    event ConfigSet(address por, address nav, bytes32 reserveId, bytes32 instrument);
    event ThresholdsSet(uint64 maxAge, uint256 maxDriftBps, uint256 refNav);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function setConfig(address por_, address nav_, bytes32 reserveId_, bytes32 instrument_) public onlyRole(ADMIN_ROLE) {
        por = IPorAggregator(por_); nav = INavOracleRouter(nav_);
        reserveId = reserveId_; instrument = instrument_;
        emit ConfigSet(por_, nav_, reserveId_, instrument_);
    }

    function setThresholds(uint64 maxAge, uint256 maxDriftBps, uint256 refNav18) public onlyRole(ADMIN_ROLE) {
        maxNavAge = maxAge; maxNavDriftBps = maxDriftBps; referenceNav18 = refNav18;
        emit ThresholdsSet(maxAge, maxDriftBps, refNav18);
    }

    function isHalted() public view returns (bool) {
        if (address(por) != address(0)) {
            (bool ok,,) = por.get(reserveId);
            if (!ok) return true;
        }
        if (address(nav) != address(0)) {
            (uint256 nav18, uint64 asOf,) = nav.get(instrument);
            if (maxNavAge > 0 && block.timestamp > asOf + maxNavAge) return true;
            if (referenceNav18 > 0 && maxNavDriftBps > 0) {
                uint256 diff = nav18 > referenceNav18 ? nav18 - referenceNav18 : referenceNav18 - nav18;
                if (diff * 10_000 > referenceNav18 * maxNavDriftBps) return true;
            }
        }
        return false;
    }
}
