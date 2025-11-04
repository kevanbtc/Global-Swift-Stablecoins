// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title OptimisticSequencer
 * @notice Optimistic rollup sequencer with fraud proof system
 * @dev Implements optimistic execution with challenge-response mechanism
 */
contract OptimisticSequencer is AccessControl, Pausable {
    using ECDSA for bytes32;

    bytes32 public constant SEQUENCER_ROLE = keccak256("SEQUENCER_ROLE");
    bytes32 public constant CHALLENGER_ROLE = keccak256("CHALLENGER_ROLE");

    struct Batch {
        uint256 batchId;
        bytes32 parentHash;
        bytes32 stateRoot;
        bytes32 transactionsHash;
        uint256 timestamp;
        address sequencer;
        bool challenged;
        bool finalized;
        uint256 challengeEndTime;
    }

    struct Challenge {
        uint256 batchId;
        address challenger;
        bytes32 assertedStateRoot;
        uint256 bond;
        uint256 timestamp;
        bool resolved;
        bool fraudProven;
    }

    struct Transaction {
        bytes32 txHash;
        address from;
        address to;
        uint256 amount;
        uint256 nonce;
        bytes data;
    }

    // Constants
    uint256 public constant CHALLENGE_PERIOD = 7 days;
    uint256 public constant CHALLENGER_BOND = 100 ether;
    uint256 public constant SEQUENCER_BOND = 1000 ether;
    
    // State variables
    mapping(uint256 => Batch) public batches;
    mapping(bytes32 => Transaction) public transactions;
    mapping(uint256 => Challenge) public challenges;
    mapping(address => uint256) public nonces;
    mapping(address => uint256) public bonds;
    
    uint256 public currentBatchId;
    bytes32 public currentStateRoot;
    uint256 public minTransactionsPerBatch;
    uint256 public maxTransactionsPerBatch;
    
    // Events
    event BatchSubmitted(
        uint256 indexed batchId,
        address indexed sequencer,
        bytes32 stateRoot
    );

    event BatchChallenged(
        uint256 indexed batchId,
        address indexed challenger,
        bytes32 assertedStateRoot
    );

    event ChallengeResolved(
        uint256 indexed batchId,
        bool fraudProven,
        address winner
    );

    event BatchFinalized(
        uint256 indexed batchId,
        bytes32 stateRoot
    );

    constructor(
        uint256 _minTxPerBatch,
        uint256 _maxTxPerBatch
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SEQUENCER_ROLE, msg.sender);
        _grantRole(CHALLENGER_ROLE, msg.sender);

        minTransactionsPerBatch = _minTxPerBatch;
        maxTransactionsPerBatch = _maxTxPerBatch;
    }

    /**
     * @notice Deposit bond for sequencing or challenging
     */
    function depositBond() external payable whenNotPaused {
        bonds[msg.sender] += msg.value;
    }

    /**
     * @notice Withdraw available bond
     * @param amount Amount to withdraw
     */
    function withdrawBond(uint256 amount) external whenNotPaused {
        require(bonds[msg.sender] >= amount, "Insufficient bond");
        require(
            !hasUnresolvedChallenges(msg.sender),
            "Has unresolved challenges"
        );
        
        bonds[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    /**
     * @notice Submit a transaction for inclusion in the next batch
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
        
        transactions[txHash] = Transaction({
            txHash: txHash,
            from: msg.sender,
            to: to,
            amount: amount,
            nonce: nonce,
            data: data
        });
        
        return txHash;
    }

    /**
     * @notice Submit a new batch
     * @param transactionHashes Transaction hashes in the batch
     * @param newStateRoot New state root after batch processing
     */
    function submitBatch(
        bytes32[] calldata transactionHashes,
        bytes32 newStateRoot
    )
        external
        onlyRole(SEQUENCER_ROLE)
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
        require(
            bonds[msg.sender] >= SEQUENCER_BOND,
            "Insufficient sequencer bond"
        );
        
        bytes32 txHash = keccak256(abi.encodePacked(transactionHashes));
        
        Batch memory batch = Batch({
            batchId: currentBatchId++,
            parentHash: keccak256(abi.encodePacked(currentStateRoot)),
            stateRoot: newStateRoot,
            transactionsHash: txHash,
            timestamp: block.timestamp,
            sequencer: msg.sender,
            challenged: false,
            finalized: false,
            challengeEndTime: block.timestamp + CHALLENGE_PERIOD
        });
        
        batches[batch.batchId] = batch;
        
        emit BatchSubmitted(
            batch.batchId,
            msg.sender,
            newStateRoot
        );
    }

    /**
     * @notice Challenge a batch with fraud proof
     * @param batchId Batch identifier
     * @param assertedStateRoot Correct state root
     * @param proof Fraud proof data
     */
    function challengeBatch(
        uint256 batchId,
        bytes32 assertedStateRoot,
        bytes calldata proof
    )
        external
        onlyRole(CHALLENGER_ROLE)
        whenNotPaused
    {
        require(
            bonds[msg.sender] >= CHALLENGER_BOND,
            "Insufficient challenger bond"
        );
        
        Batch storage batch = batches[batchId];
        require(batch.timestamp > 0, "Batch not found");
        require(!batch.finalized, "Batch already finalized");
        require(!batch.challenged, "Already challenged");
        require(
            block.timestamp <= batch.challengeEndTime,
            "Challenge period ended"
        );
        
        batch.challenged = true;
        
        challenges[batchId] = Challenge({
            batchId: batchId,
            challenger: msg.sender,
            assertedStateRoot: assertedStateRoot,
            bond: CHALLENGER_BOND,
            timestamp: block.timestamp,
            resolved: false,
            fraudProven: false
        });
        
        bonds[msg.sender] -= CHALLENGER_BOND;
        
        emit BatchChallenged(batchId, msg.sender, assertedStateRoot);
        
        // Verify the fraud proof
        verifyFraudProof(batchId, proof);
    }

    /**
     * @notice Verify a fraud proof and resolve challenge
     * @param batchId Batch identifier
     * @param proof Fraud proof data
     */
    function verifyFraudProof(uint256 batchId, bytes calldata proof)
        internal
    {
        Batch storage batch = batches[batchId];
        Challenge storage challenge = challenges[batchId];
        
        // This is a placeholder for actual fraud proof verification
        // In a real implementation, this would:
        // 1. Replay the disputed transaction
        // 2. Compare the results with the provided proof
        // 3. Determine if fraud occurred
        bool fraudProven = false; // Replace with actual verification
        
        challenge.resolved = true;
        challenge.fraudProven = fraudProven;
        
        if (fraudProven) {
            // Slash sequencer's bond
            bonds[batch.sequencer] -= SEQUENCER_BOND;
            // Reward challenger
            bonds[challenge.challenger] += CHALLENGER_BOND + SEQUENCER_BOND;
            
            // Revert to previous state
            currentStateRoot = batch.parentHash;
        } else {
            // Slash challenger's bond
            // Reward sequencer
            bonds[batch.sequencer] += CHALLENGER_BOND;
        }
        
        emit ChallengeResolved(
            batchId,
            fraudProven,
            fraudProven ? challenge.challenger : batch.sequencer
        );
    }

    /**
     * @notice Finalize a batch after challenge period
     * @param batchId Batch identifier
     */
    function finalizeBatch(uint256 batchId)
        external
        whenNotPaused
    {
        Batch storage batch = batches[batchId];
        require(batch.timestamp > 0, "Batch not found");
        require(!batch.finalized, "Already finalized");
        require(
            block.timestamp > batch.challengeEndTime,
            "Challenge period not ended"
        );
        
        if (batch.challenged) {
            Challenge storage challenge = challenges[batchId];
            require(challenge.resolved, "Challenge not resolved");
            require(!challenge.fraudProven, "Fraud proven");
        }
        
        batch.finalized = true;
        currentStateRoot = batch.stateRoot;
        
        emit BatchFinalized(batchId, batch.stateRoot);
    }

    /**
     * @notice Check if an address has unresolved challenges
     * @param account Address to check
     */
    function hasUnresolvedChallenges(address account)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < currentBatchId; i++) {
            Challenge storage challenge = challenges[i];
            if (
                !challenge.resolved &&
                (challenge.challenger == account || batches[i].sequencer == account)
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Get batch details
     * @param batchId Batch identifier
     */
    function getBatch(uint256 batchId)
        external
        view
        returns (Batch memory)
    {
        require(batches[batchId].timestamp > 0, "Batch not found");
        return batches[batchId];
    }

    /**
     * @notice Get challenge details
     * @param batchId Batch identifier
     */
    function getChallenge(uint256 batchId)
        external
        view
        returns (Challenge memory)
    {
        require(challenges[batchId].timestamp > 0, "Challenge not found");
        return challenges[batchId];
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}