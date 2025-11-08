// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ContractAccessFee
 * @notice Manages fee collection for accessing Unykorn L1 contracts
 * @dev Handles fee payments in UNYETH for contract usage rights
 */
contract ContractAccessFee is AccessControl, ReentrancyGuard {
    bytes32 public constant FEE_SETTER_ROLE = keccak256("FEE_SETTER_ROLE");
    bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");

    IERC20 public immutable feeToken; // UNYETH token

    struct ContractFee {
        uint256 baseFee;      // Base access fee in wei
        uint256 perUseFee;    // Additional fee per transaction
        bool active;          // Whether fees are enabled for this contract
        address collector;    // Who receives the fees
    }

    struct AccessGrant {
        address user;
        address contractAddress;
        uint256 grantedAt;
        uint256 expiresAt;
        uint256 usesRemaining;
        bool unlimited;
    }

    mapping(address => ContractFee) public contractFees;
    mapping(bytes32 => AccessGrant) public accessGrants; // keccak256(user, contract) => grant
    mapping(address => uint256) public collectedFees;

    event FeeSet(address indexed contractAddress, uint256 baseFee, uint256 perUseFee, address collector);
    event AccessGranted(bytes32 indexed grantId, address indexed user, address indexed contractAddress, uint256 expiresAt);
    event FeeCollected(address indexed contractAddress, address indexed user, uint256 amount, address collector);
    event ContractRegistered(address indexed contractAddress, address indexed collector);

    constructor(address _feeToken) {
        feeToken = IERC20(_feeToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_SETTER_ROLE, msg.sender);
        _grantRole(COLLECTOR_ROLE, msg.sender);
    }

    /**
     * @notice Register a contract for fee collection
     * @param contractAddress The contract to register
     * @param collector Address that receives fees
     */
    function registerContract(address contractAddress, address collector) public onlyRole(FEE_SETTER_ROLE) {
        require(contractAddress != address(0), "Invalid contract address");
        require(collector != address(0), "Invalid collector address");

        contractFees[contractAddress] = ContractFee({
            baseFee: 0,
            perUseFee: 0,
            active: false,
            collector: collector
        });

        emit ContractRegistered(contractAddress, collector);
    }

    /**
     * @notice Set fees for a registered contract
     * @param contractAddress The contract address
     * @param baseFee Base access fee
     * @param perUseFee Fee per transaction
     */
    function setContractFees(
        address contractAddress,
        uint256 baseFee,
        uint256 perUseFee
    ) public onlyRole(FEE_SETTER_ROLE) {
        require(contractFees[contractAddress].collector != address(0), "Contract not registered");

        contractFees[contractAddress].baseFee = baseFee;
        contractFees[contractAddress].perUseFee = perUseFee;
        contractFees[contractAddress].active = true;

        emit FeeSet(contractAddress, baseFee, perUseFee, contractFees[contractAddress].collector);
    }

    /**
     * @notice Grant access to a contract by paying the base fee
     * @param contractAddress The contract to access
     * @param duration Access duration in seconds (0 for unlimited)
     * @param maxUses Maximum uses (0 for unlimited)
     */
    function grantAccess(
        address contractAddress,
        uint256 duration,
        uint256 maxUses
    ) public nonReentrant {
        ContractFee memory fee = contractFees[contractAddress];
        require(fee.active, "Contract fees not active");
        require(fee.baseFee > 0 || fee.perUseFee > 0, "No fees configured");

        bytes32 grantId = keccak256(abi.encodePacked(msg.sender, contractAddress));

        // Check if user already has access
        AccessGrant memory existingGrant = accessGrants[grantId];
        if (existingGrant.expiresAt > block.timestamp && (existingGrant.unlimited || existingGrant.usesRemaining > 0)) {
            revert("Access already granted");
        }

        // Calculate fee amount
        uint256 feeAmount = fee.baseFee;
        if (maxUses > 0 && fee.perUseFee > 0) {
            feeAmount += maxUses * fee.perUseFee;
        }

        if (feeAmount > 0) {
            require(feeToken.transferFrom(msg.sender, fee.collector, feeAmount), "Fee transfer failed");
            collectedFees[contractAddress] += feeAmount;
        }

        // Grant access
        uint256 expiresAt = duration > 0 ? block.timestamp + duration : type(uint256).max;
        bool unlimited = maxUses == 0;

        accessGrants[grantId] = AccessGrant({
            user: msg.sender,
            contractAddress: contractAddress,
            grantedAt: block.timestamp,
            expiresAt: expiresAt,
            usesRemaining: maxUses,
            unlimited: unlimited
        });

        emit AccessGranted(grantId, msg.sender, contractAddress, expiresAt);
        emit FeeCollected(contractAddress, msg.sender, feeAmount, fee.collector);
    }

    /**
     * @notice Check if a user has access to a contract (called by contracts)
     * @param user User address
     * @param contractAddress Contract address
     * @return hasAccess Whether user has valid access
     */
    function checkAccess(address user, address contractAddress) public view returns (bool hasAccess) {
        bytes32 grantId = keccak256(abi.encodePacked(user, contractAddress));
        AccessGrant memory grant = accessGrants[grantId];

        if (grant.expiresAt <= block.timestamp) return false;
        if (!grant.unlimited && grant.usesRemaining == 0) return false;

        return true;
    }

    /**
     * @notice Consume one use of access (called by contracts)
     * @param user User address
     * @param contractAddress Contract address
     */
    function consumeAccess(address user, address contractAddress) public {
        // Only the contract itself can consume access
        require(msg.sender == contractAddress, "Only contract can consume access");

        bytes32 grantId = keccak256(abi.encodePacked(user, contractAddress));
        AccessGrant storage grant = accessGrants[grantId];

        require(grant.expiresAt > block.timestamp, "Access expired");
        require(grant.unlimited || grant.usesRemaining > 0, "No uses remaining");

        if (!grant.unlimited) {
            grant.usesRemaining--;

            // Charge per-use fee if configured
            ContractFee memory fee = contractFees[contractAddress];
            if (fee.perUseFee > 0) {
                require(feeToken.transferFrom(user, fee.collector, fee.perUseFee), "Per-use fee transfer failed");
                collectedFees[contractAddress] += fee.perUseFee;
                emit FeeCollected(contractAddress, user, fee.perUseFee, fee.collector);
            }
        }
    }

    /**
     * @notice Get access grant details
     * @param user User address
     * @param contractAddress Contract address
     */
    function getAccessGrant(address user, address contractAddress) public view returns (AccessGrant memory) {
        bytes32 grantId = keccak256(abi.encodePacked(user, contractAddress));
        return accessGrants[grantId];
    }

    /**
     * @notice Get contract fee details
     * @param contractAddress Contract address
     */
    function getContractFee(address contractAddress) public view returns (ContractFee memory) {
        return contractFees[contractAddress];
    }

    /**
     * @notice Withdraw collected fees (only collectors)
     * @param contractAddress Contract to withdraw from
     * @param amount Amount to withdraw
     */
    function withdrawFees(address contractAddress, uint256 amount) public {
        ContractFee memory fee = contractFees[contractAddress];
        require(fee.collector == msg.sender, "Not the collector");
        require(amount <= collectedFees[contractAddress], "Insufficient collected fees");

        collectedFees[contractAddress] -= amount;
        require(feeToken.transfer(msg.sender, amount), "Withdrawal failed");
    }

    /**
     * @notice Get total collected fees for a contract
     * @param contractAddress Contract address
     */
    function getCollectedFees(address contractAddress) public view returns (uint256) {
        return collectedFees[contractAddress];
    }
}
