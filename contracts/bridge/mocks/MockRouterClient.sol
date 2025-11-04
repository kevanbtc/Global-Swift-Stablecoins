// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "lib/chainlink/contracts/src/v0.8/shared/interfaces/IRouterClient.sol";
import {Client} from "lib/chainlink/contracts/src/v0.8/shared/libraries/Client.sol";

contract MockRouterClient is IRouterClient {
    uint256 public quotedFee;
    bytes32 public lastMessageId;
    uint64 public lastChainSelector;
    Client.EVM2AnyMessage public lastMessage;

    event Sent(bytes32 id, uint64 chain, address receiver);

    function setFee(uint256 fee) external { quotedFee = fee; }

    function getFee(uint64, Client.EVM2AnyMessage calldata) external view returns (uint256) {
        return quotedFee;
    }

    function isChainSupported(uint64) external pure returns (bool) { return true; }
    function isOfframp(uint64, address) external pure returns (bool) { return true; }

    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32)
    {
        lastChainSelector = destinationChainSelector;
        lastMessage = message;
        lastMessageId = keccak256(abi.encode(msg.sender, destinationChainSelector, block.timestamp, msg.value));
        emit Sent(lastMessageId, destinationChainSelector, abi.decode(message.receiver, (address)));
        return lastMessageId;
    }
}
