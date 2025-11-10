// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IMidnightProofVerifier
 * @notice Interface for Zero-Knowledge proof verification compatible with Midnight.js
 * @dev Implements ZK-SNARK proof verification for private transactions
 */
interface IMidnightProofVerifier {
    /**
     * @notice Verify a ZK-SNARK proof (Groth16)
     * @param a G1 point 'a' from proof
     * @param b G2 point 'b' from proof  
     * @param c G1 point 'c' from proof
     * @param publicInputs Public circuit inputs
     * @return bool True if proof is valid
     */
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata publicInputs
    ) external view returns (bool);

    /**
     * @notice Verify a batched ZK proof (multiple proofs in one)
     * @param proofs Array of encoded proofs
     * @param publicInputs Array of public inputs for each proof
     * @return bool True if all proofs are valid
     */
    function verifyBatchProof(
        bytes[] calldata proofs,
        uint256[][] calldata publicInputs
    ) external view returns (bool);

    /**
     * @notice Get verifier version/type
     * @return string Verifier identifier (e.g., "Groth16", "PLONK")
     */
    function verifierType() external pure returns (string memory);

    /**
     * @notice Check if verifier supports a specific circuit
     * @param circuitId Identifier for the circuit
     * @return bool True if circuit is supported
     */
    function supportsCircuit(bytes32 circuitId) external view returns (bool);

    /**
     * @notice Get verification key hash for a circuit
     * @param circuitId Circuit identifier
     * @return bytes32 Hash of the verification key
     */
    function getVerificationKeyHash(bytes32 circuitId) external view returns (bytes32);

    /**
     * @notice Event emitted when a proof is verified
     */
    event ProofVerified(
        bytes32 indexed proofHash,
        address indexed verifier,
        bool valid,
        uint256 timestamp
    );

    /**
     * @notice Event emitted when a new circuit is registered
     */
    event CircuitRegistered(
        bytes32 indexed circuitId,
        bytes32 vkHash,
        uint256 timestamp
    );
}
