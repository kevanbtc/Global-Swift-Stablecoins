// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IERC1594.sol";
import "./IERC1410.sol";
import "./IERC1400Document.sol";
import "./IERC1400Controller.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ERC-1400 Security Token Standard
interface IERC1400 is IERC1594, IERC1410, IERC1400Document, IERC1400Controller, IERC20 {
    // Token Information
    function granularity() external view returns (uint256);
    function totalSupplyByPartition(bytes32 partition) external view returns (uint256);
    
    // Default Partition
    function getDefaultPartition() external view returns (bytes32);
    
    // Token Metadata
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    
    // Additional Events
    event TransferByPartition(
        bytes32 indexed fromPartition,
        address operator,
        address indexed from,
        address indexed to,
        uint256 value,
        bytes data,
        bytes operatorData
    );
    
    event ChangedPartition(
        bytes32 indexed fromPartition,
        bytes32 indexed toPartition,
        uint256 value
    );
}
