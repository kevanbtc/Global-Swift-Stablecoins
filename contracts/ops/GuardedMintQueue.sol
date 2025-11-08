// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title GuardedMintQueue
/// @notice Simple T+0 / queued mint policy with per-address daily quota and global day cap.
contract GuardedMintQueue is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Limits { uint256 perAddressDaily; uint256 globalDaily; }
    Limits public limits;

    // dayKey => used
    mapping(uint256 => uint256) public globalUsed;
    // dayKey => addr => used
    mapping(uint256 => mapping(address => uint256)) public usedBy;

    event LimitsSet(uint256 perAddr, uint256 global);
    event Requested(address indexed owner, uint256 amount, bool immediate);

    constructor(address admin, uint256 perAddrDaily, uint256 globalDaily) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        limits = Limits({perAddressDaily: perAddrDaily, globalDaily: globalDaily});
        emit LimitsSet(perAddrDaily, globalDaily);
    }

    function setLimits(uint256 perAddrDaily, uint256 globalDaily) public onlyRole(ADMIN_ROLE) {
        limits = Limits({perAddressDaily: perAddrDaily, globalDaily: globalDaily});
        emit LimitsSet(perAddrDaily, globalDaily);
    }

    function _dayKey(uint256 ts) internal pure returns (uint256) { return ts / 1 days; }

    /// @notice Request a mint. Returns true if within T+0 allowance; false if it should be queued.
    function request(address owner, uint256 amount) public returns (bool immediate) {
        uint256 day = _dayKey(block.timestamp);
        Limits memory lim = limits;
        uint256 g = globalUsed[day];
        uint256 u = usedBy[day][owner];

        // compute stepwise to avoid any potential short-circuit quirks
        immediate = false;
        if (u + amount <= lim.perAddressDaily) {
            if (g + amount <= lim.globalDaily) {
                immediate = true;
            }
        }
        emit Requested(owner, amount, immediate);

        if (immediate) {
            usedBy[day][owner] = u + amount;
            globalUsed[day] = g + amount;
        }
    }

    /// @notice View helper for tests and monitoring: computes immediacy without modifying state.
    function preview(address owner, uint256 amount) public view returns (
        uint256 u, uint256 g, uint256 perAddr, uint256 glob, uint8 immediateInt
    ) {
        uint256 day = _dayKey(block.timestamp);
        Limits memory lim = limits;
        g = globalUsed[day];
        u = usedBy[day][owner];
        perAddr = lim.perAddressDaily;
        glob = lim.globalDaily;
        bool immediate = (u + amount <= perAddr) && (g + amount <= glob);
        immediateInt = immediate ? 1 : 0;
    }

    /// @notice Expose current day's counters for a given owner and global aggregate.
    function usedToday(address owner) public view returns (uint256 ownerUsed, uint256 globalUsedTotal) {
        uint256 day = _dayKey(block.timestamp);
        ownerUsed = usedBy[day][owner];
        globalUsedTotal = globalUsed[day];
    }
}
