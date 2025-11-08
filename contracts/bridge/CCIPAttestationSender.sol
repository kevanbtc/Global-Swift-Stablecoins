// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/// @title CCIP Attestation Sender
/// @notice Sends cross-chain attestations via Chainlink CCIP
contract CCIPAttestationSender is AccessControl, ReentrancyGuard {
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");
    
    IRouterClient private immutable i_router;
    mapping(uint64 => bool) public supportedChains;
    mapping(bytes32 => bool) public processedMessages;

    // Allowed receivers per destination chain
    mapping(uint64 => mapping(address => bool)) public allowedReceivers;

    // Simple global rate limit per destination chain
    struct RateCfg { uint64 windowSeconds; uint32 limit; }
    struct RateUse { uint64 windowStart; uint32 used; }
    mapping(uint64 => RateCfg) public rateCfg;
    mapping(uint64 => RateUse) private rateUse;

    struct AttestationMessage {
        address subject;          // Address being attested
        bytes32 schemaId;        // Schema identifier
        bytes32 attestationId;   // Unique attestation identifier
        bytes data;              // Attestation data
    }

    event AttestationSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed subject,
        bytes32 schemaId,
        bytes32 attestationId
    );

    event ChainSupported(uint64 chainSelector, bool supported);
    event ReceiverAllowed(uint64 chainSelector, address receiver, bool allowed);
    event RateLimitSet(uint64 chainSelector, uint64 windowSeconds, uint32 limit);

    constructor(address router) {
        require(router != address(0), "Invalid router address");
        i_router = IRouterClient(router);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ATTESTOR_ROLE, msg.sender);
    }

    /// @notice Sets whether a chain is supported for sending attestations
    function setSupportedChain(uint64 chainSelector, bool supported) public onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        supportedChains[chainSelector] = supported;
        emit ChainSupported(chainSelector, supported);
    }

    /// @notice Allow or block a specific receiver for a chain
    function setAllowedReceiver(uint64 chainSelector, address receiver, bool allowed) public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        allowedReceivers[chainSelector][receiver] = allowed;
        emit ReceiverAllowed(chainSelector, receiver, allowed);
    }

    /// @notice Configure simple global rate limit for a destination chain
    function setRateLimit(uint64 chainSelector, uint64 windowSeconds, uint32 limit) public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rateCfg[chainSelector] = RateCfg({windowSeconds: windowSeconds, limit: limit});
        emit RateLimitSet(chainSelector, windowSeconds, limit);
    }

    function _consumeRate(uint64 chainSelector) internal {
        RateCfg memory cfg = rateCfg[chainSelector];
        if (cfg.windowSeconds == 0 || cfg.limit == 0) return; // disabled
        RateUse storage u = rateUse[chainSelector];
        uint64 nowTs = uint64(block.timestamp);
        if (u.windowStart == 0 || nowTs - u.windowStart >= cfg.windowSeconds) {
            u.windowStart = nowTs; u.used = 0;
        }
        require(u.used < cfg.limit, "rate limit");
        unchecked { u.used += 1; }
    }

    /// @notice Sends an attestation to another chain via CCIP
    function sendAttestation(
        uint64 destinationChainSelector,
        address receiver,
        address subject,
        bytes32 schemaId,
        bytes32 attestationId,
        bytes calldata data
    ) public payable 
        onlyRole(ATTESTOR_ROLE) 
        nonReentrant 
    {
        require(supportedChains[destinationChainSelector], "Unsupported chain");
        require(receiver != address(0), "Invalid receiver");
        require(allowedReceivers[destinationChainSelector][receiver], "receiver not allowed");
        _consumeRate(destinationChainSelector);
        
        AttestationMessage memory message = AttestationMessage({
            subject: subject,
            schemaId: schemaId,
            attestationId: attestationId,
            data: data
        });

        bytes memory ccipMessage = abi.encode(message);
        
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: ccipMessage,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000})
            ),
            feeToken: address(0)  // Use native gas token
        });

        // Quote fee and ensure sufficient funds were provided (best-effort, router may refund excess)
        {
            uint256 fee = i_router.getFee(destinationChainSelector, evm2AnyMessage);
            require(msg.value >= fee, "insufficient fee");
        }

        bytes32 messageId = i_router.ccipSend{value: msg.value}(
            destinationChainSelector,
            evm2AnyMessage
        );

        processedMessages[messageId] = true;
        
        emit AttestationSent(
            messageId,
            destinationChainSelector,
            subject,
            schemaId,
            attestationId
        );
    }

    /// @notice Returns the fee required to send an attestation
    function getFee(
        uint64 destinationChainSelector,
        address receiver,
        AttestationMessage memory message
    ) public view returns (uint256) {
        require(supportedChains[destinationChainSelector], "Unsupported chain");
        
        bytes memory ccipMessage = abi.encode(message);
        
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: ccipMessage,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000})
            ),
            feeToken: address(0)
        });

        return i_router.getFee(
            destinationChainSelector,
            evm2AnyMessage
        );
    }

    /// @notice Allows contract to receive native token for CCIP fees
    receive() external payable {}
}
