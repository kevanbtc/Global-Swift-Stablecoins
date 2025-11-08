// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IMintableERC20 {
    function mint(address to, uint256 amount) external;
}

/// @title WormholeMintProxy (skeleton)
/// @notice Minimal proxy that allows a designated bridge to mint tokens on this chain.
contract WormholeMintProxy is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    event BridgeSet(address bridge);
    event MintForwarded(address token, address to, uint256 amount);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function setBridge(address bridge) public onlyRole(ADMIN_ROLE) {
        // grant/revoke role explicitly to keep audit trail on-chain
        if (bridge != address(0)) _grantRole(BRIDGE_ROLE, bridge);
        emit BridgeSet(bridge);
    }

    function mint(address token, address to, uint256 amt) public onlyRole(BRIDGE_ROLE) {
        IMintableERC20(token).mint(to, amt);
        emit MintForwarded(token, to, amt);
    }
}
