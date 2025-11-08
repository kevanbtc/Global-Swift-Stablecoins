// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReserveManager {
    function getReserve(address asset) external view returns (uint256);
    function updateReserve(address asset, uint256 amount) external;
    function validateReserve(address asset, uint256 amount) external view returns (bool);
}
