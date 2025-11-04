// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Provides an estimate of days-to-maturity for a vault or share (for roll logic).
interface IShareMaturityOracle {
    /// @return daysToMaturity estimated remaining days for instrument (0 if matured/cash-like)
    function daysToMaturity(address instrument) external view returns (uint16);
}
