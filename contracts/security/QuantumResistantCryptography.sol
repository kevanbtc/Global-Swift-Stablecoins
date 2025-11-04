// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title QuantumResistantCryptography
 * @notice Post-quantum cryptographic primitives for blockchain security
 * @dev Implements lattice-based cryptography and hash-based signatures
 */
contract QuantumResistantCryptography is Ownable, ReentrancyGuard {

    // Dilithium signature parameters (simplified for Solidity)
    struct DilithiumKeyPair {
        bytes publicKey;      // Public key for verification
        bytes privateKey;     // Private key for signing (encrypted)
        uint256 keyId;        // Unique key identifier
        uint256 createdAt;    // Key creation timestamp
        bool isActive;        // Key status
    }

    // Kyber KEM parameters
    struct KyberKeyPair {
        bytes publicKey;      // Public key for encapsulation
        bytes privateKey;     // Private key for decapsulation (encrypted)
        uint256 keyId;
        uint256 createdAt;
        bool isActive;
    }

    // XMSS hash-based signatures
    struct XMSSKeyPair {
        bytes publicKey;
        bytes privateKey;     // OTS private keys (encrypted)
        uint256 keyId;
        uint256 remainingSignatures; // Remaining one-time signatures
        uint256 createdAt;
        bool isActive;
    }

    // Encrypted data structure
    struct EncryptedData {
        bytes ciphertext;
        bytes nonce;
        bytes authTag;
        address encryptor;
        uint256 encryptedAt;
        Algorithm algorithm;
    }

    enum Algorithm {
        KYBER_KEM,
        DILITHIUM,
        XMSS,
        FALCON,
        SPHINCS
    }

    enum KeyStatus {
        ACTIVE,
        REVOKED,
        COMPROMISED,
        EXPIRED
    }

    // Storage
    mapping(address => DilithiumKeyPair) public dilithiumKeys;
    mapping(address => KyberKeyPair) public kyberKeys;
    mapping(address => XMSSKeyPair) public xmssKeys;
    mapping(bytes32 => EncryptedData) public encryptedData;
    mapping(bytes32 => bool) public revokedKeys;

    // Global parameters
    uint256 public constant DILITHIUM_PUBLIC_KEY_SIZE = 2592;  // bytes
    uint256 public constant DILITHIUM_SIGNATURE_SIZE = 4595;   // bytes
    uint256 public constant KYBER_PUBLIC_KEY_SIZE = 1568;      // bytes
    uint256 public constant KYBER_CIPHERTEXT_SIZE = 1568;       // bytes
    uint256 public constant XMSS_SIGNATURES_PER_KEY = 2**20;   // 1M signatures

    uint256 public keyRotationPeriod = 365 days;  // Rotate keys annually
    uint256 public maxKeyAge = 2 * 365 days;      // Max 2 years
    uint256 public totalKeysGenerated;

    // Events
    event DilithiumKeyGenerated(address indexed owner, uint256 keyId);
    event KyberKeyGenerated(address indexed owner, uint256 keyId);
    event XMSSKeyGenerated(address indexed owner, uint256 keyId);
    event DataEncrypted(bytes32 indexed dataId, address indexed encryptor, Algorithm algorithm);
    event DataDecrypted(bytes32 indexed dataId, address indexed decryptor);
    event SignatureVerified(bytes32 indexed messageHash, address indexed signer, bool valid);
    event KeyRevoked(bytes32 indexed keyHash, string reason);
    event KeyRotated(address indexed owner, Algorithm algorithm, uint256 newKeyId);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Generate Dilithium key pair for post-quantum signatures
     */
    function generateDilithiumKeyPair() external returns (uint256) {
        require(dilithiumKeys[msg.sender].createdAt == 0 || 
                block.timestamp > dilithiumKeys[msg.sender].createdAt + keyRotationPeriod,
                "Key rotation not due");

        uint256 keyId = ++totalKeysGenerated;

        // Generate key pair (simplified - in production would use proper PQ crypto)
        bytes memory publicKey = new bytes(DILITHIUM_PUBLIC_KEY_SIZE);
        bytes memory privateKey = new bytes(DILITHIUM_PUBLIC_KEY_SIZE);

        // Mock key generation - in reality would use cryptographic primitives
        for (uint256 i = 0; i < DILITHIUM_PUBLIC_KEY_SIZE; i++) {
            publicKey[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(msg.sender, keyId, i, "public"))) % 256));
            privateKey[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(msg.sender, keyId, i, "private"))) % 256));
        }

        // Encrypt private key before storage
        bytes memory encryptedPrivateKey = _encryptPrivateKey(privateKey, msg.sender);

        dilithiumKeys[msg.sender] = DilithiumKeyPair({
            publicKey: publicKey,
            privateKey: encryptedPrivateKey,
            keyId: keyId,
            createdAt: block.timestamp,
            isActive: true
        });

        emit DilithiumKeyGenerated(msg.sender, keyId);
        return keyId;
    }

    /**
     * @notice Generate Kyber key pair for post-quantum key encapsulation
     */
    function generateKyberKeyPair() external returns (uint256) {
        require(kyberKeys[msg.sender].createdAt == 0 || 
                block.timestamp > kyberKeys[msg.sender].createdAt + keyRotationPeriod,
                "Key rotation not due");

        uint256 keyId = ++totalKeysGenerated;

        bytes memory publicKey = new bytes(KYBER_PUBLIC_KEY_SIZE);
        bytes memory privateKey = new bytes(KYBER_PUBLIC_KEY_SIZE);

        // Mock key generation
        for (uint256 i = 0; i < KYBER_PUBLIC_KEY_SIZE; i++) {
            publicKey[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(msg.sender, keyId, i, "kem_public"))) % 256));
            privateKey[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(msg.sender, keyId, i, "kem_private"))) % 256));
        }

        bytes memory encryptedPrivateKey = _encryptPrivateKey(privateKey, msg.sender);

        kyberKeys[msg.sender] = KyberKeyPair({
            publicKey: publicKey,
            privateKey: encryptedPrivateKey,
            keyId: keyId,
            createdAt: block.timestamp,
            isActive: true
        });

        emit KyberKeyGenerated(msg.sender, keyId);
        return keyId;
    }

    /**
     * @notice Generate XMSS key pair for hash-based signatures
     */
    function generateXMSSKeyPair() external returns (uint256) {
        require(xmssKeys[msg.sender].createdAt == 0 || 
                block.timestamp > xmssKeys[msg.sender].createdAt + keyRotationPeriod,
                "Key rotation not due");

        uint256 keyId = ++totalKeysGenerated;

        bytes memory publicKey = new bytes(64);  // XMSS public key size
        bytes memory privateKey = new bytes(132); // XMSS private key size

        // Mock key generation
        for (uint256 i = 0; i < 64; i++) {
            publicKey[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(msg.sender, keyId, i, "xmss_public"))) % 256));
        }
        for (uint256 i = 0; i < 132; i++) {
            privateKey[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(msg.sender, keyId, i, "xmss_private"))) % 256));
        }

        bytes memory encryptedPrivateKey = _encryptPrivateKey(privateKey, msg.sender);

        xmssKeys[msg.sender] = XMSSKeyPair({
            publicKey: publicKey,
            privateKey: encryptedPrivateKey,
            keyId: keyId,
            remainingSignatures: XMSS_SIGNATURES_PER_KEY,
            createdAt: block.timestamp,
            isActive: true
        });

        emit XMSSKeyGenerated(msg.sender, keyId);
        return keyId;
    }

    /**
     * @notice Encrypt data using Kyber KEM + AES
     */
    function encryptData(
        bytes memory data,
        address recipient,
        Algorithm algorithm
    ) external returns (bytes32) {
        require(data.length > 0, "Empty data");
        require(kyberKeys[recipient].isActive, "Recipient has no active Kyber key");

        bytes32 dataId = keccak256(abi.encodePacked(data, recipient, block.timestamp));

        // Generate ephemeral key pair for encryption
        bytes memory ephemeralPublicKey = new bytes(KYBER_PUBLIC_KEY_SIZE);
        bytes memory ephemeralPrivateKey = new bytes(KYBER_PUBLIC_KEY_SIZE);

        // Mock ephemeral key generation
        for (uint256 i = 0; i < KYBER_PUBLIC_KEY_SIZE; i++) {
            ephemeralPublicKey[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(dataId, i, "ephemeral"))) % 256));
            ephemeralPrivateKey[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(dataId, i, "ephemeral_private"))) % 256));
        }

        // Perform KEM encapsulation (simplified)
        bytes memory ciphertext = new bytes(KYBER_CIPHERTEXT_SIZE);
        bytes memory sharedSecret = new bytes(32);

        // Mock KEM operations
        for (uint256 i = 0; i < 32; i++) {
            sharedSecret[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(ephemeralPublicKey, kyberKeys[recipient].publicKey, i))) % 256));
        }

        // Encrypt data with shared secret (AES-GCM simulation)
        bytes memory encryptedData = new bytes(data.length);
        bytes memory nonce = new bytes(12);
        bytes memory authTag = new bytes(16);

        // Mock AES-GCM encryption
        for (uint256 i = 0; i < data.length; i++) {
            encryptedData[i] = data[i] ^ sharedSecret[i % 32];
        }

        encryptedData[dataId] = EncryptedData({
            ciphertext: encryptedData,
            nonce: nonce,
            authTag: authTag,
            encryptor: msg.sender,
            encryptedAt: block.timestamp,
            algorithm: algorithm
        });

        emit DataEncrypted(dataId, msg.sender, algorithm);
        return dataId;
    }

    /**
     * @notice Decrypt data using Kyber KEM + AES
     */
    function decryptData(bytes32 dataId) external returns (bytes memory) {
        EncryptedData memory encrypted = encryptedData[dataId];
        require(encrypted.encryptedAt > 0, "Data not found");
        require(msg.sender == encrypted.encryptor, "Not authorized to decrypt");

        // Decrypt using stored keys (simplified)
        bytes memory decryptedData = new bytes(encrypted.ciphertext.length);
        bytes memory sharedSecret = new bytes(32);

        // Mock shared secret derivation
        for (uint256 i = 0; i < 32; i++) {
            sharedSecret[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(encrypted.nonce, i))) % 256));
        }

        // Decrypt data
        for (uint256 i = 0; i < encrypted.ciphertext.length; i++) {
            decryptedData[i] = encrypted.ciphertext[i] ^ sharedSecret[i % 32];
        }

        emit DataDecrypted(dataId, msg.sender);
        return decryptedData;
    }

    /**
     * @notice Verify Dilithium signature
     */
    function verifyDilithiumSignature(
        bytes32 messageHash,
        bytes memory signature,
        address signer
    ) external returns (bool) {
        require(dilithiumKeys[signer].isActive, "Signer has no active Dilithium key");
        require(signature.length == DILITHIUM_SIGNATURE_SIZE, "Invalid signature size");

        // Simplified signature verification (in production would use proper PQ crypto)
        bool isValid = _mockSignatureVerification(messageHash, signature, dilithiumKeys[signer].publicKey);

        emit SignatureVerified(messageHash, signer, isValid);
        return isValid;
    }

    /**
     * @notice Verify XMSS signature
     */
    function verifyXMSSSignature(
        bytes32 messageHash,
        bytes memory signature,
        address signer
    ) external returns (bool) {
        XMSSKeyPair storage keyPair = xmssKeys[signer];
        require(keyPair.isActive, "Signer has no active XMSS key");
        require(keyPair.remainingSignatures > 0, "No remaining signatures");

        // Simplified XMSS verification
        bool isValid = _mockSignatureVerification(messageHash, signature, keyPair.publicKey);

        if (isValid) {
            keyPair.remainingSignatures--;
        }

        emit SignatureVerified(messageHash, signer, isValid);
        return isValid;
    }

    /**
     * @notice Revoke a cryptographic key
     */
    function revokeKey(bytes32 keyHash, string memory reason) external onlyOwner {
        revokedKeys[keyHash] = true;
        emit KeyRevoked(keyHash, reason);
    }

    /**
     * @notice Check if a key is compromised or expired
     */
    function isKeyValid(address owner, Algorithm algorithm) external view returns (bool) {
        uint256 createdAt;

        if (algorithm == Algorithm.DILITHIUM) {
            createdAt = dilithiumKeys[owner].createdAt;
            return dilithiumKeys[owner].isActive && 
                   block.timestamp < createdAt + maxKeyAge &&
                   !revokedKeys[keccak256(abi.encodePacked(owner, algorithm, dilithiumKeys[owner].keyId))];
        } else if (algorithm == Algorithm.KYBER_KEM) {
            createdAt = kyberKeys[owner].createdAt;
            return kyberKeys[owner].isActive && 
                   block.timestamp < createdAt + maxKeyAge &&
                   !revokedKeys[keccak256(abi.encodePacked(owner, algorithm, kyberKeys[owner].keyId))];
        } else if (algorithm == Algorithm.XMSS) {
            createdAt = xmssKeys[owner].createdAt;
            return xmssKeys[owner].isActive && 
                   block.timestamp < createdAt + maxKeyAge &&
                   xmssKeys[owner].remainingSignatures > 0 &&
                   !revokedKeys[keccak256(abi.encodePacked(owner, algorithm, xmssKeys[owner].keyId))];
        }

        return false;
    }

    /**
     * @notice Update key rotation parameters
     */
    function updateParameters(
        uint256 _keyRotationPeriod,
        uint256 _maxKeyAge
    ) external onlyOwner {
        require(_keyRotationPeriod > 0, "Invalid rotation period");
        require(_maxKeyAge > _keyRotationPeriod, "Max age must exceed rotation period");

        keyRotationPeriod = _keyRotationPeriod;
        maxKeyAge = _maxKeyAge;
    }

    /**
     * @notice Get key information
     */
    function getKeyInfo(address owner, Algorithm algorithm)
        external
        view
        returns (
            uint256 keyId,
            uint256 createdAt,
            bool isActive,
            uint256 remainingSignatures
        )
    {
        if (algorithm == Algorithm.DILITHIUM) {
            DilithiumKeyPair memory keyPair = dilithiumKeys[owner];
            return (keyPair.keyId, keyPair.createdAt, keyPair.isActive, 0);
        } else if (algorithm == Algorithm.KYBER_KEM) {
            KyberKeyPair memory keyPair = kyberKeys[owner];
            return (keyPair.keyId, keyPair.createdAt, keyPair.isActive, 0);
        } else if (algorithm == Algorithm.XMSS) {
            XMSSKeyPair memory keyPair = xmssKeys[owner];
            return (keyPair.keyId, keyPair.createdAt, keyPair.isActive, keyPair.remainingSignatures);
        }

        return (0, 0, false, 0);
    }

    // Internal functions

    function _encryptPrivateKey(bytes memory privateKey, address owner) internal pure returns (bytes memory) {
        // Simplified encryption - in production would use proper encryption
        bytes memory encrypted = new bytes(privateKey.length);
        for (uint256 i = 0; i < privateKey.length; i++) {
            encrypted[i] = privateKey[i] ^ bytes1(uint8(uint256(owner) % 256));
        }
        return encrypted;
    }

    function _mockSignatureVerification(
        bytes32 messageHash,
        bytes memory signature,
        bytes memory publicKey
    ) internal pure returns (bool) {
        // Simplified signature verification - in production would use proper PQ crypto
        bytes32 computedHash = keccak256(abi.encodePacked(messageHash, signature, publicKey));
        return uint256(computedHash) % 2 == 0; // Mock verification
    }
}
