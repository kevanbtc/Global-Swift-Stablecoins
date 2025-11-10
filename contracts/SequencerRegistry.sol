// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./common/Types.sol";
import "./common/Roles.sol";
import "./common/Errors.sol";

/**
 * @title SequencerRegistry
 * @notice Registry for managing sequencer nodes and their rights
 * @dev Implements registration and management of sequencers
 */
contract SequencerRegistry is AccessControl, Pausable {
    using ECDSA for bytes32;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct SequencerNode {
        address owner;
        string endpoint;
        uint256 stake;
        bool active;
        uint256 registeredAt;
        uint256 lastHeartbeat;
    }

    // Required stake amount in native tokens
    uint256 public constant MIN_STAKE = 100 ether;
    
    // Maximum time between heartbeats
    uint256 public constant MAX_HEARTBEAT_DELAY = 1 hours;

    // State variables
    mapping(address => SequencerNode) public nodes;
    address[] public activeNodes;
    uint256 public totalStake;
    uint256 public totalNodes;

    // Events
    event NodeRegistered(
        address indexed nodeAddress,
        address indexed owner,
        string endpoint,
        uint256 stake
    );
    event NodeDeregistered(
        address indexed nodeAddress,
        address indexed owner
    );
    event StakeIncreased(
        address indexed nodeAddress,
        uint256 amount
    );
    event StakeDecreased(
        address indexed nodeAddress,
        uint256 amount
    );
    event HeartbeatReceived(
        address indexed nodeAddress,
        uint256 timestamp
    );
    event NodeStatusChanged(
        address indexed nodeAddress,
        bool active
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @notice Register a new sequencer node
     * @param nodeAddress Address of the sequencer node
     * @param endpoint Node endpoint URL
     */
    function registerNode(address nodeAddress, string memory endpoint) public payable
        whenNotPaused
    {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(nodes[nodeAddress].registeredAt == 0, "Node already registered");
        
        nodes[nodeAddress] = SequencerNode({
            owner: msg.sender,
            endpoint: endpoint,
            stake: msg.value,
            active: true,
            registeredAt: block.timestamp,
            lastHeartbeat: block.timestamp
        });
        
        activeNodes.push(nodeAddress);
        totalStake += msg.value;
        totalNodes++;
        
        emit NodeRegistered(nodeAddress, msg.sender, endpoint, msg.value);
        emit NodeStatusChanged(nodeAddress, true);
    }

    /**
     * @notice Deregister a sequencer node
     * @param nodeAddress Address of the sequencer node
     */
    function deregisterNode(address nodeAddress) public whenNotPaused
    {
        SequencerNode storage node = nodes[nodeAddress];
        require(node.registeredAt > 0, "Node not registered");
        require(
            msg.sender == node.owner || hasRole(ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        
        uint256 stake = node.stake;
        
        // Remove from active nodes array
        for (uint256 i = 0; i < activeNodes.length; i++) {
            if (activeNodes[i] == nodeAddress) {
                activeNodes[i] = activeNodes[activeNodes.length - 1];
                activeNodes.pop();
                break;
            }
        }
        
        totalStake -= stake;
        totalNodes--;
        delete nodes[nodeAddress];
        
        payable(node.owner).transfer(stake);
        
        emit NodeDeregistered(nodeAddress, node.owner);
    }

    /**
     * @notice Increase stake for a node
     * @param nodeAddress Address of the sequencer node
     */
    function increaseStake(address nodeAddress) public payable
        whenNotPaused
    {
        SequencerNode storage node = nodes[nodeAddress];
        require(node.registeredAt > 0, "Node not registered");
        require(msg.sender == node.owner, "Not node owner");
        
        node.stake += msg.value;
        totalStake += msg.value;
        
        emit StakeIncreased(nodeAddress, msg.value);
    }

    /**
     * @notice Decrease stake for a node
     * @param nodeAddress Address of the sequencer node
     * @param amount Amount to decrease
     */
    function decreaseStake(address nodeAddress, uint256 amount) public whenNotPaused
    {
        SequencerNode storage node = nodes[nodeAddress];
        require(node.registeredAt > 0, "Node not registered");
        require(msg.sender == node.owner, "Not node owner");
        require(node.stake - amount >= MIN_STAKE, "Stake too low");
        
        node.stake -= amount;
        totalStake -= amount;
        
        payable(msg.sender).transfer(amount);
        
        emit StakeDecreased(nodeAddress, amount);
    }

    /**
     * @notice Send heartbeat for a node
     * @param nodeAddress Address of the sequencer node
     */
    function sendHeartbeat(address nodeAddress) public whenNotPaused
    {
        SequencerNode storage node = nodes[nodeAddress];
        require(node.registeredAt > 0, "Node not registered");
        require(
            msg.sender == nodeAddress || msg.sender == node.owner,
            "Not authorized"
        );
        
        node.lastHeartbeat = block.timestamp;
        
        emit HeartbeatReceived(nodeAddress, block.timestamp);
    }

    /**
     * @notice Update node status
     * @param nodeAddress Address of the sequencer node
     * @param active New active status
     */
    function updateNodeStatus(address nodeAddress, bool active) public onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        SequencerNode storage node = nodes[nodeAddress];
        require(node.registeredAt > 0, "Node not registered");
        
        if (active != node.active) {
            node.active = active;
            
            if (active) {
                activeNodes.push(nodeAddress);
            } else {
                for (uint256 i = 0; i < activeNodes.length; i++) {
                    if (activeNodes[i] == nodeAddress) {
                        activeNodes[i] = activeNodes[activeNodes.length - 1];
                        activeNodes.pop();
                        break;
                    }
                }
            }
            
            emit NodeStatusChanged(nodeAddress, active);
        }
    }

    /**
     * @notice Get node details
     * @param nodeAddress Address of the sequencer node
     */
    function getNode(address nodeAddress) public view
        returns (
            address owner,
            string memory endpoint,
            uint256 stake,
            bool active,
            uint256 registeredAt,
            uint256 lastHeartbeat
        )
    {
        SequencerNode storage node = nodes[nodeAddress];
        require(node.registeredAt > 0, "Node not registered");
        
        return (
            node.owner,
            node.endpoint,
            node.stake,
            node.active,
            node.registeredAt,
            node.lastHeartbeat
        );
    }

    /**
     * @notice Get all active nodes
     */
    function getActiveNodes() public view
        returns (address[] memory)
    {
        return activeNodes;
    }

    /**
     * @notice Check if a node is healthy
     * @param nodeAddress Address of the sequencer node
     */
    function isNodeHealthy(address nodeAddress) public view
        returns (bool)
    {
        SequencerNode storage node = nodes[nodeAddress];
        if (node.registeredAt == 0 || !node.active) {
            return false;
        }
        
        return block.timestamp - node.lastHeartbeat <= MAX_HEARTBEAT_DELAY;
    }

    // Admin functions
    function pause() public onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}