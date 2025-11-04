// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title UniversalDeployer
 * @notice Factory contract for deterministic deployment of contracts
 * @dev Supports minimal proxy clones and CREATE2 deployment
 */
contract UniversalDeployer is AccessControl, Pausable {
    using Clones for address;

    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    
    // Deployment tracking
    mapping(bytes32 => address) public implementations;
    mapping(bytes32 => address[]) public deployments;
    mapping(address => bool) public isProxy;
    
    // Events
    event ImplementationRegistered(
        bytes32 indexed id,
        string name,
        address implementation
    );
    event ProxyDeployed(
        bytes32 indexed implementationId,
        address indexed proxy,
        bytes32 salt
    );
    event ContractDeployed(
        bytes32 indexed id,
        address indexed deployment,
        bytes32 salt
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEPLOYER_ROLE, msg.sender);
    }

    /**
     * @notice Register an implementation contract
     * @param name Implementation name
     * @param implementation Implementation address
     */
    function registerImplementation(
        string memory name,
        address implementation
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bytes32)
    {
        require(implementation != address(0), "Invalid implementation");
        
        bytes32 id = keccak256(abi.encodePacked(name));
        require(implementations[id] == address(0), "Already registered");
        
        implementations[id] = implementation;
        
        emit ImplementationRegistered(id, name, implementation);
        return id;
    }

    /**
     * @notice Deploy a minimal proxy clone
     * @param implementationId Implementation identifier
     * @param salt Unique salt for deterministic address
     * @param initData Initialization call data
     */
    function deployProxy(
        bytes32 implementationId,
        bytes32 salt,
        bytes memory initData
    )
        external
        onlyRole(DEPLOYER_ROLE)
        whenNotPaused
        returns (address proxy)
    {
        address implementation = implementations[implementationId];
        require(implementation != address(0), "Implementation not found");
        
        // Deploy proxy
        proxy = implementation.cloneDeterministic(salt);
        isProxy[proxy] = true;
        
        // Initialize if needed
        if (initData.length > 0) {
            (bool success,) = proxy.call(initData);
            require(success, "Initialization failed");
        }
        
        deployments[implementationId].push(proxy);
        
        emit ProxyDeployed(implementationId, proxy, salt);
    }

    /**
     * @notice Deploy contract directly using CREATE2
     * @param id Deployment identifier
     * @param bytecode Contract creation bytecode
     * @param salt Unique salt for deterministic address
     */
    function deployContract(
        bytes32 id,
        bytes memory bytecode,
        bytes32 salt
    )
        external
        onlyRole(DEPLOYER_ROLE)
        whenNotPaused
        returns (address deployment)
    {
        deployment = Create2.deploy(0, salt, bytecode);
        deployments[id].push(deployment);
        
        emit ContractDeployed(id, deployment, salt);
    }

    /**
     * @notice Calculate the deterministic address for a proxy deployment
     * @param implementationId Implementation identifier
     * @param salt Deployment salt
     */
    function computeProxyAddress(bytes32 implementationId, bytes32 salt)
        external
        view
        returns (address)
    {
        address implementation = implementations[implementationId];
        require(implementation != address(0), "Implementation not found");
        
        return implementation.predictDeterministicAddress(salt);
    }

    /**
     * @notice Calculate the deterministic address for a contract deployment
     * @param bytecode Contract creation bytecode
     * @param salt Deployment salt
     */
    function computeContractAddress(bytes memory bytecode, bytes32 salt)
        external
        view
        returns (address)
    {
        return Create2.computeAddress(salt, keccak256(bytecode));
    }

    /**
     * @notice Get all deployments for an implementation or contract type
     * @param id Implementation or deployment identifier
     */
    function getDeployments(bytes32 id)
        external
        view
        returns (address[] memory)
    {
        return deployments[id];
    }

    /**
     * @notice Check if an address is a proxy
     * @param proxy Address to check
     */
    function isProxyDeployment(address proxy)
        external
        view
        returns (bool)
    {
        return isProxy[proxy];
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}