// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAttestationOracle {
    /// @dev Structured reserve attestation for a date/epoch
    struct ReserveReport {
        bytes32 reserveId;         // e.g. keccak256("USDC_TREASURY_RESERVE")
        uint256 timestamp;         // when the proof was signed (unix)
        uint256 totalLiabilities;  // outstanding tokens/claims (in smallest units)
        uint256 totalReserves;     // backing value (in smallest units)
        string  uri;               // off-chain report or IPFS CID
        bytes   auditorSig;        // optional auditor signature (EIP-191/EIP-712)
    }

    function latest(bytes32 reserveId) external view returns (ReserveReport memory ok, bool exists);

    function hasQuorum(bytes32 reserveId) external view returns (bool);
}
