// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GlobalStablecoinRegistry
 * @notice Universal registry for all stablecoin types and implementations
 * @dev Supports fiat-backed, crypto-backed, algorithmic, commodity-backed, and hybrid stablecoins
 */
contract GlobalStablecoinRegistry is Ownable, ReentrancyGuard {

    enum StablecoinType {
        FIAT_BACKED,        // USD, EUR, GBP, JPY, etc.
        CRYPTO_BACKED,      // BTC, ETH collateralized
        ALGORITHMIC,        // Seigniorage shares, AMM-based
        COMMODITY_BACKED,   // Gold, Silver, Oil, etc.
        REAL_ESTATE_BACKED, // Property tokenization
        BASKET_BACKED,      // Multi-asset baskets
        CBDC_BACKED,        // Central bank digital currencies
        YIELD_BEARING,      // Interest-bearing stablecoins
        ALGO_STABLE,        // Algorithmic stabilization
        HYBRID             // Mixed collateral types
    }

    enum CollateralType {
        CASH,
        TREASURY_BILLS,
        COMMERCIAL_PAPER,
        CORPORATE_BONDS,
        GOLD,
        SILVER,
        OIL,
        REAL_ESTATE,
        BITCOIN,
        ETHEREUM,
        OTHER_CRYPTO,
        CBDC,
        ALGORITHMIC
    }

    enum RegulatoryFramework {
        USDC_FRAMEWORK,     // Circle USD
        USDT_FRAMEWORK,     // Tether USD
        DAI_FRAMEWORK,      // MakerDAO DAI
        FRAX_FRAMEWORK,     // Frax Finance
        LUSD_FRAMEWORK,     // Liquity LUSD
        USDP_FRAMEWORK,     // Paxos USD
        GUSD_FRAMEWORK,     // Gemini USD
        BUSD_FRAMEWORK,     // Binance USD
        USDD_FRAMEWORK,     // Tron USD
        FEI_FRAMEWORK,      // Fei Protocol
        MIM_FRAMEWORK,      // Abracadabra MIM
        USN_FRAMEWORK,      // Near Protocol USN
        EURO_FRAMEWORK,     // EUR stablecoins
        GBP_FRAMEWORK,      // GBP stablecoins
        JPY_FRAMEWORK,      // JPY stablecoins
        AUD_FRAMEWORK,      // AUD stablecoins
        CAD_FRAMEWORK,      // CAD stablecoins
        SGD_FRAMEWORK,      // SGD stablecoins
        CHF_FRAMEWORK       // CHF stablecoins
    }

    struct StablecoinProfile {
        bytes32 stablecoinId;
        string name;
        string symbol;
        address contractAddress;
        address issuer;
        StablecoinType stablecoinType;
        CollateralType collateralType;
        RegulatoryFramework regulatoryFramework;
        uint256 totalSupply;
        uint256 marketCap;
        uint256 peggedValue;        // Value pegged to (e.g., 1e18 = $1)
        uint256 collateralRatio;    // BPS (e.g., 10000 = 100%)
        uint256 mintFee;           // BPS
        uint256 redeemFee;         // BPS
        uint256 reserveRatio;      // BPS
        address reserveManager;
        address oracle;
        bool isActive;
        bool isRegulatoryApproved;
        uint256 launchDate;
        uint256 lastAudit;
        string jurisdiction;
        bytes32 regulatoryApprovalHash;
        string ipfsMetadata;
    }

    struct ReserveComposition {
        address asset;
        uint256 amount;
        uint256 weight;            // BPS in total reserves
        uint256 lastValuation;
        bool isEligible;
    }

    // Storage
    mapping(bytes32 => StablecoinProfile) public stablecoinProfiles;
    mapping(bytes32 => ReserveComposition[]) public reserveCompositions;
    mapping(address => bytes32[]) public issuerStablecoins;
    mapping(StablecoinType => bytes32[]) public stablecoinsByType;
    mapping(CollateralType => bytes32[]) public stablecoinsByCollateral;
    mapping(RegulatoryFramework => bytes32[]) public stablecoinsByFramework;
    mapping(string => bytes32) public symbolToId;

    // Global statistics
    uint256 public totalStablecoins;
    uint256 public totalMarketCap;
    uint256 public totalReserves;

    // Regulatory thresholds
    uint256 public minReserveRatio = 10000;     // 100% minimum reserves
    uint256 public maxMintFee = 100;            // 1% max mint fee
    uint256 public maxRedeemFee = 100;          // 1% max redeem fee

    // Events
    event StablecoinRegistered(bytes32 indexed stablecoinId, string name, string symbol, address indexed contractAddress);
    event StablecoinUpdated(bytes32 indexed stablecoinId, uint256 newSupply, uint256 newMarketCap);
    event ReserveUpdated(bytes32 indexed stablecoinId, address indexed asset, uint256 newAmount);
    event RegulatoryApproval(bytes32 indexed stablecoinId, bytes32 approvalHash);
    event StablecoinDeactivated(bytes32 indexed stablecoinId, string reason);

    modifier validStablecoin(bytes32 _stablecoinId) {
        require(stablecoinProfiles[_stablecoinId].contractAddress != address(0), "Stablecoin not registered");
        _;
    }

    modifier onlyIssuer(bytes32 _stablecoinId) {
        require(stablecoinProfiles[_stablecoinId].issuer == msg.sender, "Not stablecoin issuer");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new stablecoin
     */
    function registerStablecoin(
        string memory _name,
        string memory _symbol,
        address _contractAddress,
        StablecoinType _stablecoinType,
        CollateralType _collateralType,
        RegulatoryFramework _regulatoryFramework,
        uint256 _peggedValue,
        uint256 _collateralRatio,
        uint256 _mintFee,
        uint256 _redeemFee,
        address _reserveManager,
        address _oracle,
        string memory _jurisdiction,
        string memory _ipfsMetadata
    ) public returns (bytes32) {
        require(_contractAddress != address(0), "Invalid contract address");
        require(_peggedValue > 0, "Invalid pegged value");
        require(_collateralRatio >= minReserveRatio, "Collateral ratio too low");
        require(_mintFee <= maxMintFee, "Mint fee too high");
        require(_redeemFee <= maxRedeemFee, "Redeem fee too high");
        require(symbolToId[_symbol] == bytes32(0), "Symbol already exists");

        bytes32 stablecoinId = keccak256(abi.encodePacked(
            _name,
            _symbol,
            _contractAddress,
            block.timestamp
        ));

        require(stablecoinProfiles[stablecoinId].contractAddress == address(0), "Stablecoin already registered");

        stablecoinProfiles[stablecoinId] = StablecoinProfile({
            stablecoinId: stablecoinId,
            name: _name,
            symbol: _symbol,
            contractAddress: _contractAddress,
            issuer: msg.sender,
            stablecoinType: _stablecoinType,
            collateralType: _collateralType,
            regulatoryFramework: _regulatoryFramework,
            totalSupply: 0,
            marketCap: 0,
            peggedValue: _peggedValue,
            collateralRatio: _collateralRatio,
            mintFee: _mintFee,
            redeemFee: _redeemFee,
            reserveRatio: 0,
            reserveManager: _reserveManager,
            oracle: _oracle,
            isActive: true,
            isRegulatoryApproved: false,
            launchDate: block.timestamp,
            lastAudit: 0,
            jurisdiction: _jurisdiction,
            regulatoryApprovalHash: bytes32(0),
            ipfsMetadata: _ipfsMetadata
        });

        // Update mappings
        issuerStablecoins[msg.sender].push(stablecoinId);
        stablecoinsByType[_stablecoinType].push(stablecoinId);
        stablecoinsByCollateral[_collateralType].push(stablecoinId);
        stablecoinsByFramework[_regulatoryFramework].push(stablecoinId);
        symbolToId[_symbol] = stablecoinId;

        totalStablecoins++;

        emit StablecoinRegistered(stablecoinId, _name, _symbol, _contractAddress);
        return stablecoinId;
    }

    /**
     * @notice Update stablecoin supply and market cap
     */
    function updateStablecoinMetrics(
        bytes32 _stablecoinId,
        uint256 _totalSupply,
        uint256 _marketCap
    ) public onlyIssuer(_stablecoinId) validStablecoin(_stablecoinId) {
        StablecoinProfile storage profile = stablecoinProfiles[_stablecoinId];

        // Update global stats
        totalMarketCap = totalMarketCap - profile.marketCap + _marketCap;

        profile.totalSupply = _totalSupply;
        profile.marketCap = _marketCap;

        emit StablecoinUpdated(_stablecoinId, _totalSupply, _marketCap);
    }

    /**
     * @notice Update reserve composition
     */
    function updateReserveComposition(
        bytes32 _stablecoinId,
        address[] memory _assets,
        uint256[] memory _amounts,
        uint256[] memory _weights
    ) public onlyIssuer(_stablecoinId) validStablecoin(_stablecoinId) {
        require(_assets.length == _amounts.length && _amounts.length == _weights.length, "Array length mismatch");

        delete reserveCompositions[_stablecoinId];

        uint256 totalWeight = 0;
        uint256 totalReserveValue = 0;

        for (uint256 i = 0; i < _assets.length; i++) {
            require(_weights[i] > 0, "Invalid weight");

            ReserveComposition memory composition = ReserveComposition({
                asset: _assets[i],
                amount: _amounts[i],
                weight: _weights[i],
                lastValuation: block.timestamp,
                isEligible: true
            });

            reserveCompositions[_stablecoinId].push(composition);
            totalWeight += _weights[i];

            // Calculate reserve value (simplified)
            totalReserveValue += _amounts[i];

            emit ReserveUpdated(_stablecoinId, _assets[i], _amounts[i]);
        }

        require(totalWeight == 10000, "Weights must sum to 100%");

        // Update reserve ratio
        StablecoinProfile storage profile = stablecoinProfiles[_stablecoinId];
        if (profile.totalSupply > 0) {
            profile.reserveRatio = (totalReserveValue * 10000) / profile.totalSupply;
        }

        totalReserves = totalReserves - profile.reserveRatio + totalReserveValue;
    }

    /**
     * @notice Grant regulatory approval
     */
    function grantRegulatoryApproval(
        bytes32 _stablecoinId,
        bytes32 _approvalHash
    ) public onlyOwner validStablecoin(_stablecoinId) {
        StablecoinProfile storage profile = stablecoinProfiles[_stablecoinId];
        profile.isRegulatoryApproved = true;
        profile.regulatoryApprovalHash = _approvalHash;
        profile.lastAudit = block.timestamp;

        emit RegulatoryApproval(_stablecoinId, _approvalHash);
    }

    /**
     * @notice Deactivate a stablecoin
     */
    function deactivateStablecoin(
        bytes32 _stablecoinId,
        string memory _reason
    ) public onlyOwner validStablecoin(_stablecoinId) {
        StablecoinProfile storage profile = stablecoinProfiles[_stablecoinId];
        profile.isActive = false;

        // Update global stats
        totalMarketCap -= profile.marketCap;
        totalStablecoins--;

        emit StablecoinDeactivated(_stablecoinId, _reason);
    }

    /**
     * @notice Get stablecoin profile
     */
    function getStablecoinProfile(bytes32 _stablecoinId) public view
        returns (
            string memory name,
            string memory symbol,
            address contractAddress,
            StablecoinType stablecoinType,
            CollateralType collateralType,
            uint256 totalSupply,
            uint256 marketCap,
            uint256 peggedValue,
            bool isActive,
            bool isRegulatoryApproved
        )
    {
        StablecoinProfile memory profile = stablecoinProfiles[_stablecoinId];
        return (
            profile.name,
            profile.symbol,
            profile.contractAddress,
            profile.stablecoinType,
            profile.collateralType,
            profile.totalSupply,
            profile.marketCap,
            profile.peggedValue,
            profile.isActive,
            profile.isRegulatoryApproved
        );
    }

    /**
     * @notice Get reserve composition
     */
    function getReserveComposition(bytes32 _stablecoinId) public view
        returns (ReserveComposition[] memory)
    {
        return reserveCompositions[_stablecoinId];
    }

    /**
     * @notice Get stablecoins by type
     */
    function getStablecoinsByType(StablecoinType _type) public view
        returns (bytes32[] memory)
    {
        return stablecoinsByType[_type];
    }

    /**
     * @notice Get stablecoins by collateral
     */
    function getStablecoinsByCollateral(CollateralType _collateral) public view
        returns (bytes32[] memory)
    {
        return stablecoinsByCollateral[_collateral];
    }

    /**
     * @notice Get stablecoins by regulatory framework
     */
    function getStablecoinsByFramework(RegulatoryFramework _framework) public view
        returns (bytes32[] memory)
    {
        return stablecoinsByFramework[_framework];
    }

    /**
     * @notice Check if stablecoin meets regulatory requirements
     */
    function checkRegulatoryCompliance(bytes32 _stablecoinId) public view
        returns (bool isCompliant, string memory reason)
    {
        StablecoinProfile memory profile = stablecoinProfiles[_stablecoinId];

        if (!profile.isActive) {
            return (false, "Stablecoin not active");
        }

        if (!profile.isRegulatoryApproved) {
            return (false, "Not regulatory approved");
        }

        if (profile.reserveRatio < minReserveRatio) {
            return (false, "Insufficient reserves");
        }

        if (profile.lastAudit == 0 || block.timestamp - profile.lastAudit > 365 days) {
            return (false, "Audit overdue");
        }

        return (true, "Compliant");
    }

    /**
     * @notice Update regulatory thresholds
     */
    function updateRegulatoryThresholds(
        uint256 _minReserveRatio,
        uint256 _maxMintFee,
        uint256 _maxRedeemFee
    ) public onlyOwner {
        require(_minReserveRatio <= 20000, "Reserve ratio too high"); // Max 200%
        require(_maxMintFee <= 1000, "Max mint fee too high"); // Max 10%
        require(_maxRedeemFee <= 1000, "Max redeem fee too high"); // Max 10%

        minReserveRatio = _minReserveRatio;
        maxMintFee = _maxMintFee;
        maxRedeemFee = _maxRedeemFee;
    }

    /**
     * @notice Get global stablecoin statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalStablecoins,
            uint256 _totalMarketCap,
            uint256 _totalReserves
        )
    {
        return (totalStablecoins, totalMarketCap, totalReserves);
    }
}
