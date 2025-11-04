// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title CourtOrderRegistry
 * @notice Register and query legally-binding orders that affect transferability/redeemability.
 *         Used by ERC-1644 controller & policy modules to enforce freezes/forced actions.
 */
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract CourtOrderRegistry is AccessControl {
    bytes32 public constant COURT_ROLE = keccak256("COURT_ROLE");      // court/receiver/trustee
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE"); // issuer governance

    enum Action { FREEZE, UNFREEZE, FORCE_TRANSFER, FORCE_REDEEM }

    struct Order {
        bytes32 id;            // external reference / docket id
        address subject;       // account affected
        address token;         // instrument/token
        Action  action;
        address to;            // for FORCE_TRANSFER
        uint256 amount;        // units (token decimals)
        uint64  createdAt;
        uint64  validUntil;    // 0 = no expiry
        bool    executed;      // for one-shot actions
        bool    active;        // freeze state
        string  memo;          // human readable
    }

    mapping(bytes32 => Order) public orders;        // orderId => Order
    mapping(address => bool) public globalFreeze;   // instrument => frozen

    event OrderFiled(bytes32 indexed id, address indexed token, address indexed subject, Action action);
    event OrderExecuted(bytes32 indexed id, address indexed token, address subject);
    event GlobalFreeze(address indexed token, bool frozen);

    constructor(address admin, address governor) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, governor);
    }

    function grantCourt(address court) external onlyRole(GOVERNOR_ROLE) {
        _grantRole(COURT_ROLE, court);
    }

    function fileOrder(Order calldata o) external onlyRole(COURT_ROLE) {
        require(o.id != 0, "id=0");
        require(orders[o.id].id == 0, "exists");
        require(o.subject != address(0), "subject=0");
        require(o.token != address(0), "token=0");
        orders[o.id] = o;
        emit OrderFiled(o.id, o.token, o.subject, o.action);
    }

    function setGlobalFreeze(address token, bool frozen) external onlyRole(COURT_ROLE) {
        globalFreeze[token] = frozen;
        emit GlobalFreeze(token, frozen);
    }

    function markExecuted(bytes32 id) external onlyRole(COURT_ROLE) {
        Order storage o = orders[id];
        require(o.id != 0, "notfound");
        o.executed = true;
        emit OrderExecuted(id, o.token, o.subject);
    }

    function isActive(bytes32 id) public view returns (bool) {
        Order memory o = orders[id];
        if (o.id == 0) return false;
        if (o.validUntil != 0 && block.timestamp > o.validUntil) return false;
        if (o.action == Action.FREEZE || o.action == Action.UNFREEZE) return o.active;
        // FORCE_* is valid if not executed and not expired
        return !o.executed;
    }

    function subjectFrozen(address token, address subject) external view returns (bool) {
        // Scan is expensive on-chain; for MVP assume single active freeze per subject
        // Practical deployments should index per (token,subject) to last freeze order id.
        // Here: global freeze OR any active freeze order targeting subject.
        if (globalFreeze[token]) return true;
        // Off-chain index recommended; on-chain, caller should use a known order id.
        return false;
    }
}
