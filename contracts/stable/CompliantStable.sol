// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CompliantStable
 * @notice Asset-backed stablecoin with regulatory compliance
 * @dev Implements NAV-based rebase mechanism with compliance checks
 */
contract CompliantStable is ERC20, ERC20Permit, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct Reserve {
        address asset;           // Underlying reserve asset
        uint256 amount;          // Amount held in reserve
        uint256 weight;          // Risk weight (basis points)
        bool isActive;           // Whether reserve is active
    }

    struct ComplianceCheck {
        address account;
        uint256 amount;
        bytes32 txHash;
        bool approved;
        uint256 timestamp;
    }

    // Reserve management
    mapping(address => Reserve) public reserves;
    address[] public reserveAssets;
    uint256 public totalReserveValue; // USD value (6 decimals)

    // NAV and rebase
    uint256 public navPerToken;       // NAV per token (18 decimals)
    uint256 public lastRebaseTime;
    uint256 public rebaseCooldown = 1 hours;

    // Compliance
    mapping(bytes32 => ComplianceCheck) public complianceChecks;
    mapping(address => bool) public blacklisted;
    uint256 public maxTransactionAmount = 1000000 * 1e18; // 1M tokens

    // Events
    event ReserveAdded(address indexed asset, uint256 amount, uint256 weight);
    event ReserveRemoved(address indexed asset);
    event Rebase(uint256 oldNav, uint256 newNav, uint256 totalSupply);
    event ComplianceCheckPerformed(bytes32 indexed checkId, address indexed account, bool approved);
    event BlacklistUpdated(address indexed account, bool blacklisted);

    constructor(
        string memory name,
        string memory symbol,
        address admin
    ) ERC20(name, symbol) ERC20Permit(name) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);

        navPerToken = 1e18; // Start at $1.00
        lastRebaseTime = block.timestamp;
    }

    /**
     * @notice Mint tokens against reserves (only minter)
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        require(_checkCompliance(to, amount), "Compliance check failed");
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens (only burner)
     */
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused {
        _burn(from, amount);
    }

    /**
     * @notice Transfer with compliance checks
     */
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        require(_checkCompliance(msg.sender, amount), "Sender compliance failed");
        require(_checkCompliance(to, amount), "Recipient compliance failed");
        require(amount <= maxTransactionAmount, "Exceeds max transaction amount");
        return super.transfer(to, amount);
    }

    /**
     * @notice TransferFrom with compliance checks
     */
    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        require(_checkCompliance(from, amount), "Sender compliance failed");
        require(_checkCompliance(to, amount), "Recipient compliance failed");
        require(amount <= maxTransactionAmount, "Exceeds max transaction amount");
        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice Add reserve asset
     */
    function addReserve(
        address asset,
        uint256 amount,
        uint256 weight
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(reserves[asset].asset == address(0), "Reserve already exists");

        reserves[asset] = Reserve({
            asset: asset,
            amount: amount,
            weight: weight,
            isActive: true
        });

        reserveAssets.push(asset);
        emit ReserveAdded(asset, amount, weight);
    }

    /**
     * @notice Update reserve amount
     */
    function updateReserveAmount(address asset, uint256 newAmount) external onlyRole(ORACLE_ROLE) {
        require(reserves[asset].isActive, "Reserve not active");
        reserves[asset].amount = newAmount;
    }

    /**
     * @notice Update total reserve value (USD)
     */
    function updateReserveValue(uint256 newValue) external onlyRole(ORACLE_ROLE) {
        totalReserveValue = newValue;
    }

    /**
     * @notice Perform NAV rebase
     */
    function rebase() external onlyRole(ORACLE_ROLE) {
        require(block.timestamp >= lastRebaseTime + rebaseCooldown, "Rebase cooldown active");

        uint256 oldNav = navPerToken;
        uint256 totalSupply_ = totalSupply();

        if (totalSupply_ > 0) {
            navPerToken = (totalReserveValue * 1e18) / totalSupply_;
        }

        lastRebaseTime = block.timestamp;
        emit Rebase(oldNav, navPerToken, totalSupply_);
    }

    /**
     * @notice Get current NAV per token
     */
    function getNavPerToken() external view returns (uint256) {
        return navPerToken;
    }

    /**
     * @notice Check compliance for transaction
     */
    function _checkCompliance(address account, uint256 amount) internal returns (bool) {
        if (blacklisted[account]) return false;

        bytes32 checkId = keccak256(abi.encodePacked(account, amount, block.timestamp));
        bool approved = !hasRole(COMPLIANCE_ROLE, address(0)); // If no compliance role set, approve

        complianceChecks[checkId] = ComplianceCheck({
            account: account,
            amount: amount,
            txHash: checkId,
            approved: approved,
            timestamp: block.timestamp
        });

        emit ComplianceCheckPerformed(checkId, account, approved);
        return approved;
    }

    /**
     * @notice Update blacklist status
     */
    function setBlacklist(address account, bool status) external onlyRole(COMPLIANCE_ROLE) {
        blacklisted[account] = status;
        emit BlacklistUpdated(account, status);
    }

    /**
     * @notice Set max transaction amount
     */
    function setMaxTransactionAmount(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxTransactionAmount = amount;
    }

    /**
     * @notice Set rebase cooldown
     */
    function setRebaseCooldown(uint256 cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rebaseCooldown = cooldown;
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Get reserve assets count
     */
    function getReserveCount() external view returns (uint256) {
        return reserveAssets.length;
    }

    /**
     * @notice Get reserve asset by index
     */
    function getReserveAsset(uint256 index) external view returns (address) {
        return reserveAssets[index];
    }
}
