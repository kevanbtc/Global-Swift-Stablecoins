// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "./IRail.sol";

/**
 * @title ExternalRail
 * @notice Stub for off-chain rails (RTGS, Swift-ledger, bank ledgers). Uses a trusted EXECUTOR to mark releases/refunds
 *         after off-chain completion. Think of this as a two-phase commit coordinator for non-crypto legs.
 */
contract ExternalRail is IRail {
    address public admin;
    address public executor; // e.g., your off-chain agent / oracle poster / CCIP receiver

    mapping(bytes32 => Status) private _status;

    event ExecutorSet(address indexed executor);

    modifier onlyAdmin(){ require(msg.sender==admin, "XRAIL: not admin"); _; }
    modifier onlyExec(){ require(msg.sender==executor, "XRAIL: not exec"); _; }

    constructor(address _admin, address _executor){ require(_admin!=address(0) && _executor!=address(0), "XRAIL: 0"); admin=_admin; executor=_executor; }

    function setExecutor(address e) external onlyAdmin { require(e!=address(0), "XRAIL: 0"); executor=e; emit ExecutorSet(e); }

    function kind() external pure override returns (Kind){ return Kind.EXTERNAL; }

    function transferId(Transfer calldata t) public pure returns (bytes32){ return keccak256(abi.encode("XRAIL", t.from, t.to, t.amount, t.metadata)); }

    function prepare(Transfer calldata t) external payable override {
        bytes32 id = transferId(t);
        require(_status[id] == Status.NONE, "XRAIL: exists");
        // For external rails, on-chain prepare just records intent; off-chain system will perform debit/credit.
        _status[id] = Status.PREPARED;
        emit RailPrepared(id, t.from, t.to, t.asset, t.amount);
    }

    // Off-chain executor calls these once the external leg has settled.
    function markReleased(bytes32 id, Transfer calldata t) external onlyExec {
        require(_status[id] == Status.PREPARED, "XRAIL: bad state"); _status[id] = Status.RELEASED; emit RailReleased(id, t.to, t.asset, t.amount);
    }
    function markRefunded(bytes32 id, Transfer calldata t) external onlyExec {
        require(_status[id] == Status.PREPARED, "XRAIL: bad state"); _status[id] = Status.REFUNDED; emit RailRefunded(id, t.from, t.asset, t.amount);
    }

    // IRail compatibility
    function release(bytes32 id, Transfer calldata t) external override onlyAdmin { revert("XRAIL: use markReleased"); }
    function refund(bytes32 id, Transfer calldata t) external override onlyAdmin { revert("XRAIL: use markRefunded"); }
    function status(bytes32 id) external view override returns (Status){ return _status[id]; }
}
