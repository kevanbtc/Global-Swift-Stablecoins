// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Iso20022Bridge
 * @notice Event bridge to bind off-chain ISO 20022 envelopes to on-chain ops.
 * - Store minimal hashes + emit canonicalized events to feed your audit/indexers.
 */
contract Iso20022Bridge {
    address public admin;

    struct Binding {
        bytes16 uetr;         // UUIDv4 (16 bytes)
        bytes32 payloadHash;  // keccak256(XML/JSON)
        bytes32 e2eIdHash;    // optional end-to-end id hash
        uint64  boundAt;
    }

    mapping(bytes32 => Binding) public bindings; // id => Binding

    event AdminTransferred(address indexed from, address indexed to);
    event IsoBound(bytes32 indexed id, bytes16 indexed uetr, bytes32 payloadHash, bytes32 e2eIdHash);
    event IsoEvent(bytes32 indexed id, bytes16 indexed uetr, string messageType, bytes32 payloadHash);
    
    // SWIFT GPI events
    event GPIPaymentStatusUpdate(bytes32 indexed id, bytes16 indexed uetr, string status, uint256 timestamp);
    event GPITrackerUpdate(bytes32 indexed id, bytes16 indexed uetr, string trackerEventCode, bytes32 eventData);

    modifier onlyAdmin() { require(msg.sender == admin, "ISO: not admin"); _; }
    constructor(address _admin) { require(_admin != address(0), "ISO: admin 0"); admin = _admin; }

    function transferAdmin(address to) public onlyAdmin { require(to != address(0), "ISO: 0"); emit AdminTransferred(admin, to); admin = to; }

    function bind(bytes32 id, bytes16 uetr, bytes32 payloadHash, bytes32 e2eIdHash) public onlyAdmin {
        bindings[id] = Binding({uetr: uetr, payloadHash: payloadHash, e2eIdHash: e2eIdHash, boundAt: uint64(block.timestamp)});
        emit IsoBound(id, uetr, payloadHash, e2eIdHash);
    }

    function emitMessage(bytes32 id, bytes16 uetr, string calldata messageType, bytes32 payloadHash) public onlyAdmin {
        // Stateless emission; indexers can correlate to other events by id/uetr
        emit IsoEvent(id, uetr, messageType, payloadHash);
    }
    
    /// @notice Emit SWIFT GPI payment status update
    function emitGPIStatus(bytes32 id, bytes16 uetr, string calldata status) public onlyAdmin {
        emit GPIPaymentStatusUpdate(id, uetr, status, block.timestamp);
    }
    
    /// @notice Emit SWIFT GPI tracker event
    function emitGPITracker(bytes32 id, bytes16 uetr, string calldata trackerEventCode, bytes32 eventData) public onlyAdmin {
        emit GPITrackerUpdate(id, uetr, trackerEventCode, eventData);
    }
}
