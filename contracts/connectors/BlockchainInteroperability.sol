// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title BlockchainInteroperability
 * @notice Cross-chain communication and asset transfers
 * @dev Handles interoperability between different blockchain networks
 */
contract BlockchainInteroperability is Ownable, ReentrancyGuard {

    enum BlockchainNetwork {
        ETHEREUM,
        POLYGON,
        BSC,
        ARBITRUM,
        OPTIMISM,
        AVALANCHE,
        SOLANA,
        COSMOS,
        POLKADOT,
        NEAR,
        ALGORAND,
        TEZOS,
        CARDANO,
        FLOW,
        APTOS,
        SUI,
        CUSTOM
    }

    enum BridgeType {
        LOCK_MINT,
        BURN_MINT,
        LOCK_UNLOCK,
        ATOMIC_SWAP,
        STATE_CHANNEL,
        LIGHT_CLIENT,
        ORACLE_BRIDGE,
        MULTISIG_BRIDGE
    }

    enum TransferStatus {
        PENDING,
        LOCKED,
        CONFIRMED,
        COMPLETED,
        FAILED,
        REFUNDED
    }

    struct CrossChainTransfer {
        bytes32 transferId;
        address sender;
        address recipient;
        BlockchainNetwork sourceChain;
        BlockchainNetwork targetChain;
        address sourceToken;
        address targetToken;
        uint256 amount;
        uint256 fee;
        TransferStatus status;
        uint256 timestamp;
        uint256 confirmations;
        bytes32 txHash;
        bytes32 bridgeTxHash;
    }

    struct BridgeConfig {
        bytes32 bridgeId;
        BlockchainNetwork network;
        BridgeType bridgeType;
        address bridgeContract;
        address relayer;
        uint256 minConfirmations;
        uint256 maxTransferAmount;
        uint256 feePercentage; // in basis points
        bool isActive;
        mapping(address => bool) supportedTokens;
    }

    struct NetworkConfig {
        BlockchainNetwork network;
        string rpcUrl;
        uint256 chainId;
        address nativeToken;
        uint256 blockTime; // seconds
        uint256 gasPrice; // wei
        bool isActive;
    }

    // Storage
    mapping(bytes32 => CrossChainTransfer) public crossChainTransfers;
    mapping(bytes32 => BridgeConfig) public bridgeConfigs;
    mapping(BlockchainNetwork => NetworkConfig) public networkConfigs;
    mapping(address => bytes32[]) public userTransfers;
    mapping(BlockchainNetwork => bytes32[]) public networkBridges;

    // Global statistics
    uint256 public totalTransfers;
    uint256 public totalBridges;
    uint256 public totalNetworks;
    uint256 public totalVolume; // in wei

    // Protocol parameters
    uint256 public baseFee = 0.001 ether; // 0.001 ETH base fee
    uint256 public feePercentage = 25; // 0.25% fee
    uint256 public minTransferAmount = 0.01 ether;
    uint256 public maxTransferAmount = 1000 ether;
    uint256 public confirmationTimeout = 3600; // 1 hour

    // Events
    event BridgeRegistered(bytes32 indexed bridgeId, BlockchainNetwork network, BridgeType bridgeType);
    event NetworkConfigured(BlockchainNetwork network, uint256 chainId);
    event CrossChainTransferInitiated(bytes32 indexed transferId, address sender, BlockchainNetwork targetChain);
    event CrossChainTransferCompleted(bytes32 indexed transferId, bytes32 txHash);
    event TransferStatusUpdated(bytes32 indexed transferId, TransferStatus status);

    modifier validNetwork(BlockchainNetwork _network) {
        require(networkConfigs[_network].isActive, "Network not configured");
        _;
    }

    modifier validBridge(bytes32 _bridgeId) {
        require(bridgeConfigs[_bridgeId].bridgeContract != address(0), "Bridge not found");
        _;
    }

    modifier activeBridge(bytes32 _bridgeId) {
        require(bridgeConfigs[_bridgeId].isActive, "Bridge not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Configure a blockchain network
     */
    function configureNetwork(
        BlockchainNetwork _network,
        string memory _rpcUrl,
        uint256 _chainId,
        address _nativeToken,
        uint256 _blockTime,
        uint256 _gasPrice
    ) external onlyOwner {
        NetworkConfig storage config = networkConfigs[_network];
        config.network = _network;
        config.rpcUrl = _rpcUrl;
        config.chainId = _chainId;
        config.nativeToken = _nativeToken;
        config.blockTime = _blockTime;
        config.gasPrice = _gasPrice;
        config.isActive = true;

        totalNetworks++;
        emit NetworkConfigured(_network, _chainId);
    }

    /**
     * @notice Register a cross-chain bridge
     */
    function registerBridge(
        BlockchainNetwork _network,
        BridgeType _bridgeType,
        address _bridgeContract,
        address _relayer,
        uint256 _minConfirmations,
        uint256 _maxTransferAmount,
        uint256 _feePercentage
    ) external onlyOwner validNetwork(_network) returns (bytes32) {
        bytes32 bridgeId = keccak256(abi.encodePacked(
            _network,
            _bridgeType,
            _bridgeContract,
            block.timestamp
        ));

        require(bridgeConfigs[bridgeId].bridgeContract == address(0), "Bridge already exists");

        BridgeConfig storage bridge = bridgeConfigs[bridgeId];
        bridge.bridgeId = bridgeId;
        bridge.network = _network;
        bridge.bridgeType = _bridgeType;
        bridge.bridgeContract = _bridgeContract;
        bridge.relayer = _relayer;
        bridge.minConfirmations = _minConfirmations;
        bridge.maxTransferAmount = _maxTransferAmount;
        bridge.feePercentage = _feePercentage;
        bridge.isActive = true;

        networkBridges[_network].push(bridgeId);
        totalBridges++;

        emit BridgeRegistered(bridgeId, _network, _bridgeType);
        return bridgeId;
    }

    /**
     * @notice Add supported token to bridge
     */
    function addSupportedToken(bytes32 _bridgeId, address _token) external onlyOwner validBridge(_bridgeId) {
        bridgeConfigs[_bridgeId].supportedTokens[_token] = true;
    }

    /**
     * @notice Initiate cross-chain transfer
     */
    function initiateTransfer(
        BlockchainNetwork _targetChain,
        address _targetToken,
        address _recipient,
        uint256 _amount
    ) external payable validNetwork(_targetChain) returns (bytes32) {
        require(_amount >= minTransferAmount, "Amount too small");
        require(_amount <= maxTransferAmount, "Amount too large");

        // Calculate fee
        uint256 fee = (baseFee + (_amount * feePercentage) / 10000);
        require(msg.value >= fee, "Insufficient fee");

        bytes32 transferId = keccak256(abi.encodePacked(
            msg.sender,
            _targetChain,
            _recipient,
            _amount,
            block.timestamp
        ));

        CrossChainTransfer storage transfer = crossChainTransfers[transferId];
        transfer.transferId = transferId;
        transfer.sender = msg.sender;
        transfer.recipient = _recipient;
        transfer.sourceChain = BlockchainNetwork.ETHEREUM; // Assuming current chain is Ethereum
        transfer.targetChain = _targetChain;
        transfer.sourceToken = address(0); // Native token
        transfer.targetToken = _targetToken;
        transfer.amount = _amount;
        transfer.fee = fee;
        transfer.status = TransferStatus.PENDING;
        transfer.timestamp = block.timestamp;

        userTransfers[msg.sender].push(transferId);
        totalTransfers++;
        totalVolume += _amount;

        emit CrossChainTransferInitiated(transferId, msg.sender, _targetChain);
        return transferId;
    }

    /**
     * @notice Confirm cross-chain transfer (called by relayer)
     */
    function confirmTransfer(
        bytes32 _transferId,
        bytes32 _bridgeTxHash,
        uint256 _confirmations
    ) external {
        CrossChainTransfer storage transfer = crossChainTransfers[_transferId];
        require(transfer.sender != address(0), "Transfer not found");
        require(transfer.status == TransferStatus.PENDING, "Invalid status");

        // Find appropriate bridge
        bytes32[] memory bridges = networkBridges[transfer.targetChain];
        require(bridges.length > 0, "No bridge available");

        bytes32 bridgeId = bridges[0]; // Use first available bridge
        BridgeConfig memory bridge = bridgeConfigs[bridgeId];

        require(_confirmations >= bridge.minConfirmations, "Insufficient confirmations");
        require(transfer.amount <= bridge.maxTransferAmount, "Amount exceeds bridge limit");

        transfer.status = TransferStatus.CONFIRMED;
        transfer.confirmations = _confirmations;
        transfer.bridgeTxHash = _bridgeTxHash;

        emit TransferStatusUpdated(_transferId, TransferStatus.CONFIRMED);
    }

    /**
     * @notice Complete cross-chain transfer
     */
    function completeTransfer(
        bytes32 _transferId,
        bytes32 _txHash
    ) external {
        CrossChainTransfer storage transfer = crossChainTransfers[_transferId];
        require(transfer.sender != address(0), "Transfer not found");
        require(transfer.status == TransferStatus.CONFIRMED, "Transfer not confirmed");

        transfer.status = TransferStatus.COMPLETED;
        transfer.txHash = _txHash;

        emit CrossChainTransferCompleted(_transferId, _txHash);
        emit TransferStatusUpdated(_transferId, TransferStatus.COMPLETED);
    }

    /**
     * @notice Refund failed transfer
     */
    function refundTransfer(bytes32 _transferId) external {
        CrossChainTransfer storage transfer = crossChainTransfers[_transferId];
        require(transfer.sender == msg.sender, "Not transfer sender");
        require(transfer.status == TransferStatus.PENDING, "Cannot refund");
        require(block.timestamp > transfer.timestamp + confirmationTimeout, "Timeout not reached");

        transfer.status = TransferStatus.REFUNDED;

        // Refund fee (logic would depend on token type)
        payable(msg.sender).transfer(transfer.fee);

        emit TransferStatusUpdated(_transferId, TransferStatus.REFUNDED);
    }

    /**
     * @notice Get transfer details
     */
    function getTransfer(bytes32 _transferId)
        external
        view
        returns (
            address sender,
            address recipient,
            BlockchainNetwork sourceChain,
            BlockchainNetwork targetChain,
            uint256 amount,
            TransferStatus status,
            uint256 timestamp
        )
    {
        CrossChainTransfer memory transfer = crossChainTransfers[_transferId];
        return (
            transfer.sender,
            transfer.recipient,
            transfer.sourceChain,
            transfer.targetChain,
            transfer.amount,
            transfer.status,
            transfer.timestamp
        );
    }

    /**
     * @notice Get bridge details
     */
    function getBridge(bytes32 _bridgeId)
        external
        view
        returns (
            BlockchainNetwork network,
            BridgeType bridgeType,
            address bridgeContract,
            uint256 minConfirmations,
            uint256 maxTransferAmount,
            bool isActive
        )
    {
        BridgeConfig memory bridge = bridgeConfigs[_bridgeId];
        return (
            bridge.network,
            bridge.bridgeType,
            bridge.bridgeContract,
            bridge.minConfirmations,
            bridge.maxTransferAmount,
            bridge.isActive
        );
    }

    /**
     * @notice Get network configuration
     */
    function getNetworkConfig(BlockchainNetwork _network)
        external
        view
        returns (
            string memory rpcUrl,
            uint256 chainId,
            address nativeToken,
            uint256 blockTime,
            bool isActive
        )
    {
        NetworkConfig memory config = networkConfigs[_network];
        return (
            config.rpcUrl,
            config.chainId,
            config.nativeToken,
            config.blockTime,
            config.isActive
        );
    }

    /**
     * @notice Check if token is supported by bridge
     */
    function isTokenSupported(bytes32 _bridgeId, address _token) external view returns (bool) {
        return bridgeConfigs[_bridgeId].supportedTokens[_token];
    }

    /**
     * @notice Get user transfers
     */
    function getUserTransfers(address _user) external view returns (bytes32[] memory) {
        return userTransfers[_user];
    }

    /**
     * @notice Get bridges for network
     */
    function getNetworkBridges(BlockchainNetwork _network) external view returns (bytes32[] memory) {
        return networkBridges[_network];
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _baseFee,
        uint256 _feePercentage,
        uint256 _minTransferAmount,
        uint256 _maxTransferAmount,
        uint256 _confirmationTimeout
    ) external onlyOwner {
        baseFee = _baseFee;
        feePercentage = _feePercentage;
        minTransferAmount = _minTransferAmount;
        maxTransferAmount = _maxTransferAmount;
        confirmationTimeout = _confirmationTimeout;
    }

    /**
     * @notice Get global interoperability statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalTransfers,
            uint256 _totalBridges,
            uint256 _totalNetworks,
            uint256 _totalVolume
        )
    {
        return (totalTransfers, totalBridges, totalNetworks, totalVolume);
    }
}
