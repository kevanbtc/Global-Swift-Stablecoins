// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "../rails/IRail.sol";
import {RailRegistry} from "../rails/RailRegistry.sol";

/// @title StablecoinRouter
/// @notice Simple helper that routes prepare() calls to a preferred rail per token
contract StablecoinRouter {
    address public admin;
    RailRegistry public immutable registry;

    // token => railKey
    mapping(address => bytes32) public defaultRailKey;

    event AdminTransferred(address indexed from, address indexed to);
    event DefaultRailSet(address indexed token, bytes32 railKey);

    modifier onlyAdmin(){ require(msg.sender==admin, "SCR: not admin"); _; }

    constructor(address _admin, address _registry){ require(_admin!=address(0) && _registry!=address(0), "SCR: 0"); admin=_admin; registry = RailRegistry(_registry); }

    function transferAdmin(address to) public onlyAdmin { require(to!=address(0), "SCR: 0"); emit AdminTransferred(admin,to); admin=to; }
    function setDefaultRail(address token, bytes32 railKey) public onlyAdmin { defaultRailKey[token]=railKey; emit DefaultRailSet(token, railKey); }

    /// @notice Convenience method to prepare a single-leg transfer via the configured rail for the token
    function routeAndPrepare(IRail.Transfer calldata t) public payable returns (bytes32 tid){
        bytes32 key = defaultRailKey[t.asset];
        require(key != bytes32(0), "SCR: no rail");
        IRail r = IRail(registry.rails(key));
        r.prepare{value: msg.value}(t);
        tid = r.transferId(t);
    }
}
