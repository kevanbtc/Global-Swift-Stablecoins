// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title BaselIIIComplianceEngine
 * @notice Advanced Basel III risk-weighted asset calculations and capital adequacy monitoring
 * @dev Implements comprehensive RWA calculations, CAR monitoring, and regulatory reporting
 */
contract BaselIIIComplianceEngine is Ownable, ReentrancyGuard, Pausable {

    enum AssetClass {
        SOVEREIGN,
        BANK,
        CORPORATE,
        RETAIL,
        EQUITY,
        REAL_ESTATE,
        COMMODITIES,
        OTHER
    }

    enum RiskWeight {
        ZERO,       // 0%
        TWO,        // 2%
        FOUR,       // 4%
        TEN,        // 10%
        TWENTY,     // 20%
        THIRTY_FIVE,// 35%
        FIFTY,      // 50%
        SEVENTY_FIVE,// 75%
        ONE_HUNDRED,// 100%
        ONE_HUNDRED_FIFTY, // 150%
        TWO_HUNDRED_FIFTY, // 250%
        THREE_HUNDRED,     // 300%
        FOUR_HUNDRED,      // 400%
        SIX_HUNDRED,       // 600%
        ONE_THOUSAND       // 1000%
    }

    struct AssetPosition {
        address assetAddress;
        uint256 exposureAmount;    // In asset decimals
        AssetClass assetClass;
        RiskWeight riskWeight;
        uint256 maturityDate;      // For credit risk calculations
        uint256 lastUpdated;
        bool isActive;
    }

    struct CapitalPosition {
        uint256 tier1Capital;
        uint256 tier2Capital;
        uint256 totalCapital;
        uint256 riskWeightedAssets;
        uint256 capitalRatio;      // In basis points (e.g., 800 = 8%)
        uint256 leverageRatio;     // In basis points
        uint256 lastCalculated;
    }

    struct RegulatoryLimits {
        uint256 minCAR;           // Minimum Capital Adequacy Ratio (800 = 8%)
        uint256 minLeverageRatio; // Minimum Leverage Ratio (300 = 3%)
        uint256 concentrationLimit; // Single exposure limit (2500 = 25%)
        uint256 largeExposureLimit; // Large exposure limit (3000 = 30%)
        uint256 lastUpdated;
    }

    // Storage
    mapping(address => AssetPosition) public assetPositions;
    mapping(address => bool) public approvedAssets;
    address[] public activeAssets;

    CapitalPosition public capitalPosition;
    RegulatoryLimits public regulatoryLimits;

    // Configuration
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant LEVERAGE_DENOMINATOR = 33333333333333333; // 1/30 in wei (3.33% = 1/30)

    // Risk weight mappings (exposure amount => risk weight)
    mapping(uint256 => RiskWeight) public sovereignRiskWeights;
    mapping(uint256 => RiskWeight) public bankRiskWeights;
    mapping(uint256 => RiskWeight) public corporateRiskWeights;

    // Events
    event AssetPositionUpdated(address indexed asset, uint256 exposure, RiskWeight riskWeight);
    event CapitalCalculated(uint256 tier1, uint256 tier2, uint256 rwa, uint256 car);
    event RegulatoryLimitBreached(string limitType, uint256 currentValue, uint256 limitValue);
    event RiskWeightUpdated(AssetClass assetClass, uint256 exposure, RiskWeight riskWeight);

    modifier onlyApprovedAsset(address asset) {
        require(approvedAssets[asset], "Asset not approved");
        _;
    }

    constructor(
        uint256 _minCAR,
        uint256 _minLeverageRatio,
        uint256 _concentrationLimit,
        uint256 _largeExposureLimit
    ) Ownable(msg.sender) {
        regulatoryLimits = RegulatoryLimits({
            minCAR: _minCAR,
            minLeverageRatio: _minLeverageRatio,
            concentrationLimit: _concentrationLimit,
            largeExposureLimit: _largeExposureLimit,
            lastUpdated: block.timestamp
        });

        _initializeRiskWeights();
    }

    /**
     * @notice Initialize default Basel III risk weights
     */
    function _initializeRiskWeights() internal {
        // Sovereign debt risk weights (simplified)
        sovereignRiskWeights[0] = RiskWeight.ZERO; // AAA rated
        sovereignRiskWeights[1000000] = RiskWeight.TWO; // AA rated
        sovereignRiskWeights[10000000] = RiskWeight.FOUR; // A rated
        sovereignRiskWeights[50000000] = RiskWeight.TEN; // BBB rated

        // Bank risk weights
        bankRiskWeights[0] = RiskWeight.TWENTY;
        bankRiskWeights[1000000] = RiskWeight.THIRTY_FIVE;
        bankRiskWeights[10000000] = RiskWeight.FIFTY;
        bankRiskWeights[50000000] = RiskWeight.SEVENTY_FIVE;

        // Corporate risk weights
        corporateRiskWeights[0] = RiskWeight.SEVENTY_FIVE;
        corporateRiskWeights[1000000] = RiskWeight.ONE_HUNDRED;
        corporateRiskWeights[10000000] = RiskWeight.ONE_HUNDRED_FIFTY;
    }

    /**
     * @notice Add or update an asset position
     */
    function updateAssetPosition(
        address asset,
        uint256 exposureAmount,
        AssetClass assetClass,
        uint256 maturityDate
    ) external onlyOwner whenNotPaused {
        require(approvedAssets[asset], "Asset not approved");

        RiskWeight riskWeight = _calculateRiskWeight(assetClass, exposureAmount);

        if (!assetPositions[asset].isActive) {
            activeAssets.push(asset);
        }

        assetPositions[asset] = AssetPosition({
            assetAddress: asset,
            exposureAmount: exposureAmount,
            assetClass: assetClass,
            riskWeight: riskWeight,
            maturityDate: maturityDate,
            lastUpdated: block.timestamp,
            isActive: true
        });

        emit AssetPositionUpdated(asset, exposureAmount, riskWeight);

        // Recalculate capital adequacy after position update
        _calculateCapitalAdequacy();
    }

    /**
     * @notice Remove an asset position
     */
    function removeAssetPosition(address asset) external onlyOwner {
        require(assetPositions[asset].isActive, "Asset position not active");

        assetPositions[asset].isActive = false;

        // Remove from active assets array
        for (uint256 i = 0; i < activeAssets.length; i++) {
            if (activeAssets[i] == asset) {
                activeAssets[i] = activeAssets[activeAssets.length - 1];
                activeAssets.pop();
                break;
            }
        }

        // Recalculate capital adequacy after position removal
        _calculateCapitalAdequacy();
    }

    /**
     * @notice Update capital positions
     */
    function updateCapital(
        uint256 tier1Capital,
        uint256 tier2Capital
    ) external onlyOwner whenNotPaused {
        capitalPosition.tier1Capital = tier1Capital;
        capitalPosition.tier2Capital = tier2Capital;
        capitalPosition.totalCapital = tier1Capital + tier2Capital;

        _calculateCapitalAdequacy();
    }

    /**
     * @notice Calculate capital adequacy ratio
     */
    function _calculateCapitalAdequacy() internal {
        uint256 totalRWA = 0;

        // Calculate total risk-weighted assets
        for (uint256 i = 0; i < activeAssets.length; i++) {
            address asset = activeAssets[i];
            AssetPosition memory position = assetPositions[asset];

            if (position.isActive) {
                uint256 riskWeightBP = _riskWeightToBasisPoints(position.riskWeight);
                uint256 weightedExposure = (position.exposureAmount * riskWeightBP) / BASIS_POINTS;
                totalRWA += weightedExposure;
            }
        }

        capitalPosition.riskWeightedAssets = totalRWA;

        // Calculate CAR (Capital Adequacy Ratio)
        if (totalRWA > 0) {
            capitalPosition.capitalRatio = (capitalPosition.totalCapital * BASIS_POINTS) / totalRWA;
        } else {
            capitalPosition.capitalRatio = 0;
        }

        // Calculate Leverage Ratio (Total Capital / Total Exposure)
        uint256 totalExposure = _calculateTotalExposure();
        if (totalExposure > 0) {
            capitalPosition.leverageRatio = (capitalPosition.totalCapital * BASIS_POINTS) / totalExposure;
        } else {
            capitalPosition.leverageRatio = 0;
        }

        capitalPosition.lastCalculated = block.timestamp;

        emit CapitalCalculated(
            capitalPosition.tier1Capital,
            capitalPosition.tier2Capital,
            totalRWA,
            capitalPosition.capitalRatio
        );

        // Check regulatory limits
        _checkRegulatoryLimits();
    }

    /**
     * @notice Calculate total exposure across all assets
     */
    function _calculateTotalExposure() internal view returns (uint256) {
        uint256 totalExposure = 0;

        for (uint256 i = 0; i < activeAssets.length; i++) {
            address asset = activeAssets[i];
            if (assetPositions[asset].isActive) {
                totalExposure += assetPositions[asset].exposureAmount;
            }
        }

        return totalExposure;
    }

    /**
     * @notice Calculate risk weight for an asset class and exposure
     */
    function _calculateRiskWeight(
        AssetClass assetClass,
        uint256 exposure
    ) internal view returns (RiskWeight) {
        if (assetClass == AssetClass.SOVEREIGN) {
            return _getRiskWeightFromMapping(sovereignRiskWeights, exposure);
        } else if (assetClass == AssetClass.BANK) {
            return _getRiskWeightFromMapping(bankRiskWeights, exposure);
        } else if (assetClass == AssetClass.CORPORATE) {
            return _getRiskWeightFromMapping(corporateRiskWeights, exposure);
        } else if (assetClass == AssetClass.RETAIL) {
            return RiskWeight.SEVENTY_FIVE;
        } else if (assetClass == AssetClass.EQUITY) {
            return RiskWeight.ONE_HUNDRED;
        } else if (assetClass == AssetClass.REAL_ESTATE) {
            return RiskWeight.ONE_HUNDRED_FIFTY;
        } else if (assetClass == AssetClass.COMMODITIES) {
            return RiskWeight.ONE_HUNDRED;
        } else {
            return RiskWeight.ONE_HUNDRED; // Default
        }
    }

    /**
     * @notice Get risk weight from mapping based on exposure thresholds
     */
    function _getRiskWeightFromMapping(
        mapping(uint256 => RiskWeight) storage weights,
        uint256 exposure
    ) internal view returns (RiskWeight) {
        RiskWeight result = RiskWeight.ONE_HUNDRED; // Default

        // Find the highest threshold that exposure meets or exceeds
        uint256[] memory thresholds = new uint256[](4);
        thresholds[0] = 0;
        thresholds[1] = 1000000;  // 1M
        thresholds[2] = 10000000; // 10M
        thresholds[3] = 50000000; // 50M

        for (uint256 i = thresholds.length; i > 0; i--) {
            uint256 threshold = thresholds[i-1];
            if (exposure >= threshold) {
                if (weights[threshold] != RiskWeight.ZERO) {
                    result = weights[threshold];
                }
                break;
            }
        }

        return result;
    }

    /**
     * @notice Convert RiskWeight enum to basis points
     */
    function _riskWeightToBasisPoints(RiskWeight weight) internal pure returns (uint256) {
        if (weight == RiskWeight.ZERO) return 0;
        if (weight == RiskWeight.TWO) return 200;
        if (weight == RiskWeight.FOUR) return 400;
        if (weight == RiskWeight.TEN) return 1000;
        if (weight == RiskWeight.TWENTY) return 2000;
        if (weight == RiskWeight.THIRTY_FIVE) return 3500;
        if (weight == RiskWeight.FIFTY) return 5000;
        if (weight == RiskWeight.SEVENTY_FIVE) return 7500;
        if (weight == RiskWeight.ONE_HUNDRED) return 10000;
        if (weight == RiskWeight.ONE_HUNDRED_FIFTY) return 15000;
        if (weight == RiskWeight.TWO_HUNDRED_FIFTY) return 25000;
        if (weight == RiskWeight.THREE_HUNDRED) return 30000;
        if (weight == RiskWeight.FOUR_HUNDRED) return 40000;
        if (weight == RiskWeight.SIX_HUNDRED) return 60000;
        if (weight == RiskWeight.ONE_THOUSAND) return 100000;
        return 10000; // Default 100%
    }

    /**
     * @notice Check regulatory limits and emit breaches
     */
    function _checkRegulatoryLimits() internal {
        // Check CAR
        if (capitalPosition.capitalRatio < regulatoryLimits.minCAR) {
            emit RegulatoryLimitBreached(
                "CAR",
                capitalPosition.capitalRatio,
                regulatoryLimits.minCAR
            );
        }

        // Check Leverage Ratio
        if (capitalPosition.leverageRatio < regulatoryLimits.minLeverageRatio) {
            emit RegulatoryLimitBreached(
                "LeverageRatio",
                capitalPosition.leverageRatio,
                regulatoryLimits.minLeverageRatio
            );
        }

        // Check concentration limits
        uint256 totalExposure = _calculateTotalExposure();
        for (uint256 i = 0; i < activeAssets.length; i++) {
            address asset = activeAssets[i];
            if (assetPositions[asset].isActive) {
                uint256 exposureRatio = (assetPositions[asset].exposureAmount * BASIS_POINTS) / totalExposure;

                if (exposureRatio > regulatoryLimits.concentrationLimit) {
                    emit RegulatoryLimitBreached(
                        "Concentration",
                        exposureRatio,
                        regulatoryLimits.concentrationLimit
                    );
                }
            }
        }
    }

    /**
     * @notice Approve an asset for position tracking
     */
    function approveAsset(address asset, bool approved) external onlyOwner {
        approvedAssets[asset] = approved;
    }

    /**
     * @notice Update regulatory limits
     */
    function updateRegulatoryLimits(
        uint256 _minCAR,
        uint256 _minLeverageRatio,
        uint256 _concentrationLimit,
        uint256 _largeExposureLimit
    ) external onlyOwner {
        regulatoryLimits.minCAR = _minCAR;
        regulatoryLimits.minLeverageRatio = _minLeverageRatio;
        regulatoryLimits.concentrationLimit = _concentrationLimit;
        regulatoryLimits.largeExposureLimit = _largeExposureLimit;
        regulatoryLimits.lastUpdated = block.timestamp;

        // Recalculate to check new limits
        _calculateCapitalAdequacy();
    }

    /**
     * @notice Update risk weights for asset classes
     */
    function updateRiskWeights(
        AssetClass assetClass,
        uint256[] memory exposures,
        RiskWeight[] memory weights
    ) external onlyOwner {
        require(exposures.length == weights.length, "Array length mismatch");

        mapping(uint256 => RiskWeight) storage targetMapping;

        if (assetClass == AssetClass.SOVEREIGN) {
            targetMapping = sovereignRiskWeights;
        } else if (assetClass == AssetClass.BANK) {
            targetMapping = bankRiskWeights;
        } else if (assetClass == AssetClass.CORPORATE) {
            targetMapping = corporateRiskWeights;
        } else {
            revert("Unsupported asset class for custom weights");
        }

        for (uint256 i = 0; i < exposures.length; i++) {
            targetMapping[exposures[i]] = weights[i];
            emit RiskWeightUpdated(assetClass, exposures[i], weights[i]);
        }
    }

    /**
     * @notice Get current capital adequacy status
     */
    function getCapitalAdequacyStatus()
        external
        view
        returns (
            uint256 car,
            uint256 leverageRatio,
            uint256 totalRWA,
            bool carCompliant,
            bool leverageCompliant
        )
    {
        return (
            capitalPosition.capitalRatio,
            capitalPosition.leverageRatio,
            capitalPosition.riskWeightedAssets,
            capitalPosition.capitalRatio >= regulatoryLimits.minCAR,
            capitalPosition.leverageRatio >= regulatoryLimits.minLeverageRatio
        );
    }

    /**
     * @notice Get asset position details
     */
    function getAssetPosition(address asset)
        external
        view
        returns (
            uint256 exposureAmount,
            AssetClass assetClass,
            RiskWeight riskWeight,
            uint256 riskWeightedAmount,
            bool isActive
        )
    {
        AssetPosition memory position = assetPositions[asset];
        uint256 riskWeightBP = _riskWeightToBasisPoints(position.riskWeight);
        uint256 riskWeightedAmount = (position.exposureAmount * riskWeightBP) / BASIS_POINTS;

        return (
            position.exposureAmount,
            position.assetClass,
            position.riskWeight,
            riskWeightedAmount,
            position.isActive
        );
    }

    /**
     * @notice Get all active assets
     */
    function getActiveAssets() external view returns (address[] memory) {
        return activeAssets;
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
}
