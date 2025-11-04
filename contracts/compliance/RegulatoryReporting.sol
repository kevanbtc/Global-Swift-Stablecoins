// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title RegulatoryReporting
 * @notice Automated regulatory reporting for FinCEN CTR/SAR and international compliance
 * @dev Handles CTR, SAR, and other regulatory filings with encryption and audit trails
 */
contract RegulatoryReporting is Ownable, ReentrancyGuard {

    enum ReportType {
        CTR,                    // Currency Transaction Report ($10k+)
        SAR,                    // Suspicious Activity Report
        CMIR,                   // Currency and Monetary Instrument Report
        FBAR,                   // Foreign Bank Account Report
        FATCA,                  // Foreign Account Tax Compliance Act
        CRS,                    // Common Reporting Standard
        DAC6,                   // EU Mandatory Disclosure Rules
        EMIR                    // European Market Infrastructure Regulation
    }

    enum ReportStatus {
        PENDING,
        SUBMITTED,
        ACCEPTED,
        REJECTED,
        UNDER_REVIEW
    }

    enum Jurisdiction {
        US_FINCEN,
        EU_ESMA,
        UK_FCA,
        SG_MAS,
        JP_FSA,
        AU_ASIC,
        CA_FINTRAC,
        CH_FINMA
    }

    struct RegulatoryReport {
        bytes32 reportId;
        ReportType reportType;
        Jurisdiction jurisdiction;
        address subject;
        string reportData;           // Encrypted JSON data
        bytes32 dataHash;           // Hash for integrity verification
        ReportStatus status;
        uint256 submissionTimestamp;
        uint256 lastUpdated;
        string referenceNumber;     // Regulatory reference
        string rejectionReason;     // If rejected
        bool isEncrypted;
    }

    struct FilingObligation {
        bytes32 obligationId;
        ReportType reportType;
        Jurisdiction jurisdiction;
        uint256 threshold;           // Amount threshold for filing
        uint256 deadline;           // Filing deadline in seconds
        bool isActive;
        string description;
    }

    struct JurisdictionConfig {
        Jurisdiction jurisdiction;
        address regulatorAddress;    // Smart contract address for regulator
        string apiEndpoint;         // Off-chain API endpoint
        bytes32 encryptionKey;      // For report encryption
        bool isActive;
        uint256 maxReportSize;      // Max encrypted data size
    }

    // Storage
    mapping(bytes32 => RegulatoryReport) public regulatoryReports;
    mapping(bytes32 => FilingObligation) public filingObligations;
    mapping(Jurisdiction => JurisdictionConfig) public jurisdictionConfigs;

    bytes32[] public activeObligations;
    bytes32[] public pendingReports;

    // Thresholds (in wei for $1 = 1e18)
    uint256 public constant CTR_THRESHOLD = 10000 * 1e18;     // $10,000
    uint256 public constant CMIR_THRESHOLD = 10000 * 1e18;    // $10,000
    uint256 public constant SAR_THRESHOLD = 5000 * 1e18;     // $5,000 (suspicious)

    // Events
    event ReportFiled(bytes32 indexed reportId, ReportType reportType, Jurisdiction jurisdiction);
    event ReportStatusUpdated(bytes32 indexed reportId, ReportStatus status);
    event FilingObligationCreated(bytes32 indexed obligationId, ReportType reportType);
    event JurisdictionConfigured(Jurisdiction jurisdiction, bool isActive);

    constructor() Ownable(msg.sender) {
        _initializeDefaultConfigurations();
        _initializeDefaultObligations();
    }

    /**
     * @notice File a regulatory report
     */
    function fileReport(
        ReportType reportType,
        Jurisdiction jurisdiction,
        address subject,
        string memory reportData,
        bytes32 dataHash,
        bool encryptData
    ) external onlyOwner returns (bytes32) {
        require(jurisdictionConfigs[jurisdiction].isActive, "Jurisdiction not configured");

        bytes32 reportId = keccak256(abi.encodePacked(
            reportType,
            jurisdiction,
            subject,
            block.timestamp,
            dataHash
        ));

        require(regulatoryReports[reportId].submissionTimestamp == 0, "Report already exists");

        // Validate report size
        JurisdictionConfig memory config = jurisdictionConfigs[jurisdiction];
        require(bytes(reportData).length <= config.maxReportSize, "Report data too large");

        string memory finalReportData = reportData;
        bool isEncrypted = false;

        if (encryptData && config.encryptionKey != bytes32(0)) {
            // In production, would encrypt with regulator's public key
            finalReportData = _encryptReportData(reportData, config.encryptionKey);
            isEncrypted = true;
        }

        RegulatoryReport memory report = RegulatoryReport({
            reportId: reportId,
            reportType: reportType,
            jurisdiction: jurisdiction,
            subject: subject,
            reportData: finalReportData,
            dataHash: dataHash,
            status: ReportStatus.SUBMITTED,
            submissionTimestamp: block.timestamp,
            lastUpdated: block.timestamp,
            referenceNumber: "",
            rejectionReason: "",
            isEncrypted: isEncrypted
        });

        regulatoryReports[reportId] = report;
        pendingReports.push(reportId);

        emit ReportFiled(reportId, reportType, jurisdiction);
        return reportId;
    }

    /**
     * @notice Update report status (called by regulator or admin)
     */
    function updateReportStatus(
        bytes32 reportId,
        ReportStatus newStatus,
        string memory referenceNumber,
        string memory rejectionReason
    ) external onlyOwner {
        require(regulatoryReports[reportId].submissionTimestamp > 0, "Report not found");

        RegulatoryReport storage report = regulatoryReports[reportId];
        report.status = newStatus;
        report.lastUpdated = block.timestamp;

        if (newStatus == ReportStatus.ACCEPTED || newStatus == ReportStatus.REJECTED) {
            report.referenceNumber = referenceNumber;
            if (newStatus == ReportStatus.REJECTED) {
                report.rejectionReason = rejectionReason;
            }
        }

        emit ReportStatusUpdated(reportId, newStatus);
    }

    /**
     * @notice Check if transaction requires regulatory reporting
     */
    function requiresReporting(
        address from,
        address to,
        uint256 amount,
        address asset,
        string memory memo
    ) external view returns (bool needsReporting, ReportType[] memory reportTypes) {
        ReportType[] memory potentialReports = new ReportType[](8);
        uint256 reportCount = 0;

        // Check CTR threshold
        if (amount >= CTR_THRESHOLD) {
            potentialReports[reportCount] = ReportType.CTR;
            reportCount++;
        }

        // Check CMIR for monetary instruments
        if (_isMonetaryInstrument(asset) && amount >= CMIR_THRESHOLD) {
            potentialReports[reportCount] = ReportType.CMIR;
            reportCount++;
        }

        // Check for suspicious patterns (simplified)
        if (_isSuspiciousTransaction(from, to, amount, memo)) {
            potentialReports[reportCount] = ReportType.SAR;
            reportCount++;
        }

        // Check international obligations
        if (_requiresInternationalReporting(from, to, amount)) {
            potentialReports[reportCount] = ReportType.FATCA;
            reportCount++;
            potentialReports[reportCount] = ReportType.CRS;
            reportCount++;
        }

        if (reportCount > 0) {
            // Resize array to actual size
            ReportType[] memory actualReports = new ReportType[](reportCount);
            for (uint256 i = 0; i < reportCount; i++) {
                actualReports[i] = potentialReports[i];
            }
            return (true, actualReports);
        }

        return (false, new ReportType[](0));
    }

    /**
     * @notice Configure jurisdiction settings
     */
    function configureJurisdiction(
        Jurisdiction jurisdiction,
        address regulatorAddress,
        string memory apiEndpoint,
        bytes32 encryptionKey,
        uint256 maxReportSize
    ) external onlyOwner {
        JurisdictionConfig storage config = jurisdictionConfigs[jurisdiction];
        config.jurisdiction = jurisdiction;
        config.regulatorAddress = regulatorAddress;
        config.apiEndpoint = apiEndpoint;
        config.encryptionKey = encryptionKey;
        config.isActive = true;
        config.maxReportSize = maxReportSize;

        emit JurisdictionConfigured(jurisdiction, true);
    }

    /**
     * @notice Create filing obligation
     */
    function createFilingObligation(
        ReportType reportType,
        Jurisdiction jurisdiction,
        uint256 threshold,
        uint256 deadline,
        string memory description
    ) external onlyOwner returns (bytes32) {
        bytes32 obligationId = keccak256(abi.encodePacked(
            reportType,
            jurisdiction,
            threshold,
            block.timestamp
        ));

        FilingObligation memory obligation = FilingObligation({
            obligationId: obligationId,
            reportType: reportType,
            jurisdiction: jurisdiction,
            threshold: threshold,
            deadline: deadline,
            isActive: true,
            description: description
        });

        filingObligations[obligationId] = obligation;
        activeObligations.push(obligationId);

        emit FilingObligationCreated(obligationId, reportType);
        return obligationId;
    }

    /**
     * @notice Get pending reports
     */
    function getPendingReports() external view returns (bytes32[] memory) {
        return pendingReports;
    }

    /**
     * @notice Get report details
     */
    function getReport(bytes32 reportId) external view returns (
        ReportType reportType,
        Jurisdiction jurisdiction,
        ReportStatus status,
        uint256 submissionTimestamp,
        string memory referenceNumber
    ) {
        RegulatoryReport memory report = regulatoryReports[reportId];
        return (
            report.reportType,
            report.jurisdiction,
            report.status,
            report.submissionTimestamp,
            report.referenceNumber
        );
    }

    // Internal helper functions

    function _initializeDefaultConfigurations() internal {
        // Configure US FinCEN
        configureJurisdiction(
            Jurisdiction.US_FINCEN,
            address(0), // Would be actual regulator contract
            "https://fincen.gov/api/reports",
            keccak256("FINCEN_ENCRYPTION_KEY"),
            50000 // 50KB max
        );

        // Configure EU ESMA
        configureJurisdiction(
            Jurisdiction.EU_ESMA,
            address(0),
            "https://esma.europa.eu/api/reports",
            keccak256("ESMA_ENCRYPTION_KEY"),
            50000
        );

        // Configure UK FCA
        configureJurisdiction(
            Jurisdiction.UK_FCA,
            address(0),
            "https://fca.org.uk/api/reports",
            keccak256("FCA_ENCRYPTION_KEY"),
            50000
        );
    }

    function _initializeDefaultObligations() internal {
        // CTR obligation for US
        createFilingObligation(
            ReportType.CTR,
            Jurisdiction.US_FINCEN,
            CTR_THRESHOLD,
            15 days, // 15 day filing deadline
            "Currency Transaction Report for transactions over $10,000"
        );

        // SAR obligation for US
        createFilingObligation(
            ReportType.SAR,
            Jurisdiction.US_FINCEN,
            SAR_THRESHOLD,
            30 days,
            "Suspicious Activity Report for suspicious transactions"
        );

        // FATCA obligation
        createFilingObligation(
            ReportType.FATCA,
            Jurisdiction.US_FINCEN,
            50000 * 1e18, // $50k threshold
            90 days,
            "Foreign Account Tax Compliance Act reporting"
        );
    }

    function _encryptReportData(string memory data, bytes32 key) internal pure returns (string) {
        // Simplified encryption - in production would use proper encryption
        // This is just a placeholder for the concept
        return string(abi.encodePacked("ENCRYPTED:", data));
    }

    function _isMonetaryInstrument(address asset) internal view returns (bool) {
        // Check if asset is considered a monetary instrument
        // Would check against a registry of regulated assets
        return true; // Simplified
    }

    function _isSuspiciousTransaction(
        address from,
        address to,
        uint256 amount,
        string memory memo
    ) internal view returns (bool) {
        // Check for suspicious patterns
        // This would integrate with TransactionMonitoring contract
        return false; // Simplified
    }

    function _requiresInternationalReporting(
        address from,
        address to,
        uint256 amount
    ) internal view returns (bool) {
        // Check if transaction requires international reporting
        // Would check jurisdictions of from/to addresses
        return amount >= 50000 * 1e18; // Simplified threshold
    }
}
