// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "./IRail.sol";

/**
 * @title RailRegistry
 * @notice Registry of active rails used by the SettlementHub and off-chain agents.
 */
contract RailRegistry {
    address public admin;
    mapping(bytes32 => address) public rails; // railKey => railAddress

    event AdminTransferred(address indexed from, address indexed to);
    event RailSet(bytes32 indexed key, address indexed rail, IRail.Kind kind);

    modifier onlyAdmin(){ require(msg.sender==admin, "REG: not admin"); _; }
    constructor(address _admin){ require(_admin!=address(0), "REG: 0"); admin=_admin; }

    function transferAdmin(address to) external onlyAdmin { require(to!=address(0), "REG: 0"); emit AdminTransferred(admin,to); admin=to; }

    function set(bytes32 key, address rail) external onlyAdmin {
        require(rail!=address(0), "REG: 0 rail");
        IRail.Kind k = IRail(rail).kind();
        rails[key]=rail;
        emit RailSet(key, rail, k);
    }

    function get(bytes32 key) external view returns(address){ return rails[key]; }
}
