// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC-1400 (Security Token Standard) — document management
interface IERC1400Document {
    // Document Management
    function getDocument(bytes32 documentName) external view returns (string memory, bytes32, uint256);
    function setDocument(bytes32 documentName, string calldata uri, bytes32 documentHash) external;
    
    // Events
    event DocumentUpdated(bytes32 indexed documentName, string uri, bytes32 documentHash);
}
