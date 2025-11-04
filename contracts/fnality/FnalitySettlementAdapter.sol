// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FnalitySettlementAdapter
 * @notice Adapter for Fnality wholesale settlement using tokenized CB money
 * @dev Supports USC (Utility Settlement Coin), GBPf, EURf, etc.
 */
contract FnalitySettlementAdapter is Ownable {
    
    struct FnalityToken {
        address tokenAddress;
        string currency;                // USD, GBP, EUR, etc.
        address centralBank;
        bool isActive;
    }
    
    struct FnalityPvP {
        bytes32 settlementId;
        address tokenA;                 // First Fnality token
        address tokenB;                 // Second Fnality token
        uint256 amountA;
        uint256 amountB;
        address partyA;
        address partyB;
        bool isAtomic;                  // Atomic PvP settlement
        bool isCompleted;
        uint256 timestamp;
    }
    
    mapping(address => FnalityToken) public fnalityTokens;
    mapping(bytes32 => FnalityPvP) public pvpSettlements;
    
    event FnalityTokenRegistered(address indexed token, string currency);
    event FnalityPvPInitiated(bytes32 indexed settlementId);
    event FnalityPvPCompleted(bytes32 indexed settlementId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Register a Fnality token (USC, GBPf, etc.)
     */
    function registerFnalityToken(
        address tokenAddress,
        string memory currency,
        address centralBank
    ) external onlyOwner {
        fnalityTokens[tokenAddress] = FnalityToken({
            tokenAddress: tokenAddress,
            currency: currency,
            centralBank: centralBank,
            isActive: true
        });
        
        emit FnalityTokenRegistered(tokenAddress, currency);
    }
    
    /**
     * @notice Initiate atomic PvP settlement via Fnality
     */
    function initiateFnalityPvP(
        bytes32 settlementId,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address partyA,
        address partyB
    ) external returns (bool) {
        require(fnalityTokens[tokenA].isActive, "Token A not active");
        require(fnalityTokens[tokenB].isActive, "Token B not active");
        
        pvpSettlements[settlementId] = FnalityPvP({
            settlementId: settlementId,
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            partyA: partyA,
            partyB: partyB,
            isAtomic: true,
            isCompleted: false,
            timestamp: block.timestamp
        });
        
        emit FnalityPvPInitiated(settlementId);
        return true;
    }
    
    /**
     * @notice Complete Fnality PvP settlement (called by oracle/executor)
     */
    function completeFnalityPvP(bytes32 settlementId) external onlyOwner {
        FnalityPvP storage pvp = pvpSettlements[settlementId];
        require(!pvp.isCompleted, "Already completed");
        require(pvp.timestamp > 0, "Settlement not found");
        
        // Execute atomic PvP
        IERC20(pvp.tokenA).transferFrom(pvp.partyA, pvp.partyB, pvp.amountA);
        IERC20(pvp.tokenB).transferFrom(pvp.partyB, pvp.partyA, pvp.amountB);
        
        pvp.isCompleted = true;
        emit FnalityPvPCompleted(settlementId);
    }
    
    /**
     * @notice Deactivate a Fnality token
     */
    function deactivateFnalityToken(address tokenAddress) external onlyOwner {
        fnalityTokens[tokenAddress].isActive = false;
    }
    
    /**
     * @notice Get Fnality token information
     */
    function getFnalityToken(address tokenAddress) external view returns (FnalityToken memory) {
        return fnalityTokens[tokenAddress];
    }
    
    /**
     * @notice Get PvP settlement information
     */
    function getPvPSettlement(bytes32 settlementId) external view returns (FnalityPvP memory) {
        return pvpSettlements[settlementId];
    }
}
