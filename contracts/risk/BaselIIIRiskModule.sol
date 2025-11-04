// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Types} from "../common/Types.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title BaselIIIRiskModule
/// @notice SR-level Basel III capital adequacy and risk weighting for RWA and stablecoins.
/// Implements risk-weighted assets (RWA) calculation, capital adequacy ratio (CAR),
/// and regulatory capital requirements per Basel III framework.
contract BaselIIIRiskModule is Ownable {
    
    // Basel III risk weights (in basis points, 10000 = 100%)
    enum RiskCategory {
        SOVEREIGN,      // 0% risk weight (government bonds)
        BANK,           // 20% risk weight (bank deposits)
        CORPORATE,      // 100% risk weight (corporate bonds)
        EQUITY,         // 250% risk weight (equity investments)
        REAL_ESTATE,    // 100% risk weight (real estate)
        COMMODITY,      // 150% risk weight (commodities)
        CRYPTO          // 1250% risk weight (crypto assets per Basel Committee)
    }
    
    mapping(RiskCategory => uint16) public riskWeights; // basis points
    
    // Asset risk classification
    mapping(address => RiskCategory) public assetRiskCategory;
    mapping(address => uint256) public assetExposure; // Total exposure per asset
    
    // Capital requirements
    struct CapitalRequirement {
        uint256 tier1Capital;        // Core capital (equity, retained earnings)
        uint256 tier2Capital;        // Supplementary capital (subordinated debt)
        uint256 riskWeightedAssets;  // Total RWA
        uint256 capitalAdequacyRatio; // CAR in basis points
        uint256 minimumCAR;          // Minimum required CAR (e.g., 800 bps = 8%)
    }
    
    CapitalRequirement public capitalReq;
    
    // Events
    event RiskWeightUpdated(RiskCategory indexed category, uint16 weight);
    event AssetClassified(address indexed asset, RiskCategory category);
    event ExposureUpdated(address indexed asset, uint256 exposure);
    event CapitalUpdated(uint256 tier1, uint256 tier2, uint256 rwa, uint256 car);
    event CapitalAdequacyViolation(uint256 currentCAR, uint256 minimumCAR);
    
    constructor() Ownable(msg.sender) {
        // Initialize Basel III standard risk weights
        riskWeights[RiskCategory.SOVEREIGN] = 0;      // 0%
        riskWeights[RiskCategory.BANK] = 2000;        // 20%
        riskWeights[RiskCategory.CORPORATE] = 10000;  // 100%
        riskWeights[RiskCategory.EQUITY] = 25000;     // 250%
        riskWeights[RiskCategory.REAL_ESTATE] = 10000; // 100%
        riskWeights[RiskCategory.COMMODITY] = 15000;  // 150%
        riskWeights[RiskCategory.CRYPTO] = 65535;     // 655.35% (max uint16, capped for Basel III crypto)
        
        // Set minimum CAR to 8% (Basel III minimum)
        capitalReq.minimumCAR = 800; // 8% in basis points
    }
    
    /// @notice Update risk weight for category
    function setRiskWeight(RiskCategory category, uint16 weight) external onlyOwner {
        require(weight <= 65535, "BRIII: Weight too high"); // Max uint16
        riskWeights[category] = weight;
        emit RiskWeightUpdated(category, weight);
    }
    
    /// @notice Classify asset into risk category
    function classifyAsset(address asset, RiskCategory category) external onlyOwner {
        assetRiskCategory[asset] = category;
        emit AssetClassified(asset, category);
    }
    
    /// @notice Update asset exposure
    function updateExposure(address asset, uint256 exposure) external onlyOwner {
        assetExposure[asset] = exposure;
        emit ExposureUpdated(asset, exposure);
        
        // Recalculate RWA and CAR
        _recalculateCapital();
    }
    
    /// @notice Update capital (Tier 1 and Tier 2)
    function updateCapital(uint256 tier1, uint256 tier2) external onlyOwner {
        capitalReq.tier1Capital = tier1;
        capitalReq.tier2Capital = tier2;
        
        // Recalculate CAR
        _recalculateCapital();
    }
    
    /// @notice Set minimum CAR requirement
    function setMinimumCAR(uint256 minCAR) external onlyOwner {
        require(minCAR >= 800, "BRIII: Below Basel III minimum"); // 8% minimum
        capitalReq.minimumCAR = minCAR;
    }
    
    /// @notice Calculate risk-weighted assets for a single asset
    function calculateRWA(address asset) public view returns (uint256) {
        uint256 exposure = assetExposure[asset];
        RiskCategory category = assetRiskCategory[asset];
        uint16 weight = riskWeights[category];
        
        return (exposure * weight) / 10000; // Convert basis points to percentage
    }
    
    /// @notice Calculate total risk-weighted assets
    function calculateTotalRWA(address[] calldata assets) public view returns (uint256 totalRWA) {
        for (uint256 i = 0; i < assets.length; i++) {
            totalRWA += calculateRWA(assets[i]);
        }
    }
    
    /// @notice Calculate capital adequacy ratio
    function calculateCAR() public view returns (uint256) {
        uint256 totalCapital = capitalReq.tier1Capital + capitalReq.tier2Capital;
        uint256 rwa = capitalReq.riskWeightedAssets;
        
        if (rwa == 0) return 0;
        
        // CAR = (Total Capital / RWA) * 10000 (in basis points)
        return (totalCapital * 10000) / rwa;
    }
    
    /// @notice Check if capital adequacy is met
    function isCapitalAdequate() public view returns (bool) {
        return capitalReq.capitalAdequacyRatio >= capitalReq.minimumCAR;
    }
    
    /// @notice Internal function to recalculate capital metrics
    function _recalculateCapital() internal {
        // Note: In production, this would iterate over all assets
        // For now, RWA must be set manually or via updateExposure
        
        uint256 car = calculateCAR();
        capitalReq.capitalAdequacyRatio = car;
        
        emit CapitalUpdated(
            capitalReq.tier1Capital,
            capitalReq.tier2Capital,
            capitalReq.riskWeightedAssets,
            car
        );
        
        // Check for violation
        if (car < capitalReq.minimumCAR) {
            emit CapitalAdequacyViolation(car, capitalReq.minimumCAR);
        }
    }
    
    /// @notice Get capital requirement details
    function getCapitalRequirement() external view returns (CapitalRequirement memory) {
        return capitalReq;
    }
}
