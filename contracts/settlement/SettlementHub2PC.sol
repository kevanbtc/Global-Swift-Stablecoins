// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRail} from "./rails/IRail.sol";
import {RailRegistry} from "./rails/RailRegistry.sol";

/**
 * @title SettlementHub2PC
 * @notice Two‑phase commit orchestrator across two rails (legA + legB). Works for on-chain ⇄ on-chain and on-chain ⇄ external.
 *         Steps: open → prepare both legs → finalize (release both) → or cancel (refund both) on timeout or admin action.
 */
contract SettlementHub2PC {
    address public admin;
    RailRegistry public registry;

    enum State { Open, PreparedA, PreparedB, PreparedBoth, Finalized, Cancelled, Expired }

    struct IsoRefs { bytes16 uetr; bytes32 e2eHash; bytes32 payloadHash; }

    struct Leg {
        bytes32 railKey;     // key in RailRegistry
        IRail.Transfer xfer; // transfer parameters for the rail
    }

    struct Deal {
        State   state;
        uint64  createdAt;
        uint64  deadline;    // absolute deadline; after this anyone may cancel
        IsoRefs iso;
        Leg     A;
        Leg     B;
    }

    mapping(bytes32 => Deal) public deals; // id => deal

    event DealOpened(bytes32 indexed id, bytes16 uetr, uint64 deadline);
    event LegPrepared(bytes32 indexed id, uint8 legIdx, bytes32 railKey, bytes32 railTransferId);
    event Finalized(bytes32 indexed id);
    event Cancelled(bytes32 indexed id, State state);

    modifier onlyAdmin(){ require(msg.sender==admin, "HUB: not admin"); _; }

    constructor(address _admin, address _registry){ require(_admin!=address(0) && _registry!=address(0), "HUB: 0"); admin=_admin; registry = RailRegistry(_registry); }

    function open(
        bytes32 id,
        IsoRefs calldata iso,
        Leg calldata A,
        Leg calldata B,
        uint64 deadline
    ) public onlyAdmin {
        require(deals[id].createdAt == 0, "HUB: id exists");
        deals[id] = Deal({
            state: State.Open,
            createdAt: uint64(block.timestamp),
            deadline: deadline,
            iso: iso,
            A: A,
            B: B
        });
        emit DealOpened(id, iso.uetr, deadline);
    }

    function _rail(bytes32 key) internal view returns(IRail){ return IRail(registry.rails(key)); }

    function prepareA(bytes32 id) public {
        Deal storage d = deals[id]; require(d.createdAt!=0, "HUB: unknown");
        require(d.state == State.Open || d.state == State.PreparedB, "HUB: bad state A");
        IRail r = _rail(d.A.railKey); r.prepare(d.A.xfer);
        bytes32 tid = r.transferId(d.A.xfer);
        d.state = (d.state == State.Open) ? State.PreparedA : State.PreparedBoth;
        emit LegPrepared(id, 0, d.A.railKey, tid);
    }

    function prepareB(bytes32 id) public {
        Deal storage d = deals[id]; require(d.createdAt!=0, "HUB: unknown");
        require(d.state == State.Open || d.state == State.PreparedA, "HUB: bad state B");
        IRail r = _rail(d.B.railKey); r.prepare(d.B.xfer);
        bytes32 tid = r.transferId(d.B.xfer);
        d.state = (d.state == State.Open) ? State.PreparedB : State.PreparedBoth;
        emit LegPrepared(id, 1, d.B.railKey, tid);
    }

    function finalize(bytes32 id) public onlyAdmin {
        Deal storage d = deals[id]; require(d.createdAt!=0, "HUB: unknown");
        require(d.state == State.PreparedBoth, "HUB: not prepared");
        require(block.timestamp <= d.deadline, "HUB: expired");
        IRail rA = _rail(d.A.railKey); IRail rB = _rail(d.B.railKey);
        rA.release(rA.transferId(d.A.xfer), d.A.xfer);
        rB.release(rB.transferId(d.B.xfer), d.B.xfer);
        d.state = State.Finalized;
        emit Finalized(id);
    }

    function cancel(bytes32 id) public {
        Deal storage d = deals[id]; require(d.createdAt!=0, "HUB: unknown");
        bool can = (msg.sender==admin) || (block.timestamp > d.deadline);
        require(can, "HUB: no auth");
        // Refund any prepared leg
        IRail rA = _rail(d.A.railKey); IRail rB = _rail(d.B.railKey);
        if (d.state == State.PreparedA || d.state == State.PreparedBoth) { rA.refund(rA.transferId(d.A.xfer), d.A.xfer); }
        if (d.state == State.PreparedB || d.state == State.PreparedBoth) { rB.refund(rB.transferId(d.B.xfer), d.B.xfer); }
        d.state = (block.timestamp > d.deadline) ? State.Expired : State.Cancelled;
        emit Cancelled(id, d.state);
    }
}
