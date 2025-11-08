// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IComplianceRegistry.sol";
import "../interfaces/IReserveManager.sol";
import "../common/Errors.sol";

/**
 * @title TBillVault
 * @dev Treasury Bill tokenization vault with institutional-grade compliance
 * @notice Manages US Treasury Bill tokenization with KYC-gated access and regulatory compliance
 */
contract TBillVault is
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    // Treasury Bill specific data
    struct TreasuryBill {
        string cusip;
        uint256 faceValue;      // Face value in USD (6 decimals)
        uint256 purchasePrice;  // Purchase price in USD (6 decimals)
        uint256 maturityDate;   // Unix timestamp
        uint256 issueDate;      // Unix timestamp
        uint8 interestRate;     // Basis points (e.g., 425 = 4.25%)
        bool isActive;
        address custodian;      // Custodian wallet address
    }

    // User position data
    struct UserPosition {
        uint256 tokenBalance;   // TBILL tokens held
        uint256 avgPurchasePrice; // Average purchase price
        uint256 lastUpdated;    // Last position update
        bool isFrozen;          // Compliance freeze
    }

    IComplianceRegistry public complianceRegistry;
    IReserveManager public reserveManager;

    mapping(bytes32 => TreasuryBill) public treasuryBills;
    mapping(address => UserPosition) public userPositions;
    mapping(address => bool) public authorizedCustodians;

    uint256 public totalFaceValue;    // Total face value of all TBills
    uint256 public totalTokenSupply;  // Total TBILL tokens outstanding
    uint256 public minInvestment;     // Minimum investment amount
    uint256 public maxInvestment;     // Maximum investment per user

    // Events
    event TreasuryBillMinted(bytes32 indexed billId, address indexed custodian, uint256 faceValue);
    event TreasuryBillRedeemed(bytes32 indexed billId, address indexed redeemer, uint256 amount);
    event InvestmentMade(address indexed investor, uint256 amount, uint256 tokens);
    event RedemptionProcessed(address indexed investor, uint256 tokens, uint256 amount);
    event CustodianAuthorized(address indexed custodian, bool authorized);
    event ComplianceFreeze(address indexed user, bool frozen);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the TBillVault contract
     */
    function initialize(
        address _complianceRegistry,
        address _reserveManager,
        address admin
    ) public initializer {
        __ERC20_init("Treasury Bill Token", "TBILL");
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);

        complianceRegistry = IComplianceRegistry(_complianceRegistry);
        reserveManager = IReserveManager(_reserveManager);

        minInvestment = 1000 * 1e6;  // $1,000 minimum
        maxInvestment = 1000000 * 1e6; // $1M maximum per user
    }

    /**
     * @dev Authorize or deauthorize a custodian
     */
    function setCustodian(address custodian, bool authorized) public onlyRole(ADMIN_ROLE)
    {
        authorizedCustodians[custodian] = authorized;
        emit CustodianAuthorized(custodian, authorized);
    }

    /**
     * @dev Mint new Treasury Bill tokens
     */
    function mintTreasuryBill(
        string calldata cusip,
        uint256 faceValue,
        uint256 purchasePrice,
        uint256 maturityDate,
        uint256 issueDate,
        uint8 interestRate
    ) public onlyRole(TREASURY_ROLE) returns (bytes32) {
        require(faceValue > 0, "Invalid face value");
        require(purchasePrice > 0, "Invalid purchase price");
        require(maturityDate > block.timestamp, "Invalid maturity date");
        require(authorizedCustodians[msg.sender], "Unauthorized custodian");

        bytes32 billId = keccak256(abi.encodePacked(cusip, issueDate, msg.sender));

        require(!treasuryBills[billId].isActive, "Bill already exists");

        treasuryBills[billId] = TreasuryBill({
            cusip: cusip,
            faceValue: faceValue,
            purchasePrice: purchasePrice,
            maturityDate: maturityDate,
            issueDate: issueDate,
            interestRate: interestRate,
            isActive: true,
            custodian: msg.sender
        });

        totalFaceValue += faceValue;

        emit TreasuryBillMinted(billId, msg.sender, faceValue);

        return billId;
    }

    /**
     * @dev Invest in Treasury Bills (mint TBILL tokens)
     */
    function invest(uint256 usdAmount) public nonReentrant
        whenNotPaused
        returns (uint256 tokens)
    {
        require(usdAmount >= minInvestment, "Below minimum investment");
        require(usdAmount <= maxInvestment, "Above maximum investment");

        // Check compliance
        require(complianceRegistry.isCompliant(msg.sender), "Not compliant");

        UserPosition storage position = userPositions[msg.sender];
        require(!position.isFrozen, "Account frozen");

        // Calculate tokens based on current NAV
        uint256 nav = _calculateNAV();
        tokens = (usdAmount * 1e18) / nav;

        // Update position
        uint256 newTotalTokens = position.tokenBalance + tokens;
        position.avgPurchasePrice = ((position.avgPurchasePrice * position.tokenBalance) + (usdAmount * position.tokenBalance)) / newTotalTokens;
        position.tokenBalance = newTotalTokens;
        position.lastUpdated = block.timestamp;

        // Mint tokens
        _mint(msg.sender, tokens);
        totalTokenSupply += tokens;

        // Transfer USD to reserve manager
        // Note: deposit method not in IReserveManager interface
        // TODO: Implement proper reserve tracking with correct asset address
        // reserveManager.updateReserve(assetAddress, amount);

        emit InvestmentMade(msg.sender, usdAmount, tokens);
    }

    /**
     * @dev Redeem TBILL tokens for USD
     */
    function redeem(uint256 tokenAmount) public nonReentrant
        whenNotPaused
        returns (uint256 usdAmount)
    {
        require(tokenAmount > 0, "Invalid token amount");
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        UserPosition storage position = userPositions[msg.sender];
        require(!position.isFrozen, "Account frozen");

        // Calculate redemption amount based on NAV
        uint256 nav = _calculateNAV();
        usdAmount = (tokenAmount * nav) / 1e18;

        // Update position
        position.tokenBalance -= tokenAmount;
        position.lastUpdated = block.timestamp;

        // Burn tokens
        _burn(msg.sender, tokenAmount);
        totalTokenSupply -= tokenAmount;

        // Transfer USD from reserve manager
        // Note: withdraw method not in IReserveManager interface
        // TODO: Implement proper withdrawal with correct asset address
        // reserveManager.updateReserve(assetAddress, amount);

        emit RedemptionProcessed(msg.sender, tokenAmount, usdAmount);
    }

    /**
     * @dev Freeze/unfreeze user account (compliance)
     */
    function setComplianceFreeze(address user, bool frozen) public onlyRole(COMPLIANCE_ROLE)
    {
        userPositions[user].isFrozen = frozen;
        emit ComplianceFreeze(user, frozen);
    }

    /**
     * @dev Calculate Net Asset Value
     */
    function _calculateNAV() internal view returns (uint256) {
        if (totalTokenSupply == 0) return 1e18; // $1.00 initial NAV

        // NAV = (Total Face Value + Accrued Interest) / Total Token Supply
        uint256 accruedInterest = _calculateAccruedInterest();
        uint256 totalValue = totalFaceValue + accruedInterest;

        return (totalValue * 1e18) / totalTokenSupply;
    }

    /**
     * @dev Calculate accrued interest on treasury bills
     */
    function _calculateAccruedInterest() internal view returns (uint256) {
        // Simplified interest calculation
        // In production, this would calculate actual accrued interest
        // based on individual bill maturity dates and rates
        uint256 totalInterest = 0;

        // For each active treasury bill, calculate accrued interest
        // This is a simplified implementation

        return totalInterest;
    }

    /**
     * @dev Get user position details
     */
    function getUserPosition(address user) public view
        returns (
            uint256 tokenBalance,
            uint256 avgPurchasePrice,
            uint256 lastUpdated,
            bool isFrozen,
            uint256 currentValue
        )
    {
        UserPosition memory position = userPositions[user];
        uint256 nav = _calculateNAV();
        uint256 value = (position.tokenBalance * nav) / 1e18;

        return (
            position.tokenBalance,
            position.avgPurchasePrice,
            position.lastUpdated,
            position.isFrozen,
            value
        );
    }

    /**
     * @dev Get current NAV
     */
    function getNAV() public view returns (uint256) {
        return _calculateNAV();
    }

    /**
     * @dev Pause/unpause contract
     */
    function setPaused(bool paused) public onlyRole(ADMIN_ROLE) {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @dev Update investment limits
     */
    function updateInvestmentLimits(uint256 _minInvestment, uint256 _maxInvestment) public onlyRole(ADMIN_ROLE)
    {
        minInvestment = _minInvestment;
        maxInvestment = _maxInvestment;
    }

    /**
     * @dev Authorize upgrade
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(ADMIN_ROLE)
    {}

    /**
     * @dev ERC20 transfer hook for compliance
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        if (from != address(0) && to != address(0)) {
            // Check compliance for both parties
            require(complianceRegistry.isCompliant(from), "Sender not compliant");
            require(complianceRegistry.isCompliant(to), "Receiver not compliant");

            // Check if accounts are frozen
            require(!userPositions[from].isFrozen, "Sender account frozen");
            require(!userPositions[to].isFrozen, "Receiver account frozen");
        }
        super._update(from, to, amount);
    }
}
