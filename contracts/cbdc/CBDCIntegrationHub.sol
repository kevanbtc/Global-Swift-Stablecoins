// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title CBDCIntegrationHub
 * @notice Central hub for multi-CBDC integration and interoperability
 * @dev Supports digital yuan, digital euro, digital dollar, and other national CBDCs
 */
contract CBDCIntegrationHub is Ownable, ReentrancyGuard, Pausable {

    enum CBDCType {
        DIGITAL_DOLLAR,    // FedNow, Digital Dollar
        DIGITAL_EURO,      // ECB digital euro
        DIGITAL_YUAN,      // PBOC e-CNY
        DIGITAL_POUND,     // BoE digital pound
        DIGITAL_YEN,       // BoJ digital yen
        DIGITAL_SGD,       // MAS digital SGD
        DIGITAL_AUD,       // RBA digital AUD
        OTHER
    }

    enum CBDCStatus {
        INACTIVE,
        PENDING_VERIFICATION,
        ACTIVE,
        SUSPENDED,
        TERMINATED
    }

    enum InteroperabilityMode {
        DIRECT_SETTLEMENT,     // Direct CBDC-to-CBDC
        BRIDGED_SETTLEMENT,    // Via intermediary bridge
        ATOMIC_SWAP,          // Cross-chain atomic swaps
        HYBRID_MODE           // Mixed approach
    }

    struct CBDCConfig {
        CBDCType cbdcType;
        CBDCStatus status;
        address cbdcContract;
        address bridgeContract;
        address oracleContract;
        uint256 minTransferAmount;
        uint256 maxTransferAmount;
        uint256 dailyLimit;
        uint256 usedToday;
        uint256 lastResetTime;
        bool supportsCrossBorder;
        bool requiresKYC;
        string jurisdiction;
        bytes32 regulatoryApprovalHash;
    }

    struct CrossBorderTransfer {
        bytes32 transferId;
        address sender;
        address receiver;
        CBDCType fromCBDC;
        CBDCType toCBDC;
        uint256 amount;
        uint256 exchangeRate;
        uint256 feeAmount;
        InteroperabilityMode mode;
        uint256 initiatedTime;
        uint256 completedTime;
        bytes32 sourceTxHash;
        bytes32 destTxHash;
        bool isCompleted;
        string failureReason;
    }

    struct CBDCBridge {
        address bridgeAddress;
        CBDCType supportedCBDC;
        bool isActive;
        uint256 maxDailyVolume;
        uint256 currentDailyVolume;
        uint256 lastVolumeReset;
        mapping(address => bool) authorizedOperators;
    }

    // Storage
    mapping(CBDCType => CBDCConfig) public cbdcConfigs;
    mapping(bytes32 => CrossBorderTransfer) public crossBorderTransfers;
    mapping(CBDCType => CBDCBridge) public cbdcBridges;
    mapping(address => mapping(CBDCType => uint256)) public userDailyLimits;
    mapping(address => mapping(CBDCType => uint256)) public userLastActivity;

    // Global limits and counters
    uint256 public totalCrossBorderVolume;
    uint256 public totalSuccessfulTransfers;
    uint256 public totalFailedTransfers;
    uint256 public maxGlobalDailyVolume = 1000000000 * 1e18; // 1B units
    uint256 public currentGlobalDailyVolume;
    uint256 public lastGlobalReset;

    // Configuration
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public crossBorderFeeBPS = 50; // 0.5%
    uint256 public minCrossBorderAmount = 1000 * 1e18; // 1000 units
    uint256 public maxCrossBorderAmount = 10000000 * 1e18; // 10M units

    // Events
    event CBDCConfigured(CBDCType indexed cbdcType, address indexed contractAddress);
    event CrossBorderTransferInitiated(bytes32 indexed transferId, address indexed sender, CBDCType fromCBDC, CBDCType toCBDC, uint256 amount);
    event CrossBorderTransferCompleted(bytes32 indexed transferId, bytes32 destTxHash);
    event CrossBorderTransferFailed(bytes32 indexed transferId, string reason);
    event BridgeAuthorized(CBDCType indexed cbdcType, address indexed bridgeAddress);
    event DailyLimitsReset(uint256 resetTime);

    modifier validCBDC(CBDCType _cbdcType) {
        require(cbdcConfigs[_cbdcType].status == CBDCStatus.ACTIVE, "CBDC not active");
        _;
    }

    modifier withinLimits(address _user, CBDCType _cbdcType, uint256 _amount) {
        CBDCConfig memory config = cbdcConfigs[_cbdcType];
        require(_amount >= config.minTransferAmount, "Amount below minimum");
        require(_amount <= config.maxTransferAmount, "Amount above maximum");

        uint256 userUsed = userDailyLimits[_user][_cbdcType];
        require(userUsed + _amount <= config.dailyLimit, "User daily limit exceeded");

        require(currentGlobalDailyVolume + _amount <= maxGlobalDailyVolume, "Global daily limit exceeded");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Configure a CBDC for integration
     */
    function configureCBDC(
        CBDCType _cbdcType,
        address _cbdcContract,
        address _bridgeContract,
        address _oracleContract,
        uint256 _minTransferAmount,
        uint256 _maxTransferAmount,
        uint256 _dailyLimit,
        bool _supportsCrossBorder,
        bool _requiresKYC,
        string memory _jurisdiction,
        bytes32 _regulatoryApprovalHash
    ) external onlyOwner {
        require(_cbdcContract != address(0), "Invalid CBDC contract");
        require(_minTransferAmount < _maxTransferAmount, "Invalid amount limits");

        cbdcConfigs[_cbdcType] = CBDCConfig({
            cbdcType: _cbdcType,
            status: CBDCStatus.ACTIVE,
            cbdcContract: _cbdcContract,
            bridgeContract: _bridgeContract,
            oracleContract: _oracleContract,
            minTransferAmount: _minTransferAmount,
            maxTransferAmount: _maxTransferAmount,
            dailyLimit: _dailyLimit,
            usedToday: 0,
            lastResetTime: block.timestamp,
            supportsCrossBorder: _supportsCrossBorder,
            requiresKYC: _requiresKYC,
            jurisdiction: _jurisdiction,
            regulatoryApprovalHash: _regulatoryApprovalHash
        });

        emit CBDCConfigured(_cbdcType, _cbdcContract);
    }

    /**
     * @notice Authorize a bridge for CBDC operations
     */
    function authorizeBridge(
        CBDCType _cbdcType,
        address _bridgeAddress,
        uint256 _maxDailyVolume
    ) external onlyOwner {
        require(cbdcConfigs[_cbdcType].status == CBDCStatus.ACTIVE, "CBDC not configured");

        cbdcBridges[_cbdcType] = CBDCBridge({
            bridgeAddress: _bridgeAddress,
            supportedCBDC: _cbdcType,
            isActive: true,
            maxDailyVolume: _maxDailyVolume,
            currentDailyVolume: 0,
            lastVolumeReset: block.timestamp
        });

        emit BridgeAuthorized(_cbdcType, _bridgeAddress);
    }

    /**
     * @notice Initiate a cross-border CBDC transfer
     */
    function initiateCrossBorderTransfer(
        CBDCType _fromCBDC,
        CBDCType _toCBDC,
        address _receiver,
        uint256 _amount,
        InteroperabilityMode _mode
    ) external whenNotPaused validCBDC(_fromCBDC) validCBDC(_toCBDC)
              withinLimits(msg.sender, _fromCBDC, _amount) returns (bytes32) {

        require(_receiver != address(0), "Invalid receiver");
        require(_amount >= minCrossBorderAmount, "Amount below cross-border minimum");
        require(_amount <= maxCrossBorderAmount, "Amount above cross-border maximum");

        CBDCConfig memory fromConfig = cbdcConfigs[_fromCBDC];
        CBDCConfig memory toConfig = cbdcConfigs[_toCBDC];

        require(fromConfig.supportsCrossBorder && toConfig.supportsCrossBorder, "Cross-border not supported");

        // Calculate exchange rate and fees
        uint256 exchangeRate = _getExchangeRate(_fromCBDC, _toCBDC);
        uint256 feeAmount = (_amount * crossBorderFeeBPS) / BPS_DENOMINATOR;

        bytes32 transferId = keccak256(abi.encodePacked(
            msg.sender,
            _receiver,
            _fromCBDC,
            _toCBDC,
            _amount,
            block.timestamp
        ));

        crossBorderTransfers[transferId] = CrossBorderTransfer({
            transferId: transferId,
            sender: msg.sender,
            receiver: _receiver,
            fromCBDC: _fromCBDC,
            toCBDC: _toCBDC,
            amount: _amount,
            exchangeRate: exchangeRate,
            feeAmount: feeAmount,
            mode: _mode,
            initiatedTime: block.timestamp,
            completedTime: 0,
            sourceTxHash: bytes32(0),
            destTxHash: bytes32(0),
            isCompleted: false,
            failureReason: ""
        });

        // Update limits
        _updateLimits(msg.sender, _fromCBDC, _amount);

        emit CrossBorderTransferInitiated(transferId, msg.sender, _fromCBDC, _toCBDC, _amount);

        // Execute based on mode
        if (_mode == InteroperabilityMode.DIRECT_SETTLEMENT) {
            _executeDirectSettlement(transferId);
        } else if (_mode == InteroperabilityMode.BRIDGED_SETTLEMENT) {
            _executeBridgedSettlement(transferId);
        } else if (_mode == InteroperabilityMode.ATOMIC_SWAP) {
            _executeAtomicSwap(transferId);
        }

        return transferId;
    }

    /**
     * @notice Complete a cross-border transfer
     */
    function completeCrossBorderTransfer(
        bytes32 _transferId,
        bytes32 _destTxHash
    ) external onlyOwner {
        CrossBorderTransfer storage transfer = crossBorderTransfers[_transferId];
        require(!transfer.isCompleted, "Transfer already completed");
        require(bytes(transfer.failureReason).length == 0, "Transfer failed");

        transfer.isCompleted = true;
        transfer.completedTime = block.timestamp;
        transfer.destTxHash = _destTxHash;

        totalSuccessfulTransfers++;
        totalCrossBorderVolume += transfer.amount;

        emit CrossBorderTransferCompleted(_transferId, _destTxHash);
    }

    /**
     * @notice Fail a cross-border transfer
     */
    function failCrossBorderTransfer(
        bytes32 _transferId,
        string memory _reason
    ) external onlyOwner {
        CrossBorderTransfer storage transfer = crossBorderTransfers[_transferId];
        require(!transfer.isCompleted, "Transfer already completed");

        transfer.failureReason = _reason;
        totalFailedTransfers++;

        emit CrossBorderTransferFailed(_transferId, _reason);
    }

    /**
     * @notice Get exchange rate between two CBDCs
     */
    function getExchangeRate(CBDCType _fromCBDC, CBDCType _toCBDC) external view returns (uint256) {
        return _getExchangeRate(_fromCBDC, _toCBDC);
    }

    /**
     * @notice Get cross-border transfer details
     */
    function getCrossBorderTransfer(bytes32 _transferId)
        external
        view
        returns (
            address sender,
            address receiver,
            CBDCType fromCBDC,
            CBDCType toCBDC,
            uint256 amount,
            uint256 exchangeRate,
            bool isCompleted,
            uint256 initiatedTime,
            uint256 completedTime
        )
    {
        CrossBorderTransfer memory transfer = crossBorderTransfers[_transferId];
        return (
            transfer.sender,
            transfer.receiver,
            transfer.fromCBDC,
            transfer.toCBDC,
            transfer.amount,
            transfer.exchangeRate,
            transfer.isCompleted,
            transfer.initiatedTime,
            transfer.completedTime
        );
    }

    /**
     * @notice Update configuration parameters
     */
    function updateConfig(
        uint256 _crossBorderFeeBPS,
        uint256 _minCrossBorderAmount,
        uint256 _maxCrossBorderAmount,
        uint256 _maxGlobalDailyVolume
    ) external onlyOwner {
        require(_crossBorderFeeBPS <= 1000, "Fee too high"); // Max 10%
        require(_minCrossBorderAmount < _maxCrossBorderAmount, "Invalid amount limits");

        crossBorderFeeBPS = _crossBorderFeeBPS;
        minCrossBorderAmount = _minCrossBorderAmount;
        maxCrossBorderAmount = _maxCrossBorderAmount;
        maxGlobalDailyVolume = _maxGlobalDailyVolume;
    }

    /**
     * @notice Reset daily limits (called by automation)
     */
    function resetDailyLimits() external onlyOwner {
        // Reset all CBDC daily limits
        for (uint256 i = 0; i <= uint256(CBDCType.OTHER); i++) {
            CBDCType cbdcType = CBDCType(i);
            if (cbdcConfigs[cbdcType].status == CBDCStatus.ACTIVE) {
                cbdcConfigs[cbdcType].usedToday = 0;
                cbdcConfigs[cbdcType].lastResetTime = block.timestamp;

                // Reset bridge volumes
                if (cbdcBridges[cbdcType].isActive) {
                    cbdcBridges[cbdcType].currentDailyVolume = 0;
                    cbdcBridges[cbdcType].lastVolumeReset = block.timestamp;
                }
            }
        }

        currentGlobalDailyVolume = 0;
        lastGlobalReset = block.timestamp;

        emit DailyLimitsReset(block.timestamp);
    }

    /**
     * @notice Emergency pause
     */
    function emergencyPause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause
     */
    function emergencyUnpause() external onlyOwner {
        _unpause();
    }

    // Internal functions

    function _getExchangeRate(CBDCType _fromCBDC, CBDCType _toCBDC) internal view returns (uint256) {
        // Simplified - in production would query oracle
        // For now, return 1:1 exchange rate
        return 1e18; // 1.0 in 18 decimals
    }

    function _updateLimits(address _user, CBDCType _cbdcType, uint256 _amount) internal {
        userDailyLimits[_user][_cbdcType] += _amount;
        userLastActivity[_user][_cbdcType] = block.timestamp;

        cbdcConfigs[_cbdcType].usedToday += _amount;
        currentGlobalDailyVolume += _amount;
    }

    function _executeDirectSettlement(bytes32 _transferId) internal {
        // Direct CBDC-to-CBDC settlement logic
        // In production, this would interact with CBDC smart contracts
    }

    function _executeBridgedSettlement(bytes32 _transferId) internal {
        // Bridge-mediated settlement logic
        // In production, this would use authorized bridges
    }

    function _executeAtomicSwap(bytes32 _transferId) internal {
        // Cross-chain atomic swap logic
        // In production, this would use atomic swap protocols
    }
}
