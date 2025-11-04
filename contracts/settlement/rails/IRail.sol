// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRail
 * @notice Generic interface for payment/settlement rails used by the SettlementHub.
 * A "rail" abstracts how value is escrowed and released (ERC20, native, external RTGS, etc.).
 */
interface IRail {
    enum Kind { ERC20, NATIVE, EXTERNAL }
    enum Status { NONE, PREPARED, RELEASED, REFUNDED, CANCELLED }

    struct Transfer {
        address asset;     // zero for native
        address from;      // source account (or initiator)
        address to;        // beneficiary
        uint256 amount;    // atomic unit of the asset
        bytes    metadata; // optional: ISO refs, memos, routing flags
    }

    function kind() external pure returns (Kind);
    function transferId(Transfer calldata t) external pure returns (bytes32);
    function prepare(Transfer calldata t) external payable;
    function release(bytes32 id, Transfer calldata t) external;
    function refund(bytes32 id, Transfer calldata t) external;
    function status(bytes32 id) external view returns (Status);

    event RailPrepared(bytes32 indexed id, address indexed from, address indexed to, address asset, uint256 amount);
    event RailReleased(bytes32 indexed id, address indexed to, address asset, uint256 amount);
    event RailRefunded(bytes32 indexed id, address indexed to, address asset, uint256 amount);
    event RailCancelled(bytes32 indexed id);
}
