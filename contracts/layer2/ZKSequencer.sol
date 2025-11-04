// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title ZKSequencer
 * @notice ZK-Rollup sequencer for scalable transaction processing
 * @dev Implements zero-knowledge proof verification and batch processing
 */
contract ZKSequencer is AccessControl, Pausable {
    using ECDSA for bytes32;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PROVER_ROLE = keccak256("PROVER_ROLE");

    struct ZKBatch {
        uint256 batchId;
        bytes32 previousBatchHash;
        bytes32 stateRoot;
        bytes32 transactionsHash;
        bytes32 withdrawalRoot;
        uint256 timestamp;
        bool verified;
        bytes proof;
    }

    struct ZKTransaction {
        bytes32 txHash;
        address from;
        address to;
        uint256 amount;
        uint256 nonce;
        bytes data;
        bytes signature;
    }

    struct VerifierConfig {
        address verifierContract;
        bytes32 verifierCodeHash;
        uint256 proofSize;
        bool active;
    }

    // State variables
    mapping(uint256 => ZKBatch) public batches;
    mapping(bytes32 => ZKTransaction) public transactions;
    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public processedWithdrawals;
    
    VerifierConfig public verifierConfig;
    
    uint256 public currentBatchId;
    bytes32 public currentStateRoot;
    uint256 public minTransactionsPerBatch;
    uint256 public maxTransactionsPerBatch;
    uint256 public batchTimeout;
    
    // Events
    event BatchSubmitted(
        uint256 indexed batchId,
        bytes32 stateRoot,
        bytes32 transactionsHash,
        uint256 timestamp
    );

    event BatchVerified(
        uint256 indexed batchId,
        bytes32 stateRoot,
        bytes32 withdrawalRoot
    );

    event TransactionProcessed(
        bytes32 indexed txHash,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event WithdrawalProcessed(
        bytes32 indexed withdrawalHash,
        address indexed recipient,
        uint256 amount
    );

    constructor(
        address _verifierContract,
        uint256 _minTxPerBatch,
        uint256 _maxTxPerBatch,
        uint256 _batchTimeout
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(PROVER_ROLE, msg.sender);

        verifierConfig = VerifierConfig({
            verifierContract: _verifierContract,
            verifierCodeHash: keccak256(new bytes(0)),
            proofSize: 0,
            active: false
        });

        minTransactionsPerBatch = _minTxPerBatch;
        maxTransactionsPerBatch = _maxTxPerBatch;
        batchTimeout = _batchTimeout;
    }

    /**
     * @notice Submit a new transaction for inclusion in the next batch
     * @param to Recipient address
     * @param amount Transaction amount
     * @param data Additional transaction data
     */
    function submitTransaction(
        address to,
        uint256 amount,
        bytes calldata data
    )
        external
        whenNotPaused
        returns (bytes32)
    {
        uint256 nonce = nonces[msg.sender]++;
        
        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            to,
            amount,
            nonce,
            data
        ));
        
        bytes memory signature = msg.data[msg.data.length-65:];
        
        transactions[txHash] = ZKTransaction({
            txHash: txHash,
            from: msg.sender,
            to: to,
            amount: amount,
            nonce: nonce,
            data: data,
            signature: signature
        });
        
        emit TransactionProcessed(txHash, msg.sender, to, amount);
        
        return txHash;
    }

    /**
     * @notice Submit a new batch with zero-knowledge proof
     * @param transactionHashes Transaction hashes in the batch
     * @param newStateRoot New state root after batch processing
     * @param withdrawalRoot Merkle root of withdrawals
     * @param proof Zero-knowledge proof
     */
    function submitBatch(
        bytes32[] calldata transactionHashes,
        bytes32 newStateRoot,
        bytes32 withdrawalRoot,
        bytes calldata proof
    )
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        require(
            transactionHashes.length >= minTransactionsPerBatch,
            "Batch too small"
        );
        require(
            transactionHashes.length <= maxTransactionsPerBatch,
            "Batch too large"
        );
        require(verifierConfig.active, "Verifier not configured");
        require(proof.length == verifierConfig.proofSize, "Invalid proof size");
        
        bytes32 txHash = keccak256(abi.encodePacked(transactionHashes));
        
        ZKBatch memory batch = ZKBatch({
            batchId: currentBatchId++,
            previousBatchHash: keccak256(abi.encodePacked(currentStateRoot)),
            stateRoot: newStateRoot,
            transactionsHash: txHash,
            withdrawalRoot: withdrawalRoot,
            timestamp: block.timestamp,
            verified: false,
            proof: proof
        });
        
        batches[batch.batchId] = batch;
        
        emit BatchSubmitted(
            batch.batchId,
            newStateRoot,
            txHash,
            block.timestamp
        );
    }

    /**
     * @notice Verify a batch using its zero-knowledge proof
     * @param batchId Batch identifier
     */
    function verifyBatch(uint256 batchId)
        external
        onlyRole(PROVER_ROLE)
        whenNotPaused
    {
        ZKBatch storage batch = batches[batchId];
        require(batch.timestamp > 0, "Batch not found");
        require(!batch.verified, "Already verified");
        
        // Call the verifier contract
        (bool success, bytes memory result) = verifierConfig.verifierContract.call(
            abi.encodeWithSignature(
                "verifyProof(bytes,bytes32,bytes32,bytes32)",
                batch.proof,
                batch.previousBatchHash,
                batch.stateRoot,
                batch.withdrawalRoot
            )
        );
        
        require(success && abi.decode(result, (bool)), "Proof verification failed");
        
        batch.verified = true;
        currentStateRoot = batch.stateRoot;
        
        emit BatchVerified(
            batchId,
            batch.stateRoot,
            batch.withdrawalRoot
        );
    }

    /**
     * @notice Process a withdrawal
     * @param withdrawalHash Hash of the withdrawal
     * @param recipient Recipient address
     * @param amount Withdrawal amount
     * @param proof Merkle proof
     */
    function processWithdrawal(
        bytes32 withdrawalHash,
        address recipient,
        uint256 amount,
        bytes32[] calldata proof
    )
        external
        whenNotPaused
    {
        require(!processedWithdrawals[withdrawalHash], "Already processed");
        require(
            verifyMerkleProof(proof, currentStateRoot, withdrawalHash),
            "Invalid proof"
        );
        
        processedWithdrawals[withdrawalHash] = true;
        
        // Process the withdrawal (implement transfer logic)
        // This is a placeholder for the actual transfer implementation
        
        emit WithdrawalProcessed(withdrawalHash, recipient, amount);
    }

    /**
     * @notice Update verifier configuration
     * @param verifier New verifier contract address
     * @param codeHash Verifier contract code hash
     * @param proofSize Expected proof size
     */
    function updateVerifier(
        address verifier,
        bytes32 codeHash,
        uint256 proofSize
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        verifierConfig = VerifierConfig({
            verifierContract: verifier,
            verifierCodeHash: codeHash,
            proofSize: proofSize,
            active: true
        });
    }

    /**
     * @notice Verify a Merkle proof
     * @param proof Merkle proof
     * @param root Merkle root
     * @param leaf Leaf node to verify
     */
    function verifyMerkleProof(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    )
        internal
        pure
        returns (bool)
    {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (computedHash < proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }

    /**
     * @notice Get batch details
     * @param batchId Batch identifier
     */
    function getBatch(uint256 batchId)
        external
        view
        returns (ZKBatch memory)
    {
        require(batches[batchId].timestamp > 0, "Batch not found");
        return batches[batchId];
    }

    /**
     * @notice Get transaction details
     * @param txHash Transaction hash
     */
    function getTransaction(bytes32 txHash)
        external
        view
        returns (ZKTransaction memory)
    {
        require(transactions[txHash].nonce > 0, "Transaction not found");
        return transactions[txHash];
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}