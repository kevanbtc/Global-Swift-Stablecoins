// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title InstitutionalDeFiHub
 * @notice Complete institutional DeFi ecosystem with lending, trading, and yield management
 * @dev Enterprise-grade DeFi protocols for institutional participants
 */
contract InstitutionalDeFiHub is Ownable, ReentrancyGuard {

    enum ProtocolType {
        LENDING_PROTOCOL,
        DEX_PROTOCOL,
        YIELD_PROTOCOL,
        DERIVATIVES_PROTOCOL,
        SYNTHETICS_PROTOCOL,
        INSURANCE_PROTOCOL
    }

    enum RiskLevel {
        CONSERVATIVE,
        MODERATE,
        AGGRESSIVE,
        HIGH_YIELD
    }

    enum PositionType {
        LONG,
        SHORT,
        NEUTRAL,
        HEDGED
    }

    struct LendingPool {
        bytes32 poolId;
        address asset;
        address collateral;
        uint256 totalSupplied;
        uint256 totalBorrowed;
        uint256 supplyAPY;           // BPS
        uint256 borrowAPY;           // BPS
        uint256 maxLTV;              // BPS
        uint256 liquidationThreshold; // BPS
        uint256 minCollateralRatio;  // BPS
        bool isActive;
        RiskLevel riskLevel;
    }

    struct InstitutionalPosition {
        bytes32 positionId;
        address institution;
        ProtocolType protocolType;
        bytes32 poolId;
        PositionType positionType;
        address[] assets;
        uint256[] amounts;
        uint256 entryPrice;
        uint256 currentValue;
        uint256 pnl;
        uint256 leverage;            // BPS (10000 = 1x)
        uint256 liquidationPrice;
        bool isActive;
        uint256 lastUpdate;
        bytes32 riskProfile;
    }

    struct YieldStrategy {
        bytes32 strategyId;
        string strategyName;
        RiskLevel riskLevel;
        address[] tokens;
        uint256[] allocations;       // BPS
        uint256 totalValueLocked;
        uint256 apy;                 // BPS
        uint256 minInvestment;
        uint256 lockupPeriod;
        bool isActive;
        address strategist;
        bytes32 performanceHash;
    }

    struct DerivativesContract {
        bytes32 contractId;
        string instrument;
        address underlying;
        address strikeAsset;
        uint256 strikePrice;
        uint256 expiration;
        uint256 notionalAmount;
        bool isCall;                // true for call, false for put
        address buyer;
        address seller;
        uint256 premium;
        bool isSettled;
        bytes32 oracleId;
    }

    struct InsurancePolicy {
        bytes32 policyId;
        address insured;
        string coverageType;
        address asset;
        uint256 coverageAmount;
        uint256 premium;
        uint256 deductible;
        uint256 expiration;
        bool isActive;
        bool isClaimed;
        bytes32 riskAssessment;
    }

    // Storage
    mapping(bytes32 => LendingPool) public lendingPools;
    mapping(bytes32 => InstitutionalPosition) public institutionalPositions;
    mapping(bytes32 => YieldStrategy) public yieldStrategies;
    mapping(bytes32 => DerivativesContract) public derivativesContracts;
    mapping(bytes32 => InsurancePolicy) public insurancePolicies;
    mapping(address => bytes32[]) public institutionPositions;
    mapping(address => bytes32[]) public strategistStrategies;

    // Global statistics
    uint256 public totalValueLocked;
    uint256 public totalBorrowed;
    uint256 public activePositions;
    uint256 public totalInsuranceCoverage;

    // Protocol parameters
    uint256 public maxLeverage = 100000;     // 10x max leverage
    uint256 public minCollateralRatio = 15000; // 150% min collateral
    uint256 public liquidationBonus = 500;     // 5% liquidation bonus
    uint256 public protocolFee = 100;          // 1% protocol fee

    // Events
    event LendingPoolCreated(bytes32 indexed poolId, address asset, RiskLevel riskLevel);
    event PositionOpened(bytes32 indexed positionId, address indexed institution, uint256 size);
    event YieldStrategyCreated(bytes32 indexed strategyId, string name, RiskLevel riskLevel);
    event DerivativesTraded(bytes32 indexed contractId, string instrument, uint256 notional);
    event InsurancePurchased(bytes32 indexed policyId, address indexed insured, uint256 coverage);
    event LiquidationExecuted(bytes32 indexed positionId, uint256 liquidatedAmount);

    modifier validPool(bytes32 _poolId) {
        require(lendingPools[_poolId].asset != address(0), "Pool not found");
        _;
    }

    modifier validPosition(bytes32 _positionId) {
        require(institutionalPositions[_positionId].institution != address(0), "Position not found");
        _;
    }

    modifier validStrategy(bytes32 _strategyId) {
        require(yieldStrategies[_strategyId].strategist != address(0), "Strategy not found");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a lending pool
     */
    function createLendingPool(
        address _asset,
        address _collateral,
        uint256 _maxLTV,
        uint256 _liquidationThreshold,
        RiskLevel _riskLevel
    ) public onlyOwner returns (bytes32) {
        require(_asset != address(0), "Invalid asset");
        require(_maxLTV <= 9000, "LTV too high"); // Max 90%
        require(_liquidationThreshold > _maxLTV, "Invalid liquidation threshold");

        bytes32 poolId = keccak256(abi.encodePacked(
            _asset,
            _collateral,
            _riskLevel,
            block.timestamp
        ));

        require(lendingPools[poolId].asset == address(0), "Pool already exists");

        LendingPool storage pool = lendingPools[poolId];
        pool.poolId = poolId;
        pool.asset = _asset;
        pool.collateral = _collateral;
        pool.maxLTV = _maxLTV;
        pool.liquidationThreshold = _liquidationThreshold;
        pool.minCollateralRatio = 10000 + (10000 - _maxLTV); // 100% + buffer
        pool.isActive = true;
        pool.riskLevel = _riskLevel;

        emit LendingPoolCreated(poolId, _asset, _riskLevel);
        return poolId;
    }

    /**
     * @notice Open institutional position
     */
    function openInstitutionalPosition(
        ProtocolType _protocolType,
        bytes32 _poolId,
        PositionType _positionType,
        address[] memory _assets,
        uint256[] memory _amounts,
        uint256 _leverage
    ) public payable nonReentrant returns (bytes32) {
        require(_assets.length == _amounts.length, "Array length mismatch");
        require(_leverage <= maxLeverage, "Leverage too high");

        bytes32 positionId = keccak256(abi.encodePacked(
            msg.sender,
            _protocolType,
            _poolId,
            block.timestamp
        ));

        InstitutionalPosition storage position = institutionalPositions[positionId];
        position.positionId = positionId;
        position.institution = msg.sender;
        position.protocolType = _protocolType;
        position.poolId = _poolId;
        position.positionType = _positionType;
        position.assets = _assets;
        position.amounts = _amounts;
        position.leverage = _leverage;
        position.isActive = true;
        position.lastUpdate = block.timestamp;

        // Calculate position value
        uint256 totalValue = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalValue += _amounts[i];
        }
        position.currentValue = totalValue;

        institutionPositions[msg.sender].push(positionId);
        activePositions++;
        totalValueLocked += totalValue;

        emit PositionOpened(positionId, msg.sender, totalValue);
        return positionId;
    }

    /**
     * @notice Create yield strategy
     */
    function createYieldStrategy(
        string memory _strategyName,
        RiskLevel _riskLevel,
        address[] memory _tokens,
        uint256[] memory _allocations,
        uint256 _minInvestment,
        uint256 _lockupPeriod
    ) public returns (bytes32) {
        require(_tokens.length == _allocations.length, "Array length mismatch");

        // Validate allocations sum to 100%
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < _allocations.length; i++) {
            totalAllocation += _allocations[i];
        }
        require(totalAllocation == 10000, "Allocations must sum to 100%");

        bytes32 strategyId = keccak256(abi.encodePacked(
            _strategyName,
            msg.sender,
            block.timestamp
        ));

        require(yieldStrategies[strategyId].strategist == address(0), "Strategy already exists");

        YieldStrategy storage strategy = yieldStrategies[strategyId];
        strategy.strategyId = strategyId;
        strategy.strategyName = _strategyName;
        strategy.riskLevel = _riskLevel;
        strategy.tokens = _tokens;
        strategy.allocations = _allocations;
        strategy.minInvestment = _minInvestment;
        strategy.lockupPeriod = _lockupPeriod;
        strategy.isActive = true;
        strategy.strategist = msg.sender;

        strategistStrategies[msg.sender].push(strategyId);

        emit YieldStrategyCreated(strategyId, _strategyName, _riskLevel);
        return strategyId;
    }

    /**
     * @notice Trade derivatives contract
     */
    function tradeDerivatives(
        string memory _instrument,
        address _underlying,
        address _strikeAsset,
        uint256 _strikePrice,
        uint256 _expiration,
        uint256 _notionalAmount,
        bool _isCall,
        address _counterparty
    ) public payable returns (bytes32) {
        require(_expiration > block.timestamp, "Invalid expiration");
        require(_notionalAmount > 0, "Invalid notional amount");
        require(msg.value >= _notionalAmount / 100, "Insufficient premium"); // 1% premium

        bytes32 contractId = keccak256(abi.encodePacked(
            _instrument,
            _underlying,
            _strikePrice,
            _expiration,
            msg.sender,
            block.timestamp
        ));

        DerivativesContract storage derivativesContract = derivativesContracts[contractId];
        derivativesContract.contractId = contractId;
        derivativesContract.instrument = _instrument;
        derivativesContract.underlying = _underlying;
        derivativesContract.strikeAsset = _strikeAsset;
        derivativesContract.strikePrice = _strikePrice;
        derivativesContract.expiration = _expiration;
        derivativesContract.notionalAmount = _notionalAmount;
        derivativesContract.isCall = _isCall;
        derivativesContract.buyer = msg.sender;
        derivativesContract.seller = _counterparty;
        derivativesContract.premium = msg.value;

        emit DerivativesTraded(contractId, _instrument, _notionalAmount);
        return contractId;
    }

    /**
     * @notice Purchase insurance policy
     */
    function purchaseInsurance(
        string memory _coverageType,
        address _asset,
        uint256 _coverageAmount,
        uint256 _premium,
        uint256 _deductible,
        uint256 _expiration
    ) public payable returns (bytes32) {
        require(msg.value >= _premium, "Insufficient premium payment");
        require(_expiration > block.timestamp, "Invalid expiration");
        require(_coverageAmount > _deductible, "Invalid coverage structure");

        bytes32 policyId = keccak256(abi.encodePacked(
            _coverageType,
            _asset,
            msg.sender,
            block.timestamp
        ));

        InsurancePolicy storage policy = insurancePolicies[policyId];
        policy.policyId = policyId;
        policy.insured = msg.sender;
        policy.coverageType = _coverageType;
        policy.asset = _asset;
        policy.coverageAmount = _coverageAmount;
        policy.premium = _premium;
        policy.deductible = _deductible;
        policy.expiration = _expiration;
        policy.isActive = true;

        totalInsuranceCoverage += _coverageAmount;

        emit InsurancePurchased(policyId, msg.sender, _coverageAmount);
        return policyId;
    }

    /**
     * @notice Update position valuation
     */
    function updatePositionValuation(
        bytes32 _positionId,
        uint256 _newValue
    ) public validPosition(_positionId) {
        InstitutionalPosition storage position = institutionalPositions[_positionId];

        uint256 oldValue = position.currentValue;
        position.currentValue = _newValue;
        position.pnl = _newValue > position.entryPrice ?
            ((_newValue - position.entryPrice) * 10000) / position.entryPrice :
            ((position.entryPrice - _newValue) * 10000) / position.entryPrice;
        position.lastUpdate = block.timestamp;

        // Update global TVL
        if (_newValue > oldValue) {
            totalValueLocked += (_newValue - oldValue);
        } else {
            totalValueLocked -= (oldValue - _newValue);
        }

        // Check for liquidation
        if (_newValue < position.liquidationPrice && position.isActive) {
            _liquidatePosition(_positionId);
        }
    }

    /**
     * @notice Close position
     */
    function closePosition(bytes32 _positionId) public validPosition(_positionId) nonReentrant {
        InstitutionalPosition storage position = institutionalPositions[_positionId];
        require(position.institution == msg.sender, "Not position owner");
        require(position.isActive, "Position not active");

        position.isActive = false;
        activePositions--;
        totalValueLocked -= position.currentValue;

        // Return assets (simplified)
        // In production, this would handle actual asset transfers
    }

    /**
     * @notice Claim insurance
     */
    function claimInsurance(bytes32 _policyId, uint256 _claimAmount) public {
        InsurancePolicy storage policy = insurancePolicies[_policyId];
        require(policy.insured == msg.sender, "Not policy holder");
        require(policy.isActive, "Policy not active");
        require(!policy.isClaimed, "Already claimed");
        require(block.timestamp <= policy.expiration, "Policy expired");
        require(_claimAmount <= policy.coverageAmount, "Claim exceeds coverage");

        policy.isClaimed = true;
        policy.isActive = false;

        // Transfer claim amount (simplified)
        payable(msg.sender).transfer(_claimAmount);
    }

    /**
     * @notice Internal liquidation function
     */
    function _liquidatePosition(bytes32 _positionId) internal {
        InstitutionalPosition storage position = institutionalPositions[_positionId];
        position.isActive = false;
        activePositions--;

        // Calculate liquidation amount with bonus
        uint256 liquidationAmount = (position.currentValue * (10000 + liquidationBonus)) / 10000;

        emit LiquidationExecuted(_positionId, liquidationAmount);
    }

    /**
     * @notice Get lending pool details
     */
    function getLendingPool(bytes32 _poolId) public view
        returns (
            address asset,
            uint256 totalSupplied,
            uint256 supplyAPY,
            uint256 borrowAPY,
            bool isActive
        )
    {
        LendingPool memory pool = lendingPools[_poolId];
        return (
            pool.asset,
            pool.totalSupplied,
            pool.supplyAPY,
            pool.borrowAPY,
            pool.isActive
        );
    }

    /**
     * @notice Get institutional position
     */
    function getInstitutionalPosition(bytes32 _positionId) public view
        returns (
            address institution,
            PositionType positionType,
            uint256 currentValue,
            uint256 pnl,
            bool isActive
        )
    {
        InstitutionalPosition memory position = institutionalPositions[_positionId];
        return (
            position.institution,
            position.positionType,
            position.currentValue,
            position.pnl,
            position.isActive
        );
    }

    /**
     * @notice Get yield strategy
     */
    function getYieldStrategy(bytes32 _strategyId) public view
        returns (
            string memory strategyName,
            RiskLevel riskLevel,
            uint256 apy,
            uint256 totalValueLocked,
            bool isActive
        )
    {
        YieldStrategy memory strategy = yieldStrategies[_strategyId];
        return (
            strategy.strategyName,
            strategy.riskLevel,
            strategy.apy,
            strategy.totalValueLocked,
            strategy.isActive
        );
    }

    /**
     * @notice Get derivatives contract
     */
    function getDerivativesContract(bytes32 _contractId) public view
        returns (
            string memory instrument,
            uint256 strikePrice,
            uint256 notionalAmount,
            bool isCall,
            bool isSettled
        )
    {
        DerivativesContract memory derivativesContract = derivativesContracts[_contractId];
        return (
            derivativesContract.instrument,
            derivativesContract.strikePrice,
            derivativesContract.notionalAmount,
            derivativesContract.isCall,
            derivativesContract.isSettled
        );
    }

    /**
     * @notice Get insurance policy
     */
    function getInsurancePolicy(bytes32 _policyId) public view
        returns (
            address insured,
            string memory coverageType,
            uint256 coverageAmount,
            bool isActive,
            bool isClaimed
        )
    {
        InsurancePolicy memory policy = insurancePolicies[_policyId];
        return (
            policy.insured,
            policy.coverageType,
            policy.coverageAmount,
            policy.isActive,
            policy.isClaimed
        );
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _maxLeverage,
        uint256 _minCollateralRatio,
        uint256 _liquidationBonus,
        uint256 _protocolFee
    ) public onlyOwner {
        maxLeverage = _maxLeverage;
        minCollateralRatio = _minCollateralRatio;
        liquidationBonus = _liquidationBonus;
        protocolFee = _protocolFee;
    }

    /**
     * @notice Get global DeFi statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalValueLocked,
            uint256 _totalBorrowed,
            uint256 _activePositions,
            uint256 _totalInsuranceCoverage
        )
    {
        return (totalValueLocked, totalBorrowed, activePositions, totalInsuranceCoverage);
    }
}
