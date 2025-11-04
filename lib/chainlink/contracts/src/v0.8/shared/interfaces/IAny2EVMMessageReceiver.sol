// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAny2EVMMessageReceiver {
    /// @notice handle an inbound message from any chain
    /// @dev Minimal placeholder for compilation only.
    function ccipReceive(bytes calldata data) external;
}
