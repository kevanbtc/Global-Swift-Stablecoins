// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../settlement/rails/IRail.sol";
import "./interfaces/IMidnightBridge.sol";
import "./interfaces/IMidnightProofVerifier.sol";

/**
 * @title MidnightSettlementAdapter
 * @notice Bridge adapter for private settlements via Midnight network
 * @dev Integrates with StablecoinRouter and RailRegistry for private cross-chain settlements
 * @dev Follows the same pattern as AgoraTokenizedDepositAdapter, RLNMultiCBDCAdapter, FnalitySettlementAdapter
 */
abstract contract MidnightSettlementAdapter is IRail, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // State variables
    IMidnightBridge public midnightBridge;
    IMidnightProofVerifier public proofVerifier;
    address public stablecoinRouter;
    
    // Settlement tracking
    mapping(bytes32 => Settlement) public settlements;
    mapping(bytes32 => bool) public processedProofs;
    mapping(address => bool) public supportedAssets;
    
    // Privacy commitments
    mapping(bytes32 => Commitment) public commitments;
    mapping(bytes32 => bool) public spentNullifiers;
    
    // Statistics
    uint256 public totalSettlements;
    uint256 public totalPrivateVolume;
    uint256 public totalPublicVolume;

    // Structs
    struct Settlement {
        bytes32 settlementId;
        address initiator;
        address asset;
        uint256 amount;
        bytes32 commitment;
        bytes32 publicDataHash;
        SettlementStatus status;
        uint256 timestamp;
        bytes32 midnightTxHash;
    }

    struct Commitment {
        bytes32 commitmentHash;
        address owner;
        uint256 encryptedAmount;
        bool spent;
        uint256 timestamp;
    }

    struct ZKProof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[] publicInputs;
    }

    enum SettlementStatus {
        Pending,
        Verified,
        Completed,
        Failed,
        Cancelled
    }

    // Events
    event PrivateSettlementInitiated(
        bytes32 indexed settlementId,
        address indexed initiator,
        address indexed asset,
        bytes32 commitment,
        uint256 timestamp
    );

    event PrivateSettlementVerified(
        bytes32 indexed settlementId,
        bytes32 indexed proofId,
        uint256 timestamp
    );

    event PrivateSettlementCompleted(
        bytes32 indexed settlementId,
        bytes32 indexed midnightTxHash,
        uint256 publicAmount,
        uint256 timestamp
    );

    event CommitmentCreated(
        bytes32 indexed commitmentHash,
        address indexed owner,
        uint256 timestamp
    );

    event NullifierSpent(
        bytes32 indexed nullifier,
        bytes32 indexed settlementId,
        uint256 timestamp
    );

    event AssetSupported(address indexed asset, bool supported);
    event MidnightBridgeUpdated(address indexed oldBridge, address indexed newBridge);
    event ProofVerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    /**
     * @notice Constructor
     * @param _midnightBridge Address of Midnight bridge contract
     * @param _proofVerifier Address of ZK proof verifier
     * @param _stablecoinRouter Address of stablecoin router
     */
    constructor(
        address _midnightBridge,
        address _proofVerifier,
        address _stablecoinRouter,
        address _admin
    ) {
        require(_midnightBridge != address(0), "Invalid bridge");
        require(_proofVerifier != address(0), "Invalid verifier");
        require(_stablecoinRouter != address(0), "Invalid router");
        require(_admin != address(0), "Invalid admin");

        midnightBridge = IMidnightBridge(_midnightBridge);
        proofVerifier = IMidnightProofVerifier(_proofVerifier);
        stablecoinRouter = _stablecoinRouter;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);
    }

    /**
     * @notice Initiate private settlement with ZK proof
     * @param asset Token address to settle
     * @param amount Amount (encrypted in commitment)
     * @param commitment Privacy commitment hash
     * @param proof Zero-knowledge proof
     * @param publicData Public metadata
     */
    function initiatePrivateSettlement(
        address asset,
        uint256 amount,
        bytes32 commitment,
        bytes calldata proof,
        bytes calldata publicData
    ) external nonReentrant whenNotPaused returns (bytes32 settlementId) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Invalid amount");
        require(commitment != bytes32(0), "Invalid commitment");
        require(!commitments[commitment].spent, "Commitment already spent");

        // Generate settlement ID
        settlementId = keccak256(
            abi.encodePacked(
                msg.sender,
                asset,
                amount,
                commitment,
                block.timestamp,
                totalSettlements
            )
        );

        // Verify ZK proof
        ZKProof memory zkProof = abi.decode(proof, (ZKProof));
        require(
            proofVerifier.verifyProof(zkProof.a, zkProof.b, zkProof.c, zkProof.publicInputs),
            "Invalid ZK proof"
        );
        require(!processedProofs[keccak256(proof)], "Proof already used");

        // Create commitment
        commitments[commitment] = Commitment({
            commitmentHash: commitment,
            owner: msg.sender,
            encryptedAmount: amount,
            spent: false,
            timestamp: block.timestamp
        });

        // Create settlement record
        settlements[settlementId] = Settlement({
            settlementId: settlementId,
            initiator: msg.sender,
            asset: asset,
            amount: amount,
            commitment: commitment,
            publicDataHash: keccak256(publicData),
            status: SettlementStatus.Pending,
            timestamp: block.timestamp,
            midnightTxHash: bytes32(0)
        });

        // Mark proof as processed
        processedProofs[keccak256(proof)] = true;

        // Transfer tokens to contract
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        totalSettlements++;
        totalPrivateVolume += amount;

        emit PrivateSettlementInitiated(settlementId, msg.sender, asset, commitment, block.timestamp);
        emit CommitmentCreated(commitment, msg.sender, block.timestamp);

        return settlementId;
    }

    /**
     * @notice Complete private settlement after Midnight network confirmation
     * @param settlementId Settlement identifier
     * @param midnightTxHash Midnight network transaction hash
     * @param nullifier Nullifier to prevent double-spending
     * @param destinationProof Proof of destination ownership
     */
    function completePrivateSettlement(
        bytes32 settlementId,
        bytes32 midnightTxHash,
        bytes32 nullifier,
        bytes calldata destinationProof
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        Settlement storage settlement = settlements[settlementId];
        require(settlement.status == SettlementStatus.Pending, "Invalid status");
        require(!spentNullifiers[nullifier], "Nullifier already spent");

        // Verify Midnight network confirmation
        require(
            midnightBridge.verifyTransaction(midnightTxHash, destinationProof),
            "Invalid Midnight transaction"
        );

        // Mark nullifier as spent
        spentNullifiers[nullifier] = true;
        commitments[settlement.commitment].spent = true;

        // Update settlement
        settlement.status = SettlementStatus.Completed;
        settlement.midnightTxHash = midnightTxHash;

        emit NullifierSpent(nullifier, settlementId, block.timestamp);
        emit PrivateSettlementCompleted(
            settlementId,
            midnightTxHash,
            settlement.amount,
            block.timestamp
        );
    }

    /**
     * @notice Selective disclosure for regulatory compliance
     * @param settlementId Settlement to disclose
     * @param requester Address requesting disclosure (must be authorized)
     * @param decryptionKey Key to decrypt private data
     */
    function selectiveDisclose(
        bytes32 settlementId,
        address requester,
        bytes calldata decryptionKey
    ) external view returns (
        address initiator,
        address beneficiary,
        uint256 actualAmount,
        bytes memory privateMetadata
    ) {
        Settlement storage settlement = settlements[settlementId];
        require(settlement.timestamp > 0, "Settlement not found");
        
        // Only settlement initiator or authorized compliance officers can disclose
        require(
            msg.sender == settlement.initiator || hasRole(OPERATOR_ROLE, msg.sender),
            "Not authorized"
        );

        // In production, decrypt the private data using the key
        // This is a placeholder for the actual decryption logic
        initiator = settlement.initiator;
        actualAmount = settlement.amount;
        
        // Return encrypted metadata for regulator processing
        privateMetadata = abi.encode(settlement.commitment, settlement.publicDataHash);
        
        return (initiator, address(0), actualAmount, privateMetadata);
    }

    /**
     * @notice IRail implementation: Release funds to recipient
     * @param recipient Recipient address
     * @param asset Token address
     * @param amount Amount to release
     */
    function release(
        address recipient,
        address asset,
        uint256 amount
    ) external onlyRole(SETTLEMENT_ROLE) nonReentrant whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Invalid amount");
        require(IERC20(asset).balanceOf(address(this)) >= amount, "Insufficient balance");

        IERC20(asset).safeTransfer(recipient, amount);
        totalPublicVolume += amount;

        emit RailReleased(bytes32(0), recipient, asset, amount);
    }

    /**
     * @notice IRail implementation: Check if rail supports asset
     */
    function supportsAsset(address asset) external view returns (bool) {
        return supportedAssets[asset];
    }

    /**
     * @notice IRail implementation: Get rail identifier
     */
    function railId() external pure returns (bytes32) {
        return keccak256("MIDNIGHT_SETTLEMENT_RAIL");
    }

    /**
     * @notice Add or remove supported asset
     */
    function setSupportedAsset(address asset, bool supported) external onlyRole(OPERATOR_ROLE) {
        require(asset != address(0), "Invalid asset");
        supportedAssets[asset] = supported;
        emit AssetSupported(asset, supported);
    }

    /**
     * @notice Update Midnight bridge address
     */
    function setMidnightBridge(address newBridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newBridge != address(0), "Invalid bridge");
        address oldBridge = address(midnightBridge);
        midnightBridge = IMidnightBridge(newBridge);
        emit MidnightBridgeUpdated(oldBridge, newBridge);
    }

    /**
     * @notice Update proof verifier address
     */
    function setProofVerifier(address newVerifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newVerifier != address(0), "Invalid verifier");
        address oldVerifier = address(proofVerifier);
        proofVerifier = IMidnightProofVerifier(newVerifier);
        emit ProofVerifierUpdated(oldVerifier, newVerifier);
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause
     */
    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    /**
     * @notice Get settlement details
     */
    function getSettlement(bytes32 settlementId) external view returns (Settlement memory) {
        return settlements[settlementId];
    }

    /**
     * @notice Get commitment details
     */
    function getCommitment(bytes32 commitmentHash) external view returns (Commitment memory) {
        return commitments[commitmentHash];
    }

    /**
     * @notice Check if nullifier is spent
     */
    function isNullifierSpent(bytes32 nullifier) external view returns (bool) {
        return spentNullifiers[nullifier];
    }

    /**
     * @notice Get statistics
     */
    function getStatistics() external view returns (
        uint256 settlements,
        uint256 privateVolume,
        uint256 publicVolume
    ) {
        return (totalSettlements, totalPrivateVolume, totalPublicVolume);
    }
}
