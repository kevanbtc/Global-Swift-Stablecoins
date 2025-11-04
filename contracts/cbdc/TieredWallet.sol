// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title TieredWallet
 * @notice Multi-tiered wallet system for CBDC with different access levels
 * @dev Implements tiered access control and limits for CBDC transactions
 */
contract TieredWallet is AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TIER_MANAGER_ROLE = keccak256("TIER_MANAGER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    enum TierLevel {
        Unverified,   // Basic tier with minimal limits
        Retail,       // Standard retail user
        Business,     // Business account
        Institutional,// Financial institution
        Central       // Central bank level
    }

    struct Tier {
        TierLevel level;
        uint256 dailyLimit;
        uint256 monthlyLimit;
        uint256 transactionLimit;
        bool requiresApproval;
        uint256 cooldownPeriod;
        bool active;
    }

    struct WalletInfo {
        address owner;
        TierLevel tier;
        uint256 dailyUsed;
        uint256 monthlyUsed;
        uint256 lastDailyReset;
        uint256 lastMonthlyReset;
        uint256 lastTransaction;
        bool frozen;
        mapping(address => bool) approvedOperators;
    }

    struct TransactionRequest {
        bytes32 requestId;
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
        bool approved;
        mapping(address => bool) approvals;
        uint256 approvalCount;
    }

    // State variables
    mapping(TierLevel => Tier) public tiers;
    mapping(address => WalletInfo) public wallets;
    mapping(bytes32 => TransactionRequest) public transactionRequests;
    mapping(address => bytes32[]) public pendingRequests;
    
    IERC20 public cbdcToken;
    uint256 public requiredApprovals;
    
    // Events
    event TierConfigured(
        TierLevel indexed level,
        uint256 dailyLimit,
        uint256 monthlyLimit,
        uint256 transactionLimit
    );

    event WalletTierChanged(
        address indexed wallet,
        TierLevel oldTier,
        TierLevel newTier
    );

    event TransactionRequested(
        bytes32 indexed requestId,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event TransactionApproved(
        bytes32 indexed requestId,
        address indexed approver
    );

    event TransactionExecuted(
        bytes32 indexed requestId,
        address from,
        address to,
        uint256 amount
    );

    event WalletFrozen(
        address indexed wallet,
        address indexed by,
        string reason
    );

    event WalletUnfrozen(
        address indexed wallet,
        address indexed by
    );

    constructor(
        address _cbdcToken,
        uint256 _requiredApprovals
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TIER_MANAGER_ROLE, msg.sender);
        _grantRole(COMPLIANCE_ROLE, msg.sender);

        cbdcToken = IERC20(_cbdcToken);
        requiredApprovals = _requiredApprovals;

        // Configure default tiers
        configureTier(
            TierLevel.Unverified,
            1000e18,    // 1,000 tokens daily
            5000e18,    // 5,000 tokens monthly
            100e18,     // 100 tokens per transaction
            false,      // No approval required
            0           // No cooldown
        );

        configureTier(
            TierLevel.Retail,
            10000e18,   // 10,000 tokens daily
            50000e18,   // 50,000 tokens monthly
            1000e18,    // 1,000 tokens per transaction
            false,      // No approval required
            1 hours     // 1 hour cooldown
        );

        configureTier(
            TierLevel.Business,
            100000e18,  // 100,000 tokens daily
            1000000e18, // 1,000,000 tokens monthly
            10000e18,   // 10,000 tokens per transaction
            true,       // Requires approval
            2 hours     // 2 hours cooldown
        );

        configureTier(
            TierLevel.Institutional,
            1000000e18, // 1,000,000 tokens daily
            10000000e18,// 10,000,000 tokens monthly
            100000e18,  // 100,000 tokens per transaction
            true,       // Requires approval
            4 hours     // 4 hours cooldown
        );

        configureTier(
            TierLevel.Central,
            type(uint256).max, // Unlimited daily
            type(uint256).max, // Unlimited monthly
            type(uint256).max, // Unlimited per transaction
            true,             // Requires approval
            24 hours         // 24 hours cooldown
        );
    }

    /**
     * @notice Configure a tier's parameters
     * @param level Tier level
     * @param dailyLimit Daily transaction limit
     * @param monthlyLimit Monthly transaction limit
     * @param transactionLimit Per-transaction limit
     * @param requiresApproval Whether transactions need approval
     * @param cooldownPeriod Cooldown between transactions
     */
    function configureTier(
        TierLevel level,
        uint256 dailyLimit,
        uint256 monthlyLimit,
        uint256 transactionLimit,
        bool requiresApproval,
        uint256 cooldownPeriod
    )
        public
        onlyRole(TIER_MANAGER_ROLE)
    {
        require(monthlyLimit >= dailyLimit, "Monthly limit too low");
        require(transactionLimit <= dailyLimit, "Transaction limit too high");
        
        tiers[level] = Tier({
            level: level,
            dailyLimit: dailyLimit,
            monthlyLimit: monthlyLimit,
            transactionLimit: transactionLimit,
            requiresApproval: requiresApproval,
            cooldownPeriod: cooldownPeriod,
            active: true
        });
        
        emit TierConfigured(
            level,
            dailyLimit,
            monthlyLimit,
            transactionLimit
        );
    }

    /**
     * @notice Set a wallet's tier level
     * @param wallet Wallet address
     * @param level New tier level
     */
    function setWalletTier(address wallet, TierLevel level)
        external
        onlyRole(TIER_MANAGER_ROLE)
        whenNotPaused
    {
        require(tiers[level].active, "Tier not active");
        
        TierLevel oldTier = wallets[wallet].tier;
        wallets[wallet].tier = level;
        
        emit WalletTierChanged(wallet, oldTier, level);
    }

    /**
     * @notice Initiate a transaction
     * @param to Recipient address
     * @param amount Transfer amount
     */
    function initiateTransaction(address to, uint256 amount)
        external
        whenNotPaused
        returns (bytes32)
    {
        WalletInfo storage wallet = wallets[msg.sender];
        Tier storage tier = tiers[wallet.tier];
        
        require(!wallet.frozen, "Wallet frozen");
        require(
            block.timestamp >= wallet.lastTransaction + tier.cooldownPeriod,
            "Cooldown period"
        );
        
        // Reset daily/monthly limits if needed
        if (block.timestamp >= wallet.lastDailyReset + 1 days) {
            wallet.dailyUsed = 0;
            wallet.lastDailyReset = block.timestamp;
        }
        
        if (block.timestamp >= wallet.lastMonthlyReset + 30 days) {
            wallet.monthlyUsed = 0;
            wallet.lastMonthlyReset = block.timestamp;
        }
        
        require(amount <= tier.transactionLimit, "Exceeds transaction limit");
        require(
            wallet.dailyUsed + amount <= tier.dailyLimit,
            "Exceeds daily limit"
        );
        require(
            wallet.monthlyUsed + amount <= tier.monthlyLimit,
            "Exceeds monthly limit"
        );
        
        bytes32 requestId = keccak256(abi.encodePacked(
            msg.sender,
            to,
            amount,
            block.timestamp
        ));
        
        TransactionRequest storage request = transactionRequests[requestId];
        request.requestId = requestId;
        request.from = msg.sender;
        request.to = to;
        request.amount = amount;
        request.timestamp = block.timestamp;
        
        if (!tier.requiresApproval) {
            executeTransaction(requestId);
        } else {
            pendingRequests[msg.sender].push(requestId);
            emit TransactionRequested(requestId, msg.sender, to, amount);
        }
        
        return requestId;
    }

    /**
     * @notice Approve a pending transaction
     * @param requestId Transaction request ID
     */
    function approveTransaction(bytes32 requestId)
        external
        onlyRole(COMPLIANCE_ROLE)
        whenNotPaused
    {
        TransactionRequest storage request = transactionRequests[requestId];
        require(request.timestamp > 0, "Request not found");
        require(!request.approved, "Already approved");
        require(!request.approvals[msg.sender], "Already approved by you");
        
        request.approvals[msg.sender] = true;
        request.approvalCount++;
        
        emit TransactionApproved(requestId, msg.sender);
        
        if (request.approvalCount >= requiredApprovals) {
            executeTransaction(requestId);
        }
    }

    /**
     * @notice Execute an approved transaction
     * @param requestId Transaction request ID
     */
    function executeTransaction(bytes32 requestId) internal {
        TransactionRequest storage request = transactionRequests[requestId];
        WalletInfo storage wallet = wallets[request.from];
        
        request.approved = true;
        wallet.lastTransaction = block.timestamp;
        wallet.dailyUsed += request.amount;
        wallet.monthlyUsed += request.amount;
        
        cbdcToken.transferFrom(request.from, request.to, request.amount);
        
        emit TransactionExecuted(
            requestId,
            request.from,
            request.to,
            request.amount
        );
    }

    /**
     * @notice Freeze a wallet
     * @param wallet Wallet to freeze
     * @param reason Reason for freezing
     */
    function freezeWallet(address wallet, string calldata reason)
        external
        onlyRole(COMPLIANCE_ROLE)
    {
        require(!wallets[wallet].frozen, "Already frozen");
        
        wallets[wallet].frozen = true;
        
        emit WalletFrozen(wallet, msg.sender, reason);
    }

    /**
     * @notice Unfreeze a wallet
     * @param wallet Wallet to unfreeze
     */
    function unfreezeWallet(address wallet)
        external
        onlyRole(COMPLIANCE_ROLE)
    {
        require(wallets[wallet].frozen, "Not frozen");
        
        wallets[wallet].frozen = false;
        
        emit WalletUnfrozen(wallet, msg.sender);
    }

    /**
     * @notice Add an approved operator for a wallet
     * @param operator Operator address
     */
    function addOperator(address operator)
        external
        whenNotPaused
    {
        require(operator != address(0), "Invalid operator");
        wallets[msg.sender].approvedOperators[operator] = true;
    }

    /**
     * @notice Remove an approved operator for a wallet
     * @param operator Operator address
     */
    function removeOperator(address operator)
        external
    {
        wallets[msg.sender].approvedOperators[operator] = false;
    }

    /**
     * @notice Get wallet information
     * @param wallet Wallet address
     */
    function getWalletInfo(address wallet)
        external
        view
        returns (
            TierLevel tier,
            uint256 dailyUsed,
            uint256 monthlyUsed,
            uint256 lastTransaction,
            bool frozen
        )
    {
        WalletInfo storage info = wallets[wallet];
        return (
            info.tier,
            info.dailyUsed,
            info.monthlyUsed,
            info.lastTransaction,
            info.frozen
        );
    }

    /**
     * @notice Get transaction request details
     * @param requestId Request ID
     */
    function getTransactionRequest(bytes32 requestId)
        external
        view
        returns (
            address from,
            address to,
            uint256 amount,
            uint256 timestamp,
            bool approved,
            uint256 approvalCount
        )
    {
        TransactionRequest storage request = transactionRequests[requestId];
        require(request.timestamp > 0, "Request not found");
        
        return (
            request.from,
            request.to,
            request.amount,
            request.timestamp,
            request.approved,
            request.approvalCount
        );
    }

    /**
     * @notice Check if an address is an approved operator
     * @param wallet Wallet address
     * @param operator Operator address
     */
    function isApprovedOperator(address wallet, address operator)
        external
        view
        returns (bool)
    {
        return wallets[wallet].approvedOperators[operator];
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}