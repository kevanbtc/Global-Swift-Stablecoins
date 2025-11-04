// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReleaseGuard {
    /// @notice Returns whether a rail may release a given token/amount to a beneficiary.
    /// @dev Implementations can enforce PoR freshness, policy constraints, etc.
    /// @return ok True if release is permitted
    /// @return reason Optional machine-readable reason stub
    function canRelease(address token, address to, uint256 amount) external view returns (bool ok, bytes memory reason);
}
