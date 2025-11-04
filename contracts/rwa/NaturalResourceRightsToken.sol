// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title NaturalResourceRightsToken
 * @notice NFT representing natural resource rights (water, minerals, land)
 * @dev Each NFT is a unique deed/right with legal enforceability
 */
contract NaturalResourceRightsToken is ERC721, AccessControl {
    
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    
    enum ResourceType { WATER, MINERAL, LAND, TIMBER, OIL_GAS }
    
    struct ResourceRight {
        uint256 tokenId;
        ResourceType resourceType;
        string jurisdiction;            // Legal jurisdiction
        string legalDescription;        // Metes and bounds description
        bytes32 deedHash;              // IPFS hash of legal deed
        bytes32 surveyHash;            // IPFS hash of survey
        uint256 acreage;               // Size in acres
        uint256 annualYield;           // Estimated annual yield (units vary)
        address registeredOwner;
        uint256 registrationDate;
        bool isEncumbered;             // Has liens/mortgages
    }
    
    struct WaterRight {
        uint256 tokenId;
        uint256 annualAllocation;      // Acre-feet per year
        string waterSource;            // River, aquifer, etc.
        uint256 priority;              // Priority date (earlier = senior)
        bool isSenior;                 // Senior vs junior right
    }
    
    struct MineralRight {
        uint256 tokenId;
        string[] minerals;             // Gold, silver, copper, etc.
        uint256 royaltyRate;           // Percentage (scaled by 100)
        bool includesSubsurface;       // Full subsurface rights
    }
    
    mapping(uint256 => ResourceRight) public resourceRights;
    mapping(uint256 => WaterRight) public waterRights;
    mapping(uint256 => MineralRight) public mineralRights;
    
    uint256 private _nextTokenId;
    
    event ResourceRightRegistered(uint256 indexed tokenId, ResourceType resourceType, string jurisdiction);
    event WaterRightAllocated(uint256 indexed tokenId, uint256 allocation);
    event MineralRightGranted(uint256 indexed tokenId, string[] minerals);
    
    constructor() ERC721("Natural Resource Rights", "NRR") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @notice Register a new natural resource right
     */
    function registerResourceRight(
        ResourceType resourceType,
        string memory jurisdiction,
        string memory legalDescription,
        bytes32 deedHash,
        bytes32 surveyHash,
        uint256 acreage,
        address owner
    ) external onlyRole(REGISTRAR_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        
        resourceRights[tokenId] = ResourceRight({
            tokenId: tokenId,
            resourceType: resourceType,
            jurisdiction: jurisdiction,
            legalDescription: legalDescription,
            deedHash: deedHash,
            surveyHash: surveyHash,
            acreage: acreage,
            annualYield: 0,
            registeredOwner: owner,
            registrationDate: block.timestamp,
            isEncumbered: false
        });
        
        _safeMint(owner, tokenId);
        
        emit ResourceRightRegistered(tokenId, resourceType, jurisdiction);
        return tokenId;
    }
    
    /**
     * @notice Allocate water rights to a token
     */
    function allocateWaterRight(
        uint256 tokenId,
        uint256 annualAllocation,
        string memory waterSource,
        uint256 priority,
        bool isSenior
    ) external onlyRole(REGISTRAR_ROLE) {
        require(resourceRights[tokenId].resourceType == ResourceType.WATER, "Not a water right");
        
        waterRights[tokenId] = WaterRight({
            tokenId: tokenId,
            annualAllocation: annualAllocation,
            waterSource: waterSource,
            priority: priority,
            isSenior: isSenior
        });
        
        emit WaterRightAllocated(tokenId, annualAllocation);
    }
    
    /**
     * @notice Grant mineral rights to a token
     */
    function grantMineralRight(
        uint256 tokenId,
        string[] memory minerals,
        uint256 royaltyRate,
        bool includesSubsurface
    ) external onlyRole(REGISTRAR_ROLE) {
        require(resourceRights[tokenId].resourceType == ResourceType.MINERAL, "Not a mineral right");
        
        mineralRights[tokenId] = MineralRight({
            tokenId: tokenId,
            minerals: minerals,
            royaltyRate: royaltyRate,
            includesSubsurface: includesSubsurface
        });
        
        emit MineralRightGranted(tokenId, minerals);
    }
    
    /**
     * @notice Update encumbrance status
     */
    function setEncumbrance(uint256 tokenId, bool encumbered) external onlyRole(REGISTRAR_ROLE) {
        resourceRights[tokenId].isEncumbered = encumbered;
    }
    
    /**
     * @notice Get resource right information
     */
    function getResourceRight(uint256 tokenId) external view returns (ResourceRight memory) {
        return resourceRights[tokenId];
    }
    
    /**
     * @notice Get water right information
     */
    function getWaterRight(uint256 tokenId) external view returns (WaterRight memory) {
        return waterRights[tokenId];
    }
    
    /**
     * @notice Get mineral right information
     */
    function getMineralRight(uint256 tokenId) external view returns (MineralRight memory) {
        return mineralRights[tokenId];
    }
    
    /**
     * @notice Override transfer to check encumbrance
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        // Check if resource is encumbered
        require(!resourceRights[tokenId].isEncumbered, "Resource is encumbered");

        // Update registered owner
        resourceRights[tokenId].registeredOwner = to;
    }

    /**
     * @notice Override supportsInterface to resolve multiple inheritance
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
