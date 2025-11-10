// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IRail} from "../settlement/rails/IRail.sol";
import {RailRegistry} from "../settlement/rails/RailRegistry.sol";
import {Types} from "../common/Types.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title UnykornL1Bridge
/// @notice Bridge contract for cross-chain settlement on Unykorn L1 via Besu.
/// Handles permissioned nodes, privacy groups, and rail discovery for multi-chain rails.
contract UnykornL1Bridge is Ownable, ReentrancyGuard {
    RailRegistry public immutable registry;
    mapping(address => Types.BesuNode) public besuNodes;
    mapping(bytes32 => bool) public activePrivacyGroups;

    event BesuNodeRegistered(address indexed node, Types.BesuPermission permission);
    event PrivacyGroupActivated(bytes32 indexed groupId);
    event CrossChainSettlementInitiated(bytes32 indexed railKey, address indexed token, uint256 amount);

    constructor(address _registry) Ownable(msg.sender) {
        require(_registry != address(0), "UL1B: 0");
        registry = RailRegistry(_registry);
    }

    /// @notice Register a Besu node with permissions and privacy group.
    function registerBesuNode(
        address node,
        Types.BesuPermission permission,
        bytes32 privacyGroup
    ) public onlyOwner {
        besuNodes[node] = Types.BesuNode({
            nodeAddress: node,
            permission: permission,
            privacyGroup: privacyGroup
        });
        activePrivacyGroups[privacyGroup] = true;
        emit BesuNodeRegistered(node, permission);
        emit PrivacyGroupActivated(privacyGroup);
    }

    /// @notice Initiate cross-chain settlement via a registered rail.
    function initiateCrossChainSettlement(
        bytes32 railKey,
        address token,
        address from,
        address to,
        uint256 amount
    ) public nonReentrant {
        address railAddr = registry.get(railKey);
        require(railAddr != address(0), "UL1B: Rail not found");

        // Prepare transfer via rail
        IRail.Transfer memory xfer = IRail.Transfer({
            asset: token,
            from: from,
            to: to,
            amount: amount,
            metadata: abi.encode(besuNodes[msg.sender].privacyGroup) // Include privacy group
        });

        // Call rail's prepare function (assumes rail implements prepare/release)
        IRail(railAddr).prepare{value: 0}(xfer);

        emit CrossChainSettlementInitiated(railKey, token, amount);
    }

    /// @notice Check if a node has admin permission.
    function hasAdminPermission(address node) public view returns (bool) {
        return besuNodes[node].permission == Types.BesuPermission.ADMIN;
    }
}
