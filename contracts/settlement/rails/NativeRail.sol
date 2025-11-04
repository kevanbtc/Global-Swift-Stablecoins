// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "./IRail.sol";

/**
 * @title NativeRail
 * @notice Escrow/release native coin (ETH/MATIC) via msg.value on prepare.
 */
contract NativeRail is IRail {
    address public admin;
    mapping(bytes32 => Status) private _status;

    modifier onlyAdmin(){ require(msg.sender==admin, "RNAT: not admin"); _; }
    constructor(address _admin){ require(_admin!=address(0), "RNAT: 0"); admin=_admin; }

    function kind() external pure override returns (Kind){ return Kind.NATIVE; }

    function transferId(Transfer calldata t) public pure returns (bytes32){
        return keccak256(abi.encode(address(0), t.from, t.to, t.amount, t.metadata));
    }

    function prepare(Transfer calldata t) external payable override {
        bytes32 id = transferId(t);
        require(_status[id] == Status.NONE, "RNAT: exists");
        require(msg.value == t.amount, "RNAT: bad msg.value");
        _status[id] = Status.PREPARED;
        emit RailPrepared(id, t.from, t.to, address(0), t.amount);
    }

    function release(bytes32 id, Transfer calldata t) external override onlyAdmin {
        require(_status[id] == Status.PREPARED, "RNAT: bad state");
        _status[id] = Status.RELEASED;
        (bool ok,) = t.to.call{value: t.amount}(""); require(ok, "RNAT: xfer fail");
        emit RailReleased(id, t.to, address(0), t.amount);
    }

    function refund(bytes32 id, Transfer calldata t) external override onlyAdmin {
        require(_status[id] == Status.PREPARED, "RNAT: bad state");
        _status[id] = Status.REFUNDED;
        (bool ok,) = t.from.call{value: t.amount}(""); require(ok, "RNAT: refund fail");
        emit RailRefunded(id, t.from, address(0), t.amount);
    }

    function status(bytes32 id) external view override returns (Status){ return _status[id]; }
}
