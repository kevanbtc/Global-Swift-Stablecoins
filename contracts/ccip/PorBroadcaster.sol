// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Errors} from "../common/Errors.sol";

/// @notice Minimal CCIP client interface subset (no external deps)
library Client {
    struct EVMTokenAmount { address token; uint256 amount; }
    struct EVMExtraArgsV1 { uint256 gasLimit; bool strict; } // strict sequencing
    struct EVM2AnyMessage {
        address receiver;      // EVM receiver
        bytes data;            // calldata
        EVMTokenAmount[] tokenAmounts;
        address feeToken;      // 0x0 native if none
        bytes extraArgs;       // abi.encode(EVMExtraArgsV1)
    }
}

interface IRouterClient {
    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message) external view returns (uint256);
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message) external payable returns (bytes32);
}

interface IReserveQuorumView {
    struct Snapshot { uint256 totalAssets1e18; uint256 totalLiabilities1e18; uint256 cash1e18; uint256 tBills1e18; uint256 repos1e18; uint256 other1e18; bytes32 documentsCid; uint64 asOf; }
    function latestSealed() external view returns (uint64 epoch, Snapshot memory s);
}

/// @notice Broadcast reserve snapshots to other chains via CCIP
contract PorBroadcaster {
    address public immutable router;
    address public immutable reserve;
    address public governor;
    bool    public paused;

    event GovernorChanged(address indexed oldGov, address indexed newGov);
    event Paused(bool p);
    event Broadcasted(bytes32 messageId, uint64 dst, address receiver, uint64 epoch, uint256 totalAssets1e18);

    modifier onlyGov() { if (msg.sender != governor) revert Errors.Unauthorized(); _; }

    constructor(address router_, address reserve_, address governor_) {
        router = router_; reserve = reserve_; governor = governor_; paused = false;
    }

    function setGovernor(address g) external onlyGov { emit GovernorChanged(governor, g); governor = g; }
    function setPaused(bool p) external onlyGov { paused = p; emit Paused(p); }

    function _message(address receiver) internal view returns (Client.EVM2AnyMessage memory m, uint64 epoch, IReserveQuorumView.Snapshot memory s) {
        (epoch, s) = IReserveQuorumView(reserve).latestSealed();
        bytes memory payload = abi.encode(
            keccak256("PoRSnapshotV1"),
            epoch,
            s.totalAssets1e18,
            s.totalLiabilities1e18,
            s.cash1e18,
            s.tBills1e18,
            s.repos1e18,
            s.other1e18,
            s.documentsCid,
            s.asOf
        );
        Client.EVMTokenAmount[] memory empty;
        m = Client.EVM2AnyMessage({
            receiver: receiver,
            data: payload,
            tokenAmounts: empty,
            feeToken: address(0),
            extraArgs: abi.encode(Client.EVMExtraArgsV1({gasLimit: 200_000, strict: true}))
        });
    }

    function quote(uint64 dstChain, address receiver) external view returns (uint256 feeWei) {
        (Client.EVM2AnyMessage memory msg_,,,) = _messageView(receiver);
        feeWei = IRouterClient(router).getFee(dstChain, msg_);
    }

    // helper to avoid stack too deep (view)
    function _messageView(address receiver) internal view returns (Client.EVM2AnyMessage memory m, uint64 epoch, IReserveQuorumView.Snapshot memory s, bytes memory payload) {
        (epoch, s) = IReserveQuorumView(reserve).latestSealed();
        payload = abi.encode(keccak256("PoRSnapshotV1"), epoch, s.totalAssets1e18, s.totalLiabilities1e18, s.cash1e18, s.tBills1e18, s.repos1e18, s.other1e18, s.documentsCid, s.asOf);
        Client.EVMTokenAmount[] memory empty;
        m = Client.EVM2AnyMessage({receiver: receiver, data: payload, tokenAmounts: empty, feeToken: address(0), extraArgs: abi.encode(Client.EVMExtraArgsV1({gasLimit: 200000, strict: true}))});
    }

    function broadcast(uint64 dstChain, address receiver) external payable onlyGov returns (bytes32 id) {
        if (paused) revert Errors.Paused();
        (Client.EVM2AnyMessage memory m, uint64 epoch, IReserveQuorumView.Snapshot memory s) = _message(receiver);
        uint256 feeQuote = IRouterClient(router).getFee(dstChain, m);
        if (msg.value < feeQuote) revert Errors.InvalidParam();
        id = IRouterClient(router).ccipSend{value: msg.value}(dstChain, m);
        emit Broadcasted(id, dstChain, receiver, epoch, s.totalAssets1e18);
    }
}
