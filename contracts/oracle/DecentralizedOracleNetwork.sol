// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DecentralizedOracleNetwork
 * @notice Decentralized oracle network with reputation-based consensus and fallback mechanisms
 * @dev Provides high-reliability price feeds with multiple redundancy layers
 */
contract DecentralizedOracleNetwork is Ownable, ReentrancyGuard {
    struct OracleNode {
        address nodeAddress;
        uint256 reputationScore;
        uint256 lastSubmission;
        uint256 totalSubmissions;
        uint256 successfulSubmissions;
        bool isActive;
    }

    struct PriceFeed {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        uint8 decimalPlaces;
    }

    struct AssetData {
        mapping(address => PriceFeed) nodePrices;
        address[] activeNodes;
        PriceFeed consensusPrice;
        uint256 lastUpdate;
        bool emergencyMode;
    }

    mapping(address => OracleNode) public nodes;
    mapping(address => AssetData) public assets; // asset => data
    mapping(address => bool) public authorizedAssets;

    uint256 public constant MIN_REPUTATION_SCORE = 100;
    uint256 public constant MAX_REPUTATION_SCORE = 1000;
    uint256 public constant CONSENSUS_THRESHOLD = 70; // 70% agreement required
    uint256 public constant MAX_DEVIATION_PERCENT = 500; // 5% max deviation
    uint256 public constant SUBMISSION_TIMEOUT = 1 hours;

    event OracleNodeRegistered(address indexed node, uint256 initialReputation);
    event PriceSubmitted(address indexed node, address indexed asset, uint256 price, uint256 confidence);
    event ConsensusReached(address indexed asset, uint256 price, uint256 confidence, uint256 timestamp);
    event EmergencyModeActivated(address indexed asset);
    event EmergencyModeDeactivated(address indexed asset);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new oracle node
     */
    function registerOracleNode(address nodeAddress, uint256 initialReputation) public onlyOwner {
        require(initialReputation >= MIN_REPUTATION_SCORE, "Reputation too low");
        require(initialReputation <= MAX_REPUTATION_SCORE, "Reputation too high");
        require(!nodes[nodeAddress].isActive, "Node already registered");

        nodes[nodeAddress] = OracleNode({
            nodeAddress: nodeAddress,
            reputationScore: initialReputation,
            lastSubmission: 0,
            totalSubmissions: 0,
            successfulSubmissions: 0,
            isActive: true
        });

        emit OracleNodeRegistered(nodeAddress, initialReputation);
    }

    /**
     * @notice Authorize an asset for price feeds
     */
    function authorizeAsset(address asset, bool authorized) public onlyOwner {
        authorizedAssets[asset] = authorized;
    }

    /**
     * @notice Submit price data from oracle node
     */
    function submitPriceData(
        address asset,
        uint256 price,
        uint256 confidence,
        uint8 decimalPlaces
    ) public nonReentrant {
        require(nodes[msg.sender].isActive, "Node not active");
        require(authorizedAssets[asset], "Asset not authorized");
        require(confidence > 0, "Invalid confidence");

        OracleNode storage node = nodes[msg.sender];
        AssetData storage assetData = assets[asset];

        // Update node price
        assetData.nodePrices[msg.sender] = PriceFeed({
            price: price,
            timestamp: block.timestamp,
            confidence: confidence,
            decimalPlaces: decimalPlaces
        });

        // Add to active nodes if not present
        if (assetData.nodePrices[msg.sender].timestamp == 0) {
            assetData.activeNodes.push(msg.sender);
        }

        // Update node statistics
        node.lastSubmission = block.timestamp;
        node.totalSubmissions++;

        emit PriceSubmitted(msg.sender, asset, price, confidence);

        // Attempt consensus calculation
        _calculateConsensus(asset);
    }

    /**
     * @notice Get latest consensus price for asset
     */
    function getPrice(address asset) public view returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence,
        bool isValid
    ) {
        AssetData storage assetData = assets[asset];
        require(assetData.lastUpdate > 0, "No price data");

        PriceFeed memory consensus = assetData.consensusPrice;
        return (
            consensus.price,
            consensus.timestamp,
            consensus.confidence,
            !assetData.emergencyMode && (block.timestamp - consensus.timestamp) < SUBMISSION_TIMEOUT
        );
    }

    /**
     * @notice Get price from specific node
     */
    function getNodePrice(address asset, address node) public view returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence
    ) {
        PriceFeed memory feed = assets[asset].nodePrices[node];
        return (feed.price, feed.timestamp, feed.confidence);
    }

    /**
     * @notice Activate emergency mode for asset (governance only)
     */
    function activateEmergencyMode(address asset) public onlyOwner {
        assets[asset].emergencyMode = true;
        emit EmergencyModeActivated(asset);
    }

    /**
     * @notice Deactivate emergency mode for asset
     */
    function deactivateEmergencyMode(address asset) public onlyOwner {
        assets[asset].emergencyMode = false;
        emit EmergencyModeDeactivated(asset);
    }

    // Internal functions

    function _calculateConsensus(address asset) internal {
        AssetData storage assetData = assets[asset];
        address[] memory activeNodes = assetData.activeNodes;

        if (activeNodes.length < 3) return; // Need minimum 3 nodes

        uint256[] memory prices = new uint256[](activeNodes.length);
        uint256[] memory weights = new uint256[](activeNodes.length);
        uint256 totalWeight = 0;

        // Collect prices and calculate weights based on reputation and recency
        for (uint i = 0; i < activeNodes.length; i++) {
            address nodeAddr = activeNodes[i];
            PriceFeed memory feed = assetData.nodePrices[nodeAddr];
            OracleNode memory node = nodes[nodeAddr];

            if (feed.timestamp == 0 || (block.timestamp - feed.timestamp) > SUBMISSION_TIMEOUT) {
                continue; // Skip stale data
            }

            prices[i] = feed.price;
            weights[i] = node.reputationScore * feed.confidence / 100;
            totalWeight += weights[i];
        }

        if (totalWeight == 0) return;

        // Calculate weighted median
        uint256 consensusPrice = _calculateWeightedMedian(prices, weights, totalWeight);

        // Calculate confidence based on deviation
        uint256 totalConfidence = _calculateConfidence(prices, weights, consensusPrice);

        // Update consensus if confidence meets threshold
        if (totalConfidence >= CONSENSUS_THRESHOLD) {
            assetData.consensusPrice = PriceFeed({
                price: consensusPrice,
                timestamp: block.timestamp,
                confidence: totalConfidence,
                decimalPlaces: 8 // Standard 8 decimals for prices
            });
            assetData.lastUpdate = block.timestamp;

            // Update node reputations based on consensus
            _updateNodeReputations(asset, consensusPrice);

            emit ConsensusReached(asset, consensusPrice, totalConfidence, block.timestamp);
        }
    }

    function _calculateWeightedMedian(
        uint256[] memory prices,
        uint256[] memory weights,
        uint256 totalWeight
    ) internal pure returns (uint256) {
        // Simplified weighted median calculation
        // In production, would implement proper statistical median
        uint256 weightedSum = 0;
        for (uint i = 0; i < prices.length; i++) {
            weightedSum += prices[i] * weights[i];
        }
        return weightedSum / totalWeight;
    }

    function _calculateConfidence(
        uint256[] memory prices,
        uint256[] memory weights,
        uint256 consensusPrice
    ) internal pure returns (uint256) {
        uint256 totalDeviation = 0;
        uint256 totalWeight = 0;

        for (uint i = 0; i < prices.length; i++) {
            if (prices[i] == 0) continue;

            uint256 deviation = consensusPrice > prices[i] ?
                ((consensusPrice - prices[i]) * 10000) / consensusPrice :
                ((prices[i] - consensusPrice) * 10000) / consensusPrice;

            if (deviation <= MAX_DEVIATION_PERCENT) {
                totalWeight += weights[i];
            } else {
                totalDeviation += deviation * weights[i];
            }
        }

        // Return confidence as percentage (0-100)
        return totalWeight * 100 / (totalWeight + totalDeviation);
    }

    function _updateNodeReputations(address asset, uint256 consensusPrice) internal {
        AssetData storage assetData = assets[asset];
        address[] memory activeNodes = assetData.activeNodes;

        for (uint i = 0; i < activeNodes.length; i++) {
            address nodeAddr = activeNodes[i];
            OracleNode storage node = nodes[nodeAddr];
            PriceFeed memory feed = assetData.nodePrices[nodeAddr];

            if (feed.timestamp == 0) continue;

            // Calculate deviation from consensus
            uint256 deviation = consensusPrice > feed.price ?
                ((consensusPrice - feed.price) * 10000) / consensusPrice :
                ((feed.price - consensusPrice) * 10000) / consensusPrice;

            // Update reputation based on accuracy
            if (deviation <= MAX_DEVIATION_PERCENT) {
                node.successfulSubmissions++;
                node.reputationScore = node.reputationScore < MAX_REPUTATION_SCORE ?
                    node.reputationScore + 1 : MAX_REPUTATION_SCORE;
            } else {
                node.reputationScore = node.reputationScore > MIN_REPUTATION_SCORE ?
                    node.reputationScore - 5 : MIN_REPUTATION_SCORE;
            }
        }
    }
}
