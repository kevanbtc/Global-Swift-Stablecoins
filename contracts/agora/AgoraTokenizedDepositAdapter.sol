// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AgoraTokenizedDepositAdapter
 * @notice Adapter for BIS Project Agorá tokenized deposits + CBDC
 * @dev Integrates with programmable ledger for unified liquidity
 */
contract AgoraTokenizedDepositAdapter is Ownable {
    
    struct TokenizedDeposit {
        address depositToken;           // Tokenized deposit contract
        address issuerBank;             // Issuing commercial bank
        string currency;                // ISO currency code
        bool isCBDC;                    // True if central bank money
        uint256 totalSupply;            // Total tokenized amount
        bytes32 agoraLedgerRef;        // Reference to Agorá ledger
    }
    
    struct AgoraSettlement {
        bytes32 settlementId;
        address[] depositTokens;        // Multiple tokenized deposits
        uint256[] amounts;              // Amounts per token
        address beneficiary;
        bool isAtomic;                  // Atomic multi-currency settlement
        uint256 timestamp;
        bytes32 swiftUETR;             // Link to SWIFT payment
    }
    
    mapping(address => TokenizedDeposit) public deposits;
    mapping(bytes32 => AgoraSettlement) public settlements;
    
    event DepositRegistered(address indexed token, address indexed bank, string currency);
    event AgoraSettlementInitiated(bytes32 indexed settlementId, address indexed beneficiary);
    event AgoraSettlementCompleted(bytes32 indexed settlementId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Register a tokenized deposit from Agorá
     */
    function registerTokenizedDeposit(
        address depositToken,
        address issuerBank,
        string memory currency,
        bool isCBDC,
        bytes32 agoraLedgerRef
    ) public onlyOwner {
        deposits[depositToken] = TokenizedDeposit({
            depositToken: depositToken,
            issuerBank: issuerBank,
            currency: currency,
            isCBDC: isCBDC,
            totalSupply: IERC20(depositToken).totalSupply(),
            agoraLedgerRef: agoraLedgerRef
        });
        
        emit DepositRegistered(depositToken, issuerBank, currency);
    }
    
    /**
     * @notice Initiate atomic multi-currency settlement via Agorá
     */
    function initiateAgoraSettlement(
        bytes32 settlementId,
        address[] memory depositTokens,
        uint256[] memory amounts,
        address beneficiary,
        bytes32 swiftUETR
    ) public returns (bool) {
        require(depositTokens.length == amounts.length, "Length mismatch");
        
        settlements[settlementId] = AgoraSettlement({
            settlementId: settlementId,
            depositTokens: depositTokens,
            amounts: amounts,
            beneficiary: beneficiary,
            isAtomic: true,
            timestamp: block.timestamp,
            swiftUETR: swiftUETR
        });
        
        emit AgoraSettlementInitiated(settlementId, beneficiary);
        return true;
    }
    
    /**
     * @notice Complete Agorá settlement (called by oracle/executor)
     */
    function completeAgoraSettlement(bytes32 settlementId) public onlyOwner {
        AgoraSettlement storage settlement = settlements[settlementId];
        require(settlement.timestamp > 0, "Settlement not found");
        
        // Transfer all tokenized deposits atomically
        for (uint i = 0; i < settlement.depositTokens.length; i++) {
            IERC20(settlement.depositTokens[i]).transfer(
                settlement.beneficiary,
                settlement.amounts[i]
            );
        }
        
        emit AgoraSettlementCompleted(settlementId);
    }
    
    /**
     * @notice Get deposit information
     */
    function getDeposit(address depositToken) public view returns (TokenizedDeposit memory) {
        return deposits[depositToken];
    }
    
    /**
     * @notice Get settlement information
     */
    function getSettlement(bytes32 settlementId) public view returns (AgoraSettlement memory) {
        return settlements[settlementId];
    }
}
