// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Types} from "../common/Types.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TravelRuleEngine
/// @notice SR-level FATF Travel Rule enforcement for VASPs (Virtual Asset Service Providers).
/// Enforces transaction reporting, originator/beneficiary information collection,
/// and cross-border compliance for stablecoins and RWA transfers.
contract TravelRuleEngine is Ownable, ReentrancyGuard {
    
    // Travel Rule threshold (e.g., $1000 USD equivalent)
    uint256 public travelRuleThreshold;
    
    // VASP registry
    struct VASP {
        string name;
        string jurisdiction;
        bytes32 licenseHash;
        bool active;
        uint256 registeredAt;
    }
    
    mapping(address => VASP) public vasps;
    mapping(address => bool) public isVASP;
    
    // Transaction reporting
    struct TravelRuleData {
        address originator;
        address beneficiary;
        string originatorInfo; // Name, address, account number
        string beneficiaryInfo;
        uint256 amount;
        string currency;
        uint256 timestamp;
        bool reported;
    }
    
    mapping(bytes32 => TravelRuleData) public travelRuleReports; // txHash => data
    
    // Events
    event VASPRegistered(address indexed vasp, string name, string jurisdiction);
    event VASPDeactivated(address indexed vasp);
    event TravelRuleThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event TravelRuleReported(bytes32 indexed txHash, address indexed originator, address indexed beneficiary, uint256 amount);
    event TravelRuleViolation(bytes32 indexed txHash, address indexed violator, string reason);
    
    constructor(uint256 _threshold) Ownable(msg.sender) {
        travelRuleThreshold = _threshold;
    }
    
    /// @notice Register VASP
    function registerVASP(
        address vasp,
        string calldata name,
        string calldata jurisdiction,
        bytes32 licenseHash
    ) public onlyOwner {
        require(vasp != address(0), "TRE: 0");
        require(!isVASP[vasp], "TRE: Already registered");
        
        vasps[vasp] = VASP({
            name: name,
            jurisdiction: jurisdiction,
            licenseHash: licenseHash,
            active: true,
            registeredAt: block.timestamp
        });
        
        isVASP[vasp] = true;
        emit VASPRegistered(vasp, name, jurisdiction);
    }
    
    /// @notice Deactivate VASP
    function deactivateVASP(address vasp) public onlyOwner {
        require(isVASP[vasp], "TRE: Not registered");
        vasps[vasp].active = false;
        emit VASPDeactivated(vasp);
    }
    
    /// @notice Update travel rule threshold
    function setTravelRuleThreshold(uint256 newThreshold) public onlyOwner {
        uint256 oldThreshold = travelRuleThreshold;
        travelRuleThreshold = newThreshold;
        emit TravelRuleThresholdUpdated(oldThreshold, newThreshold);
    }
    
    /// @notice Report transaction for travel rule compliance
    function reportTransaction(
        bytes32 txHash,
        address originator,
        address beneficiary,
        string calldata originatorInfo,
        string calldata beneficiaryInfo,
        uint256 amount,
        string calldata currency
    ) public nonReentrant {
        require(isVASP[msg.sender], "TRE: Not VASP");
        require(vasps[msg.sender].active, "TRE: VASP inactive");
        require(amount >= travelRuleThreshold, "TRE: Below threshold");
        require(travelRuleReports[txHash].timestamp == 0, "TRE: Already reported");
        
        travelRuleReports[txHash] = TravelRuleData({
            originator: originator,
            beneficiary: beneficiary,
            originatorInfo: originatorInfo,
            beneficiaryInfo: beneficiaryInfo,
            amount: amount,
            currency: currency,
            timestamp: block.timestamp,
            reported: true
        });
        
        emit TravelRuleReported(txHash, originator, beneficiary, amount);
    }
    
    /// @notice Check if transaction requires travel rule reporting
    function requiresTravelRule(uint256 amount) public view returns (bool) {
        return amount >= travelRuleThreshold;
    }
    
    /// @notice Verify transaction has been reported
    function isReported(bytes32 txHash) public view returns (bool) {
        return travelRuleReports[txHash].reported;
    }
    
    /// @notice Get travel rule data for transaction
    function getTravelRuleData(bytes32 txHash) public view returns (TravelRuleData memory) {
        return travelRuleReports[txHash];
    }
    
    /// @notice Enforce travel rule compliance (called by rails/routers)
    function enforceTravelRule(
        bytes32 txHash,
        address originator,
        address beneficiary,
        uint256 amount
    ) public view returns (bool compliant, string memory reason) {
        // Check if amount requires reporting
        if (amount < travelRuleThreshold) {
            return (true, "Below threshold");
        }
        
        // Check if transaction has been reported
        if (!travelRuleReports[txHash].reported) {
            return (false, "Travel rule not reported");
        }
        
        // Verify originator and beneficiary match
        TravelRuleData memory data = travelRuleReports[txHash];
        if (data.originator != originator || data.beneficiary != beneficiary) {
            return (false, "Originator/beneficiary mismatch");
        }
        
        return (true, "Compliant");
    }
}
