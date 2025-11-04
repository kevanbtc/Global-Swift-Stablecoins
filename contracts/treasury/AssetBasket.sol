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
 * @title AssetBasket
 * @dev Multi-asset basket tokenization with institutional-grade compliance
 * @notice Creates tokenized baskets of multiple assets with NAV calculation and rebalancing
 */
contract AssetBasket is
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PORTFOLIO_MANAGER_ROLE = keccak256("PORTFOLIO_MANAGER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    // Basket composition data
    struct BasketComposition {
        string name;
        string symbol;
        address[] assets;           // Array of underlying asset addresses
        uint256[] weights;          // Corresponding weights in basis points (total = 10000)
        uint256 totalShares;        // Total basket shares outstanding
        uint256 navPerShare;        // Net Asset Value per share (18 decimals)
        uint256 lastNavUpdate;      // Last NAV update timestamp
        uint256 lastRebalance;      // Last rebalance timestamp
        uint256 rebalanceInterval;  // Rebalance interval in seconds
        uint8 managementFee;       // Annual management fee in basis points
        bool isActive;
        address portfolioManager;
    }

    // User position data
    struct UserPosition {
        uint256 tokenBalance;       // Basket tokens held
        uint256 avgPurchasePrice;   // Average purchase price
        uint256 lastUpdated;        // Last position update
        bool isFrozen;              // Compliance freeze
    }

    // Investment limits
    struct BasketLimits {
        uint256 minInvestment;      // Minimum investment amount
        uint256 maxInvestment;      // Maximum investment per user
        uint256 maxTotalSupply;     // Maximum total supply
        bool requiresAccreditation; // Requires accredited investor status
        uint256 redemptionFee;      // Redemption fee in basis points
    }

    IComplianceRegistry public complianceRegistry;
    IReserveManager public reserveManager;
    IPriceOracle public priceOracle;

    mapping(bytes32 => BasketComposition) public basketData;
    mapping(address => UserPosition) public userPositions;
    mapping(address => BasketLimits) public basketLimits;

    bytes32[] public activeBaskets;
    uint256 public totalBasketValue; // Total value of all baskets

    // Events
    event BasketCreated(bytes32 indexed basketId, string name, address indexed manager);
    event BasketInvested(bytes32 indexed basketId, address indexed user, uint256 usdAmount, uint256 tokens);
    event BasketRedeemed(bytes32 indexed basketId, address indexed user, uint256 tokens, uint256 usdAmount);
    event BasketRebalanced(bytes32 indexed basketId, uint256[] newWeights);
    event NAVUpdated(bytes32 indexed basketId, uint256 oldNav, uint256 newNav);
    event ComplianceFreeze(address indexed user, bool frozen);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the AssetBasket contract
     */
    function initialize(
        address _complianceRegistry,
        address _reserveManager,
        address _priceOracle,
        address admin
    ) external initializer {
        __ERC20_init("Asset Basket Token", "BASKET");
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PORTFOLIO_MANAGER_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);

        complianceRegistry = IComplianceRegistry(_complianceRegistry);
        reserveManager = IReserveManager(_reserveManager);
        priceOracle = IPriceOracle(_priceOracle);
    }

    /**
     * @dev Create a new asset basket
     */
    function createBasket(
        string calldata name,
        string calldata symbol,
        address[] calldata assets,
        uint256[] calldata weights,
        uint256 rebalanceInterval,
        uint8 managementFee
    ) external onlyRole(PORTFOLIO_MANAGER_ROLE) returns (bytes32) {
        require(assets.length > 0, "No assets provided");
        require(assets.length == weights.length, "Assets and weights mismatch");
        require(_validateWeights(weights), "Invalid weights");

        bytes32 basketId = keccak256(abi.encodePacked(name, symbol, block.timestamp));

        require(!basketData[basketId].isActive, "Basket already exists");

        basketData[basketId] = BasketComposition({
            name: name,
            symbol: symbol,
            assets: assets,
            weights: weights,
            totalShares: 0,
            navPerShare: 1e18, // Initial NAV = $1.00
            lastNavUpdate: block.timestamp,
            lastRebalance: block.timestamp,
            rebalanceInterval: rebalanceInterval,
            managementFee: managementFee,
            isActive: true,
            portfolioManager: msg.sender
        });

        activeBaskets.push(basketId);

        // Set default basket limits
        basketLimits[address(uint160(uint256(basketId)))] = BasketLimits({
            minInvestment: 50000 * 1e18,  // $50,000 minimum
            maxInvestment: 50000000 * 1e18, // $50M maximum per user
            maxTotalSupply: 1000000000 * 1e18, // $1B total supply
            requiresAccreditation: true,
            redemptionFee: 50 // 0.5% redemption fee
        });

        emit BasketCreated(basketId, name, msg.sender);

        return basketId;
    }

    /**
     * @dev Invest in an asset basket
     */
    function investInBasket(bytes32 basketId, uint256 usdAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 tokens)
    {
        BasketComposition storage basket = basketData[basketId];
        require(basket.isActive, "Basket not active");

        BasketLimits memory limits = basketLimits[address(uint160(uint256(basketId)))];
        require(usdAmount >= limits.minInvestment, "Below minimum investment");

        // Check compliance
        require(complianceRegistry.isCompliant(msg.sender), "Not compliant");
        if (limits.requiresAccreditation) {
            require(complianceRegistry.isAccredited(msg.sender), "Not accredited");
        }

        UserPosition storage position = userPositions[msg.sender];
        require(!position.isFrozen, "Account frozen");

        // Check total supply limit
        uint256 currentSupply = totalSupply();
        require(currentSupply + usdAmount <= limits.maxTotalSupply, "Exceeds total supply limit");

        // Check user investment limit
        uint256 userCurrentValue = (position.tokenBalance * basket.navPerShare) / 1e18;
        require(userCurrentValue + usdAmount <= limits.maxInvestment, "Exceeds user investment limit");

        // Calculate tokens to mint based on NAV
        tokens = (usdAmount * 1e18) / basket.navPerShare;

        // Update basket data
        basket.totalShares += tokens;

        // Update user position
        uint256 newTotalTokens = position.tokenBalance + tokens;
        position.avgPurchasePrice = ((position.avgPurchasePrice * position.tokenBalance) +
                                   (usdAmount * position.tokenBalance)) / newTotalTokens;
        position.tokenBalance = newTotalTokens;
        position.lastUpdated = block.timestamp;

        // Mint basket tokens
        _mint(msg.sender, tokens);
        totalBasketValue += usdAmount;

        // Allocate funds to underlying assets based on weights
        _allocateToAssets(basketId, usdAmount);

        emit BasketInvested(basketId, msg.sender, usdAmount, tokens);
    }

    /**
     * @dev Redeem basket tokens
     */
    function redeemFromBasket(bytes32 basketId, uint256 tokenAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 usdAmount)
    {
        BasketComposition storage basket = basketData[basketId];
        require(basket.isActive, "Basket not active");

        UserPosition storage position = userPositions[msg.sender];
        require(!position.isFrozen, "Account frozen");
        require(position.tokenBalance >= tokenAmount, "Insufficient balance");

        BasketLimits memory limits = basketLimits[address(uint160(uint256(basketId)))];

        // Calculate redemption amount
        usdAmount = (tokenAmount * basket.navPerShare) / 1e18;

        // Apply redemption fee
        if (limits.redemptionFee > 0) {
            uint256 fee = (usdAmount * limits.redemptionFee) / 10000;
            usdAmount -= fee;
        }

        // Update basket data
        basket.totalShares -= tokenAmount;

        // Update user position
        position.tokenBalance -= tokenAmount;
        position.lastUpdated = block.timestamp;

        // Burn basket tokens
        _burn(msg.sender, tokenAmount);
        totalBasketValue -= (tokenAmount * basket.navPerShare) / 1e18;

        // Deallocate from underlying assets
        _deallocateFromAssets(basketId, usdAmount);

        emit BasketRedeemed(basketId, msg.sender, tokenAmount, usdAmount);
    }

    /**
     * @dev Rebalance basket composition
     */
    function rebalanceBasket(bytes32 basketId, uint256[] calldata newWeights)
        external
        onlyRole(PORTFOLIO_MANAGER_ROLE)
    {
        BasketComposition storage basket = basketData[basketId];
        require(basket.isActive, "Basket not active");
        require(basket.portfolioManager == msg.sender, "Not basket manager");
        require(newWeights.length == basket.assets.length, "Weights length mismatch");
        require(_validateWeights(newWeights), "Invalid weights");

        // Check rebalance interval
        require(block.timestamp >= basket.lastRebalance + basket.rebalanceInterval, "Rebalance too soon");

        basket.weights = newWeights;
        basket.lastRebalance = block.timestamp;

        // Perform actual rebalancing of underlying assets
        _performRebalance(basketId);

        emit BasketRebalanced(basketId, newWeights);
    }

    /**
     * @dev Update NAV for a basket
     */
    function updateBasketNAV(bytes32 basketId)
        external
        onlyRole(PORTFOLIO_MANAGER_ROLE)
        returns (uint256 newNav)
    {
        BasketComposition storage basket = basketData[basketId];
        require(basket.isActive, "Basket not active");
        require(basket.portfolioManager == msg.sender, "Not basket manager");

        uint256 oldNav = basket.navPerShare;
        newNav = _calculateBasketNAV(basketId);

        basket.navPerShare = newNav;
        basket.lastNavUpdate = block.timestamp;

        emit NAVUpdated(basketId, oldNav, newNav);
    }

    /**
     * @dev Allocate funds to underlying assets based on weights
     */
    function _allocateToAssets(bytes32 basketId, uint256 usdAmount) internal {
        BasketComposition memory basket = basketData[basketId];

        for (uint256 i = 0; i < basket.assets.length; i++) {
            uint256 allocation = (usdAmount * basket.weights[i]) / 10000;
            if (allocation > 0) {
                // In production, this would interact with the reserve manager
                // to allocate funds to specific assets
            }
        }
    }

    /**
     * @dev Deallocate funds from underlying assets
     */
    function _deallocateFromAssets(bytes32 basketId, uint256 usdAmount) internal {
        BasketComposition memory basket = basketData[basketId];

        for (uint256 i = 0; i < basket.assets.length; i++) {
            uint256 deallocation = (usdAmount * basket.weights[i]) / 10000;
            if (deallocation > 0) {
                // In production, this would interact with the reserve manager
                // to deallocate funds from specific assets
            }
        }
    }

    /**
     * @dev Perform rebalancing of underlying assets
     */
    function _performRebalance(bytes32 basketId) internal {
        // Implementation would rebalance the underlying asset allocations
        // based on new weights. This is a complex operation that would
        // involve trading assets to match target allocations.
    }

    /**
     * @dev Calculate basket NAV based on underlying asset prices
     */
    function _calculateBasketNAV(bytes32 basketId) internal view returns (uint256) {
        BasketComposition memory basket = basketData[basketId];
        uint256 totalValue = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < basket.assets.length; i++) {
            try priceOracle.getPrice(basket.assets[i]) returns (uint256 price) {
                uint256 assetValue = (price * basket.weights[i]) / 10000;
                totalValue += assetValue;
                totalWeight += basket.weights[i];
            } catch {
                // Fallback to last known price or skip
                continue;
            }
        }

        if (totalWeight == 0) return basket.navPerShare; // Fallback to current NAV

        return (totalValue * 1e18) / totalWeight;
    }

    /**
     * @dev Validate that weights sum to 10000 (100%)
     */
    function _validateWeights(uint256[] memory weights) internal pure returns (bool) {
        uint256 total = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            total += weights[i];
        }
        return total == 10000;
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
     * @dev Update basket limits
     */
    function updateBasketLimits(
        bytes32 basketId,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 maxTotalSupply,
        bool requiresAccreditation,
        uint256 redemptionFee
    ) external onlyRole(ADMIN_ROLE) {
        basketLimits[address(uint160(uint256(basketId)))] = BasketLimits({
            minInvestment: minInvestment,
            maxInvestment: maxInvestment,
            maxTotalSupply: maxTotalSupply,
            requiresAccreditation: requiresAccreditation,
            redemptionFee: redemptionFee
        });
    }

    /**
     * @dev Get basket details
     */
    function getBasketData(bytes32 basketId)
        external
        view
        returns (
            string memory name,
            string memory symbol,
            address[] memory assets,
            uint256[] memory weights,
            uint256 totalShares,
            uint256 navPerShare,
            uint256 lastNavUpdate,
            uint256 lastRebalance,
            uint256 rebalanceInterval,
            uint8 managementFee,
            bool isActive,
            address portfolioManager
        )
    {
        BasketComposition memory basket = basketData[basketId];
        return (
            basket.name,
            basket.symbol,
            basket.assets,
            basket.weights,
            basket.totalShares,
            basket.navPerShare,
            basket.lastNavUpdate,
            basket.lastRebalance,
            basket.rebalanceInterval,
            basket.managementFee,
            basket.isActive,
            basket.portfolioManager
        );
    }

    /**
     * @dev Get current basket NAV
     */
    function getCurrentBasketNAV(bytes32 basketId) external view returns (uint256) {
        return _calculateBasketNAV(basketId);
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
        // Simplified: assumes single basket NAV, in production would aggregate
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
     * @dev Get all active baskets
     */
    function getActiveBaskets() external view returns (bytes32[] memory) {
        return activeBaskets;
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
