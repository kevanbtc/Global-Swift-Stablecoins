// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC-1400 (Security Token Standard) — controller operations
interface IERC1400Controller {
    // Controller Operations
    function controllerTransfer(address from, address to, uint256 value, bytes calldata data, bytes calldata operatorData) external;
    function controllerRedeem(address tokenHolder, uint256 value, bytes calldata data, bytes calldata operatorData) external;
    
    // Controller Queries
    function isControllable() external view returns (bool);
    
    // Events
    event ControllerTransfer(address controller, address indexed from, address indexed to, uint256 value, bytes data, bytes operatorData);
    event ControllerRedemption(address controller, address indexed tokenHolder, uint256 value, bytes data, bytes operatorData);
}
