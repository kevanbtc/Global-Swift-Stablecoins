// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

contract MockRouterClient is IRouterClient {
    uint256 public quotedFee;
    bytes32 public lastMessageId;
    uint64 public lastChainSelector;
    Client.EVM2AnyMessage public lastMessage;

    event Sent(bytes32 id, uint64 chain, address receiver);

    function setFee(uint256 fee) public { quotedFee = fee; }

    function getFee(uint64, Client.EVM2AnyMessage calldata) public view returns (uint256) {
        return quotedFee;
    }

    function isChainSupported(uint64) public pure returns (bool) { return true; }
    function isOfframp(uint64, address) public pure returns (bool) { return true; }

    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message) public payable
        returns (bytes32)
    {
        lastChainSelector = destinationChainSelector;
        lastMessage = message;
        lastMessageId = keccak256(abi.encode(msg.sender, destinationChainSelector, block.timestamp, msg.value));
        emit Sent(lastMessageId, destinationChainSelector, abi.decode(message.receiver, (address)));
        return lastMessageId;
    }
}
