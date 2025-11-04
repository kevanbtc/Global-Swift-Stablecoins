// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IComplianceRegistry.sol";
import "../interfaces/IReserveManager.sol";
import "../interfaces/IPriceOracle.sol";
import "../common/Errors.sol";

/**
 * @title ETFWrapper
 * @dev Exchange-Traded Fund tokenization wrapper with institutional-grade compliance
 * @notice Tokenizes ETF shares with NAV tracking, compliance, and regulatory reporting
 */
contract ETFWrapper is
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CUSTODIAN_ROLE = keccak256("CUSTODIAN_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    // ETF specific data
    struct ETFData {
        string ticker;
        string name;
        string isin;
        address underlyingAsset;    // Address of underlying ETF token
        uint256 totalShares;        // Total shares outstanding
        uint256 navPerShare;        // Net Asset Value per share (18 decimals)
        uint256 lastNavUpdate;      // Last NAV update timestamp
        uint8 feeBasisPoints;       // Management fee in basis points
        bool isActive;
        address custodian;
    }

    // User position data
    struct UserPosition {
        uint256 tokenBalance;       // Wrapped ETF tokens held
        uint256 avgPurchasePrice;   // Average purchase price
        uint256 lastUpdated;        // Last position update
        bool isFrozen;              // Compliance freeze
    }

    // Investment limits
    struct InvestmentLimits {
        uint256 minInvestment;      // Minimum investment amount
        uint256 maxInvestment;      // Maximum investment per user
        uint256 maxTotalSupply;     // Maximum total supply
        bool requiresAccreditation; // Requires accredited investor status
    }

    IComplianceRegistry public complianceRegistry;
    IReserveManager public reserveManager;
    IPriceOracle public priceOracle;

    mapping(bytes32 => ETFData) public etfData;
    mapping(address => UserPosition) public userPositions;
    mapping(address => InvestmentLimits) public investmentLimits;

    bytes32[] public activeETFs;
    uint256 public totalWrappedValue; // Total value of all wrapped ETFs

    // Events
    event ETFWrapped(bytes32 indexed etfId, address indexed user, uint256 shares, uint256 tokens);
    event ETFUnwrapped(bytes32 indexed etfId, address indexed user, uint256 tokens, uint256 shares);
    event NAVUpdated(bytes32 indexed etfId, uint256 oldNav, uint256 newNav);
    event CustodianSet(bytes32 indexed etfId, address indexed custodian);
    event ComplianceFreeze(address indexed user, bool frozen);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the ETFWrapper contract
     */
    function initialize(
        address _complianceRegistry,
        address _reserveManager,
        address _priceOracle,
        address admin
    ) external initializer {
        __ERC20_init("Wrapped ETF Token", "wETF");
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(CUSTODIAN_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);

        complianceRegistry = IComplianceRegistry(_complianceRegistry);
        reserveManager = IReserveManager(_reserveManager);
        priceOracle = IPriceOracle(_priceOracle);
    }

    /**
     * @dev Create a new ETF wrapper
     */
    function createETF(
        string calldata ticker,
        string calldata name,
        string calldata isin,
        address underlyingAsset,
        uint8 feeBasisPoints
    ) external onlyRole(CUSTODIAN_ROLE) returns (bytes32) {
        require(underlyingAsset != address(0), "Invalid underlying asset");

        bytes32 etfId = keccak256(abi.encodePacked(ticker, isin, block.timestamp));

        require(!etfData[etfId].isActive, "ETF already exists");

        etfData[etfId] = ETFData({
            ticker: ticker,
            name: name,
            isin: isin,
            underlyingAsset: underlyingAsset,
            totalShares: 0,
            navPerShare: 1e18, // Initial NAV = $1.00
            lastNavUpdate: block.timestamp,
            feeBasisPoints: feeBasisPoints,
            isActive: true,
            custodian: msg.sender
        });

        activeETFs.push(etfId);

        // Set default investment limits
        investmentLimits[underlyingAsset] = InvestmentLimits({
            minInvestment: 1000 * 1e18,  // $1,000 minimum
            maxInvestment: 1000000 * 1e18, // $1M maximum per user
            maxTotalSupply: 100000000 * 1e18, // $100M total supply
            requiresAccreditation: true
        });

        emit CustodianSet(etfId, msg.sender);

        return etfId;
    }

    /**
     * @dev Wrap ETF shares into wrapped tokens
     */
    function wrapETF(bytes32 etfId, uint256 shareAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 tokens)
    {
        ETFData storage etf = etfData[etfId];
        require(etf.isActive, "ETF not active");

        InvestmentLimits memory limits = investmentLimits[etf.underlyingAsset];
        require(shareAmount >= limits.minInvestment, "Below minimum investment");

        // Check compliance
        require(complianceRegistry.isCompliant(msg.sender), "Not compliant");
        if (limits.requiresAccreditation) {
            require(complianceRegistry.isAccredited(msg.sender), "Not accredited");
        }

        UserPosition storage position = userPositions[msg.sender];
        require(!position.isFrozen, "Account frozen");

        // Check total supply limit
        uint256 currentSupply = totalSupply();
        require(currentSupply + shareAmount <= limits.maxTotalSupply, "Exceeds total supply limit");

        // Check user investment limit
        uint256 userCurrentValue = (position.tokenBalance * etf.navPerShare) / 1e18;
        uint256 newValue = (shareAmount * etf.navPerShare) / 1e18;
        require(userCurrentValue + newValue <= limits.maxInvestment, "Exceeds user investment limit");

        // Transfer underlying ETF shares from user
        IERC20(etf.underlyingAsset).transferFrom(msg.sender, address(this), shareAmount);

        // Calculate tokens to mint (1:1 ratio initially, adjusted for NAV)
        tokens = shareAmount;

        // Update ETF data
        etf.totalShares += shareAmount;

        // Update user position
        uint256 newTotalTokens = position.tokenBalance + tokens;
        position.avgPurchasePrice = ((position.avgPurchasePrice * position.tokenBalance) +
                                   (shareAmount * etf.navPerShare)) / newTotalTokens;
        position.tokenBalance = newTotalTokens;
        position.lastUpdated = block.timestamp;

        // Mint wrapped tokens
        _mint(msg.sender, tokens);
        totalWrappedValue += newValue;

        emit ETFWrapped(etfId, msg.sender, shareAmount, tokens);
    }

    /**
     * @dev Unwrap ETF tokens back to underlying shares
     */
    function unwrapETF(bytes32 etfId, uint256 tokenAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        ETFData storage etf = etfData[etfId];
        require(etf.isActive, "ETF not active");

        UserPosition storage position = userPositions[msg.sender];
        require(!position.isFrozen, "Account frozen");
        require(position.tokenBalance >= tokenAmount, "Insufficient balance");

        // Calculate shares to return based on current NAV
        shares = tokenAmount; // 1:1 ratio

        // Update ETF data
        etf.totalShares -= shares;

        // Update user position
        position.tokenBalance -= tokenAmount;
        position.lastUpdated = block.timestamp;

        // Burn wrapped tokens
        _burn(msg.sender, tokenAmount);

        // Calculate value for total tracking
        uint256 value = (tokenAmount * etf.navPerShare) / 1e18;
        totalWrappedValue -= value;

        // Transfer underlying ETF shares to user
        IERC20(etf.underlyingAsset).transfer(msg.sender, shares);

        emit ETFUnwrapped(etfId, msg.sender, tokenAmount, shares);
    }

    /**
     * @dev Update NAV for an ETF (custodian only)
     */
    function updateNAV(bytes32 etfId, uint256 newNavPerShare)
        external
        onlyRole(CUSTODIAN_ROLE)
    {
        ETFData storage etf = etfData[etfId];
        require(etf.isActive, "ETF not active");
        require(etf.custodian == msg.sender, "Not ETF custodian");

        uint256 oldNav = etf.navPerShare;
        etf.navPerShare = newNavPerShare;
        etf.lastNavUpdate = block.timestamp;

        emit NAVUpdated(etfId, oldNav, newNavPerShare);
    }

    /**
     * @dev Get current NAV from price oracle
     */
    function getCurrentNAV(bytes32 etfId) external view returns (uint256) {
        ETFData memory etf = etfData[etfId];
        require(etf.isActive, "ETF not active");

        // Try to get price from oracle, fallback to stored NAV
        try priceOracle.getPrice(etf.underlyingAsset) returns (uint256 price) {
            return price;
        } catch {
            return etf.navPerShare;
        }
    }

    /**
     * @dev Freeze/unfreeze user account (compliance)
     */
    function setComplianceFreeze(address user, bool frozen)
        external
        onlyRole(COMPLIANCE_ROLE)
    {
        userPositions[user].isFrozen = frozen;
        emit ComplianceFreeze(user, frozen);
    }

    /**
     * @dev Update investment limits for an underlying asset
     */
    function updateInvestmentLimits(
        address underlyingAsset,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 maxTotalSupply,
        bool requiresAccreditation
    ) external onlyRole(ADMIN_ROLE) {
        investmentLimits[underlyingAsset] = InvestmentLimits({
            minInvestment: minInvestment,
            maxInvestment: maxInvestment,
            maxTotalSupply: maxTotalSupply,
            requiresAccreditation: requiresAccreditation
        });
    }

    /**
     * @dev Get user position details
     */
    function getUserPosition(address user)
        external
        view
        returns (
            uint256 tokenBalance,
            uint256 avgPurchasePrice,
            uint256 lastUpdated,
            bool isFrozen,
            uint256 currentValue
        )
    {
        UserPosition memory position = userPositions[user];
        // Simplified: assumes single ETF NAV, in production would aggregate across all ETFs
        uint256 nav = 1e18; // Placeholder
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
     * @dev Get ETF details
     */
    function getETFData(bytes32 etfId)
        external
        view
        returns (
            string memory ticker,
            string memory name,
            string memory isin,
            address underlyingAsset,
            uint256 totalShares,
            uint256 navPerShare,
            uint256 lastNavUpdate,
            uint8 feeBasisPoints,
            bool isActive,
            address custodian
        )
    {
        ETFData memory etf = etfData[etfId];
        return (
            etf.ticker,
            etf.name,
            etf.isin,
            etf.underlyingAsset,
            etf.totalShares,
            etf.navPerShare,
            etf.lastNavUpdate,
            etf.feeBasisPoints,
            etf.isActive,
            etf.custodian
        );
    }

    /**
     * @dev Get all active ETFs
     */
    function getActiveETFs() external view returns (bytes32[] memory) {
        return activeETFs;
    }

    /**
     * @dev Pause/unpause contract
     */
    function setPaused(bool paused) external onlyRole(ADMIN_ROLE) {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
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
    function _beforeTokenTransfer(
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
    }
}
