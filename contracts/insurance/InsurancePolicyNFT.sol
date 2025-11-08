// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";

/// @title InsurancePolicyNFT
/// @notice ERC721 for insurance policies with coverage/premium, claims management
contract InsurancePolicyNFT is ERC721, AccessControl, Pausable {
    enum ClaimStatus { None, Filed, InReview, Approved, Rejected, Paid }

    struct Policy {
        uint256 coverage;     // maximum coverage amount
        uint256 premium;      // annual premium
        uint64  startDate;    // unix
        uint64  endDate;      // unix
        bool    active;       // false if cancelled/lapsed
    }

    struct Claim {
        uint256 amount;
        uint64  filedAt;
        string  evidence;      // IPFS CID or similar
        ClaimStatus status;
        uint256 paidAmount;    // if approved & paid
    }

    uint256 private _id;
    mapping(uint256 => Policy) public policies;
    mapping(uint256 => Claim[]) public claims;
    mapping(uint256 => uint256) public totalClaimed; // running sum of paid claims per policy

    event PolicyIssued(uint256 indexed tokenId, uint256 coverage, uint256 premium);
    event PolicyStatusChanged(uint256 indexed tokenId, bool active);
    event ClaimFiled(uint256 indexed tokenId, uint256 claimIdx, uint256 amount);
    event ClaimStatusChanged(uint256 indexed tokenId, uint256 claimIdx, ClaimStatus status);
    event ClaimPaid(uint256 indexed tokenId, uint256 claimIdx, uint256 amount);

    constructor(address admin) ERC721("Insurance Policy", "INSURE") {
        _grantRole(PolicyRoles.ROLE_ADMIN, admin);
        _grantRole(PolicyRoles.ROLE_ISSUER, admin);
        _grantRole(PolicyRoles.ROLE_GUARDIAN, admin);
    }

    function pause() public onlyRole(PolicyRoles.ROLE_GUARDIAN) { _pause(); }
    function unpause() public onlyRole(PolicyRoles.ROLE_GUARDIAN) { _unpause(); }

    function issue(
        address to,
        uint256 coverage,
        uint256 premium,
        uint64 startDate,
        uint64 endDate
    ) public onlyRole(PolicyRoles.ROLE_ISSUER) whenNotPaused returns (uint256 tokenId) {
        require(startDate < endDate, "bad dates");
        tokenId = ++_id;
        policies[tokenId] = Policy(coverage, premium, startDate, endDate, true);
        _safeMint(to, tokenId);
        emit PolicyIssued(tokenId, coverage, premium);
    }

    function fileClaim(
        uint256 tokenId,
        uint256 amount,
        string calldata evidence
    ) public whenNotPaused {
        // ensure token exists and get owner
        address owner;
        try this.ownerOf(tokenId) returns (address o) { owner = o; } catch { revert("no policy"); }

        // only policy owner or approved may file a claim
        require(
            owner == msg.sender || getApproved(tokenId) == msg.sender || isApprovedForAll(owner, msg.sender),
            "not policy holder"
        );
        require(amount > 0, "invalid amount");

        Policy storage policy = policies[tokenId];
        require(policy.active, "not active");
        require(block.timestamp >= policy.startDate && block.timestamp <= policy.endDate, "not in effect");
        require(amount + totalClaimed[tokenId] <= policy.coverage, "exceeds coverage");

        uint256 idx = claims[tokenId].length;
        claims[tokenId].push(Claim(amount, uint64(block.timestamp), evidence, ClaimStatus.Filed, 0));
        emit ClaimFiled(tokenId, idx, amount);
    }

    function updateClaimStatus(
        uint256 tokenId,
        uint256 claimIdx,
        ClaimStatus status,
        uint256 paidAmount
    ) public onlyRole(PolicyRoles.ROLE_ADMIN) whenNotPaused {
        Policy storage policy = policies[tokenId];
        require(policy.active, "not active");
        require(claimIdx < claims[tokenId].length, "bad claim index");

        Claim storage claim = claims[tokenId][claimIdx];
        require(claim.status != ClaimStatus.Paid, "already paid");
        
        if (status == ClaimStatus.Paid) {
            require(paidAmount > 0 && paidAmount <= claim.amount, "invalid amount");
            require(paidAmount + totalClaimed[tokenId] <= policy.coverage, "exceeds coverage");
            claim.paidAmount = paidAmount;
            totalClaimed[tokenId] += paidAmount;
            emit ClaimPaid(tokenId, claimIdx, paidAmount);
        }
        
        claim.status = status;
        emit ClaimStatusChanged(tokenId, claimIdx, status);
    }

    function setPolicyStatus(uint256 tokenId, bool active) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        policies[tokenId].active = active;
        emit PolicyStatusChanged(tokenId, active);
    }

    function availableCoverage(uint256 tokenId) public view returns (uint256) {
        return policies[tokenId].coverage - totalClaimed[tokenId];
    }

    // OZ v5: resolve multiple inheritance for ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
