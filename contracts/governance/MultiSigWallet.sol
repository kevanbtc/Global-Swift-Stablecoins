// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MultiSigWallet
 * @notice Institutional-grade multi-signature wallet for high-value operations
 * @dev Implements configurable multi-signature requirements with timelock and emergency controls
 */
contract MultiSigWallet is Ownable, ReentrancyGuard {

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 numConfirmations;
        uint256 submissionTime;
        uint256 executionTime;
    }

    struct Signer {
        bool isActive;
        uint256 weight;           // Voting weight for weighted multisig
        string role;             // Role description
        uint256 lastActivity;    // Last transaction timestamp
    }

    // Multi-signature settings
    uint256 public requiredConfirmations;
    uint256 public totalSigners;
    uint256 public totalWeight;
    uint256 public requiredWeight;     // For weighted multisig

    // Time controls
    uint256 public timelockPeriod;     // Minimum delay before execution
    uint256 public emergencyPeriod;    // Emergency execution window

    // Transaction tracking
    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => bool)) public confirmations;
    mapping(address => Signer) public signers;

    uint256 public transactionCount;
    uint256[] public pendingTransactions;

    // Emergency controls
    bool public emergencyMode;
    uint256 public emergencyActivationTime;
    address public emergencyActivator;

    // Constants
    uint256 public constant MAX_TIMELOCK = 7 days;
    uint256 public constant MIN_TIMELOCK = 1 hours;
    uint256 public constant MAX_SIGNERS = 20;
    uint256 public constant EMERGENCY_WINDOW = 24 hours;

    // Events
    event SignerAdded(address indexed signer, uint256 weight, string role);
    event SignerRemoved(address indexed signer);
    event TransactionSubmitted(uint256 indexed txId, address indexed submitter);
    event TransactionConfirmed(uint256 indexed txId, address indexed confirmer);
    event TransactionExecuted(uint256 indexed txId);
    event TransactionCancelled(uint256 indexed txId);
    event EmergencyModeActivated(address indexed activator);
    event EmergencyModeDeactivated();

    modifier onlySigner() {
        require(signers[msg.sender].isActive, "Not an active signer");
        _;
    }

    modifier notExecuted(uint256 _txId) {
        require(!transactions[_txId].executed, "Transaction already executed");
        _;
    }

    modifier notConfirmed(uint256 _txId) {
        require(!confirmations[_txId][msg.sender], "Transaction already confirmed");
        _;
    }

    constructor(
        address[] memory _signers,
        uint256[] memory _weights,
        string[] memory _roles,
        uint256 _requiredConfirmations,
        uint256 _timelockPeriod
    ) Ownable(msg.sender) {
        require(_signers.length > 0, "At least one signer required");
        require(_signers.length <= MAX_SIGNERS, "Too many signers");
        require(_signers.length == _weights.length && _weights.length == _roles.length, "Array length mismatch");
        require(_requiredConfirmations > 0 && _requiredConfirmations <= _signers.length, "Invalid confirmation requirement");
        require(_timelockPeriod >= MIN_TIMELOCK && _timelockPeriod <= MAX_TIMELOCK, "Invalid timelock period");

        requiredConfirmations = _requiredConfirmations;
        timelockPeriod = _timelockPeriod;

        for (uint256 i = 0; i < _signers.length; i++) {
            require(_signers[i] != address(0), "Invalid signer address");
            require(_weights[i] > 0, "Weight must be > 0");
            require(!signers[_signers[i]].isActive, "Duplicate signer");

            signers[_signers[i]] = Signer({
                isActive: true,
                weight: _weights[i],
                role: _roles[i],
                lastActivity: block.timestamp
            });

            totalSigners++;
            totalWeight += _weights[i];

            emit SignerAdded(_signers[i], _weights[i], _roles[i]);
        }

        // Default to simple multisig (not weighted)
        requiredWeight = requiredConfirmations;
    }

    /**
     * @notice Submit a new transaction for approval
     */
    function submitTransaction(
        address _to,
        uint256 _value,
        bytes memory _data
    ) public onlySigner returns (uint256) {
        require(_to != address(0), "Invalid destination");

        uint256 txId = transactionCount++;

        transactions[txId] = Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0,
            submissionTime: block.timestamp,
            executionTime: 0
        });

        pendingTransactions.push(txId);

        // Auto-confirm by submitter
        _confirmTransaction(txId);

        emit TransactionSubmitted(txId, msg.sender);
        return txId;
    }

    /**
     * @notice Confirm a pending transaction
     */
    function confirmTransaction(uint256 _txId) public onlySigner
        notExecuted(_txId)
        notConfirmed(_txId)
    {
        _confirmTransaction(_txId);
    }

    /**
     * @notice Execute a confirmed transaction
     */
    function executeTransaction(uint256 _txId) public onlySigner
        notExecuted(_txId)
        nonReentrant
    {
        Transaction storage transaction = transactions[_txId];
        require(_isConfirmed(_txId), "Transaction not confirmed");
        require(_canExecute(_txId), "Timelock not expired");

        transaction.executed = true;
        transaction.executionTime = block.timestamp;

        // Update signer activity
        signers[msg.sender].lastActivity = block.timestamp;

        // Remove from pending list
        _removePendingTransaction(_txId);

        // Execute the transaction
        (bool success,) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Transaction execution failed");

        emit TransactionExecuted(_txId);
    }

    /**
     * @notice Cancel a pending transaction
     */
    function cancelTransaction(uint256 _txId) public onlyOwner notExecuted(_txId) {
        _removePendingTransaction(_txId);
        emit TransactionCancelled(_txId);
    }

    /**
     * @notice Emergency execution (bypasses timelock)
     */
    function emergencyExecute(uint256 _txId) public onlySigner
        notExecuted(_txId)
        nonReentrant
    {
        require(emergencyMode, "Emergency mode not active");
        require(
            block.timestamp <= emergencyActivationTime + EMERGENCY_WINDOW,
            "Emergency window expired"
        );

        Transaction storage transaction = transactions[_txId];
        require(_isConfirmed(_txId), "Transaction not confirmed");

        transaction.executed = true;
        transaction.executionTime = block.timestamp;

        signers[msg.sender].lastActivity = block.timestamp;
        _removePendingTransaction(_txId);

        (bool success,) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Emergency execution failed");

        emit TransactionExecuted(_txId);
    }

    /**
     * @notice Activate emergency mode
     */
    function activateEmergencyMode() public onlySigner {
        require(!emergencyMode, "Emergency mode already active");

        emergencyMode = true;
        emergencyActivationTime = block.timestamp;
        emergencyActivator = msg.sender;

        emit EmergencyModeActivated(msg.sender);
    }

    /**
     * @notice Deactivate emergency mode
     */
    function deactivateEmergencyMode() public onlyOwner {
        require(emergencyMode, "Emergency mode not active");

        emergencyMode = false;
        emergencyActivationTime = 0;
        emergencyActivator = address(0);

        emit EmergencyModeDeactivated();
    }

    /**
     * @notice Add a new signer
     */
    function addSigner(
        address _signer,
        uint256 _weight,
        string memory _role
    ) public onlyOwner {
        require(_signer != address(0), "Invalid signer address");
        require(!signers[_signer].isActive, "Signer already exists");
        require(totalSigners < MAX_SIGNERS, "Maximum signers reached");
        require(_weight > 0, "Weight must be > 0");

        signers[_signer] = Signer({
            isActive: true,
            weight: _weight,
            role: _role,
            lastActivity: block.timestamp
        });

        totalSigners++;
        totalWeight += _weight;

        emit SignerAdded(_signer, _weight, _role);
    }

    /**
     * @notice Remove a signer
     */
    function removeSigner(address _signer) public onlyOwner {
        require(signers[_signer].isActive, "Signer not active");
        require(totalSigners > requiredConfirmations, "Cannot remove required signer");

        totalSigners--;
        totalWeight -= signers[_signer].weight;
        signers[_signer].isActive = false;

        emit SignerRemoved(_signer);
    }

    /**
     * @notice Update multisig settings
     */
    function updateSettings(
        uint256 _requiredConfirmations,
        uint256 _timelockPeriod
    ) public onlyOwner {
        require(_requiredConfirmations > 0 && _requiredConfirmations <= totalSigners, "Invalid confirmation requirement");
        require(_timelockPeriod >= MIN_TIMELOCK && _timelockPeriod <= MAX_TIMELOCK, "Invalid timelock period");

        requiredConfirmations = _requiredConfirmations;
        timelockPeriod = _timelockPeriod;
        requiredWeight = _requiredConfirmations; // Update for simple multisig
    }

    /**
     * @notice Get transaction details
     */
    function getTransaction(uint256 _txId) public view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 numConfirmations,
            uint256 submissionTime
        )
    {
        Transaction memory transaction = transactions[_txId];
        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations,
            transaction.submissionTime
        );
    }

    /**
     * @notice Get pending transactions
     */
    function getPendingTransactions() public view returns (uint256[] memory) {
        return pendingTransactions;
    }

    /**
     * @notice Check if transaction is confirmed
     */
    function isConfirmed(uint256 _txId) public view returns (bool) {
        return _isConfirmed(_txId);
    }

    /**
     * @notice Check if transaction can be executed
     */
    function canExecute(uint256 _txId) public view returns (bool) {
        return _canExecute(_txId);
    }

    /**
     * @notice Get signer information
     */
    function getSignerInfo(address _signer) public view
        returns (bool isActive, uint256 weight, string memory role, uint256 lastActivity)
    {
        Signer memory signer = signers[_signer];
        return (signer.isActive, signer.weight, signer.role, signer.lastActivity);
    }

    // Internal functions

    function _confirmTransaction(uint256 _txId) internal {
        confirmations[_txId][msg.sender] = true;
        transactions[_txId].numConfirmations++;

        signers[msg.sender].lastActivity = block.timestamp;

        emit TransactionConfirmed(_txId, msg.sender);
    }

    function _isConfirmed(uint256 _txId) internal view returns (bool) {
        return transactions[_txId].numConfirmations >= requiredConfirmations;
    }

    function _canExecute(uint256 _txId) internal view returns (bool) {
        Transaction memory transaction = transactions[_txId];

        // Emergency mode bypasses timelock
        if (emergencyMode) {
            return true;
        }

        // Check timelock
        return block.timestamp >= transaction.submissionTime + timelockPeriod;
    }

    function _removePendingTransaction(uint256 _txId) internal {
        for (uint256 i = 0; i < pendingTransactions.length; i++) {
            if (pendingTransactions[i] == _txId) {
                pendingTransactions[i] = pendingTransactions[pendingTransactions.length - 1];
                pendingTransactions.pop();
                break;
            }
        }
    }

    // Fallback function to receive ETH
    receive() external payable {}
}
