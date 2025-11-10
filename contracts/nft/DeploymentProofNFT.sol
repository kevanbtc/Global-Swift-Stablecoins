// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DeploymentProofNFT
 * @notice NFT contract that proves ownership and deployment of contracts on Unykorn L1
 * @dev Each deployed contract gets an NFT that serves as immutable proof of deployment
 */
contract DeploymentProofNFT is ERC721, ERC721URIStorage, AccessControl {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    uint256 private _tokenIdCounter;

    struct ContractProof {
        address contractAddress;
        address deployer;
        uint256 deployedAt;
        string contractName;
        string version;
        bytes32 codeHash;
        bool verified;
    }

    mapping(uint256 => ContractProof) public contractProofs;
    mapping(address => uint256[]) public deployerTokens;
    mapping(address => uint256) public contractToToken;

    event ContractDeployed(
        uint256 indexed tokenId,
        address indexed contractAddress,
        address indexed deployer,
        string contractName
    );

    event ContractVerified(uint256 indexed tokenId, address indexed verifier);

    constructor() ERC721("Unykorn Deployment Proof", "UDP") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEPLOYER_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
    }

    /**
     * @notice Mint an NFT proof for a deployed contract
     * @param contractAddress The address of the deployed contract
     * @param contractName Name of the contract
     * @param version Version of the contract
     * @param metadataURI IPFS URI for contract metadata
     */
    function mintDeploymentProof(
        address contractAddress,
        string memory contractName,
        string memory version,
        string memory metadataURI
    ) public onlyRole(DEPLOYER_ROLE) returns (uint256) {
        require(contractAddress != address(0), "Invalid contract address");
        require(contractToToken[contractAddress] == 0, "Contract already registered");

    // Start token IDs from 1 to avoid zero-value sentinel conflicts in mappings
    uint256 tokenId = ++_tokenIdCounter;


        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);

        contractProofs[tokenId] = ContractProof({
            contractAddress: contractAddress,
            deployer: msg.sender,
            deployedAt: block.timestamp,
            contractName: contractName,
            version: version,
            codeHash: contractAddress.codehash,
            verified: false
        });

        deployerTokens[msg.sender].push(tokenId);
        contractToToken[contractAddress] = tokenId;

        emit ContractDeployed(tokenId, contractAddress, msg.sender, contractName);

        return tokenId;
    }

    /**
     * @notice Verify a contract deployment (called by authorized verifiers)
     * @param tokenId The token ID of the deployment proof
     */
    function verifyDeployment(uint256 tokenId) public onlyRole(VERIFIER_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        contractProofs[tokenId].verified = true;
        emit ContractVerified(tokenId, msg.sender);
    }

    /**
     * @notice Get all tokens owned by a deployer
     * @param deployer Address of the deployer
     */
    function getDeployerTokens(address deployer) public view returns (uint256[] memory) {
        return deployerTokens[deployer];
    }

    /**
     * @notice Get contract proof details
     * @param tokenId Token ID
     */
    function getContractProof(uint256 tokenId) public view returns (ContractProof memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return contractProofs[tokenId];
    }

    /**
     * @notice Check if a contract is verified
     * @param contractAddress Contract address to check
     */
    function isContractVerified(address contractAddress) public view returns (bool) {
        uint256 tokenId = contractToToken[contractAddress];
        if (tokenId == 0) return false;
        return contractProofs[tokenId].verified;
    }

    // Override functions
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
