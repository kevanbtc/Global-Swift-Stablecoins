// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../common/Types.sol";
import "../common/Roles.sol";
import "../common/Errors.sol";

/**
 * @title SequencerMetrics
 * @notice Collects and analyzes performance metrics for the sequencer network
 * @dev Implements metric collection, aggregation, and analysis
 */
contract SequencerMetrics is AccessControl, Pausable {
    bytes32 public constant METRICS_ROLE = keccak256("METRICS_ROLE");
    bytes32 public constant ANALYZER_ROLE = keccak256("ANALYZER_ROLE");

    struct BatchMetrics {
        uint256 batchId;
        uint256 transactionCount;
        uint256 gasUsed;
        uint256 processingTime;
        uint256 confirmationTime;
        uint256 executionTime;
        uint256 timestamp;
    }

    struct SequencerMetric {
        uint256 totalBatches;
        uint256 totalTransactions;
        uint256 avgTransactionsPerBatch;
        uint256 avgProcessingTime;
        uint256 avgConfirmationTime;
        uint256 totalGasUsed;
        uint256 successRate;
        uint256 lastUpdateTime;
    }

    struct TimeWindowMetrics {
        uint256 startTime;
        uint256 endTime;
        uint256 batchCount;
        uint256 txCount;
        uint256 avgTxPerBatch;
        uint256 totalGas;
        uint256 successCount;
        uint256 failureCount;
    }

    // State variables
    mapping(address => SequencerMetric) public sequencerMetrics;
    mapping(uint256 => BatchMetrics) public batchMetrics;
    mapping(uint256 => TimeWindowMetrics) public hourlyMetrics;
    mapping(uint256 => TimeWindowMetrics) public dailyMetrics;

    uint256 public totalBatches;
    uint256 public totalTransactions;
    uint256 public currentHour;
    uint256 public currentDay;

    // Events
    event BatchMetricsRecorded(
        uint256 indexed batchId,
        uint256 txCount,
        uint256 gasUsed,
        uint256 processingTime
    );

    event MetricsUpdated(
        address indexed sequencer,
        uint256 totalBatches,
        uint256 avgTxPerBatch,
        uint256 timestamp
    );

    event TimeWindowUpdated(
        uint256 indexed windowId,
        bool isHourly,
        uint256 txCount,
        uint256 successRate
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(METRICS_ROLE, msg.sender);
        _grantRole(ANALYZER_ROLE, msg.sender);
        
        currentHour = block.timestamp / 1 hours;
        currentDay = block.timestamp / 1 days;
    }

    /**
     * @notice Record metrics for a processed batch
     * @param batchId Batch identifier
     * @param txCount Number of transactions
     * @param gasUsed Gas consumed
     * @param processingTime Time taken to process
     * @param confirmationTime Time taken for confirmations
     * @param executionTime Time taken for execution
     */
    function recordBatchMetrics(
        uint256 batchId,
        uint256 txCount,
        uint256 gasUsed,
        uint256 processingTime,
        uint256 confirmationTime,
        uint256 executionTime
    ) public onlyRole(METRICS_ROLE)
        whenNotPaused
    {
        BatchMetrics memory metrics = BatchMetrics({
            batchId: batchId,
            transactionCount: txCount,
            gasUsed: gasUsed,
            processingTime: processingTime,
            confirmationTime: confirmationTime,
            executionTime: executionTime,
            timestamp: block.timestamp
        });
        
        batchMetrics[batchId] = metrics;
        totalBatches++;
        totalTransactions += txCount;
        
        updateTimeWindows(txCount, gasUsed, processingTime, true);
        
        emit BatchMetricsRecorded(
            batchId,
            txCount,
            gasUsed,
            processingTime
        );
    }

    /**
     * @notice Update sequencer-specific metrics
     * @param sequencer Sequencer address
     * @param batches Number of batches processed
     * @param txCount Total transactions
     * @param gasUsed Total gas used
     * @param successCount Number of successful transactions
     */
    function updateSequencerMetrics(
        address sequencer,
        uint256 batches,
        uint256 txCount,
        uint256 gasUsed,
        uint256 successCount
    ) public onlyRole(METRICS_ROLE)
        whenNotPaused
    {
        SequencerMetric storage metrics = sequencerMetrics[sequencer];
        
        metrics.totalBatches += batches;
        metrics.totalTransactions += txCount;
        metrics.totalGasUsed += gasUsed;
        metrics.successRate = (successCount * 100) / txCount;
        
        if (batches > 0) {
            metrics.avgTransactionsPerBatch = txCount / batches;
        }
        
        metrics.lastUpdateTime = block.timestamp;
        
        emit MetricsUpdated(
            sequencer,
            metrics.totalBatches,
            metrics.avgTransactionsPerBatch,
            block.timestamp
        );
    }

    /**
     * @notice Update time-based metrics windows
     * @param txCount Transaction count
     * @param gasUsed Gas used
     * @param processingTime Processing time
     * @param success Whether the batch was successful
     */
    function updateTimeWindows(
        uint256 txCount,
        uint256 gasUsed,
        uint256 processingTime,
        bool success
    )
        internal
    {
        uint256 currentHourId = block.timestamp / 1 hours;
        uint256 currentDayId = block.timestamp / 1 days;
        
        // Update hourly metrics
        if (currentHourId > currentHour) {
            currentHour = currentHourId;
        }
        
        TimeWindowMetrics storage hourly = hourlyMetrics[currentHourId];
        if (hourly.startTime == 0) {
            hourly.startTime = currentHourId * 1 hours;
            hourly.endTime = hourly.startTime + 1 hours;
        }
        
        updateTimeWindow(hourly, txCount, gasUsed, success);
        
        // Update daily metrics
        if (currentDayId > currentDay) {
            currentDay = currentDayId;
        }
        
        TimeWindowMetrics storage daily = dailyMetrics[currentDayId];
        if (daily.startTime == 0) {
            daily.startTime = currentDayId * 1 days;
            daily.endTime = daily.startTime + 1 days;
        }
        
        updateTimeWindow(daily, txCount, gasUsed, success);
    }

    /**
     * @notice Update a specific time window
     * @param window Time window to update
     * @param txCount Transaction count
     * @param gasUsed Gas used
     * @param success Whether the batch was successful
     */
    function updateTimeWindow(
        TimeWindowMetrics storage window,
        uint256 txCount,
        uint256 gasUsed,
        bool success
    )
        internal
    {
        window.batchCount++;
        window.txCount += txCount;
        window.totalGas += gasUsed;
        
        if (success) {
            window.successCount++;
        } else {
            window.failureCount++;
        }
        
        if (window.batchCount > 0) {
            window.avgTxPerBatch = window.txCount / window.batchCount;
        }
    }

    /**
     * @notice Get metrics for a specific batch
     * @param batchId Batch identifier
     */
    function getBatchMetrics(uint256 batchId) public view
        returns (BatchMetrics memory)
    {
        return batchMetrics[batchId];
    }

    /**
     * @notice Get metrics for a specific sequencer
     * @param sequencer Sequencer address
     */
    function getSequencerMetrics(address sequencer) public view
        returns (SequencerMetric memory)
    {
        return sequencerMetrics[sequencer];
    }

    /**
     * @notice Get metrics for a specific hour
     * @param hour Hour timestamp (in hours)
     */
    function getHourlyMetrics(uint256 hour) public view
        returns (TimeWindowMetrics memory)
    {
        return hourlyMetrics[hour];
    }

    /**
     * @notice Get metrics for a specific day
     * @param day Day timestamp (in days)
     */
    function getDailyMetrics(uint256 day) public view
        returns (TimeWindowMetrics memory)
    {
        return dailyMetrics[day];
    }

    /**
     * @notice Get system-wide performance indicators
     */
    function getSystemMetrics() public view
        returns (
            uint256 _totalBatches,
            uint256 _totalTransactions,
            uint256 _avgTxPerBatch,
            uint256 _currentHourTx,
            uint256 _currentDayTx
        )
    {
        TimeWindowMetrics storage hourly = hourlyMetrics[currentHour];
        TimeWindowMetrics storage daily = dailyMetrics[currentDay];
        
        return (
            totalBatches,
            totalTransactions,
            totalTransactions / (totalBatches > 0 ? totalBatches : 1),
            hourly.txCount,
            daily.txCount
        );
    }

    // Admin functions
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}