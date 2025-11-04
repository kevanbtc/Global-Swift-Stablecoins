// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Proof-of-Reserves oracle (freshness + NAV / liabilities).
interface IReserveOracle {
    function isFresh() external view returns (bool);
    function navUSD() external view returns (uint256);        // 18 decimals
    function liabilitiesUSD() external view returns (uint256); // 18 decimals
}

/// @notice Weights assets for RWA risk (Basel-like).
interface IRiskWeights {
    /// @return bps e.g., 0-12500 (0-125%)
    function weightOf(address asset) external view returns (uint16);
}

/// @notice Eligible reserve valuation in USD (18 decimals).
interface IEligibleReserve {
    function eligibleValueUSD() external view returns (uint256);
}

/// @notice Travel Rule preclear hook; implement off-chain + post attestation on-chain.
interface ITravelRule {
    function hasPermit(address from, address to, uint256 amt, uint64 ttl) external view returns (bool);
}
