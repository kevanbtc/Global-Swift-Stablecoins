// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CBDCInfrastructure
 * @notice Central Bank Digital Currency infrastructure and management
 * @dev Manages CBDC operations, monetary policy, and regulatory compliance
 */
contract CBDCInfrastructure is Ownable, ReentrancyGuard {

    enum CBDCType {
        RETAIL,
        WHOLESALE,
        CROSS_BORDER,
        PROGRAMMABLE
    }

    enum MonetaryPolicy {
        FIXED_SUPPLY,
        INFLATION_TARGETING,
        EXCHANGE_RATE_TARGET,
        QUANTITY_THEORY,
        MODERN_MONETARY_THEORY
    }

    enum TransactionType {
        TRANSFER,
        MINT,
        BURN,
        FREEZE,
        UNFREEZE,
        CONFISCATE,
        PROGRAMMABLE_EXECUTION
    }

    struct CBDCConfig {
        address cbdcToken;
        CBDCType cbdcType;
        MonetaryPolicy monetaryPolicy;
        uint256 maxSupply;
        uint256 currentSupply;
        uint256 interestRate; // basis points
        uint256 demurrageRate; // basis points
        bool programmable;
        bool crossBorderEnabled;
        mapping(address => bool) authorizedMinters;
        mapping(address => bool) authorizedBurners;
    }

    struct MonetaryPolicyParams {
        uint256 inflationTarget; // basis points
        uint256 unemploymentTarget; // basis points
        uint256 gdpGrowthTarget; // basis points
        uint256 exchangeRateTarget; // USD per unit * 1e18
        uint256 quantityMultiplier; // velocity adjustment
    }

    struct ProgrammableTransaction {
        bytes32 txId;
        address from;
        address to;
        uint256 amount;
        bytes32 conditionHash;
        bytes32 executionHash;
        uint256 expiryTime;
        bool executed;
        bool programmable;
    }

    // Storage
    mapping(bytes32 => CBDCConfig) public cbdcConfigs;
    mapping(bytes32 => MonetaryPolicyParams) public monetaryPolicies;
    mapping(bytes32 => ProgrammableTransaction) public programmableTransactions;

    bytes32[] public activeCBDCs;
    bytes32[] public pendingTransactions;

    // Global parameters
    uint256 public globalMaxSupply = 1000000000 * 1e18; // 1B units
    uint256 public globalInterestRate = 500; // 5%
    uint256 public emergencyStopThreshold = 1000000 * 1e18; // 1M units

    // Events
    event CBDCCreated(bytes32 indexed cbdcId, CBDCType cbdcType, address tokenAddress);
    event SupplyAdjusted(bytes32 indexed cbdcId, uint256 oldSupply, uint256 newSupply);
    event ProgrammableTransactionCreated(bytes32 indexed txId, address indexed from, address indexed to);
    event ProgrammableTransactionExecuted(bytes32 indexed txId, bytes32 executionHash);
    event MonetaryPolicyUpdated(bytes32 indexed cbdcId, MonetaryPolicy policy);
    event EmergencyStop(bytes32 indexed cbdcId, string reason);

    modifier validCBDC(bytes32 _cbdcId) {
        require(cbdcConfigs[_cbdcId].cbdcToken != address(0), "CBDC not found");
        _;
    }

    modifier onlyAuthorizedMinter(bytes32 _cbdcId) {
        require(cbdcConfigs[_cbdcId].authorizedMinters[msg.sender], "Not authorized minter");
        _;
    }

    modifier onlyAuthorizedBurner(bytes32 _cbdcId) {
        require(cbdcConfigs[_cbdcId].authorizedBurners[msg.sender], "Not authorized burner");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new CBDC configuration
     */
    function createCBDC(
        bytes32 _cbdcId,
        address _tokenAddress,
        CBDCType _cbdcType,
        MonetaryPolicy _monetaryPolicy,
        uint256 _maxSupply,
        bool _programmable,
        bool _crossBorderEnabled
    ) public onlyOwner returns (bytes32) {
        require(cbdcConfigs[_cbdcId].cbdcToken == address(0), "CBDC already exists");
        require(_maxSupply <= globalMaxSupply, "Supply exceeds global limit");

        CBDCConfig storage config = cbdcConfigs[_cbdcId];
        config.cbdcToken = _tokenAddress;
        config.cbdcType = _cbdcType;
        config.monetaryPolicy = _monetaryPolicy;
        config.maxSupply = _maxSupply;
        config.programmable = _programmable;
        config.crossBorderEnabled = _crossBorderEnabled;

        activeCBDCs.push(_cbdcId);

        emit CBDCCreated(_cbdcId, _cbdcType, _tokenAddress);
        return _cbdcId;
    }

    /**
     * @notice Adjust CBDC supply through monetary policy
     */
    function adjustSupply(
        bytes32 _cbdcId,
        uint256 _newSupply,
        string memory _reason
    ) public onlyOwner validCBDC(_cbdcId) {
        CBDCConfig storage config = cbdcConfigs[_cbdcId];
        uint256 oldSupply = config.currentSupply;

        require(_newSupply <= config.maxSupply, "Supply exceeds CBDC limit");

        config.currentSupply = _newSupply;

        emit SupplyAdjusted(_cbdcId, oldSupply, _newSupply);
    }

    /**
     * @notice Set monetary policy parameters
     */
    function setMonetaryPolicyParams(
        bytes32 _cbdcId,
        uint256 _inflationTarget,
        uint256 _unemploymentTarget,
        uint256 _gdpGrowthTarget,
        uint256 _exchangeRateTarget,
        uint256 _quantityMultiplier
    ) public onlyOwner validCBDC(_cbdcId) {
        MonetaryPolicyParams storage params = monetaryPolicies[_cbdcId];
        params.inflationTarget = _inflationTarget;
        params.unemploymentTarget = _unemploymentTarget;
        params.gdpGrowthTarget = _gdpGrowthTarget;
        params.exchangeRateTarget = _exchangeRateTarget;
        params.quantityMultiplier = _quantityMultiplier;

        emit MonetaryPolicyUpdated(_cbdcId, cbdcConfigs[_cbdcId].monetaryPolicy);
    }

    /**
     * @notice Authorize minter for CBDC
     */
    function authorizeMinter(bytes32 _cbdcId, address _minter, bool _authorized) public onlyOwner
        validCBDC(_cbdcId)
    {
        cbdcConfigs[_cbdcId].authorizedMinters[_minter] = _authorized;
    }

    /**
     * @notice Authorize burner for CBDC
     */
    function authorizeBurner(bytes32 _cbdcId, address _burner, bool _authorized) public onlyOwner
        validCBDC(_cbdcId)
    {
        cbdcConfigs[_cbdcId].authorizedBurners[_burner] = _authorized;
    }

    /**
     * @notice Create programmable transaction
     */
    function createProgrammableTransaction(
        bytes32 _cbdcId,
        address _to,
        uint256 _amount,
        bytes32 _conditionHash,
        uint256 _expiryTime
    ) public validCBDC(_cbdcId) returns (bytes32) {
        require(cbdcConfigs[_cbdcId].programmable, "CBDC not programmable");

        bytes32 txId = keccak256(abi.encodePacked(
            _cbdcId, msg.sender, _to, _amount, block.timestamp
        ));

        ProgrammableTransaction storage tx = programmableTransactions[txId];
        tx.txId = txId;
        tx.from = msg.sender;
        tx.to = _to;
        tx.amount = _amount;
        tx.conditionHash = _conditionHash;
        tx.expiryTime = _expiryTime;
        tx.programmable = true;

        pendingTransactions.push(txId);

        emit ProgrammableTransactionCreated(txId, msg.sender, _to);
        return txId;
    }

    /**
     * @notice Execute programmable transaction
     */
    function executeProgrammableTransaction(
        bytes32 _txId,
        bytes32 _executionHash
    ) public {
        ProgrammableTransaction storage tx = programmableTransactions[_txId];
        require(tx.programmable, "Not a programmable transaction");
        require(!tx.executed, "Transaction already executed");
        require(block.timestamp <= tx.expiryTime, "Transaction expired");

        tx.executionHash = _executionHash;
        tx.executed = true;

        // Remove from pending
        for (uint256 i = 0; i < pendingTransactions.length; i++) {
            if (pendingTransactions[i] == _txId) {
                pendingTransactions[i] = pendingTransactions[pendingTransactions.length - 1];
                pendingTransactions.pop();
                break;
            }
        }

        emit ProgrammableTransactionExecuted(_txId, _executionHash);
    }

    /**
     * @notice Emergency stop for CBDC
     */
    function emergencyStop(bytes32 _cbdcId, string memory _reason) public onlyOwner validCBDC(_cbdcId) {
        // Implementation would freeze all operations for this CBDC
        emit EmergencyStop(_cbdcId, _reason);
    }

    /**
     * @notice Get CBDC configuration
     */
    function getCBDCConfig(bytes32 _cbdcId) public view
        returns (
            address tokenAddress,
            CBDCType cbdcType,
            MonetaryPolicy monetaryPolicy,
            uint256 maxSupply,
            uint256 currentSupply,
            bool programmable,
            bool crossBorderEnabled
        )
    {
        CBDCConfig storage config = cbdcConfigs[_cbdcId];
        return (
            config.cbdcToken,
            config.cbdcType,
            config.monetaryPolicy,
            config.maxSupply,
            config.currentSupply,
            config.programmable,
            config.crossBorderEnabled
        );
    }

    /**
     * @notice Get monetary policy parameters
     */
    function getMonetaryPolicyParams(bytes32 _cbdcId) public view
        returns (
            uint256 inflationTarget,
            uint256 unemploymentTarget,
            uint256 gdpGrowthTarget,
            uint256 exchangeRateTarget,
            uint256 quantityMultiplier
        )
    {
        MonetaryPolicyParams memory params = monetaryPolicies[_cbdcId];
        return (
            params.inflationTarget,
            params.unemploymentTarget,
            params.gdpGrowthTarget,
            params.exchangeRateTarget,
            params.quantityMultiplier
        );
    }

    /**
     * @notice Get programmable transaction details
     */
    function getProgrammableTransaction(bytes32 _txId) public view
        returns (
            address from,
            address to,
            uint256 amount,
            bytes32 conditionHash,
            uint256 expiryTime,
            bool executed
        )
    {
        ProgrammableTransaction memory tx = programmableTransactions[_txId];
        return (
            tx.from,
            tx.to,
            tx.amount,
            tx.conditionHash,
            tx.expiryTime,
            tx.executed
        );
    }

    /**
     * @notice Check if address is authorized minter
     */
    function isAuthorizedMinter(bytes32 _cbdcId, address _minter) public view returns (bool) {
        return cbdcConfigs[_cbdcId].authorizedMinters[_minter];
    }

    /**
     * @notice Check if address is authorized burner
     */
    function isAuthorizedBurner(bytes32 _cbdcId, address _burner) public view returns (bool) {
        return cbdcConfigs[_cbdcId].authorizedBurners[_burner];
    }

    /**
     * @notice Get active CBDCs
     */
    function getActiveCBDCs() public view returns (bytes32[] memory) {
        return activeCBDCs;
    }

    /**
     * @notice Get pending programmable transactions
     */
    function getPendingTransactions() public view returns (bytes32[] memory) {
        return pendingTransactions;
    }

    /**
     * @notice Update global parameters
     */
    function updateGlobalParameters(
        uint256 _globalMaxSupply,
        uint256 _globalInterestRate,
        uint256 _emergencyStopThreshold
    ) public onlyOwner {
        globalMaxSupply = _globalMaxSupply;
        globalInterestRate = _globalInterestRate;
        emergencyStopThreshold = _emergencyStopThreshold;
    }
}
