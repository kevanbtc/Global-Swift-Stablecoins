// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRouterClient} from "lib/chainlink/contracts/src/v0.8/shared/interfaces/IRouterClient.sol";
import {Client} from "lib/chainlink/contracts/src/v0.8/shared/libraries/Client.sol";

/// @title CcipDistributor
/// @notice Minimal CCIP sender for distribution messages (e.g., mint/redeem instructions) to remote receivers.
contract CcipDistributor is AccessControl, ReentrancyGuard {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    IRouterClient private immutable i_router;
    mapping(uint64 => bool) public supportedChains;
    mapping(uint64 => mapping(address => bool)) public allowedReceivers;

    event ChainSupported(uint64 chainSelector, bool supported);
    event ReceiverAllowed(uint64 chainSelector, address receiver, bool allowed);
    event Sent(bytes32 msgId, uint64 dst, address receiver, bytes payload);

    constructor(address router, address admin) {
        require(router != address(0), "router");
        i_router = IRouterClient(router);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, admin);
    }

    function setSupportedChain(uint64 chainSelector, bool supported) external onlyRole(GOVERNOR_ROLE) {
        supportedChains[chainSelector] = supported;
        emit ChainSupported(chainSelector, supported);
    }

    function setAllowedReceiver(uint64 chainSelector, address receiver, bool allowed) external onlyRole(GOVERNOR_ROLE) {
        allowedReceivers[chainSelector][receiver] = allowed;
        emit ReceiverAllowed(chainSelector, receiver, allowed);
    }

    function send(uint64 dstChain, address receiver, bytes calldata payload)
        external
        payable
        onlyRole(GOVERNOR_ROLE)
        nonReentrant
        returns (bytes32)
    {
        require(supportedChains[dstChain], "chain");
        require(allowedReceivers[dstChain][receiver], "recv");

        Client.EVM2AnyMessage memory m = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 300_000, strict: false})),
            feeToken: address(0)
        });

        uint256 fee = i_router.getFee(dstChain, m);
        require(msg.value >= fee, "fee");
        bytes32 id_ = i_router.ccipSend{value: msg.value}(dstChain, m);
        emit Sent(id_, dstChain, receiver, payload);
        return id_;
    }

    receive() external payable {}
}
