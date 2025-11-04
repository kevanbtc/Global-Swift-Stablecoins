// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Regulatory Guardian
/// @notice Operation-code based guard with multi-approval to flip critical flags (e.g., pause MINT/REBASE/TRANSFER segments)
contract RegGuardian is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // opCode -> paused
    mapping(bytes4 => bool) public pausedOp;

    // proposalId -> approvals -> executed
    struct Proposal { bytes32 id; bytes4 op; bool toPause; uint8 required; uint8 approvals; bool executed; mapping(address=>bool) voted; }
    mapping(bytes32 => Proposal) private _props;

    event Proposed(bytes32 indexed id, bytes4 op, bool toPause, uint8 required);
    event Approved(bytes32 indexed id, address guardian, uint8 approvals, uint8 required);
    event Executed(bytes32 indexed id, bytes4 op, bool paused);

    constructor(address admin, address[] memory guardians, uint8 defaultThreshold){
        _grantRole(DEFAULT_ADMIN_ROLE, admin); _grantRole(ADMIN_ROLE, admin);
        for (uint256 i=0;i<guardians.length;i++){ _grantRole(GUARDIAN_ROLE, guardians[i]); }
        // store threshold via a dummy proposal with id 0; we pass required on each proposal instead for flexibility
        require(defaultThreshold>0, "thr");
    }

    function isPaused(bytes4 op) external view returns (bool){ return pausedOp[op]; }

    function propose(bytes4 op, bool toPause, uint8 required) external onlyRole(ADMIN_ROLE) returns (bytes32 id){
        require(required>0, "thr");
        id = keccak256(abi.encode(op, toPause, block.number, block.timestamp));
        Proposal storage p = _props[id];
        p.id = id; p.op = op; p.toPause = toPause; p.required = required;
        emit Proposed(id, op, toPause, required);
    }

    function approve(bytes32 id) external onlyRole(GUARDIAN_ROLE) {
        Proposal storage p = _props[id]; require(p.id == id, "no prop"); require(!p.executed, "done"); require(!p.voted[msg.sender], "voted");
        p.voted[msg.sender] = true; p.approvals += 1; emit Approved(id, msg.sender, p.approvals, p.required);
    }

    function execute(bytes32 id) external onlyRole(ADMIN_ROLE){
        Proposal storage p = _props[id]; require(p.id == id, "no prop"); require(!p.executed, "done"); require(p.approvals >= p.required, "not enough" );
        pausedOp[p.op] = p.toPause; p.executed = true; emit Executed(id, p.op, p.toPause);
    }
}
