// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title GoldRWAToken
 * @notice Tokenized in-ground gold reserves
 * @dev Each token represents 1 troy ounce of proven/probable gold reserves
 */
contract GoldRWAToken is ERC20, AccessControl {
    
    bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
    
    struct GoldReserve {
        string mineLocation;            // GPS coordinates or jurisdiction
        uint256 provenReserves;         // Troy ounces (proven)
        uint256 probableReserves;       // Troy ounces (probable)
        bytes32 geologicalSurveyHash;   // IPFS hash of survey
        bytes32 miningRightsHash;       // IPFS hash of rights deed
        address miningCompany;
        uint256 lastAuditTimestamp;
        bool isActive;
    }
    
    struct GoldAudit {
        bytes32 reserveId;
        uint256 auditedAmount;          // Troy ounces verified
        address auditor;
        bytes32 reportHash;             // IPFS hash of audit report
        uint256 timestamp;
    }
    
    mapping(bytes32 => GoldReserve) public reserves;
    mapping(bytes32 => GoldAudit[]) public audits;
    
    event ReserveRegistered(bytes32 indexed reserveId, string location, uint256 amount);
    event ReserveAudited(bytes32 indexed reserveId, uint256 amount, address auditor);
    event GoldMinted(address indexed to, uint256 amount, bytes32 reserveId);
    
    constructor() ERC20("Gold RWA Token", "GRWA") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @notice Register new in-ground gold reserve
     */
    function registerReserve(
        bytes32 reserveId,
        string memory mineLocation,
        uint256 provenReserves,
        uint256 probableReserves,
        bytes32 geologicalSurveyHash,
        bytes32 miningRightsHash,
        address miningCompany
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        reserves[reserveId] = GoldReserve({
            mineLocation: mineLocation,
            provenReserves: provenReserves,
            probableReserves: probableReserves,
            geologicalSurveyHash: geologicalSurveyHash,
            miningRightsHash: miningRightsHash,
            miningCompany: miningCompany,
            lastAuditTimestamp: block.timestamp,
            isActive: true
        });
        
        emit ReserveRegistered(reserveId, mineLocation, provenReserves);
    }
    
    /**
     * @notice Audit gold reserve (by certified auditor)
     */
    function auditReserve(
        bytes32 reserveId,
        uint256 auditedAmount,
        bytes32 reportHash
    ) public onlyRole(AUDITOR_ROLE) {
        require(reserves[reserveId].isActive, "Reserve not active");
        
        audits[reserveId].push(GoldAudit({
            reserveId: reserveId,
            auditedAmount: auditedAmount,
            auditor: msg.sender,
            reportHash: reportHash,
            timestamp: block.timestamp
        }));
        
        reserves[reserveId].lastAuditTimestamp = block.timestamp;
        
        emit ReserveAudited(reserveId, auditedAmount, msg.sender);
    }
    
    /**
     * @notice Mint tokens against audited reserves
     */
    function mintAgainstReserve(
        address to,
        uint256 amount,
        bytes32 reserveId
    ) public onlyRole(MINER_ROLE) {
        require(reserves[reserveId].isActive, "Reserve not active");
        require(
            reserves[reserveId].provenReserves >= totalSupply() + amount,
            "Exceeds proven reserves"
        );
        
        _mint(to, amount);
        emit GoldMinted(to, amount, reserveId);
    }
    
    /**
     * @notice Get reserve information
     */
    function getReserve(bytes32 reserveId) public view returns (GoldReserve memory) {
        return reserves[reserveId];
    }
    
    /**
     * @notice Get audit history for a reserve
     */
    function getAuditHistory(bytes32 reserveId, uint256 index) public view returns (GoldAudit memory) {
        return audits[reserveId][index];
    }
    
    /**
     * @notice Get number of audits for a reserve
     */
    function getAuditCount(bytes32 reserveId) public view returns (uint256) {
        return audits[reserveId].length;
    }
}
