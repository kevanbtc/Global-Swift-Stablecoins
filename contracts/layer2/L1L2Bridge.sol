// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title L1L2Bridge
 * @notice Bridge for asset transfers between L1 and L2
 * @dev Implements secure bridging with verification and rollup support
 */
contract L1L2Bridge is AccessControl, Pausable {
    bytes32 public constant BRIDGE_OPERATOR_ROLE = keccak256("BRIDGE_OPERATOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    struct BridgeConfig {
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 withdrawalDelay;
        uint256 validatorThreshold;
        bool paused;
    }

    struct Transfer {
        bytes32 transferId;
        address token;
        address sender;
        address recipient;
        uint256 amount;
        uint256 timestamp;
        TransferState state;
        uint256 confirmations;
        mapping(address => bool) validatorConfirmations;
    }

    enum TransferState {
        Pending,
        Confirmed,
        Executed,
        Rejected
    }

    struct TokenConfig {
        bool supported;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 dailyLimit;
        uint256 dailyUsed;
        uint256 lastResetTime;
    }

    // State variables
    mapping(bytes32 => Transfer) public transfers;
    mapping(address => TokenConfig) public supportedTokens;
    mapping(address => uint256) public totalDeposited;
    mapping(address => uint256) public totalWithdrawn;
    
    BridgeConfig public config;
    uint256 public transferNonce;
    
    // Events
    event DepositInitiated(
        bytes32 indexed transferId,
        address indexed token,
        address indexed sender,
        address recipient,
        uint256 amount
    );

    event WithdrawalInitiated(
        bytes32 indexed transferId,
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    event TransferConfirmed(
        bytes32 indexed transferId,
        address indexed validator,
        uint256 confirmations
    );

    event TransferExecuted(
        bytes32 indexed transferId,
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    event TransferRejected(
        bytes32 indexed transferId,
        string reason
    );

    constructor(
        uint256 _minDeposit,
        uint256 _maxDeposit,
        uint256 _withdrawalDelay,
        uint256 _validatorThreshold
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BRIDGE_OPERATOR_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);

        config = BridgeConfig({
            minDeposit: _minDeposit,
            maxDeposit: _maxDeposit,
            withdrawalDelay: _withdrawalDelay,
            validatorThreshold: _validatorThreshold,
            paused: false
        });
    }

    /**
     * @notice Configure a token for bridging
     * @param token Token address
     * @param minAmount Minimum transfer amount
     * @param maxAmount Maximum transfer amount
     * @param dailyLimit Daily transfer limit
     */
    function configureToken(
        address token,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    ) public onlyRole(BRIDGE_OPERATOR_ROLE)
    {
        require(token != address(0), "Invalid token");
        require(maxAmount > minAmount, "Invalid limits");
        
        supportedTokens[token] = TokenConfig({
            supported: true,
            minAmount: minAmount,
            maxAmount: maxAmount,
            dailyLimit: dailyLimit,
            dailyUsed: 0,
            lastResetTime: block.timestamp
        });
    }

    /**
     * @notice Initiate a deposit from L1 to L2
     * @param token Token address
     * @param recipient L2 recipient address
     * @param amount Amount to transfer
     */
    function initiateDeposit(
        address token,
        address recipient,
        uint256 amount
    ) public whenNotPaused
        returns (bytes32)
    {
        TokenConfig storage tokenConfig = supportedTokens[token];
        require(tokenConfig.supported, "Token not supported");
        require(amount >= tokenConfig.minAmount, "Amount too low");
        require(amount <= tokenConfig.maxAmount, "Amount too high");
        
        // Update daily limits
        if (block.timestamp >= tokenConfig.lastResetTime + 1 days) {
            tokenConfig.dailyUsed = 0;
            tokenConfig.lastResetTime = block.timestamp;
        }
        
        require(
            tokenConfig.dailyUsed + amount <= tokenConfig.dailyLimit,
            "Daily limit exceeded"
        );
        
        tokenConfig.dailyUsed += amount;
        
        // Transfer tokens to bridge
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        bytes32 transferId = keccak256(abi.encodePacked(
            token,
            msg.sender,
            recipient,
            amount,
            transferNonce++
        ));
        
        Transfer storage transfer = transfers[transferId];
        transfer.transferId = transferId;
        transfer.token = token;
        transfer.sender = msg.sender;
        transfer.recipient = recipient;
        transfer.amount = amount;
        transfer.timestamp = block.timestamp;
        transfer.state = TransferState.Pending;
        
        totalDeposited[token] += amount;
        
        emit DepositInitiated(
            transferId,
            token,
            msg.sender,
            recipient,
            amount
        );
        
        return transferId;
    }

    /**
     * @notice Initiate a withdrawal from L2 to L1
     * @param token Token address
     * @param recipient L1 recipient address
     * @param amount Amount to transfer
     */
    function initiateWithdrawal(
        address token,
        address recipient,
        uint256 amount
    ) public onlyRole(BRIDGE_OPERATOR_ROLE)
        whenNotPaused
        returns (bytes32)
    {
        TokenConfig storage tokenConfig = supportedTokens[token];
        require(tokenConfig.supported, "Token not supported");
        require(amount >= tokenConfig.minAmount, "Amount too low");
        require(amount <= tokenConfig.maxAmount, "Amount too high");
        
        bytes32 transferId = keccak256(abi.encodePacked(
            token,
            address(this),
            recipient,
            amount,
            transferNonce++
        ));
        
        Transfer storage transfer = transfers[transferId];
        transfer.transferId = transferId;
        transfer.token = token;
        transfer.sender = address(this);
        transfer.recipient = recipient;
        transfer.amount = amount;
        transfer.timestamp = block.timestamp;
        transfer.state = TransferState.Pending;
        
        emit WithdrawalInitiated(
            transferId,
            token,
            recipient,
            amount
        );
        
        return transferId;
    }

    /**
     * @notice Confirm a transfer
     * @param transferId Transfer identifier
     */
    function confirmTransfer(bytes32 transferId) public onlyRole(VALIDATOR_ROLE)
        whenNotPaused
    {
        Transfer storage transfer = transfers[transferId];
        require(transfer.timestamp > 0, "Transfer not found");
        require(transfer.state == TransferState.Pending, "Invalid state");
        require(
            !transfer.validatorConfirmations[msg.sender],
            "Already confirmed"
        );
        
        transfer.validatorConfirmations[msg.sender] = true;
        transfer.confirmations++;
        
        emit TransferConfirmed(
            transferId,
            msg.sender,
            transfer.confirmations
        );
        
        if (transfer.confirmations >= config.validatorThreshold) {
            transfer.state = TransferState.Confirmed;
        }
    }

    /**
     * @notice Execute a confirmed transfer
     * @param transferId Transfer identifier
     */
    function executeTransfer(bytes32 transferId) public onlyRole(BRIDGE_OPERATOR_ROLE)
        whenNotPaused
    {
        Transfer storage transfer = transfers[transferId];
        require(transfer.timestamp > 0, "Transfer not found");
        require(transfer.state == TransferState.Confirmed, "Not confirmed");
        require(
            block.timestamp >= transfer.timestamp + config.withdrawalDelay,
            "Withdrawal delay"
        );
        
        transfer.state = TransferState.Executed;
        
        // Execute the transfer
        IERC20(transfer.token).transfer(transfer.recipient, transfer.amount);
        
        totalWithdrawn[transfer.token] += transfer.amount;
        
        emit TransferExecuted(
            transferId,
            transfer.token,
            transfer.recipient,
            transfer.amount
        );
    }

    /**
     * @notice Reject a transfer
     * @param transferId Transfer identifier
     * @param reason Rejection reason
     */
    function rejectTransfer(bytes32 transferId, string calldata reason) public onlyRole(BRIDGE_OPERATOR_ROLE)
    {
        Transfer storage transfer = transfers[transferId];
        require(transfer.timestamp > 0, "Transfer not found");
        require(transfer.state == TransferState.Pending, "Invalid state");
        
        transfer.state = TransferState.Rejected;
        
        // Return tokens to sender if it's a deposit
        if (transfer.sender != address(this)) {
            IERC20(transfer.token).transfer(transfer.sender, transfer.amount);
            totalDeposited[transfer.token] -= transfer.amount;
        }
        
        emit TransferRejected(transferId, reason);
    }

    /**
     * @notice Get transfer details
     * @param transferId Transfer identifier
     */
    function getTransfer(bytes32 transferId) public view
        returns (
            address token,
            address sender,
            address recipient,
            uint256 amount,
            uint256 timestamp,
            TransferState state,
            uint256 confirmations
        )
    {
        Transfer storage transfer = transfers[transferId];
        require(transfer.timestamp > 0, "Transfer not found");
        
        return (
            transfer.token,
            transfer.sender,
            transfer.recipient,
            transfer.amount,
            transfer.timestamp,
            transfer.state,
            transfer.confirmations
        );
    }

    /**
     * @notice Check if a validator has confirmed a transfer
     * @param transferId Transfer identifier
     * @param validator Validator address
     */
    function hasValidatorConfirmed(bytes32 transferId, address validator) public view
        returns (bool)
    {
        Transfer storage transfer = transfers[transferId];
        require(transfer.timestamp > 0, "Transfer not found");
        return transfer.validatorConfirmations[validator];
    }

    /**
     * @notice Update bridge configuration
     * @param minDeposit Minimum deposit amount
     * @param maxDeposit Maximum deposit amount
     * @param withdrawalDelay Withdrawal delay period
     * @param validatorThreshold Required validator confirmations
     */
    function updateConfig(
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 withdrawalDelay,
        uint256 validatorThreshold
    ) public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(maxDeposit > minDeposit, "Invalid deposit limits");
        require(validatorThreshold > 0, "Invalid threshold");
        
        config.minDeposit = minDeposit;
        config.maxDeposit = maxDeposit;
        config.withdrawalDelay = withdrawalDelay;
        config.validatorThreshold = validatorThreshold;
    }

    // Admin functions
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}