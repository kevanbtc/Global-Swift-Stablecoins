// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IProofOfReserves {
    /// @notice A simple interface a Stablecoin/RWA can call before mint/redeem
    function checkMint(bytes32 reserveId, uint256 amount) external view returns (bool);
    function checkRedeem(bytes32 reserveId, uint256 amount) external view returns (bool);
}
