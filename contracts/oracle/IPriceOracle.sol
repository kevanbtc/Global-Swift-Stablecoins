// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for fetching on-chain/off-chain fed price with decimals.
///         Implement using Chainlink/Pyth/custom NAV oracle as you prefer.
interface IPriceOracle {
    /// @return price latest price scaled by `decimals()`
    /// @return decimals decimals of the returned price
    function getPrice(address asset) external view returns (uint256 price, uint8 decimals);
    function decimals(address asset) external view returns (uint8);
}
