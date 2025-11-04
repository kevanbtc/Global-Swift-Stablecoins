// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Client} from "../libraries/Client.sol";

interface IRouterClient {
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32);

    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        view
        returns (uint256);
}
