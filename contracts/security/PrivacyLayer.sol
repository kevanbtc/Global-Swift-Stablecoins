// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title PrivacyLayer
 * @notice Enhanced privacy layer for CBDC transactions
 * @dev Implements stealth addresses and confidential transactions
 */
contract PrivacyLayer is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;
    using Counters for Counters.Counter;

    bytes32 public constant PRIVACY_ADMIN_ROLE = keccak256("PRIVACY_ADMIN_ROLE");
    bytes32 public constant MIXER_ROLE = keccak256("MIXER_ROLE");

    enum CommitmentState {
        Pending,    // Commitment created but not used
        Active,     // Commitment in active use
        Spent,      // Commitment has been spent
        Revoked    // Commitment has been revoked
    }

    struct Commitment {
        bytes32 commitmentHash;
        uint256 amount;
        address owner;
        uint256 timestamp;
        CommitmentState state;
        bytes metadata;
    }

    struct StealthAddress {
        address publicAddress;
        bytes32 viewKey;
        bytes32 spendKey;
        uint256 nonce;
        bool active;
    }

    struct ConfidentialTransaction {
        bytes32 txHash;
        bytes32[] inputCommitments;
        bytes32[] outputCommitments;
        bytes proof;
        uint256 timestamp;
        bool verified;
    }

    // State variables
    mapping(bytes32 => Commitment) public commitments;
    mapping(address => mapping(bytes32 => StealthAddress)) public stealthAddresses;
    mapping(bytes32 => ConfidentialTransaction) public transactions;
    mapping(address => Counters.Counter) private nonces;
    
    uint256 public constant MIN_MIXING_DELAY = 1 hours;
    uint256 public constant MAX_COMMITMENT_AGE = 30 days;
    
    // Events
    event CommitmentCreated(
        bytes32 indexed commitmentHash,
        uint256 amount,
        address indexed owner
    );

    event CommitmentSpent(
        bytes32 indexed commitmentHash,
        bytes32 indexed txHash
    );

    event StealthAddressCreated(
        address indexed owner,
        bytes32 indexed viewKey
    );

    event ConfidentialTransactionCreated(
        bytes32 indexed txHash,
        uint256 timestamp
    );

    event PrivacyProofVerified(
        bytes32 indexed txHash,
        bool success
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PRIVACY_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Create a new commitment
     * @param amount Amount to commit
     * @param metadata Additional encrypted metadata
     */
    function createCommitment(uint256 amount, bytes calldata metadata)
        external
        nonReentrant
        returns (bytes32)
    {
        require(amount > 0, "Invalid amount");
        
        bytes32 commitmentHash = keccak256(abi.encodePacked(
            msg.sender,
            amount,
            metadata,
            _incrementNonce(msg.sender)
        ));
        
        commitments[commitmentHash] = Commitment({
            commitmentHash: commitmentHash,
            amount: amount,
            owner: msg.sender,
            timestamp: block.timestamp,
            state: CommitmentState.Pending,
            metadata: metadata
        });
        
        emit CommitmentCreated(commitmentHash, amount, msg.sender);
        
        return commitmentHash;
    }

    /**
     * @notice Create a new stealth address
     * @param viewKey Public view key
     * @param spendKey Public spend key
     */
    function createStealthAddress(bytes32 viewKey, bytes32 spendKey)
        external
        returns (address)
    {
        require(viewKey != bytes32(0), "Invalid view key");
        require(spendKey != bytes32(0), "Invalid spend key");
        
        address stealthAddr = address(uint160(uint256(keccak256(abi.encodePacked(
            msg.sender,
            viewKey,
            spendKey,
            _incrementNonce(msg.sender)
        )))));
        
        stealthAddresses[msg.sender][viewKey] = StealthAddress({
            publicAddress: stealthAddr,
            viewKey: viewKey,
            spendKey: spendKey,
            nonce: nonces[msg.sender].current(),
            active: true
        });
        
        emit StealthAddressCreated(msg.sender, viewKey);
        
        return stealthAddr;
    }

    /**
     * @notice Create a confidential transaction
     * @param inputCommitments Input commitment hashes
     * @param outputCommitments Output commitment hashes
     * @param proof Zero-knowledge proof
     */
    function createConfidentialTransaction(
        bytes32[] calldata inputCommitments,
        bytes32[] calldata outputCommitments,
        bytes calldata proof
    )
        external
        nonReentrant
        returns (bytes32)
    {
        require(inputCommitments.length > 0, "No inputs");
        require(outputCommitments.length > 0, "No outputs");
        require(proof.length > 0, "Invalid proof");
        
        // Verify input commitments
        uint256 totalInput = 0;
        for (uint256 i = 0; i < inputCommitments.length; i++) {
            Commitment storage commitment = commitments[inputCommitments[i]];
            require(
                commitment.state == CommitmentState.Active,
                "Invalid input commitment"
            );
            require(
                commitment.owner == msg.sender,
                "Not commitment owner"
            );
            totalInput = totalInput + commitment.amount;
        }
        
        // Verify output commitments
        uint256 totalOutput = 0;
        for (uint256 i = 0; i < outputCommitments.length; i++) {
            Commitment storage commitment = commitments[outputCommitments[i]];
            require(
                commitment.state == CommitmentState.Pending,
                "Invalid output commitment"
            );
            totalOutput = totalOutput + commitment.amount;
        }
        
        require(totalInput == totalOutput, "Amount mismatch");
        
        bytes32 txHash = keccak256(abi.encodePacked(
            inputCommitments,
            outputCommitments,
            proof,
            block.timestamp
        ));
        
        transactions[txHash] = ConfidentialTransaction({
            txHash: txHash,
            inputCommitments: inputCommitments,
            outputCommitments: outputCommitments,
            proof: proof,
            timestamp: block.timestamp,
            verified: false
        });
        
        emit ConfidentialTransactionCreated(txHash, block.timestamp);
        
        return txHash;
    }

    /**
     * @notice Verify a confidential transaction
     * @param txHash Transaction hash
     */
    function verifyTransaction(bytes32 txHash)
        external
        onlyRole(MIXER_ROLE)
    {
        ConfidentialTransaction storage tx = transactions[txHash];
        require(tx.timestamp > 0, "Transaction not found");
        require(!tx.verified, "Already verified");
        
        // Verify the zero-knowledge proof
        bool proofValid = _verifyZKProof(
            tx.inputCommitments,
            tx.outputCommitments,
            tx.proof
        );
        
        require(proofValid, "Invalid proof");
        
        // Update commitment states
        for (uint256 i = 0; i < tx.inputCommitments.length; i++) {
            commitments[tx.inputCommitments[i]].state = CommitmentState.Spent;
            emit CommitmentSpent(tx.inputCommitments[i], txHash);
        }
        
        for (uint256 i = 0; i < tx.outputCommitments.length; i++) {
            commitments[tx.outputCommitments[i]].state = CommitmentState.Active;
        }
        
        tx.verified = true;
        
        emit PrivacyProofVerified(txHash, true);
    }

    /**
     * @notice Verify a zero-knowledge proof
     * @param inputs Input commitment hashes
     * @param outputs Output commitment hashes
     * @param proof Zero-knowledge proof
     */
    function _verifyZKProof(
        bytes32[] memory inputs,
        bytes32[] memory outputs,
        bytes memory proof
    )
        internal
        pure
        returns (bool)
    {
        // This is a placeholder for actual ZK proof verification
        // In practice, this would implement a specific ZK proving system
        // such as Groth16, Plonk, or other suitable protocol
        return true;
    }

    /**
     * @notice Increment and return nonce for an address
     * @param account Account address
     */
    function _incrementNonce(address account)
        internal
        returns (uint256)
    {
        nonces[account].increment();
        return nonces[account].current();
    }

    /**
     * @notice Get commitment details
     * @param commitmentHash Commitment hash
     */
    function getCommitment(bytes32 commitmentHash)
        external
        view
        returns (Commitment memory)
    {
        return commitments[commitmentHash];
    }

    /**
     * @notice Get transaction details
     * @param txHash Transaction hash
     */
    function getTransaction(bytes32 txHash)
        external
        view
        returns (ConfidentialTransaction memory)
    {
        return transactions[txHash];
    }

    /**
     * @notice Get stealth address details
     * @param owner Owner address
     * @param viewKey View key
     */
    function getStealthAddress(address owner, bytes32 viewKey)
        external
        view
        returns (StealthAddress memory)
    {
        return stealthAddresses[owner][viewKey];
    }

    /**
     * @notice Revoke a commitment
     * @param commitmentHash Commitment hash
     */
    function revokeCommitment(bytes32 commitmentHash)
        external
        onlyRole(PRIVACY_ADMIN_ROLE)
    {
        Commitment storage commitment = commitments[commitmentHash];
        require(commitment.timestamp > 0, "Commitment not found");
        require(
            commitment.state == CommitmentState.Active ||
            commitment.state == CommitmentState.Pending,
            "Invalid state"
        );
        
        commitment.state = CommitmentState.Revoked;
    }
}