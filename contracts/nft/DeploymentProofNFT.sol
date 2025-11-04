// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "lib/openzeppelin-contracts/contracts/utils/Counters.sol";

/**
 * @title DeploymentProofNFT
 * @notice NFT contract that proves ownership and deployment of contracts on Unykorn L1
 * @dev Each deployed contract gets an NFT that serves as immutable proof of deployment
 */
contract DeploymentProofNFT is ERC721, ERC721URIStorage, AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    Counters.Counter private _tokenIdCounter;

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
    ) external onlyRole(DEPLOYER_ROLE) returns (uint256) {
        require(contractAddress != address(0), "Invalid contract address");
        require(contractToToken[contractAddress] == 0, "Contract already registered");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

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
    function verifyDeployment(uint256 tokenId) external onlyRole(VERIFIER_ROLE) {
        require(_exists(tokenId), "Token does not exist");
        contractProofs[tokenId].verified = true;
        emit ContractVerified(tokenId, msg.sender);
    }

    /**
     * @notice Get all tokens owned by a deployer
     * @param deployer Address of the deployer
     */
    function getDeployerTokens(address deployer) external view returns (uint256[] memory) {
        return deployerTokens[deployer];
    }

    /**
     * @notice Get contract proof details
     * @param tokenId Token ID
     */
    function getContractProof(uint256 tokenId) external view returns (ContractProof memory) {
        require(_exists(tokenId), "Token does not exist");
        return contractProofs[tokenId];
    }

    /**
     * @notice Check if a contract is verified
     * @param contractAddress Contract address to check
     */
    function isContractVerified(address contractAddress) external view returns (bool) {
        uint256 tokenId = contractToToken[contractAddress];
        if (tokenId == 0) return false;
        return contractProofs[tokenId].verified;
    }

    // Override functions
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
