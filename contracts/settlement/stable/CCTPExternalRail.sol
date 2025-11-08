// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "../rails/IRail.sol";

/// @title CCTPExternalRail
/// @notice Specialized external rail for USDC CCTP flows. Uses an authorized executor to mark finalization.
/// @dev This is a thin variant of ExternalRail with a distinct transferId domain and optional domain metadata.
contract CCTPExternalRail is IRail {
    address public admin;
    address public executor; // e.g., off-chain agent that monitors Circle CCTP events
    uint32  public domain;   // optional: Circle domain id for this chain

    mapping(bytes32 => Status) private _status;

    event ExecutorSet(address indexed executor);
    event DomainSet(uint32 domain);

    modifier onlyAdmin(){ require(msg.sender==admin, "CCTP: not admin"); _; }
    modifier onlyExec(){ require(msg.sender==executor, "CCTP: not exec"); _; }

    constructor(address _admin, address _executor, uint32 _domain){ require(_admin!=address(0) && _executor!=address(0), "CCTP: 0"); admin=_admin; executor=_executor; domain=_domain; }

    function setExecutor(address e) public onlyAdmin { require(e!=address(0), "CCTP: 0"); executor=e; emit ExecutorSet(e); }
    function setDomain(uint32 d) public onlyAdmin { domain = d; emit DomainSet(d); }

    function kind() public pure override returns (Kind){ return Kind.EXTERNAL; }

    function transferId(Transfer calldata t) public pure returns (bytes32){ return keccak256(abi.encode("CCTP", t.from, t.to, t.amount, t.metadata)); }

    function prepare(Transfer calldata t) public payable override {
        bytes32 id = transferId(t);
        require(_status[id] == Status.NONE, "CCTP: exists");
        _status[id] = Status.PREPARED;
        emit RailPrepared(id, t.from, t.to, t.asset, t.amount);
    }

    function markReleased(bytes32 id, Transfer calldata t) public onlyExec {
        require(_status[id] == Status.PREPARED, "CCTP: bad state"); _status[id] = Status.RELEASED; emit RailReleased(id, t.to, t.asset, t.amount);
    }
    function markRefunded(bytes32 id, Transfer calldata t) public onlyExec {
        require(_status[id] == Status.PREPARED, "CCTP: bad state"); _status[id] = Status.REFUNDED; emit RailRefunded(id, t.from, t.asset, t.amount);
    }

    // IRail compat (admin paths are disabled in favor of executor markers)
    function release(bytes32 /*id*/, Transfer calldata /*t*/) public override onlyAdmin { revert("CCTP: use markReleased"); }
    function refund(bytes32 /*id*/, Transfer calldata /*t*/) public override onlyAdmin { revert("CCTP: use markRefunded"); }
    function status(bytes32 id) public view override returns (Status){ return _status[id]; }
}
