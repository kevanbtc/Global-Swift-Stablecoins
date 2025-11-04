// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/ProxyAdmin.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title SystemBootstrap
 * @notice System initialization and bootstrapping contract
 * @dev Manages the deployment and configuration of core system components
 */
contract SystemBootstrap is AccessControl, Pausable {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // Component registry
    struct Component {
        address implementation;
        address proxy;
        bytes32 componentType;
        uint256 version;
        bool initialized;
        bool upgradeable;
    }
    
    // Component tracking
    mapping(bytes32 => Component) public components;
    mapping(bytes32 => address[]) public componentVersions;
    mapping(address => bytes32) public componentIds;
    
    // Proxy admin
    ProxyAdmin public proxyAdmin;
    
    // Events
    event ComponentDeployed(
        bytes32 indexed componentId,
        address implementation,
        address proxy
    );
    event ComponentUpgraded(
        bytes32 indexed componentId,
        address oldImplementation,
        address newImplementation
    );
    event ComponentInitialized(
        bytes32 indexed componentId,
        bytes initData
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEPLOYER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        // Deploy proxy admin
        proxyAdmin = new ProxyAdmin();
    }

    /**
     * @notice Deploy a new system component
     * @param componentId Component identifier
     * @param implementation Implementation contract address
     * @param initData Initialization data
     * @param upgradeable Whether the component is upgradeable
     */
    function deployComponent(
        bytes32 componentId,
        address implementation,
        bytes memory initData,
        bool upgradeable
    )
        external
        onlyRole(DEPLOYER_ROLE)
        whenNotPaused
        returns (address proxy)
    {
        require(implementation != address(0), "Invalid implementation");
        require(components[componentId].implementation == address(0),
            "Component exists");
        
        if (upgradeable) {
            // Deploy transparent proxy
            proxy = address(new TransparentUpgradeableProxy(
                implementation,
                address(proxyAdmin),
                initData
            ));
        } else {
            // Deploy implementation directly
            proxy = implementation;
            if (initData.length > 0) {
                (bool success,) = proxy.call(initData);
                require(success, "Initialization failed");
            }
        }
        
        Component memory component = Component({
            implementation: implementation,
            proxy: proxy,
            componentType: componentId,
            version: 1,
            initialized: true,
            upgradeable: upgradeable
        });
        
        components[componentId] = component;
        componentVersions[componentId].push(implementation);
        componentIds[proxy] = componentId;
        
        emit ComponentDeployed(componentId, implementation, proxy);
        
        if (initData.length > 0) {
            emit ComponentInitialized(componentId, initData);
        }
    }

    /**
     * @notice Upgrade a component implementation
     * @param componentId Component identifier
     * @param newImplementation New implementation address
     * @param data Upgrade data
     */
    function upgradeComponent(
        bytes32 componentId,
        address newImplementation,
        bytes memory data
    )
        external
        onlyRole(UPGRADER_ROLE)
        whenNotPaused
    {
        Component storage component = components[componentId];
        require(component.initialized, "Component not found");
        require(component.upgradeable, "Not upgradeable");
        require(newImplementation != address(0), "Invalid implementation");
        
        address oldImplementation = component.implementation;
        
        if (data.length > 0) {
            proxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(component.proxy)),
                newImplementation,
                data
            );
        } else {
            proxyAdmin.upgrade(
                TransparentUpgradeableProxy(payable(component.proxy)),
                newImplementation
            );
        }
        
        component.implementation = newImplementation;
        component.version++;
        componentVersions[componentId].push(newImplementation);
        
        emit ComponentUpgraded(
            componentId,
            oldImplementation,
            newImplementation
        );
    }

    /**
     * @notice Get component details
     * @param componentId Component identifier
     */
    function getComponent(bytes32 componentId)
        external
        view
        returns (
            address implementation,
            address proxy,
            bytes32 componentType,
            uint256 version,
            bool initialized,
            bool upgradeable
        )
    {
        Component memory component = components[componentId];
        require(component.initialized, "Component not found");
        
        return (
            component.implementation,
            component.proxy,
            component.componentType,
            component.version,
            component.initialized,
            component.upgradeable
        );
    }

    /**
     * @notice Get component version history
     * @param componentId Component identifier
     */
    function getComponentVersions(bytes32 componentId)
        external
        view
        returns (address[] memory)
    {
        return componentVersions[componentId];
    }

    /**
     * @notice Get component ID from proxy address
     * @param proxy Proxy contract address
     */
    function getComponentId(address proxy)
        external
        view
        returns (bytes32)
    {
        bytes32 componentId = componentIds[proxy];
        require(components[componentId].initialized, "Component not found");
        return componentId;
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}