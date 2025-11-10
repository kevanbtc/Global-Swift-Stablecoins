// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";

/// @title SBLC721
/// @notice ERC721 for Standby Letters of Credit with issuer LEI, beneficiary, face value, expiry
contract SBLC721 is ERC721, AccessControl, Pausable {
    enum Status { Active, Drawn, Expired, Cancelled }

    struct SBLC {
        bytes32 issuerLEI;  // ISO 17442 Legal Entity Identifier
        address beneficiary;
        uint256 faceValue;
        uint64  issueDate;
        uint64  expiry;
        Status  status;
    }

    uint256 private _id;
    mapping(uint256 => SBLC) public letters;

    event LetterIssued(uint256 indexed tokenId, bytes32 issuerLEI, address beneficiary, uint256 faceValue);
    event LetterDrawn(uint256 indexed tokenId);
    event LetterExpired(uint256 indexed tokenId);
    event LetterCancelled(uint256 indexed tokenId);

    constructor(address admin) ERC721("Standby Letter of Credit", "SBLC") {
        _grantRole(PolicyRoles.ROLE_ADMIN, admin);
        _grantRole(PolicyRoles.ROLE_ISSUER, admin);
        _grantRole(PolicyRoles.ROLE_GUARDIAN, admin);
    }

    function pause() public onlyRole(PolicyRoles.ROLE_GUARDIAN) { _pause(); }
    function unpause() public onlyRole(PolicyRoles.ROLE_GUARDIAN) { _unpause(); }

    function issue(
        bytes32 issuerLEI,
        address beneficiary,
        uint256 faceValue,
        uint64 issueDate,
        uint64 expiry
    ) public onlyRole(PolicyRoles.ROLE_ISSUER) whenNotPaused returns (uint256 tokenId) {
        require(issueDate < expiry, "bad dates");
        tokenId = ++_id;
        letters[tokenId] = SBLC(issuerLEI, beneficiary, faceValue, issueDate, expiry, Status.Active);
        _safeMint(beneficiary, tokenId); // to beneficiary
        emit LetterIssued(tokenId, issuerLEI, beneficiary, faceValue);
    }

    function draw(uint256 tokenId) public onlyRole(PolicyRoles.ROLE_ADMIN) whenNotPaused {
        SBLC storage letter = letters[tokenId];
        require(letter.status == Status.Active, "not active");
        require(block.timestamp <= letter.expiry, "expired");
        letter.status = Status.Drawn;
        emit LetterDrawn(tokenId);
    }

    function expire(uint256 tokenId) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        SBLC storage letter = letters[tokenId];
        require(letter.status == Status.Active, "not active");
        require(block.timestamp > letter.expiry, "not expired");
        letter.status = Status.Expired;
        emit LetterExpired(tokenId);
    }

    function cancel(uint256 tokenId) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        SBLC storage letter = letters[tokenId];
        require(letter.status == Status.Active, "not active");
        letter.status = Status.Cancelled;
        emit LetterCancelled(tokenId);
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
