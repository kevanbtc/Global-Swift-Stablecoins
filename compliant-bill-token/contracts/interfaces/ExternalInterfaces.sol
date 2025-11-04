// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IReserveOracle { function isFresh() external view returns (bool); function navUSD() external view returns (uint256); function liabilitiesUSD() external view returns (uint256); }
interface IRiskWeights { function weightOf(address asset) external view returns (uint16); }
interface IEligibleReserve { function eligibleValueUSD() external view returns (uint256); }
interface ITravelRule { function hasPermit(address from, address to, uint256 amt, uint64 ttl) external view returns (bool); }
