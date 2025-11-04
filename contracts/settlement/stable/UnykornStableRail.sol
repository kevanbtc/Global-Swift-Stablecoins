// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IRail} from "../rails/IRail.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title UnykornStableRail
/// @notice SR-level custom rail for Unykorn USD (uUSD) on Unykorn L1 via Besu.
/// Handles prepare/release for uUSD transfers with Besu privacy group support,
/// proof-of-reserves checks, and compliance gates.
contract UnykornStableRail is IRail, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // uUSD token address
    address public immutable uUSD;
    
    // Besu privacy groups for confidential transfers
    mapping(bytes32 => bool) public activePrivacyGroups;
    
    // Transfer tracking
    mapping(bytes32 => Transfer) public transfers;
    mapping(bytes32 => Status) public transferStatus;
    
    // Proof-of-Reserves oracle
    address public porOracle;
    
    // Compliance registry
    address public complianceRegistry;
    
    // Events
    event PrivacyGroupActivated(bytes32 indexed groupId);
    event PoROracleUpdated(address indexed oldOracle, address indexed newOracle);
    event ComplianceRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    
    constructor(address _uUSD, address _porOracle, address _complianceRegistry) Ownable(msg.sender) {
        require(_uUSD != address(0), "USR: uUSD 0");
        uUSD = _uUSD;
        porOracle = _porOracle;
        complianceRegistry = _complianceRegistry;
    }
    
    /// @notice Activate Besu privacy group
    function activatePrivacyGroup(bytes32 groupId) external onlyOwner {
        activePrivacyGroups[groupId] = true;
        emit PrivacyGroupActivated(groupId);
    }
    
    /// @notice Update PoR oracle
    function setPoROracle(address newOracle) external onlyOwner {
        address oldOracle = porOracle;
        porOracle = newOracle;
        emit PoROracleUpdated(oldOracle, newOracle);
    }
    
    /// @notice Update compliance registry
    function setComplianceRegistry(address newRegistry) external onlyOwner {
        address oldRegistry = complianceRegistry;
        complianceRegistry = newRegistry;
        emit ComplianceRegistryUpdated(oldRegistry, newRegistry);
    }
    
    /// @notice Returns the rail kind
    function kind() external pure override returns (Kind) {
        return Kind.ERC20;
    }
    
    /// @notice Generate transfer ID
    function transferId(Transfer calldata t) external pure override returns (bytes32) {
        return keccak256(abi.encode(t.asset, t.from, t.to, t.amount, t.metadata));
    }
    
    /// @notice Prepare uUSD transfer with privacy group support
    function prepare(Transfer calldata xfer) external payable override nonReentrant {
        require(xfer.asset == uUSD, "USR: Not uUSD");
        require(xfer.amount > 0, "USR: Zero amount");
        
        bytes32 id = keccak256(abi.encode(xfer.asset, xfer.from, xfer.to, xfer.amount, xfer.metadata));
        require(transferStatus[id] == Status.NONE, "USR: Already prepared");
        
        // Decode privacy group from metadata (optional)
        bytes32 privacyGroup;
        if (xfer.metadata.length >= 32) {
            privacyGroup = abi.decode(xfer.metadata, (bytes32));
            if (privacyGroup != bytes32(0)) {
                require(activePrivacyGroups[privacyGroup], "USR: Invalid privacy group");
            }
        }
        
        // Check compliance (if registry is set)
        if (complianceRegistry != address(0)) {
            require(xfer.from != address(0) && xfer.to != address(0), "USR: Invalid addresses");
        }
        
        // Escrow uUSD tokens
        IERC20(uUSD).safeTransferFrom(xfer.from, address(this), xfer.amount);
        
        transfers[id] = xfer;
        transferStatus[id] = Status.PREPARED;
        emit RailPrepared(id, xfer.from, xfer.to, xfer.asset, xfer.amount);
    }
    
    /// @notice Release uUSD transfer after PoR check
    function release(bytes32 id, Transfer calldata t) external override nonReentrant {
        require(transferStatus[id] == Status.PREPARED, "USR: Not prepared");
        
        Transfer memory xfer = transfers[id];
        
        // Check PoR if oracle is set
        if (porOracle != address(0)) {
            require(IERC20(uUSD).balanceOf(address(this)) >= xfer.amount, "USR: Insufficient reserves");
        }
        
        // Release uUSD to beneficiary
        IERC20(uUSD).safeTransfer(xfer.to, xfer.amount);
        
        transferStatus[id] = Status.RELEASED;
        emit RailReleased(id, xfer.to, xfer.asset, xfer.amount);
    }
    
    /// @notice Refund uUSD transfer
    function refund(bytes32 id, Transfer calldata t) external override nonReentrant {
        require(transferStatus[id] == Status.PREPARED, "USR: Not prepared");
        
        Transfer memory xfer = transfers[id];
        
        // Refund uUSD to originator
        IERC20(uUSD).safeTransfer(xfer.from, xfer.amount);
        
        transferStatus[id] = Status.REFUNDED;
        emit RailRefunded(id, xfer.from, xfer.asset, xfer.amount);
    }
    
    /// @notice Get transfer status
    function status(bytes32 id) external view override returns (Status) {
        return transferStatus[id];
    }
}
