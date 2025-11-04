// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title DNASequencer
 * @notice Sequencer for managing transactions and state transitions
 * @dev Implements sequencing and ordering for transactions
 */
contract DNASequencer is AccessControl, Pausable {
    using ECDSA for bytes32;

    bytes32 public constant SEQUENCER_ROLE = keccak256("SEQUENCER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    
    // Batch configuration
    uint256 public constant MAX_BATCH_SIZE = 1000;
    uint256 public constant MIN_BATCH_SIZE = 10;
    uint256 public constant MAX_BATCH_DELAY = 1 hours;
    
    struct Batch {
        uint256 batchId;
        bytes32[] transactionHashes;
        bytes32 stateRoot;
        bytes32 parentBatch;
        uint256 timestamp;
        bool executed;
        mapping(address => bool) confirmations;
        uint256 confirmationCount;
    }
    
    struct Transaction {
        bytes32 txHash;
        address sender;
        bytes data;
        uint256 nonce;
        uint256 timestamp;
        bool executed;
    }
    
    // State variables
    mapping(bytes32 => Batch) public batches;
    mapping(bytes32 => Transaction) public transactions;
    mapping(address => uint256) public nonces;
    
    uint256 public currentBatchId;
    bytes32 public currentBatch;
    uint256 public lastBatchTimestamp;
    
    // Events
    event TransactionSubmitted(
        bytes32 indexed txHash,
        address indexed sender,
        uint256 nonce
    );
    event BatchCreated(
        bytes32 indexed batchId,
        uint256 size,
        bytes32 stateRoot
    );
    event BatchConfirmed(
        bytes32 indexed batchId,
        address indexed sequencer
    );
    event BatchExecuted(
        bytes32 indexed batchId,
        uint256 timestamp
    );
    event TransactionExecuted(
        bytes32 indexed txHash,
        bool success
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SEQUENCER_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
    }

    /**
     * @notice Submit a transaction for sequencing
     * @param data Transaction data
     */
    function submitTransaction(bytes memory data)
        external
        whenNotPaused
        returns (bytes32)
    {
        uint256 nonce = nonces[msg.sender]++;
        
        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            data,
            nonce,
            block.timestamp
        ));
        
        transactions[txHash] = Transaction({
            txHash: txHash,
            sender: msg.sender,
            data: data,
            nonce: nonce,
            timestamp: block.timestamp,
            executed: false
        });
        
        emit TransactionSubmitted(txHash, msg.sender, nonce);
        
        return txHash;
    }

    /**
     * @notice Create a new batch of transactions
     * @param txHashes Transaction hashes to include
     * @param stateRoot State root after batch execution
     */
    function createBatch(bytes32[] memory txHashes, bytes32 stateRoot)
        external
        onlyRole(SEQUENCER_ROLE)
        whenNotPaused
    {
        require(txHashes.length >= MIN_BATCH_SIZE, "Batch too small");
        require(txHashes.length <= MAX_BATCH_SIZE, "Batch too large");
        require(
            block.timestamp >= lastBatchTimestamp + MAX_BATCH_DELAY,
            "Too soon"
        );
        
        bytes32 batchId = keccak256(abi.encodePacked(
            currentBatchId++,
            txHashes,
            stateRoot
        ));
        
        Batch storage batch = batches[batchId];
        batch.batchId = currentBatchId;
        batch.transactionHashes = txHashes;
        batch.stateRoot = stateRoot;
        batch.parentBatch = currentBatch;
        batch.timestamp = block.timestamp;
        batch.executed = false;
        batch.confirmationCount = 0;
        
        currentBatch = batchId;
        lastBatchTimestamp = block.timestamp;
        
        emit BatchCreated(batchId, txHashes.length, stateRoot);
    }

    /**
     * @notice Confirm a batch
     * @param batchId Batch identifier
     */
    function confirmBatch(bytes32 batchId)
        external
        onlyRole(SEQUENCER_ROLE)
        whenNotPaused
    {
        Batch storage batch = batches[batchId];
        require(batch.timestamp > 0, "Batch not found");
        require(!batch.executed, "Already executed");
        require(!batch.confirmations[msg.sender], "Already confirmed");
        
        batch.confirmations[msg.sender] = true;
        batch.confirmationCount++;
        
        emit BatchConfirmed(batchId, msg.sender);
    }

    /**
     * @notice Execute a batch of transactions
     * @param batchId Batch identifier
     */
    function executeBatch(bytes32 batchId)
        external
        onlyRole(EXECUTOR_ROLE)
        whenNotPaused
    {
        Batch storage batch = batches[batchId];
        require(batch.timestamp > 0, "Batch not found");
        require(!batch.executed, "Already executed");
        require(
            batch.confirmationCount >= getRoleMemberCount(SEQUENCER_ROLE) / 2 + 1,
            "Insufficient confirmations"
        );
        
        batch.executed = true;
        
        for (uint256 i = 0; i < batch.transactionHashes.length; i++) {
            bytes32 txHash = batch.transactionHashes[i];
            Transaction storage tx = transactions[txHash];
            
            if (!tx.executed) {
                tx.executed = true;
                (bool success,) = tx.sender.call(tx.data);
                emit TransactionExecuted(txHash, success);
            }
        }
        
        emit BatchExecuted(batchId, block.timestamp);
    }

    /**
     * @notice Get batch details
     * @param batchId Batch identifier
     */
    function getBatch(bytes32 batchId)
        external
        view
        returns (
            uint256 id,
            bytes32[] memory txHashes,
            bytes32 stateRoot,
            bytes32 parentBatch,
            uint256 timestamp,
            bool executed,
            uint256 confirmations
        )
    {
        Batch storage batch = batches[batchId];
        require(batch.timestamp > 0, "Batch not found");
        
        return (
            batch.batchId,
            batch.transactionHashes,
            batch.stateRoot,
            batch.parentBatch,
            batch.timestamp,
            batch.executed,
            batch.confirmationCount
        );
    }

    /**
     * @notice Get transaction details
     * @param txHash Transaction hash
     */
    function getTransaction(bytes32 txHash)
        external
        view
        returns (
            address sender,
            bytes memory data,
            uint256 nonce,
            uint256 timestamp,
            bool executed
        )
    {
        Transaction storage tx = transactions[txHash];
        require(tx.timestamp > 0, "Transaction not found");
        
        return (
            tx.sender,
            tx.data,
            tx.nonce,
            tx.timestamp,
            tx.executed
        );
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}