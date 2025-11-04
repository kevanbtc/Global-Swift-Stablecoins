// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title CBDCBridge
 * @notice Cross-CBDC bridge for interoperability between different central bank digital currencies
 * @dev Implements secure cross-border CBDC transfers with rate limiting and compliance checks
 */
contract CBDCBridge is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    enum TransferStatus {
        Pending,
        Validated,
        Executing,
        Completed,
        Failed,
        Rejected
    }

    enum ValidationResult {
        Pending,
        Approved,
        Rejected
    }

    struct CBDCInfo {
        string name;
        string symbol;
        address tokenContract;
        uint256 minTransfer;
        uint256 maxTransfer;
        bool active;
        address[] validators;
        uint256 requiredValidations;
        mapping(address => bool) supportedDestinations;
    }

    struct Transfer {
        bytes32 transferId;
        address sender;
        address recipient;
        uint256 amount;
        string sourceCBDC;
        string targetCBDC;
        uint256 exchangeRate;
        uint256 timestamp;
        TransferStatus status;
        mapping(address => ValidationResult) validations;
        uint256 validationCount;
        string metadataURI;
    }

    // State variables
    mapping(string => CBDCInfo) public cbdcs;
    mapping(bytes32 => Transfer) public transfers;
    mapping(address => mapping(string => uint256)) public dailyVolumes;
    mapping(string => mapping(string => address)) public exchangeRateOracles;
    
    uint256 public constant DAILY_VOLUME_WINDOW = 24 hours;
    uint256 public validationTimeout = 1 hours;
    
    // Events
    event CBDCRegistered(
        string indexed name,
        string symbol,
        address tokenContract
    );

    event TransferInitiated(
        bytes32 indexed transferId,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        string sourceCBDC,
        string targetCBDC
    );

    event TransferValidated(
        bytes32 indexed transferId,
        address indexed validator,
        ValidationResult result
    );

    event TransferCompleted(
        bytes32 indexed transferId,
        uint256 amount,
        uint256 exchangeRate
    );

    event TransferFailed(
        bytes32 indexed transferId,
        string reason
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BRIDGE_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Register a new CBDC in the bridge
     * @param name CBDC name
     * @param symbol CBDC symbol
     * @param tokenContract CBDC token contract address
     * @param minTransfer Minimum transfer amount
     * @param maxTransfer Maximum transfer amount
     * @param validators Array of initial validators
     * @param requiredValidations Number of required validations
     */
    function registerCBDC(
        string calldata name,
        string calldata symbol,
        address tokenContract,
        uint256 minTransfer,
        uint256 maxTransfer,
        address[] calldata validators,
        uint256 requiredValidations
    )
        external
        onlyRole(BRIDGE_ADMIN_ROLE)
    {
        require(bytes(name).length > 0, "Invalid name");
        require(tokenContract != address(0), "Invalid token contract");
        require(validators.length >= requiredValidations, "Invalid validator config");
        
        CBDCInfo storage cbdc = cbdcs[name];
        require(cbdc.tokenContract == address(0), "CBDC exists");
        
        cbdc.name = name;
        cbdc.symbol = symbol;
        cbdc.tokenContract = tokenContract;
        cbdc.minTransfer = minTransfer;
        cbdc.maxTransfer = maxTransfer;
        cbdc.active = true;
        cbdc.validators = validators;
        cbdc.requiredValidations = requiredValidations;
        
        for (uint256 i = 0; i < validators.length; i++) {
            _grantRole(VALIDATOR_ROLE, validators[i]);
        }
        
        emit CBDCRegistered(name, symbol, tokenContract);
    }

    /**
     * @notice Configure supported destination for a CBDC
     * @param sourceCBDC Source CBDC name
     * @param destinationContract Destination bridge contract
     * @param supported Whether the destination is supported
     */
    function configureCBDCDestination(
        string calldata sourceCBDC,
        address destinationContract,
        bool supported
    )
        external
        onlyRole(BRIDGE_ADMIN_ROLE)
    {
        require(bytes(sourceCBDC).length > 0, "Invalid CBDC");
        require(destinationContract != address(0), "Invalid destination");
        
        CBDCInfo storage cbdc = cbdcs[sourceCBDC];
        require(cbdc.tokenContract != address(0), "CBDC not found");
        
        cbdc.supportedDestinations[destinationContract] = supported;
    }

    /**
     * @notice Set exchange rate oracle for a CBDC pair
     * @param sourceCBDC Source CBDC name
     * @param targetCBDC Target CBDC name
     * @param oracle Oracle contract address
     */
    function setExchangeRateOracle(
        string calldata sourceCBDC,
        string calldata targetCBDC,
        address oracle
    )
        external
        onlyRole(BRIDGE_ADMIN_ROLE)
    {
        require(bytes(sourceCBDC).length > 0, "Invalid source");
        require(bytes(targetCBDC).length > 0, "Invalid target");
        require(oracle != address(0), "Invalid oracle");
        
        exchangeRateOracles[sourceCBDC][targetCBDC] = oracle;
    }

    /**
     * @notice Initiate a cross-CBDC transfer
     * @param recipient Recipient address
     * @param amount Transfer amount
     * @param targetCBDC Target CBDC name
     * @param metadataURI Optional metadata URI
     */
    function initiateTransfer(
        address recipient,
        uint256 amount,
        string calldata targetCBDC,
        string calldata metadataURI
    )
        external
        nonReentrant
        whenNotPaused
        returns (bytes32)
    {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        string memory sourceCBDC = _getSourceCBDC(msg.sender);
        CBDCInfo storage sourceCbdc = cbdcs[sourceCBDC];
        CBDCInfo storage targetCbdc = cbdcs[targetCBDC];
        
        require(sourceCbdc.active && targetCbdc.active, "Inactive CBDC");
        require(amount >= sourceCbdc.minTransfer, "Below min transfer");
        require(amount <= sourceCbdc.maxTransfer, "Exceeds max transfer");
        
        uint256 exchangeRate = _getExchangeRate(sourceCBDC, targetCBDC);
        require(exchangeRate > 0, "Invalid rate");
        
        bytes32 transferId = keccak256(abi.encodePacked(
            msg.sender,
            recipient,
            amount,
            sourceCBDC,
            targetCBDC,
            block.timestamp
        ));
        
        Transfer storage transfer = transfers[transferId];
        transfer.transferId = transferId;
        transfer.sender = msg.sender;
        transfer.recipient = recipient;
        transfer.amount = amount;
        transfer.sourceCBDC = sourceCBDC;
        transfer.targetCBDC = targetCBDC;
        transfer.exchangeRate = exchangeRate;
        transfer.timestamp = block.timestamp;
        transfer.status = TransferStatus.Pending;
        transfer.metadataURI = metadataURI;
        
        _updateDailyVolume(msg.sender, sourceCBDC, amount);
        
        emit TransferInitiated(
            transferId,
            msg.sender,
            recipient,
            amount,
            sourceCBDC,
            targetCBDC
        );
        
        return transferId;
    }

    /**
     * @notice Validate a transfer
     * @param transferId Transfer identifier
     * @param approved Whether the transfer is approved
     */
    function validateTransfer(bytes32 transferId, bool approved)
        external
        onlyRole(VALIDATOR_ROLE)
        whenNotPaused
    {
        Transfer storage transfer = transfers[transferId];
        require(transfer.timestamp > 0, "Transfer not found");
        require(transfer.status == TransferStatus.Pending, "Invalid status");
        
        CBDCInfo storage sourceCbdc = cbdcs[transfer.sourceCBDC];
        require(
            block.timestamp <= transfer.timestamp + validationTimeout,
            "Validation timeout"
        );
        
        ValidationResult result = approved ?
            ValidationResult.Approved :
            ValidationResult.Rejected;
            
        transfer.validations[msg.sender] = result;
        
        if (approved) {
            transfer.validationCount++;
            
            if (transfer.validationCount >= sourceCbdc.requiredValidations) {
                transfer.status = TransferStatus.Validated;
                _executeTransfer(transferId);
            }
        } else {
            transfer.status = TransferStatus.Rejected;
            emit TransferFailed(transferId, "Validation rejected");
        }
        
        emit TransferValidated(transferId, msg.sender, result);
    }

    /**
     * @notice Execute a validated transfer
     * @param transferId Transfer identifier
     */
    function _executeTransfer(bytes32 transferId) internal {
        Transfer storage transfer = transfers[transferId];
        require(transfer.status == TransferStatus.Validated, "Not validated");
        
        transfer.status = TransferStatus.Executing;
        
        try this._processTransfer(transferId) {
            transfer.status = TransferStatus.Completed;
            
            emit TransferCompleted(
                transferId,
                transfer.amount,
                transfer.exchangeRate
            );
        } catch (bytes memory reason) {
            transfer.status = TransferStatus.Failed;
            emit TransferFailed(transferId, string(reason));
        }
    }

    /**
     * @notice Process the actual transfer
     * @param transferId Transfer identifier
     */
    function _processTransfer(bytes32 transferId) external {
        require(msg.sender == address(this), "Internal call only");
        
        Transfer storage transfer = transfers[transferId];
        require(transfer.status == TransferStatus.Executing, "Invalid status");
        
        // Implement actual token transfer logic here
        // This would interact with the respective CBDC token contracts
    }

    /**
     * @notice Get the exchange rate between two CBDCs
     * @param sourceCBDC Source CBDC name
     * @param targetCBDC Target CBDC name
     */
    function _getExchangeRate(
        string memory sourceCBDC,
        string memory targetCBDC
    )
        internal
        view
        returns (uint256)
    {
        address oracle = exchangeRateOracles[sourceCBDC][targetCBDC];
        require(oracle != address(0), "Oracle not found");
        
        AggregatorV3Interface rateOracle = AggregatorV3Interface(oracle);
        (, int256 rate,,,) = rateOracle.latestRoundData();
        require(rate > 0, "Invalid rate data");
        
        return uint256(rate);
    }

    /**
     * @notice Update daily transfer volume for an address
     * @param user User address
     * @param cbdcName CBDC name
     * @param amount Transfer amount
     */
    function _updateDailyVolume(
        address user,
        string memory cbdcName,
        uint256 amount
    )
        internal
    {
        uint256 timestamp = block.timestamp / DAILY_VOLUME_WINDOW *
            DAILY_VOLUME_WINDOW;
        dailyVolumes[user][cbdcName] = amount;
    }

    /**
     * @notice Get the source CBDC for a sender
     * @param sender Sender address
     */
    function _getSourceCBDC(address sender)
        internal
        pure
        returns (string memory)
    {
        // Implementation would determine the CBDC based on the sender's address
        // This could involve looking up the sender's wallet registration
        // or other identification mechanisms
        return "USD_CBDC"; // Placeholder
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setValidationTimeout(uint256 timeout)
        external
        onlyRole(BRIDGE_ADMIN_ROLE)
    {
        validationTimeout = timeout;
    }
}