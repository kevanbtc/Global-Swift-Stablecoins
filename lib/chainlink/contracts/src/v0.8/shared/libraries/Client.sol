// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Client {
    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    struct EVMExtraArgsV1 {
        uint256 gasLimit;
        bool strict;
    }

    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        bytes extraArgs;
        address feeToken;
    }

    function _argsToBytes(EVMExtraArgsV1 memory args) internal pure returns (bytes memory) {
        return abi.encode(args.gasLimit, args.strict);
    }
}
