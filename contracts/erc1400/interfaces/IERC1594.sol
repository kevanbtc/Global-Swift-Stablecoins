// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC-1594 (Security Token Standard) — issuance/redemption hooks
interface IERC1594 {
    // Transfers with additional data hooks
    function transferWithData(address to, uint256 value, bytes calldata data) external;
    function transferFromWithData(address from, address to, uint256 value, bytes calldata data) external;

    // Issuance / Redemption
    function isIssuable() external view returns (bool);
    function issue(address to, uint256 value, bytes calldata data) external;
    function redeem(uint256 value, bytes calldata data) external;
    function redeemFrom(address from, uint256 value, bytes calldata data) external;

    // Validation (off-chain prechecks)
    function canTransfer(address to, uint256 value, bytes calldata data) external view returns (bytes1, bytes32, bytes32);
}
