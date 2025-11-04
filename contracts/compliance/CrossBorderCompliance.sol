// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CrossBorderCompliance
 * @notice Jurisdiction-specific compliance rules for cross-border transactions
 * @dev Handles tax compliance, withholding requirements, and international regulations
 */
contract CrossBorderCompliance is Ownable, ReentrancyGuard {

    enum Jurisdiction {
        US,         // United States
        EU,         // European Union
        UK,         // United Kingdom
        SG,         // Singapore
        JP,         // Japan
        AU,         // Australia
        CA,         // Canada
        CH,         // Switzerland
        HK,         // Hong Kong
        OTHER       // Other jurisdictions
    }

    enum TaxType {
        WITHHOLDING,
        VAT,
        GST,
        CAPITAL_GAINS,
        WEALTH,
        INHERITANCE
    }

    enum ComplianceStatus {
        COMPLIANT,
        PENDING_REVIEW,
        REQUIRES_WITHHOLDING,
        BLOCKED,
        REQUIRES_REPORTING
    }

    struct JurisdictionRules {
        Jurisdiction jurisdiction;
        bool requiresFATCA;
        bool requiresCRS;
        bool requiresQI;
        uint256 withholdingRate;      // Basis points (e.g., 3000 = 30%)
        uint256 vatRate;             // Basis points
        bool requiresGAAR;           // General Anti-Avoidance Rules
        bool requiresCFC;            // Controlled Foreign Corporation rules
        string[] restrictedActivities;
        bool isActive;
    }

    struct TaxObligation {
        bytes32 obligationId;
        address taxpayer;
        address recipient;
        Jurisdiction sourceJurisdiction;
        Jurisdiction targetJurisdiction;
        TaxType taxType;
        uint256 amount;
        uint256 taxAmount;
        uint256 dueDate;
        bool isPaid;
        bool isExempt;
        string exemptionReason;
    }

    struct CrossBorderTransfer {
        bytes32 transferId;
        address from;
        address to;
        uint256 amount;
        address asset;
        Jurisdiction fromJurisdiction;
        Jurisdiction toJurisdiction;
        ComplianceStatus status;
        uint256 timestamp;
        uint256 withholdingAmount;
        bool requiresReporting;
        string[] complianceFlags;
    }

    // Storage
    mapping(Jurisdiction => JurisdictionRules) public jurisdictionRules;
    mapping(bytes32 => TaxObligation) public taxObligations;
    mapping(bytes32 => CrossBorderTransfer) public crossBorderTransfers;

    bytes32[] public activeObligations;
    bytes32[] public pendingTransfers;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant US_WITHHOLDING_RATE = 3000; // 30%
    uint256 public constant EU_WITHHOLDING_RATE = 0;    // 0% for qualified jurisdictions

    // Events
    event JurisdictionConfigured(Jurisdiction jurisdiction, bool isActive);
    event TaxObligationCreated(bytes32 indexed obligationId, address taxpayer, TaxType taxType);
    event TaxPaid(bytes32 indexed obligationId, uint256 amount);
    event CrossBorderTransferReviewed(bytes32 indexed transferId, ComplianceStatus status);
    event WithholdingApplied(bytes32 indexed transferId, uint256 amount);

    constructor() Ownable(msg.sender) {
        _initializeDefaultJurisdictionRules();
    }

    /**
     * @notice Configure jurisdiction-specific compliance rules
     */
    function configureJurisdiction(
        Jurisdiction jurisdiction,
        bool requiresFATCA,
        bool requiresCRS,
        bool requiresQI,
        uint256 withholdingRate,
        uint256 vatRate,
        bool requiresGAAR,
        bool requiresCFC,
        string[] memory restrictedActivities
    ) external onlyOwner {
        JurisdictionRules storage rules = jurisdictionRules[jurisdiction];
        rules.jurisdiction = jurisdiction;
        rules.requiresFATCA = requiresFATCA;
        rules.requiresCRS = requiresCRS;
        rules.requiresQI = requiresQI;
        rules.withholdingRate = withholdingRate;
        rules.vatRate = vatRate;
        rules.requiresGAAR = requiresGAAR;
        rules.requiresCFC = requiresCFC;
        rules.restrictedActivities = restrictedActivities;
        rules.isActive = true;

        emit JurisdictionConfigured(jurisdiction, true);
    }

    /**
     * @notice Assess cross-border transfer compliance
     */
    function assessCrossBorderCompliance(
        address from,
        address to,
        uint256 amount,
        address asset,
        Jurisdiction fromJurisdiction,
        Jurisdiction toJurisdiction,
        string memory memo
    ) external returns (bytes32, ComplianceStatus) {
        require(jurisdictionRules[fromJurisdiction].isActive, "Invalid source jurisdiction");
        require(jurisdictionRules[toJurisdiction].isActive, "Invalid target jurisdiction");

        bytes32 transferId = keccak256(abi.encodePacked(
            from, to, amount, asset, fromJurisdiction, toJurisdiction, block.timestamp
        ));

        ComplianceStatus status = _assessComplianceStatus(
            from, to, amount, fromJurisdiction, toJurisdiction, memo
        );

        uint256 withholdingAmount = _calculateWithholding(
            amount, fromJurisdiction, toJurisdiction, status
        );

        string[] memory complianceFlags = _generateComplianceFlags(
            fromJurisdiction, toJurisdiction, status
        );

        CrossBorderTransfer memory transfer = CrossBorderTransfer({
            transferId: transferId,
            from: from,
            to: to,
            amount: amount,
            asset: asset,
            fromJurisdiction: fromJurisdiction,
            toJurisdiction: toJurisdiction,
            status: status,
            timestamp: block.timestamp,
            withholdingAmount: withholdingAmount,
            requiresReporting: _requiresReporting(fromJurisdiction, toJurisdiction),
            complianceFlags: complianceFlags
        });

        crossBorderTransfers[transferId] = transfer;

        if (status == ComplianceStatus.REQUIRES_WITHHOLDING ||
            status == ComplianceStatus.PENDING_REVIEW) {
            pendingTransfers.push(transferId);
        }

        emit CrossBorderTransferReviewed(transferId, status);

        if (withholdingAmount > 0) {
            emit WithholdingApplied(transferId, withholdingAmount);
        }

        return (transferId, status);
    }

    /**
     * @notice Create tax obligation for cross-border transaction
     */
    function createTaxObligation(
        address taxpayer,
        address recipient,
        Jurisdiction sourceJurisdiction,
        Jurisdiction targetJurisdiction,
        TaxType taxType,
        uint256 amount,
        uint256 dueDate
    ) external onlyOwner returns (bytes32) {
        bytes32 obligationId = keccak256(abi.encodePacked(
            taxpayer, recipient, taxType, amount, block.timestamp
        ));

        uint256 taxAmount = _calculateTaxAmount(amount, taxType, sourceJurisdiction, targetJurisdiction);

        TaxObligation memory obligation = TaxObligation({
            obligationId: obligationId,
            taxpayer: taxpayer,
            recipient: recipient,
            sourceJurisdiction: sourceJurisdiction,
            targetJurisdiction: targetJurisdiction,
            taxType: taxType,
            amount: amount,
            taxAmount: taxAmount,
            dueDate: dueDate,
            isPaid: false,
            isExempt: false,
            exemptionReason: ""
        });

        taxObligations[obligationId] = obligation;
        activeObligations.push(obligationId);

        emit TaxObligationCreated(obligationId, taxpayer, taxType);
        return obligationId;
    }

    /**
     * @notice Pay tax obligation
     */
    function payTaxObligation(bytes32 obligationId) external payable nonReentrant {
        TaxObligation storage obligation = taxObligations[obligationId];
        require(obligation.taxpayer == msg.sender, "Not authorized");
        require(!obligation.isPaid, "Already paid");
        require(!obligation.isExempt, "Tax exempt");
        require(msg.value >= obligation.taxAmount, "Insufficient payment");

        obligation.isPaid = true;

        // Transfer excess payment back
        if (msg.value > obligation.taxAmount) {
            payable(msg.sender).transfer(msg.value - obligation.taxAmount);
        }

        emit TaxPaid(obligationId, obligation.taxAmount);
    }

    /**
     * @notice Grant tax exemption
     */
    function grantTaxExemption(
        bytes32 obligationId,
        string memory exemptionReason
    ) external onlyOwner {
        TaxObligation storage obligation = taxObligations[obligationId];
        require(!obligation.isPaid, "Already paid");

        obligation.isExempt = true;
        obligation.exemptionReason = exemptionReason;
    }

    /**
     * @notice Check if transfer is compliant
     */
    function isTransferCompliant(bytes32 transferId) external view returns (bool) {
        CrossBorderTransfer memory transfer = crossBorderTransfers[transferId];
        return transfer.status == ComplianceStatus.COMPLIANT ||
               transfer.status == ComplianceStatus.REQUIRES_REPORTING;
    }

    /**
     * @notice Get withholding amount for transfer
     */
    function getWithholdingAmount(bytes32 transferId) external view returns (uint256) {
        return crossBorderTransfers[transferId].withholdingAmount;
    }

    /**
     * @notice Get compliance flags for transfer
     */
    function getComplianceFlags(bytes32 transferId) external view returns (string[] memory) {
        return crossBorderTransfers[transferId].complianceFlags;
    }

    // Internal helper functions

    function _initializeDefaultJurisdictionRules() internal {
        // US Rules
        string[] memory usRestrictions = new string[](2);
        usRestrictions[0] = "gambling";
        usRestrictions[1] = "weapons";
        configureJurisdiction(
            Jurisdiction.US,
            true,   // FATCA
            true,   // CRS
            true,   // QI
            US_WITHHOLDING_RATE,
            0,      // No VAT
            true,   // GAAR
            true,   // CFC
            usRestrictions
        );

        // EU Rules
        string[] memory euRestrictions = new string[](1);
        euRestrictions[0] = "money_laundering";
        configureJurisdiction(
            Jurisdiction.EU,
            true,   // FATCA
            true,   // CRS
            false,  // QI
            EU_WITHHOLDING_RATE,
            2000,   // 20% VAT
            true,   // GAAR
            true,   // CFC
            euRestrictions
        );

        // Singapore Rules
        string[] memory sgRestrictions = new string[](0);
        configureJurisdiction(
            Jurisdiction.SG,
            false,  // FATCA
            true,   // CRS
            false,  // QI
            0,      // No withholding
            800,    // 8% GST
            false,  // GAAR
            false,  // CFC
            sgRestrictions
        );
    }

    function _assessComplianceStatus(
        address from,
        address to,
        uint256 amount,
        Jurisdiction fromJurisdiction,
        Jurisdiction toJurisdiction,
        string memory memo
    ) internal view returns (ComplianceStatus) {
        JurisdictionRules memory fromRules = jurisdictionRules[fromJurisdiction];
        JurisdictionRules memory toRules = jurisdictionRules[toJurisdiction];

        // Check restricted activities
        if (_isRestrictedActivity(memo, fromRules.restrictedActivities) ||
            _isRestrictedActivity(memo, toRules.restrictedActivities)) {
            return ComplianceStatus.BLOCKED;
        }

        // Check withholding requirements
        if (fromRules.withholdingRate > 0 || toRules.withholdingRate > 0) {
            return ComplianceStatus.REQUIRES_WITHHOLDING;
        }

        // Check reporting requirements
        if (fromRules.requiresFATCA || fromRules.requiresCRS ||
            toRules.requiresFATCA || toRules.requiresCRS) {
            return ComplianceStatus.REQUIRES_REPORTING;
        }

        // Check GAAR/CFC requirements
        if (fromRules.requiresGAAR || fromRules.requiresCFC ||
            toRules.requiresGAAR || toRules.requiresCFC) {
            return ComplianceStatus.PENDING_REVIEW;
        }

        return ComplianceStatus.COMPLIANT;
    }

    function _calculateWithholding(
        uint256 amount,
        Jurisdiction fromJurisdiction,
        Jurisdiction toJurisdiction,
        ComplianceStatus status
    ) internal view returns (uint256) {
        if (status != ComplianceStatus.REQUIRES_WITHHOLDING) {
            return 0;
        }

        JurisdictionRules memory fromRules = jurisdictionRules[fromJurisdiction];
        JurisdictionRules memory toRules = jurisdictionRules[toJurisdiction];

        uint256 rate = fromRules.withholdingRate > toRules.withholdingRate ?
                      fromRules.withholdingRate : toRules.withholdingRate;

        return (amount * rate) / BASIS_POINTS;
    }

    function _calculateTaxAmount(
        uint256 amount,
        TaxType taxType,
        Jurisdiction sourceJurisdiction,
        Jurisdiction targetJurisdiction
    ) internal view returns (uint256) {
        JurisdictionRules memory sourceRules = jurisdictionRules[sourceJurisdiction];
        JurisdictionRules memory targetRules = jurisdictionRules[targetJurisdiction];

        if (taxType == TaxType.WITHHOLDING) {
            uint256 rate = sourceRules.withholdingRate > targetRules.withholdingRate ?
                          sourceRules.withholdingRate : targetRules.withholdingRate;
            return (amount * rate) / BASIS_POINTS;
        } else if (taxType == TaxType.VAT) {
            uint256 rate = sourceRules.vatRate > targetRules.vatRate ?
                          sourceRules.vatRate : targetRules.vatRate;
            return (amount * rate) / BASIS_POINTS;
        }

        return 0;
    }

    function _generateComplianceFlags(
        Jurisdiction fromJurisdiction,
        Jurisdiction toJurisdiction,
        ComplianceStatus status
    ) internal view returns (string[] memory) {
        string[] memory flags = new string[](10);
        uint256 flagCount = 0;

        JurisdictionRules memory fromRules = jurisdictionRules[fromJurisdiction];
        JurisdictionRules memory toRules = jurisdictionRules[toJurisdiction];

        if (fromRules.requiresFATCA || toRules.requiresFATCA) {
            flags[flagCount++] = "FATCA";
        }
        if (fromRules.requiresCRS || toRules.requiresCRS) {
            flags[flagCount++] = "CRS";
        }
        if (fromRules.requiresQI || toRules.requiresQI) {
            flags[flagCount++] = "QI";
        }
        if (fromRules.requiresGAAR || toRules.requiresGAAR) {
            flags[flagCount++] = "GAAR";
        }
        if (fromRules.requiresCFC || toRules.requiresCFC) {
            flags[flagCount++] = "CFC";
        }
        if (status == ComplianceStatus.REQUIRES_WITHHOLDING) {
            flags[flagCount++] = "WITHHOLDING";
        }
        if (status == ComplianceStatus.REQUIRES_REPORTING) {
            flags[flagCount++] = "REPORTING";
        }

        // Resize array to actual size
        string[] memory actualFlags = new string[](flagCount);
        for (uint256 i = 0; i < flagCount; i++) {
            actualFlags[i] = flags[i];
        }

        return actualFlags;
    }

    function _requiresReporting(
        Jurisdiction fromJurisdiction,
        Jurisdiction toJurisdiction
    ) internal view returns (bool) {
        JurisdictionRules memory fromRules = jurisdictionRules[fromJurisdiction];
        JurisdictionRules memory toRules = jurisdictionRules[toJurisdiction];

        return fromRules.requiresFATCA || fromRules.requiresCRS ||
               toRules.requiresFATCA || toRules.requiresCRS;
    }

    function _isRestrictedActivity(
        string memory activity,
        string[] memory restrictions
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < restrictions.length; i++) {
            if (keccak256(bytes(activity)) == keccak256(bytes(restrictions[i]))) {
                return true;
            }
        }
        return false;
    }
}
