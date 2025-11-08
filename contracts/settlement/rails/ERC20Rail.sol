// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "./IRail.sol";

interface IERC20 { function transferFrom(address, address, uint256) external returns (bool); function transfer(address, uint256) external returns (bool); }

/**
 * @title ERC20Rail
 * @notice Escrow + release ERC-20 tokens for SettlementHub using a two-phase flow.
 */
contract ERC20Rail is IRail {
    address public admin;

    mapping(bytes32 => Status) private _status;

    modifier onlyAdmin(){ require(msg.sender==admin, "R20: not admin"); _; }
    constructor(address _admin){ require(_admin!=address(0), "R20: 0"); admin=_admin; }

    function kind() public pure override returns (Kind){ return Kind.ERC20; }

    function transferId(Transfer calldata t) public pure returns (bytes32){
        return keccak256(abi.encode(t.asset, t.from, t.to, t.amount, t.metadata));
    }

    function prepare(Transfer calldata t) public payable override {
        require(t.asset != address(0), "R20: asset 0");
        bytes32 id = transferId(t);
        require(_status[id] == Status.NONE, "R20: exists");
        require(IERC20(t.asset).transferFrom(t.from, address(this), t.amount), "R20: pull fail");
        _status[id] = Status.PREPARED;
        emit RailPrepared(id, t.from, t.to, t.asset, t.amount);
    }

    function release(bytes32 id, Transfer calldata t) public override onlyAdmin {
        require(_status[id] == Status.PREPARED, "R20: bad state");
        _status[id] = Status.RELEASED;
        require(IERC20(t.asset).transfer(t.to, t.amount), "R20: xfer fail");
        emit RailReleased(id, t.to, t.asset, t.amount);
    }

    function refund(bytes32 id, Transfer calldata t) public override onlyAdmin {
        require(_status[id] == Status.PREPARED, "R20: bad state");
        _status[id] = Status.REFUNDED;
        require(IERC20(t.asset).transfer(t.from, t.amount), "R20: refund fail");
        emit RailRefunded(id, t.from, t.asset, t.amount);
    }

    function status(bytes32 id) public view override returns (Status){ return _status[id]; }
}
