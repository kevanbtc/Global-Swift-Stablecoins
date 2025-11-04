// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC-1410 (Partially Fungible Token Standard) - partition-based balances
interface IERC1410 {
    // Partition queries
    function balanceOfByPartition(bytes32 partition, address tokenHolder) external view returns (uint256);
    function partitionsOf(address tokenHolder) external view returns (bytes32[] memory);
    
    // Partition transfers
    function transferByPartition(bytes32 partition, address to, uint256 value, bytes calldata data) external returns (bytes32);
    function operatorTransferByPartition(bytes32 partition, address from, address to, uint256 value, bytes calldata data, bytes calldata operatorData) external returns (bytes32);
    
    // Partition operators
    function authorizeOperatorByPartition(bytes32 partition, address operator) external;
    function revokeOperatorByPartition(bytes32 partition, address operator) external;
    function isOperatorForPartition(bytes32 partition, address operator, address tokenHolder) external view returns (bool);
}
