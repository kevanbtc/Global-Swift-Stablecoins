// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title ERC1644Controller
 * @notice Controller for ERC-1644 force transfer/redeem, wired to CourtOrderRegistry.
 */
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {CourtOrderRegistry} from "./CourtOrderRegistry.sol";

interface IERC20Forceable {
    function controllerTransfer(address from, address to, uint256 value, bytes calldata data) external;
    function controllerRedeem(address from, uint256 value, bytes calldata data) external;
    function decimals() external view returns (uint8);
}

interface ICourtOrderRegistry {
    enum Action { FREEZE, UNFREEZE, FORCE_TRANSFER, FORCE_REDEEM }
    struct Order {
        bytes32 id;
        address subject;
        address token;
        Action  action;
        address to;
        uint256 amount;
        uint64  createdAt;
        uint64  validUntil;
        bool    executed;
        bool    active;
        string  memo;
    }
    function orders(bytes32 id) external view returns (Order memory);
    function isActive(bytes32 id) external view returns (bool);
    function markExecuted(bytes32 id) external;
}

contract ERC1644Controller is AccessControl {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant GOVERNOR_ROLE   = keccak256("GOVERNOR_ROLE");

    ICourtOrderRegistry public registry;

    event Forced(address indexed token, address indexed from, address indexed to, uint256 amount, bytes32 orderId);
    event ForcedRedeem(address indexed token, address indexed from, uint256 amount, bytes32 orderId);

    constructor(address admin, address governor, address registry_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
        registry = ICourtOrderRegistry(registry_);
    }

    function grantController(address who) public onlyRole(GOVERNOR_ROLE) {
        _grantRole(CONTROLLER_ROLE, who);
    }

    function forceTransfer(bytes32 orderId) public onlyRole(CONTROLLER_ROLE) {
        ICourtOrderRegistry.Order memory o = registry.orders(orderId);
        require(registry.isActive(orderId), "inactive");
        require(o.action == ICourtOrderRegistry.Action.FORCE_TRANSFER, "not transfer");
        IERC20Forceable(o.token).controllerTransfer(o.subject, o.to, o.amount, abi.encode(orderId));
        registry.markExecuted(orderId);
        emit Forced(o.token, o.subject, o.to, o.amount, orderId);
    }

    function forceRedeem(bytes32 orderId) public onlyRole(CONTROLLER_ROLE) {
        ICourtOrderRegistry.Order memory o = registry.orders(orderId);
        require(registry.isActive(orderId), "inactive");
        require(o.action == ICourtOrderRegistry.Action.FORCE_REDEEM, "not redeem");
        IERC20Forceable(o.token).controllerRedeem(o.subject, o.amount, abi.encode(orderId));
        registry.markExecuted(orderId);
        emit ForcedRedeem(o.token, o.subject, o.amount, orderId);
    }
}
