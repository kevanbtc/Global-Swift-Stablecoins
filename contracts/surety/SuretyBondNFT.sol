// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";

/// @title SuretyBondNFT
/// @notice ERC721 for surety bonds with penal sum, parties, and claims lifecycle
contract SuretyBondNFT is ERC721, AccessControl, Pausable {
    enum ClaimStatus { None, Filed, Approved, Rejected, Paid }

    struct Bond {
        address principal;  // party performing obligation
        address obligee;   // beneficiary
        uint256 penalSum;  // maximum payout
        uint64  issueDate; // unix
        uint64  expiry;    // unix
        bool    active;    // false if released/defaulted
    }

    struct Claim {
        uint256 amount;
        uint64  filedAt;
        string  evidence; // IPFS CID or similar
        ClaimStatus status;
    }

    uint256 private _id;
    mapping(uint256 => Bond) public bonds;
    mapping(uint256 => Claim[]) public claims;

    event BondIssued(uint256 indexed tokenId, address principal, address obligee, uint256 penalSum);
    event BondStatusChanged(uint256 indexed tokenId, bool active);
    event ClaimFiled(uint256 indexed tokenId, uint256 claimIdx, uint256 amount);
    event ClaimStatusChanged(uint256 indexed tokenId, uint256 claimIdx, ClaimStatus status);

    constructor(address admin) ERC721("Surety Bond", "SURETY") {
        _grantRole(PolicyRoles.ROLE_ADMIN, admin);
        _grantRole(PolicyRoles.ROLE_ISSUER, admin);
        _grantRole(PolicyRoles.ROLE_GUARDIAN, admin);
    }

    function pause() public onlyRole(PolicyRoles.ROLE_GUARDIAN) { _pause(); }
    function unpause() public onlyRole(PolicyRoles.ROLE_GUARDIAN) { _unpause(); }

    function issue(
        address principal,
        address obligee,
        uint256 penalSum,
        uint64 issueDate,
        uint64 expiry
    ) public onlyRole(PolicyRoles.ROLE_ISSUER) whenNotPaused returns (uint256 tokenId) {
        require(issueDate < expiry, "bad dates");
        tokenId = ++_id;
        bonds[tokenId] = Bond(principal, obligee, penalSum, issueDate, expiry, true);
        _safeMint(principal, tokenId); // to principal (the one performing obligation)
        emit BondIssued(tokenId, principal, obligee, penalSum);
    }

    function fileClaim(
        uint256 tokenId,
        uint256 amount,
        string calldata evidence
    ) public whenNotPaused {
        Bond storage bond = bonds[tokenId];
        require(msg.sender == bond.obligee, "not obligee");
        require(bond.active, "not active");
        require(block.timestamp <= bond.expiry, "expired");
        require(amount <= bond.penalSum, "exceeds penal sum");

        uint256 idx = claims[tokenId].length;
        claims[tokenId].push(Claim(amount, uint64(block.timestamp), evidence, ClaimStatus.Filed));
        emit ClaimFiled(tokenId, idx, amount);
    }

    function setClaimStatus(uint256 tokenId, uint256 claimIdx, ClaimStatus status) public onlyRole(PolicyRoles.ROLE_ADMIN) whenNotPaused 
    {
        require(bonds[tokenId].active, "not active");
        Claim storage claim = claims[tokenId][claimIdx];
        require(claim.status == ClaimStatus.Filed, "not filed");
        claim.status = status;
        emit ClaimStatusChanged(tokenId, claimIdx, status);
    }

    function setBondStatus(uint256 tokenId, bool active) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        bonds[tokenId].active = active;
        emit BondStatusChanged(tokenId, active);
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
