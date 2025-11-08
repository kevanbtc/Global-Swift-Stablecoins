// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FractionalAssetProtocol
 * @notice Protocol for fractional ownership of high-value assets
 * @dev Supports real estate, art, collectibles, intellectual property, and other illiquid assets
 */
contract FractionalAssetProtocol is Ownable, ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;

    enum AssetType {
        REAL_ESTATE,
        ART_COLLECTIBLE,
        VINTAGE_CAR,
        WATCH_JEWELRY,
        INTELLECTUAL_PROPERTY,
        MINING_RIGHTS,
        WATER_RIGHTS,
        TIMBER_LAND,
        FARMLAND,
        COMMERCIAL_PROPERTY,
        OTHER
    }

    enum AssetStatus {
        PROPOSED,
        UNDER_REVIEW,
        VERIFIED,
        TOKENIZING,
        ACTIVE,
        LIQUIDATING,
        RETIRED
    }

    enum FractionType {
        ERC20_SHARES,
        ERC1155_SHARES,
        REBASING_SHARES,
        YIELD_BEARING_SHARES
    }

    struct FractionalAsset {
        bytes32 assetId;
        string assetName;
        string assetDescription;
        AssetType assetType;
        AssetStatus status;
        address custodian;          // Asset custodian/escrow
        address originalOwner;
        address fractionToken;      // ERC20 token representing fractions
        FractionType fractionType;
        uint256 totalValue;         // Total asset valuation
        uint256 totalFractions;     // Total fraction tokens
        uint256 availableFractions; // Available for purchase
        uint256 fractionPrice;      // Price per fraction
        uint256 minimumInvestment;  // Minimum fraction purchase
        uint256 lockupPeriod;       // Lock-up period for fractions
        uint256 yieldPercentage;    // Annual yield percentage (BPS)
        uint256 lastYieldDistribution;
        uint256 totalYieldDistributed;
        string ipfsMetadata;
        bytes32 valuationHash;
        bool isRebasing;
        uint256 rebaseFrequency;    // How often to rebase NAV
        uint256 lastRebase;
    }

    struct FractionOwnership {
        bytes32 assetId;
        address owner;
        uint256 fractionAmount;
        uint256 purchaseDate;
        uint256 lockExpiry;
        uint256 accumulatedYield;
        uint256 votingPower;        // Governance voting power
        bool isLocked;
    }

    struct AssetValuation {
        bytes32 assetId;
        uint256 valuation;
        uint256 valuationDate;
        address appraiser;
        string methodology;
        bytes32 supportingDocsHash;
        bool isAccepted;
    }

    struct YieldDistribution {
        bytes32 assetId;
        uint256 totalYield;
        uint256 yieldPerFraction;
        uint256 distributionDate;
        address yieldToken;
        bool isDistributed;
    }

    // Storage
    mapping(bytes32 => FractionalAsset) public fractionalAssets;
    mapping(bytes32 => mapping(address => FractionOwnership)) public fractionOwnerships;
    mapping(bytes32 => AssetValuation[]) public assetValuations;
    mapping(bytes32 => YieldDistribution[]) public yieldDistributions;
    mapping(address => bytes32[]) public ownerAssets;
    mapping(address => bytes32[]) public ownerFractions;

    // Global statistics
    uint256 public totalAssets;
    uint256 public totalAssetValue;
    uint256 public totalFractionsMinted;
    uint256 public totalYieldDistributed;

    // Protocol parameters
    uint256 public minAssetValue = 100000 * 1e18;     // $100k minimum
    uint256 public maxFractionSupply = 1000000000;     // 1B max fractions
    uint256 public minFractionPrice = 1 * 1e18;        // $1 minimum
    uint256 public maxLockupPeriod = 365 days;         // 1 year max lockup
    uint256 public valuationValidityPeriod = 180 days; // 6 months

    // Events
    event AssetProposed(bytes32 indexed assetId, string assetName, AssetType assetType);
    event AssetVerified(bytes32 indexed assetId, address custodian);
    event AssetTokenized(bytes32 indexed assetId, address fractionToken, uint256 totalFractions);
    event FractionsPurchased(bytes32 indexed assetId, address indexed buyer, uint256 fractionAmount);
    event FractionsSold(bytes32 indexed assetId, address indexed seller, uint256 fractionAmount);
    event YieldDistributed(bytes32 indexed assetId, uint256 totalYield);
    event AssetRevalued(bytes32 indexed assetId, uint256 newValuation);
    event AssetLiquidated(bytes32 indexed assetId, uint256 proceeds);

    modifier validAsset(bytes32 _assetId) {
        require(fractionalAssets[_assetId].custodian != address(0), "Asset not found");
        _;
    }

    modifier onlyAssetCustodian(bytes32 _assetId) {
        require(fractionalAssets[_assetId].custodian == msg.sender, "Not asset custodian");
        _;
    }

    modifier assetActive(bytes32 _assetId) {
        require(fractionalAssets[_assetId].status == AssetStatus.ACTIVE, "Asset not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Propose a new asset for fractionalization
     */
    function proposeAsset(
        string memory _assetName,
        string memory _assetDescription,
        AssetType _assetType,
        uint256 _totalValue,
        uint256 _totalFractions,
        uint256 _fractionPrice,
        uint256 _minimumInvestment,
        uint256 _lockupPeriod,
        string memory _ipfsMetadata
    ) public whenNotPaused returns (bytes32) {
        require(_totalValue >= minAssetValue, "Asset value too low");
        require(_totalFractions > 0 && _totalFractions <= maxFractionSupply, "Invalid fraction supply");
        require(_fractionPrice >= minFractionPrice, "Fraction price too low");
        require(_lockupPeriod <= maxLockupPeriod, "Lockup period too long");
        require(bytes(_assetName).length > 0, "Invalid asset name");

        bytes32 assetId = keccak256(abi.encodePacked(
            _assetName,
            _assetType,
            _totalValue,
            block.timestamp,
            msg.sender
        ));

        require(fractionalAssets[assetId].custodian == address(0), "Asset already exists");

        fractionalAssets[assetId] = FractionalAsset({
            assetId: assetId,
            assetName: _assetName,
            assetDescription: _assetDescription,
            assetType: _assetType,
            status: AssetStatus.PROPOSED,
            custodian: address(0), // To be assigned during verification
            originalOwner: msg.sender,
            fractionToken: address(0), // To be deployed
            fractionType: FractionType.ERC20_SHARES,
            totalValue: _totalValue,
            totalFractions: _totalFractions,
            availableFractions: _totalFractions,
            fractionPrice: _fractionPrice,
            minimumInvestment: _minimumInvestment,
            lockupPeriod: _lockupPeriod,
            yieldPercentage: 0,
            lastYieldDistribution: 0,
            totalYieldDistributed: 0,
            ipfsMetadata: _ipfsMetadata,
            valuationHash: bytes32(0),
            isRebasing: false,
            rebaseFrequency: 0,
            lastRebase: 0
        });

        ownerAssets[msg.sender].push(assetId);
        totalAssets++;

        emit AssetProposed(assetId, _assetName, _assetType);
        return assetId;
    }

    /**
     * @notice Verify and approve an asset for tokenization
     */
    function verifyAsset(
        bytes32 _assetId,
        address _custodian,
        address _fractionToken,
        bytes32 _valuationHash
    ) public onlyOwner validAsset(_assetId) {
        FractionalAsset storage asset = fractionalAssets[_assetId];
        require(asset.status == AssetStatus.PROPOSED, "Asset not in proposed status");
        require(_custodian != address(0), "Invalid custodian");
        require(_fractionToken != address(0), "Invalid fraction token");

        asset.custodian = _custodian;
        asset.fractionToken = _fractionToken;
        asset.valuationHash = _valuationHash;
        asset.status = AssetStatus.VERIFIED;

        emit AssetVerified(_assetId, _custodian);
    }

    /**
     * @notice Activate asset tokenization
     */
    function activateAsset(bytes32 _assetId) public onlyAssetCustodian(_assetId) validAsset(_assetId) {
        FractionalAsset storage asset = fractionalAssets[_assetId];
        require(asset.status == AssetStatus.VERIFIED, "Asset not verified");
        require(asset.fractionToken != address(0), "Fraction token not set");

        asset.status = AssetStatus.ACTIVE;

        emit AssetTokenized(_assetId, asset.fractionToken, asset.totalFractions);
    }

    /**
     * @notice Purchase asset fractions
     */
    function purchaseFractions(
        bytes32 _assetId,
        uint256 _fractionAmount
    ) public payable whenNotPaused assetActive(_assetId) nonReentrant {
        FractionalAsset storage asset = fractionalAssets[_assetId];
        require(_fractionAmount >= asset.minimumInvestment, "Below minimum investment");
        require(_fractionAmount <= asset.availableFractions, "Insufficient available fractions");

        uint256 totalCost = _fractionAmount * asset.fractionPrice;
        require(msg.value >= totalCost, "Insufficient payment");

        // Transfer payment to custodian
        payable(asset.custodian).transfer(totalCost);

        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }

        // Mint fraction tokens to buyer
        // Note: In production, this would interact with the fraction token contract
        // For now, we track ownership internally

        FractionOwnership storage ownership = fractionOwnerships[_assetId][msg.sender];
        ownership.assetId = _assetId;
        ownership.owner = msg.sender;
        ownership.fractionAmount += _fractionAmount;
        ownership.purchaseDate = block.timestamp;
        ownership.lockExpiry = block.timestamp + asset.lockupPeriod;
        ownership.isLocked = asset.lockupPeriod > 0;

        ownerFractions[msg.sender].push(_assetId);
        asset.availableFractions -= _fractionAmount;
        totalFractionsMinted += _fractionAmount;

        emit FractionsPurchased(_assetId, msg.sender, _fractionAmount);
    }

    /**
     * @notice Sell asset fractions
     */
    function sellFractions(
        bytes32 _assetId,
        uint256 _fractionAmount
    ) public assetActive(_assetId) nonReentrant {
        FractionOwnership storage ownership = fractionOwnerships[_assetId][msg.sender];
        require(ownership.fractionAmount >= _fractionAmount, "Insufficient fractions");
        require(!ownership.isLocked || block.timestamp >= ownership.lockExpiry, "Fractions still locked");

        FractionalAsset storage asset = fractionalAssets[_assetId];

        // Calculate sale proceeds
        uint256 saleProceeds = _fractionAmount * asset.fractionPrice;

        // Transfer proceeds to seller
        payable(msg.sender).transfer(saleProceeds);

        ownership.fractionAmount -= _fractionAmount;
        asset.availableFractions += _fractionAmount;

        emit FractionsSold(_assetId, msg.sender, _fractionAmount);
    }

    /**
     * @notice Distribute yield to fraction holders
     */
    function distributeYield(
        bytes32 _assetId,
        uint256 _totalYield,
        address _yieldToken
    ) public onlyAssetCustodian(_assetId) assetActive(_assetId) whenNotPaused {
        require(_totalYield > 0, "Invalid yield amount");

        FractionalAsset storage asset = fractionalAssets[_assetId];
        require(asset.totalFractions > 0, "No fractions minted");

        uint256 yieldPerFraction = (_totalYield * 1e18) / asset.totalFractions;

        YieldDistribution memory distribution = YieldDistribution({
            assetId: _assetId,
            totalYield: _totalYield,
            yieldPerFraction: yieldPerFraction,
            distributionDate: block.timestamp,
            yieldToken: _yieldToken,
            isDistributed: false
        });

        yieldDistributions[_assetId].push(distribution);

        asset.lastYieldDistribution = block.timestamp;
        asset.totalYieldDistributed += _totalYield;

        // Transfer yield tokens to contract for distribution
        IERC20(_yieldToken).safeTransferFrom(msg.sender, address(this), _totalYield);

        emit YieldDistributed(_assetId, _totalYield);
    }

    /**
     * @notice Claim yield for fraction holder
     */
    function claimYield(bytes32 _assetId) public whenNotPaused {
        FractionOwnership storage ownership = fractionOwnerships[_assetId][msg.sender];
        require(ownership.fractionAmount > 0, "No fractions owned");

        uint256 claimableYield = 0;
        YieldDistribution[] storage distributions = yieldDistributions[_assetId];

        for (uint256 i = 0; i < distributions.length; i++) {
            if (!distributions[i].isDistributed) {
                uint256 entitledYield = (ownership.fractionAmount * distributions[i].yieldPerFraction) / 1e18;
                claimableYield += entitledYield;
                distributions[i].isDistributed = true; // Mark as distributed for this user
            }
        }

        require(claimableYield > 0, "No yield to claim");

        ownership.accumulatedYield += claimableYield;

        // Transfer yield to claimant
        address yieldToken = distributions[distributions.length - 1].yieldToken;
        IERC20(yieldToken).safeTransfer(msg.sender, claimableYield);
    }

    /**
     * @notice Revalue an asset
     */
    function revalueAsset(
        bytes32 _assetId,
        uint256 _newValuation,
        string memory _methodology,
        bytes32 _supportingDocsHash
    ) public onlyAssetCustodian(_assetId) validAsset(_assetId) {
        require(_newValuation > 0, "Invalid valuation");

        FractionalAsset storage asset = fractionalAssets[_assetId];

        AssetValuation memory valuation = AssetValuation({
            assetId: _assetId,
            valuation: _newValuation,
            valuationDate: block.timestamp,
            appraiser: msg.sender,
            methodology: _methodology,
            supportingDocsHash: _supportingDocsHash,
            isAccepted: true
        });

        assetValuations[_assetId].push(valuation);
        asset.totalValue = _newValuation;
        asset.valuationHash = keccak256(abi.encodePacked(_newValuation, _methodology, _supportingDocsHash));

        // Adjust fraction price based on new valuation
        if (asset.totalFractions > 0) {
            asset.fractionPrice = (_newValuation * 1e18) / asset.totalFractions;
        }

        emit AssetRevalued(_assetId, _newValuation);
    }

    /**
     * @notice Liquidate an asset
     */
    function liquidateAsset(bytes32 _assetId) public onlyAssetCustodian(_assetId) validAsset(_assetId) {
        FractionalAsset storage asset = fractionalAssets[_assetId];
        require(asset.status == AssetStatus.ACTIVE, "Asset not active");

        // Calculate total liquidation proceeds (simplified)
        uint256 liquidationProceeds = asset.totalValue; // Assume full recovery

        asset.status = AssetStatus.LIQUIDATING;

        // Distribute proceeds to fraction holders proportionally
        uint256 proceedsPerFraction = (liquidationProceeds * 1e18) / asset.totalFractions;

        // In production, this would iterate through all fraction holders
        // For now, we mark as liquidated

        asset.status = AssetStatus.RETIRED;

        emit AssetLiquidated(_assetId, liquidationProceeds);
    }

    /**
     * @notice Get asset details
     */
    function getAsset(bytes32 _assetId) public view
        returns (
            string memory assetName,
            AssetType assetType,
            AssetStatus status,
            uint256 totalValue,
            uint256 totalFractions,
            uint256 availableFractions,
            uint256 fractionPrice
        )
    {
        FractionalAsset memory asset = fractionalAssets[_assetId];
        return (
            asset.assetName,
            asset.assetType,
            asset.status,
            asset.totalValue,
            asset.totalFractions,
            asset.availableFractions,
            asset.fractionPrice
        );
    }

    /**
     * @notice Get fraction ownership
     */
    function getFractionOwnership(bytes32 _assetId, address _owner) public view
        returns (
            uint256 fractionAmount,
            uint256 accumulatedYield,
            bool isLocked,
            uint256 lockExpiry
        )
    {
        FractionOwnership memory ownership = fractionOwnerships[_assetId][_owner];
        return (
            ownership.fractionAmount,
            ownership.accumulatedYield,
            ownership.isLocked,
            ownership.lockExpiry
        );
    }

    /**
     * @notice Get latest asset valuation
     */
    function getLatestValuation(bytes32 _assetId) public view
        returns (
            uint256 valuation,
            uint256 valuationDate,
            address appraiser,
            string memory methodology
        )
    {
        AssetValuation[] memory valuations = assetValuations[_assetId];
        if (valuations.length == 0) {
            return (0, 0, address(0), "");
        }

        AssetValuation memory latest = valuations[valuations.length - 1];
        return (
            latest.valuation,
            latest.valuationDate,
            latest.appraiser,
            latest.methodology
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateParameters(
        uint256 _minAssetValue,
        uint256 _maxFractionSupply,
        uint256 _minFractionPrice,
        uint256 _maxLockupPeriod
    ) public onlyOwner {
        minAssetValue = _minAssetValue;
        maxFractionSupply = _maxFractionSupply;
        minFractionPrice = _minFractionPrice;
        maxLockupPeriod = _maxLockupPeriod;
    }

    /**
     * @notice Emergency pause
     */
    function emergencyPause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause
     */
    function emergencyUnpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Get global statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalAssets,
            uint256 _totalAssetValue,
            uint256 _totalFractionsMinted,
            uint256 _totalYieldDistributed
        )
    {
        return (totalAssets, totalAssetValue, totalFractionsMinted, totalYieldDistributed);
    }
}
