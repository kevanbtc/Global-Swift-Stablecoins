// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title DecentralizedIdentity
 * @notice Self-sovereign identity management with verifiable credentials
 * @dev Implements DID (Decentralized Identifier) standard with ZKP verification
 */
contract DecentralizedIdentity is Ownable, ReentrancyGuard, Pausable {

    enum CredentialStatus {
        ACTIVE,
        REVOKED,
        SUSPENDED,
        EXPIRED
    }

    enum VerificationLevel {
        BASIC,      // Email/phone verification
        STANDARD,   // Government ID verification
        ENHANCED,   // Biometric + enhanced due diligence
        PREMIUM     // Institutional-grade verification
    }

    struct DIDDocument {
        string did;
        address controller;
        uint256 createdAt;
        uint256 updatedAt;
        bool isActive;
        string[] publicKeys;
        string[] serviceEndpoints;
        mapping(string => string) metadata;
    }

    struct VerifiableCredential {
        bytes32 credentialId;
        string did;
        string issuer;
        string subject;
        string credentialType;
        uint256 issuanceDate;
        uint256 expirationDate;
        CredentialStatus status;
        bytes32 credentialHash;
        string ipfsHash;        // IPFS hash of full credential
        VerificationLevel level;
        bytes32[] claims;       // Hashed claims
        bytes signature;
    }

    struct IdentityProfile {
        string did;
        address walletAddress;
        VerificationLevel verificationLevel;
        uint256 trustScore;     // 0-1000
        uint256 reputationScore; // 0-1000
        bool isAccreditedInvestor;
        bool isProfessionalEntity;
        string jurisdiction;
        string[] credentials;
        mapping(string => bytes32) attributes; // key => hash
        uint256 lastActivity;
        bool isFrozen;
    }

    struct ZKPProof {
        bytes32 proofId;
        string circuitId;
        bytes proofData;
        bytes32 publicInputsHash;
        address prover;
        uint256 timestamp;
        bool isValid;
        string verificationKey;
    }

    // Storage
    mapping(string => DIDDocument) public didDocuments;
    mapping(bytes32 => VerifiableCredential) public verifiableCredentials;
    mapping(string => IdentityProfile) public identityProfiles;
    mapping(bytes32 => ZKPProof) public zkpProofs;
    mapping(address => string) public addressToDID;
    mapping(string => address) public didToAddress;

    // Global parameters
    uint256 public credentialExpiration = 365 days;
    uint256 public maxCredentialsPerDID = 50;
    uint256 public minTrustScore = 500;        // Minimum for enhanced features
    uint256 public verificationCooldown = 30 days; // Time between re-verifications

    uint256 public totalDIDs;
    uint256 public totalCredentials;
    uint256 public totalZKPProofs;

    // Trusted issuers
    mapping(string => bool) public trustedIssuers;
    mapping(string => VerificationLevel) public issuerLevels;

    // Events
    event DIDCreated(string indexed did, address indexed controller);
    event DIDUpdated(string indexed did, address indexed controller);
    event CredentialIssued(bytes32 indexed credentialId, string indexed did, string issuer);
    event CredentialRevoked(bytes32 indexed credentialId, string reason);
    event IdentityVerified(string indexed did, VerificationLevel level);
    event ZKPVerified(bytes32 indexed proofId, string circuitId, bool isValid);
    event TrustScoreUpdated(string indexed did, uint256 newScore);

    modifier onlyDIDController(string memory _did) {
        require(didDocuments[_did].controller == msg.sender, "Not DID controller");
        _;
    }

    modifier validDID(string memory _did) {
        require(didDocuments[_did].isActive, "DID not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Create a new Decentralized Identifier (DID)
     */
    function createDID(string memory _method) external whenNotPaused returns (string memory) {
        require(bytes(addressToDID[msg.sender]).length == 0, "Address already has DID");

        // Generate DID using method-specific format
        string memory did = string(abi.encodePacked(
            "did:",
            _method,
            ":",
            Strings.toHexString(uint256(uint160(msg.sender)), 20),
            Strings.toString(block.timestamp)
        ));

        require(!didDocuments[did].isActive, "DID already exists");

        DIDDocument storage doc = didDocuments[did];
        doc.did = did;
        doc.controller = msg.sender;
        doc.createdAt = block.timestamp;
        doc.updatedAt = block.timestamp;
        doc.isActive = true;

        // Create identity profile
        IdentityProfile storage profile = identityProfiles[did];
        profile.did = did;
        profile.walletAddress = msg.sender;
        profile.verificationLevel = VerificationLevel.BASIC;
        profile.trustScore = 300; // Base trust score
        profile.reputationScore = 500; // Base reputation
        profile.lastActivity = block.timestamp;

        // Link address to DID
        addressToDID[msg.sender] = did;
        didToAddress[did] = msg.sender;

        totalDIDs++;

        emit DIDCreated(did, msg.sender);
        return did;
    }

    /**
     * @notice Update DID document
     */
    function updateDIDDocument(
        string memory _did,
        string[] memory _publicKeys,
        string[] memory _serviceEndpoints
    ) external onlyDIDController(_did) validDID(_did) whenNotPaused {
        DIDDocument storage doc = didDocuments[_did];
        doc.publicKeys = _publicKeys;
        doc.serviceEndpoints = _serviceEndpoints;
        doc.updatedAt = block.timestamp;

        emit DIDUpdated(_did, msg.sender);
    }

    /**
     * @notice Issue a verifiable credential
     */
    function issueCredential(
        string memory _subjectDID,
        string memory _credentialType,
        bytes32[] memory _claims,
        string memory _ipfsHash,
        VerificationLevel _level
    ) external whenNotPaused returns (bytes32) {
        require(trustedIssuers[string(abi.encodePacked(msg.sender))], "Not trusted issuer");
        require(didDocuments[_subjectDID].isActive, "Subject DID not active");
        require(_claims.length > 0, "No claims provided");

        bytes32 credentialId = keccak256(abi.encodePacked(
            _subjectDID,
            _credentialType,
            block.timestamp,
            totalCredentials++
        ));

        // Create credential hash
        bytes32 credentialHash = keccak256(abi.encodePacked(
            _subjectDID,
            _credentialType,
            _claims,
            _ipfsHash,
            block.timestamp
        ));

        // Mock signature (in production would use proper signing)
        bytes memory signature = abi.encodePacked(
            keccak256(abi.encodePacked(credentialHash, msg.sender))
        );

        verifiableCredentials[credentialId] = VerifiableCredential({
            credentialId: credentialId,
            did: _subjectDID,
            issuer: string(abi.encodePacked(msg.sender)),
            subject: _subjectDID,
            credentialType: _credentialType,
            issuanceDate: block.timestamp,
            expirationDate: block.timestamp + credentialExpiration,
            status: CredentialStatus.ACTIVE,
            credentialHash: credentialHash,
            ipfsHash: _ipfsHash,
            level: _level,
            claims: _claims,
            signature: signature
        });

        // Add to identity profile
        IdentityProfile storage profile = identityProfiles[_subjectDID];
        profile.credentials.push(string(abi.encodePacked(credentialId)));
        profile.verificationLevel = _level > profile.verificationLevel ? _level : profile.verificationLevel;

        // Update trust score based on credential
        _updateTrustScore(_subjectDID, _level);

        emit CredentialIssued(credentialId, _subjectDID, string(abi.encodePacked(msg.sender)));
        return credentialId;
    }

    /**
     * @notice Verify a credential with ZKP
     */
    function verifyCredentialWithZKP(
        bytes32 _credentialId,
        string memory _circuitId,
        bytes memory _proofData,
        bytes32 _publicInputsHash
    ) external whenNotPaused returns (bool) {
        VerifiableCredential storage credential = verifiableCredentials[_credentialId];
        require(credential.status == CredentialStatus.ACTIVE, "Credential not active");
        require(block.timestamp <= credential.expirationDate, "Credential expired");

        // Create ZKP proof record
        bytes32 proofId = keccak256(abi.encodePacked(
            _credentialId,
            _circuitId,
            _publicInputsHash,
            block.timestamp
        ));

        // Mock ZKP verification (in production would verify actual proof)
        bool isValid = _mockZKPVerification(_proofData, _publicInputsHash);

        zkpProofs[proofId] = ZKPProof({
            proofId: proofId,
            circuitId: _circuitId,
            proofData: _proofData,
            publicInputsHash: _publicInputsHash,
            prover: msg.sender,
            timestamp: block.timestamp,
            isValid: isValid,
            verificationKey: "mock_vk" // In production would store actual VK
        });

        totalZKPProofs++;

        emit ZKPVerified(proofId, _circuitId, isValid);

        // Update trust score if verification successful
        if (isValid) {
            IdentityProfile storage profile = identityProfiles[credential.did];
            profile.trustScore = profile.trustScore + 50 > 1000 ? 1000 : profile.trustScore + 50;
            emit TrustScoreUpdated(credential.did, profile.trustScore);
        }

        return isValid;
    }

    /**
     * @notice Revoke a credential
     */
    function revokeCredential(bytes32 _credentialId, string memory _reason) external {
        VerifiableCredential storage credential = verifiableCredentials[_credentialId];
        require(credential.issuer == string(abi.encodePacked(msg.sender)) || owner() == msg.sender, "Not authorized");

        credential.status = CredentialStatus.REVOKED;

        // Update identity profile
        IdentityProfile storage profile = identityProfiles[credential.did];
        profile.trustScore = profile.trustScore > 100 ? profile.trustScore - 100 : 0;

        emit CredentialRevoked(_credentialId, _reason);
    }

    /**
     * @notice Verify identity for access control
     */
    function verifyIdentityForAccess(
        string memory _did,
        VerificationLevel _requiredLevel,
        uint256 _minTrustScore
    ) external view returns (bool) {
        IdentityProfile memory profile = identityProfiles[_did];
        require(profile.walletAddress != address(0), "Identity not found");

        return (
            profile.verificationLevel >= _requiredLevel &&
            profile.trustScore >= _minTrustScore &&
            !profile.isFrozen &&
            block.timestamp - profile.lastActivity <= verificationCooldown
        );
    }

    /**
     * @notice Get DID document
     */
    function getDIDDocument(string memory _did)
        external
        view
        returns (
            address controller,
            uint256 createdAt,
            uint256 updatedAt,
            bool isActive,
            string[] memory publicKeys,
            string[] memory serviceEndpoints
        )
    {
        DIDDocument storage doc = didDocuments[_did];
        return (
            doc.controller,
            doc.createdAt,
            doc.updatedAt,
            doc.isActive,
            doc.publicKeys,
            doc.serviceEndpoints
        );
    }

    /**
     * @notice Get verifiable credential
     */
    function getVerifiableCredential(bytes32 _credentialId)
        external
        view
        returns (
            string memory did,
            string memory issuer,
            string memory credentialType,
            uint256 issuanceDate,
            uint256 expirationDate,
            CredentialStatus status,
            VerificationLevel level
        )
    {
        VerifiableCredential memory credential = verifiableCredentials[_credentialId];
        return (
            credential.did,
            credential.issuer,
            credential.credentialType,
            credential.issuanceDate,
            credential.expirationDate,
            credential.status,
            credential.level
        );
    }

    /**
     * @notice Get identity profile
     */
    function getIdentityProfile(string memory _did)
        external
        view
        returns (
            address walletAddress,
            VerificationLevel verificationLevel,
            uint256 trustScore,
            uint256 reputationScore,
            bool isAccreditedInvestor,
            bool isProfessionalEntity,
            string memory jurisdiction
        )
    {
        IdentityProfile memory profile = identityProfiles[_did];
        return (
            profile.walletAddress,
            profile.verificationLevel,
            profile.trustScore,
            profile.reputationScore,
            profile.isAccreditedInvestor,
            profile.isProfessionalEntity,
            profile.jurisdiction
        );
    }

    /**
     * @notice Add trusted issuer
     */
    function addTrustedIssuer(
        string memory _issuer,
        VerificationLevel _level
    ) external onlyOwner {
        trustedIssuers[_issuer] = true;
        issuerLevels[_issuer] = _level;
    }

    /**
     * @notice Update identity attributes
     */
    function updateIdentityAttributes(
        string memory _did,
        string[] memory _keys,
        bytes32[] memory _values
    ) external onlyDIDController(_did) validDID(_did) whenNotPaused {
        require(_keys.length == _values.length, "Mismatched arrays");

        IdentityProfile storage profile = identityProfiles[_did];
        for (uint256 i = 0; i < _keys.length; i++) {
            profile.attributes[_keys[i]] = _values[i];
        }

        profile.lastActivity = block.timestamp;
    }

    /**
     * @notice Freeze/unfreeze identity
     */
    function setIdentityFrozen(string memory _did, bool _frozen) external onlyOwner {
        IdentityProfile storage profile = identityProfiles[_did];
        require(profile.walletAddress != address(0), "Identity not found");

        profile.isFrozen = _frozen;
    }

    /**
     * @notice Update protocol parameters
     */
    function updateParameters(
        uint256 _credentialExpiration,
        uint256 _maxCredentialsPerDID,
        uint256 _minTrustScore,
        uint256 _verificationCooldown
    ) external onlyOwner {
        credentialExpiration = _credentialExpiration;
        maxCredentialsPerDID = _maxCredentialsPerDID;
        minTrustScore = _minTrustScore;
        verificationCooldown = _verificationCooldown;
    }

    /**
     * @notice Emergency pause
     */
    function emergencyPause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause
     */
    function emergencyUnpause() external onlyOwner {
        _unpause();
    }

    // Internal functions

    function _updateTrustScore(string memory _did, VerificationLevel _level) internal {
        IdentityProfile storage profile = identityProfiles[_did];

        uint256 scoreIncrease;
        if (_level == VerificationLevel.PREMIUM) scoreIncrease = 300;
        else if (_level == VerificationLevel.ENHANCED) scoreIncrease = 200;
        else if (_level == VerificationLevel.STANDARD) scoreIncrease = 100;
        else scoreIncrease = 50;

        profile.trustScore = profile.trustScore + scoreIncrease > 1000 ? 1000 : profile.trustScore + scoreIncrease;

        emit TrustScoreUpdated(_did, profile.trustScore);
    }

    function _mockZKPVerification(bytes memory _proofData, bytes32 _publicInputsHash) internal pure returns (bool) {
        // Simplified ZKP verification (in production would use proper ZKP verification)
        bytes32 computedHash = keccak256(abi.encodePacked(_proofData, _publicInputsHash));
        return uint256(computedHash) % 2 == 0; // Mock verification
    }
}

// Simple Strings library for DID generation
library Strings {
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = bytes1(uint8(48 + uint256(value & 0xf)));
            if (uint8(buffer[i]) > 57) buffer[i] = bytes1(uint8(buffer[i]) + 39);
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
