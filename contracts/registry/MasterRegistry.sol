// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {RailRegistry} from "../settlement/rails/RailRegistry.sol";
import {StablecoinRegistry} from "../settlement/stable/StablecoinRegistry.sol";
import {ComplianceRegistryUpgradeable} from "../compliance/ComplianceRegistryUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MasterRegistry
/// @notice SR-level unified registry linking all system registries for global discovery.
/// Provides a single entry point for discovering rails, stablecoins, compliance rules,
/// RWA assets, oracles, and SWIFT adapters across the entire Unykorn ecosystem.
contract MasterRegistry is Ownable {
    
    // Core registries
    RailRegistry public railRegistry;
    StablecoinRegistry public stablecoinRegistry;
    ComplianceRegistryUpgradeable public complianceRegistry;
    
    // Additional registries
    address public rwaRegistry;
    address public oracleRegistry;
    address public swiftRegistry;
    address public besuBridgeRegistry;
    
    // System metadata
    struct SystemInfo {
        string chainName;
        uint256 chainId;
        string version;
        uint256 deployedAt;
    }
    
    SystemInfo public systemInfo;
    
    // Events
    event RailRegistrySet(address indexed registry);
    event StablecoinRegistrySet(address indexed registry);
    event ComplianceRegistrySet(address indexed registry);
    event RWARegistrySet(address indexed registry);
    event OracleRegistrySet(address indexed registry);
    event SWIFTRegistrySet(address indexed registry);
    event BesuBridgeRegistrySet(address indexed registry);
    event SystemInfoUpdated(string chainName, uint256 chainId, string version);
    
    constructor(
        address _railRegistry,
        address _stablecoinRegistry,
        address _complianceRegistry
    ) Ownable(msg.sender) {
        require(_railRegistry != address(0), "MR: RailRegistry 0");
        require(_stablecoinRegistry != address(0), "MR: StablecoinRegistry 0");
        require(_complianceRegistry != address(0), "MR: ComplianceRegistry 0");
        
        railRegistry = RailRegistry(_railRegistry);
        stablecoinRegistry = StablecoinRegistry(_stablecoinRegistry);
        complianceRegistry = ComplianceRegistryUpgradeable(_complianceRegistry);
        
        // Initialize system info
        systemInfo = SystemInfo({
            chainName: "Unykorn Layer 1",
            chainId: 7777,
            version: "1.0.0",
            deployedAt: block.timestamp
        });
        
        emit RailRegistrySet(_railRegistry);
        emit StablecoinRegistrySet(_stablecoinRegistry);
        emit ComplianceRegistrySet(_complianceRegistry);
    }
    
    /// @notice Set RWA registry
    function setRWARegistry(address registry) external onlyOwner {
        rwaRegistry = registry;
        emit RWARegistrySet(registry);
    }
    
    /// @notice Set oracle registry
    function setOracleRegistry(address registry) external onlyOwner {
        oracleRegistry = registry;
        emit OracleRegistrySet(registry);
    }
    
    /// @notice Set SWIFT registry
    function setSWIFTRegistry(address registry) external onlyOwner {
        swiftRegistry = registry;
        emit SWIFTRegistrySet(registry);
    }
    
    /// @notice Set Besu bridge registry
    function setBesuBridgeRegistry(address registry) external onlyOwner {
        besuBridgeRegistry = registry;
        emit BesuBridgeRegistrySet(registry);
    }
    
    /// @notice Update system info
    function updateSystemInfo(
        string calldata chainName,
        uint256 chainId,
        string calldata version
    ) external onlyOwner {
        systemInfo.chainName = chainName;
        systemInfo.chainId = chainId;
        systemInfo.version = version;
        emit SystemInfoUpdated(chainName, chainId, version);
    }
    
    /// @notice Get all registry addresses
    function getAllRegistries() external view returns (
        address rail,
        address stablecoin,
        address compliance,
        address rwa,
        address oracle,
        address swift,
        address besuBridge
    ) {
        return (
            address(railRegistry),
            address(stablecoinRegistry),
            address(complianceRegistry),
            rwaRegistry,
            oracleRegistry,
            swiftRegistry,
            besuBridgeRegistry
        );
    }
    
    /// @notice Get rail address
    function getRail(bytes32 railKey) external view returns (address) {
        return railRegistry.get(railKey);
    }
    
    /// @notice Get stablecoin metadata
    function getStablecoin(address token) external view returns (StablecoinRegistry.Meta memory) {
        return stablecoinRegistry.get(token);
    }
    
    /// @notice Check compliance for address
    function isCompliant(address account) external view returns (bool) {
        // Simplified - in production, call actual compliance check
        return account != address(0);
    }
    
    /// @notice Get system info
    function getSystemInfo() external view returns (SystemInfo memory) {
        return systemInfo;
    }
}
