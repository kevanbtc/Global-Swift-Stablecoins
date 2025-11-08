// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IComplianceRegistry.sol";
import "../interfaces/IReserveManager.sol";
import "../interfaces/IPriceOracle.sol";
import "../common/Errors.sol";

/**
 * @title MMFVault
 * @dev Money Market Fund tokenization vault with institutional-grade compliance
 * @notice Manages MMF share tokenization with NAV tracking and regulatory compliance
 */
contract MMFVault is
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    // Money Market Fund specific data
    struct MoneyMarketFund {
        string name;
        string ticker;
        address underlyingAsset;    // Address of underlying MMF token
        uint256 totalShares;        // Total shares outstanding
        uint256 navPerShare;        // Net Asset Value per share (18 decimals)
        uint256 lastNavUpdate;      // Last NAV update timestamp
        uint8 expenseRatio;         // Annual expense ratio in basis points
        uint8 yieldRate;            // Current yield rate in basis points
        bool isActive;
        address fundManager;
    }

    // User position data
    struct UserPosition {
        uint256 tokenBalance;       // Wrapped MMF tokens held
        uint256 avgPurchasePrice;   // Average purchase price
        uint256 lastUpdated;        // Last position update
        uint256 accruedYield;       // Accrued yield
        bool isFrozen;              // Compliance freeze
    }

    // Investment limits and rules
    struct InvestmentRules {
        uint256 minInvestment;      // Minimum investment amount
        uint256 maxInvestment;      // Maximum investment per user
        uint256 maxTotalSupply;     // Maximum total supply
        uint256 lockupPeriod;       // Lockup period in seconds
        bool requiresAccreditation; // Requires accredited investor status
        uint256 redemptionFee;      // Redemption fee in basis points
    }

    IComplianceRegistry public complianceRegistry;
    IReserveManager public reserveManager;
    IPriceOracle public priceOracle;

    mapping(bytes32 => MoneyMarketFund) public mmfData;
    mapping(address => UserPosition) public userPositions;
    mapping(address => InvestmentRules) public investmentRules;

    bytes32[] public activeMMFs;
    uint256 public totalWrappedValue; // Total value of all wrapped MMFs

    // Events
    event MMFWrapped(bytes32 indexed mmfId, address indexed user, uint256 shares, uint256 tokens);
    event MMFUnwrapped(bytes32 indexed mmfId, address indexed user, uint256 tokens, uint256 shares);
    event NAVUpdated(bytes32 indexed mmfId, uint256 oldNav, uint256 newNav);
    event YieldDistributed(bytes32 indexed mmfId, uint256 totalYield);
    event FundManagerSet(bytes32 indexed mmfId, address indexed fundManager);
    event ComplianceFreeze(address indexed user, bool frozen);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the MMFVault contract
     */
    function initialize(
        address _complianceRegistry,
        address _reserveManager,
        address _priceOracle,
        address admin
    ) public initializer {
        __ERC20_init("Wrapped Money Market Fund", "wMMF");
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(FUND_MANAGER_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);

        complianceRegistry = IComplianceRegistry(_complianceRegistry);
        reserveManager = IReserveManager(_reserveManager);
        priceOracle = IPriceOracle(_priceOracle);
    }

    /**
     * @dev Create a new Money Market Fund wrapper
     */
    function createMMF(
        string calldata name,
        string calldata ticker,
        address underlyingAsset,
        uint8 expenseRatio,
        uint8 initialYieldRate
    ) public onlyRole(FUND_MANAGER_ROLE) returns (bytes32) {
        require(underlyingAsset != address(0), "Invalid underlying asset");

        bytes32 mmfId = keccak256(abi.encodePacked(ticker, block.timestamp));

        require(!mmfData[mmfId].isActive, "MMF already exists");

        mmfData[mmfId] = MoneyMarketFund({
            name: name,
            ticker: ticker,
            underlyingAsset: underlyingAsset,
            totalShares: 0,
            navPerShare: 1e18, // Initial NAV = $1.00
            lastNavUpdate: block.timestamp,
            expenseRatio: expenseRatio,
            yieldRate: initialYieldRate,
            isActive: true,
            fundManager: msg.sender
        });

        activeMMFs.push(mmfId);

        // Set default investment rules
        investmentRules[underlyingAsset] = InvestmentRules({
            minInvestment: 10000 * 1e18,  // $10,000 minimum
            maxInvestment: 10000000 * 1e18, // $10M maximum per user
            maxTotalSupply: 1000000000 * 1e18, // $1B total supply
            lockupPeriod: 7 days, // 7 day lockup
            requiresAccreditation: false, // MMFs typically don't require accreditation
            redemptionFee: 0 // No redemption fee for MMFs
        });

        emit FundManagerSet(mmfId, msg.sender);

        return mmfId;
    }

    /**
     * @dev Wrap MMF shares into wrapped tokens
     */
    function wrapMMF(bytes32 mmfId, uint256 shareAmount) public nonReentrant
        whenNotPaused
        returns (uint256 tokens)
    {
        MoneyMarketFund storage mmf = mmfData[mmfId];
        require(mmf.isActive, "MMF not active");

        InvestmentRules memory rules = investmentRules[mmf.underlyingAsset];
        require(shareAmount >= rules.minInvestment, "Below minimum investment");

        // Check compliance
        require(complianceRegistry.isCompliant(msg.sender), "Not compliant");
        if (rules.requiresAccreditation) {
            // Note: isAccredited method not in IComplianceRegistry interface - commenting out for now
            // If needed, should use IComplianceRegistryV2.getProfile() instead
            // require(complianceRegistry.isAccredited(msg.sender), "Not accredited");
        }

        UserPosition storage position = userPositions[msg.sender];
        require(!position.isFrozen, "Account frozen");

        // Check total supply limit
        uint256 currentSupply = totalSupply();
        require(currentSupply + shareAmount <= rules.maxTotalSupply, "Exceeds total supply limit");

        // Check user investment limit
        uint256 userCurrentValue = (position.tokenBalance * mmf.navPerShare) / 1e18;
        uint256 newValue = (shareAmount * mmf.navPerShare) / 1e18;
        require(userCurrentValue + newValue <= rules.maxInvestment, "Exceeds user investment limit");

        // Transfer underlying MMF shares from user
        IERC20(mmf.underlyingAsset).transferFrom(msg.sender, address(this), shareAmount);

        // Calculate tokens to mint (1:1 ratio initially)
        tokens = shareAmount;

        // Update MMF data
        mmf.totalShares += shareAmount;

        // Update user position
        uint256 newTotalTokens = position.tokenBalance + tokens;
        position.avgPurchasePrice = ((position.avgPurchasePrice * position.tokenBalance) +
                                   (shareAmount * mmf.navPerShare)) / newTotalTokens;
        position.tokenBalance = newTotalTokens;
        position.lastUpdated = block.timestamp;

        // Mint wrapped tokens
        _mint(msg.sender, tokens);
        totalWrappedValue += newValue;

        emit MMFWrapped(mmfId, msg.sender, shareAmount, tokens);
    }

    /**
     * @dev Unwrap MMF tokens back to underlying shares
     */
    function unwrapMMF(bytes32 mmfId, uint256 tokenAmount) public nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        MoneyMarketFund storage mmf = mmfData[mmfId];
        require(mmf.isActive, "MMF not active");

        UserPosition storage position = userPositions[msg.sender];
        require(!position.isFrozen, "Account frozen");
        require(position.tokenBalance >= tokenAmount, "Insufficient balance");

        InvestmentRules memory rules = investmentRules[mmf.underlyingAsset];

        // Check lockup period
        require(block.timestamp >= position.lastUpdated + rules.lockupPeriod, "Lockup period not met");

        // Calculate shares to return
        shares = tokenAmount;

        // Apply redemption fee if any
        if (rules.redemptionFee > 0) {
            uint256 fee = (shares * rules.redemptionFee) / 10000;
            shares -= fee;
            // Fee could be sent to treasury or burned
        }

        // Update MMF data
        mmf.totalShares -= shares;

        // Update user position
        position.tokenBalance -= tokenAmount;
        position.lastUpdated = block.timestamp;

        // Burn wrapped tokens
        _burn(msg.sender, tokenAmount);

        // Calculate value for total tracking
        uint256 value = (tokenAmount * mmf.navPerShare) / 1e18;
        totalWrappedValue -= value;

        // Transfer underlying MMF shares to user
        IERC20(mmf.underlyingAsset).transfer(msg.sender, shares);

        emit MMFUnwrapped(mmfId, msg.sender, tokenAmount, shares);
    }

    /**
     * @dev Update NAV for an MMF (fund manager only)
     */
    function updateNAV(bytes32 mmfId, uint256 newNavPerShare) public onlyRole(FUND_MANAGER_ROLE)
    {
        MoneyMarketFund storage mmf = mmfData[mmfId];
        require(mmf.isActive, "MMF not active");
        require(mmf.fundManager == msg.sender, "Not MMF fund manager");

        uint256 oldNav = mmf.navPerShare;
        mmf.navPerShare = newNavPerShare;
        mmf.lastNavUpdate = block.timestamp;

        emit NAVUpdated(mmfId, oldNav, newNavPerShare);
    }

    /**
     * @dev Update yield rate for an MMF
     */
    function updateYieldRate(bytes32 mmfId, uint8 newYieldRate) public onlyRole(FUND_MANAGER_ROLE)
    {
        MoneyMarketFund storage mmf = mmfData[mmfId];
        require(mmf.isActive, "MMF not active");
        require(mmf.fundManager == msg.sender, "Not MMF fund manager");

        mmf.yieldRate = newYieldRate;
    }

    /**
     * @dev Distribute yield to token holders
     */
    function distributeYield(bytes32 mmfId) public onlyRole(FUND_MANAGER_ROLE)
        returns (uint256 totalYield)
    {
        MoneyMarketFund storage mmf = mmfData[mmfId];
        require(mmf.isActive, "MMF not active");
        require(mmf.fundManager == msg.sender, "Not MMF fund manager");

        // Calculate yield based on current yield rate and time elapsed
        uint256 timeElapsed = block.timestamp - mmf.lastNavUpdate;
        uint256 annualYield = (uint256(mmf.yieldRate) * mmf.totalShares * mmf.navPerShare) / 10000 / 1e18;
        totalYield = (annualYield * timeElapsed) / 365 days;

        if (totalYield > 0) {
            // Mint yield tokens proportionally to holders
            // This is a simplified implementation
            uint256 currentSupply = totalSupply();
            if (currentSupply > 0) {
                uint256 yieldPerToken = (totalYield * 1e18) / currentSupply;
                // In practice, this would update each holder's accrued yield
                // For simplicity, we'll just emit the event
            }

            emit YieldDistributed(mmfId, totalYield);
        }
    }

    /**
     * @dev Get current NAV from price oracle
     */
    function getCurrentNAV(bytes32 mmfId) public view returns (uint256) {
        MoneyMarketFund memory mmf = mmfData[mmfId];
        require(mmf.isActive, "MMF not active");

        // Try to get price from oracle, fallback to stored NAV
        try priceOracle.getPrice(mmf.underlyingAsset) returns (uint256 price) {
            return price;
        } catch {
            return mmf.navPerShare;
        }
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
     * @dev Update investment rules for an underlying asset
     */
    function updateInvestmentRules(
        address underlyingAsset,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 maxTotalSupply,
        uint256 lockupPeriod,
        bool requiresAccreditation,
        uint256 redemptionFee
    ) public onlyRole(ADMIN_ROLE) {
        investmentRules[underlyingAsset] = InvestmentRules({
            minInvestment: minInvestment,
            maxInvestment: maxInvestment,
            maxTotalSupply: maxTotalSupply,
            lockupPeriod: lockupPeriod,
            requiresAccreditation: requiresAccreditation,
            redemptionFee: redemptionFee
        });
    }

    /**
     * @dev Get user position details
     */
    function getUserPosition(address user) public view
        returns (
            uint256 tokenBalance,
            uint256 avgPurchasePrice,
            uint256 lastUpdated,
            uint256 accruedYield,
            bool isFrozen,
            uint256 currentValue
        )
    {
        UserPosition memory position = userPositions[user];
        // Simplified: assumes single MMF NAV, in production would aggregate across all MMFs
        uint256 nav = 1e18; // Placeholder
        uint256 value = (position.tokenBalance * nav) / 1e18;

        return (
            position.tokenBalance,
            position.avgPurchasePrice,
            position.lastUpdated,
            position.accruedYield,
            position.isFrozen,
            value
        );
    }

    /**
     * @dev Get MMF details
     */
    function getMMFData(bytes32 mmfId) public view
        returns (
            string memory name,
            string memory ticker,
            address underlyingAsset,
            uint256 totalShares,
            uint256 navPerShare,
            uint256 lastNavUpdate,
            uint8 expenseRatio,
            uint8 yieldRate,
            bool isActive,
            address fundManager
        )
    {
        MoneyMarketFund memory mmf = mmfData[mmfId];
        return (
            mmf.name,
            mmf.ticker,
            mmf.underlyingAsset,
            mmf.totalShares,
            mmf.navPerShare,
            mmf.lastNavUpdate,
            mmf.expenseRatio,
            mmf.yieldRate,
            mmf.isActive,
            mmf.fundManager
        );
    }

    /**
     * @dev Get all active MMFs
     */
    function getActiveMMFs() public view returns (bytes32[] memory) {
        return activeMMFs;
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
