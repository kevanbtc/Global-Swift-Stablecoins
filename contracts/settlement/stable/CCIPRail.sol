// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "../rails/IRail.sol";

/// @title CCIPRail
/// @notice Thin rail that models CCIP-delivered transfers. A designated executor marks results after message delivery.
contract CCIPRail is IRail {
    address public admin;
    address public executor; // e.g., CCIP receiver adapter or trusted agent

    mapping(bytes32 => Status) private _status;

    event ExecutorSet(address indexed executor);

    modifier onlyAdmin(){ require(msg.sender==admin, "CCIP: not admin"); _; }
    modifier onlyExec(){ require(msg.sender==executor, "CCIP: not exec"); _; }

    constructor(address _admin, address _executor){ require(_admin!=address(0) && _executor!=address(0), "CCIP: 0"); admin=_admin; executor=_executor; }

    function setExecutor(address e) public onlyAdmin { require(e!=address(0), "CCIP: 0"); executor=e; emit ExecutorSet(e); }

    function kind() public pure override returns (Kind){ return Kind.EXTERNAL; }

    function transferId(Transfer calldata t) public pure returns (bytes32){ return keccak256(abi.encode("CCIP", t.from, t.to, t.amount, t.metadata)); }

    function prepare(Transfer calldata t) public payable override {
        bytes32 id = transferId(t);
        require(_status[id] == Status.NONE, "CCIP: exists");
        _status[id] = Status.PREPARED;
        emit RailPrepared(id, t.from, t.to, t.asset, t.amount);
    }

    function markReleased(bytes32 id, Transfer calldata t) public onlyExec {
        require(_status[id] == Status.PREPARED, "CCIP: bad state"); _status[id] = Status.RELEASED; emit RailReleased(id, t.to, t.asset, t.amount);
    }
    function markRefunded(bytes32 id, Transfer calldata t) public onlyExec {
        require(_status[id] == Status.PREPARED, "CCIP: bad state"); _status[id] = Status.REFUNDED; emit RailRefunded(id, t.from, t.asset, t.amount);
    }

    // IRail compat (admin paths are disabled in favor of executor markers)
    function release(bytes32 /*id*/, Transfer calldata /*t*/) public override onlyAdmin { revert("CCIP: use markReleased"); }
    function refund(bytes32 /*id*/, Transfer calldata /*t*/) public override onlyAdmin { revert("CCIP: use markRefunded"); }
    function status(bytes32 id) public view override returns (Status){ return _status[id]; }
}
