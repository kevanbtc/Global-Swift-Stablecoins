// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceOracle {
    function getPrice(address asset) external view returns (uint256);
    function updatePrice(address asset, uint256 price) external;
    function validatePrice(address asset, uint256 price) external view returns (bool);
}
