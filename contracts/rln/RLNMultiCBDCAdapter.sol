// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RLNMultiCBDCAdapter
 * @notice Adapter for Regulated Liability Network (RLN) multi-CBDC settlement
 * @dev Enables atomic FX settlement across multiple CBDCs
 */
contract RLNMultiCBDCAdapter is Ownable {
    
    struct CBDCToken {
        address tokenAddress;
        string jurisdiction;            // US, EU, UK, SG, etc.
        string currencyCode;            // USD, EUR, GBP, SGD
        address centralBank;            // Issuing central bank
        bool isActive;
    }
    
    struct RLNSettlement {
        bytes32 settlementId;
        address[] cbdcTokens;           // Multiple CBDCs
        uint256[] amounts;              // Amounts per CBDC
        address[] participants;         // Settlement participants
        uint256 fxRate;                 // Agreed FX rate (scaled by 1e18)
        bool isCompleted;
        uint256 timestamp;
    }
    
    mapping(address => CBDCToken) public cbdcs;
    mapping(bytes32 => RLNSettlement) public settlements;
    
    event CBDCRegistered(address indexed token, string jurisdiction, string currency);
    event RLNSettlementInitiated(bytes32 indexed settlementId);
    event RLNSettlementCompleted(bytes32 indexed settlementId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Register a CBDC token in RLN
     */
    function registerCBDC(
        address tokenAddress,
        string memory jurisdiction,
        string memory currencyCode,
        address centralBank
    ) public onlyOwner {
        cbdcs[tokenAddress] = CBDCToken({
            tokenAddress: tokenAddress,
            jurisdiction: jurisdiction,
            currencyCode: currencyCode,
            centralBank: centralBank,
            isActive: true
        });
        
        emit CBDCRegistered(tokenAddress, jurisdiction, currencyCode);
    }
    
    /**
     * @notice Initiate atomic multi-CBDC FX settlement
     */
    function initiateRLNSettlement(
        bytes32 settlementId,
        address[] memory cbdcTokens,
        uint256[] memory amounts,
        address[] memory participants,
        uint256 fxRate
    ) public returns (bool) {
        require(cbdcTokens.length == amounts.length, "Length mismatch");
        require(cbdcTokens.length >= 2, "Need at least 2 CBDCs");
        
        settlements[settlementId] = RLNSettlement({
            settlementId: settlementId,
            cbdcTokens: cbdcTokens,
            amounts: amounts,
            participants: participants,
            fxRate: fxRate,
            isCompleted: false,
            timestamp: block.timestamp
        });
        
        emit RLNSettlementInitiated(settlementId);
        return true;
    }
    
    /**
     * @notice Complete RLN settlement (called by oracle/executor)
     */
    function completeRLNSettlement(bytes32 settlementId) public onlyOwner {
        RLNSettlement storage settlement = settlements[settlementId];
        require(!settlement.isCompleted, "Already completed");
        require(settlement.timestamp > 0, "Settlement not found");
        
        settlement.isCompleted = true;
        emit RLNSettlementCompleted(settlementId);
    }
    
    /**
     * @notice Deactivate a CBDC token
     */
    function deactivateCBDC(address tokenAddress) public onlyOwner {
        cbdcs[tokenAddress].isActive = false;
    }
    
    /**
     * @notice Get CBDC information
     */
    function getCBDC(address tokenAddress) public view returns (CBDCToken memory) {
        return cbdcs[tokenAddress];
    }
    
    /**
     * @notice Get settlement information
     */
    function getSettlement(bytes32 settlementId) public view returns (RLNSettlement memory) {
        return settlements[settlementId];
    }
}
