// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ITravelRule} from "../interfaces/ExternalInterfaces.sol";
contract TravelRuleMock is ITravelRule { mapping(bytes32=>bool) public ok; function set(address f,address t,uint256 amt,uint64 ttl,bool yes) external { ok[keccak256(abi.encode(f,t,amt,ttl))]=yes; } function hasPermit(address f,address t,uint256 a,uint64 ttl) external view returns (bool){ return ok[keccak256(abi.encode(f,t,a,ttl))]; } }
