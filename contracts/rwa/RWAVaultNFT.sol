// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PolicyRoles} from "../governance/PolicyRoles.sol";

/// @title RWAVaultNFT
/// @notice Title NFT representing a single RWA vault (document bundle, lien stack, appraisal hash)
contract RWAVaultNFT is ERC721URIStorage, AccessControl, Pausable {
    struct VaultMeta {
        bytes32 assetType;      // e.g. keccak256("GOLD_BAR") / "T_BILL" / "REAL_ESTATE"
        bytes32 jurisdiction;   // legal jurisdiction code
        bytes32 appraisalHash;  // hash of appraisal PDF/JSON on IPFS
        bytes32 lienStackHash;  // encoded waterfall/claims
        bool    locked;         // when true, disallow transfer except by admin (escrow or lien)
    }

    uint256 private _id;
    mapping(uint256 => VaultMeta) public vaults;

    event VaultMinted(uint256 indexed tokenId, address to, bytes32 assetType, bytes32 jurisdiction);
    event Locked(uint256 indexed tokenId, bool locked);
    event MetaUpdated(uint256 indexed tokenId, bytes32 appraisalHash, bytes32 lienStackHash);

    constructor(address admin) ERC721("RWA Vault", "RWA-VLT") {
        _grantRole(PolicyRoles.ROLE_ADMIN, admin);
        _grantRole(PolicyRoles.ROLE_ISSUER, admin);
        _grantRole(PolicyRoles.ROLE_GUARDIAN, admin);
    }

    function pause() public onlyRole(PolicyRoles.ROLE_GUARDIAN) { _pause(); }
    function unpause() public onlyRole(PolicyRoles.ROLE_GUARDIAN) { _unpause(); }

    function mint(
        address to,
        string calldata tokenURI_,
        bytes32 assetType,
        bytes32 jurisdiction,
        bytes32 appraisalHash,
        bytes32 lienStackHash
    ) public onlyRole(PolicyRoles.ROLE_ISSUER) whenNotPaused returns (uint256 tokenId) {
        tokenId = ++_id;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);
        vaults[tokenId] = VaultMeta(assetType, jurisdiction, appraisalHash, lienStackHash, false);
        emit VaultMinted(tokenId, to, assetType, jurisdiction);
    }

    function setLocked(uint256 tokenId, bool on) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        vaults[tokenId].locked = on; emit Locked(tokenId, on);
    }

    function updateMeta(uint256 tokenId, bytes32 appraisalHash, bytes32 lienStackHash) public onlyRole(PolicyRoles.ROLE_ADMIN) {
        vaults[tokenId].appraisalHash = appraisalHash;
        vaults[tokenId].lienStackHash = lienStackHash;
        emit MetaUpdated(tokenId, appraisalHash, lienStackHash);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        whenNotPaused
        returns (address previousOwner)
    {
        if (vaults[tokenId].locked) {
            require(hasRole(PolicyRoles.ROLE_ADMIN, msg.sender), "locked");
        }
        previousOwner = super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 iid)
        public view override(AccessControl, ERC721URIStorage) returns (bool)
    {
        return super.supportsInterface(iid);
    }
}
