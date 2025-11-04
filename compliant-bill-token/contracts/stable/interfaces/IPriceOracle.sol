// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceOracle {
    // returns price in 1e18 units for 1 unit of collateral
    function priceE18(address asset) external view returns (uint256 price, uint64 lastUpdate);
}
