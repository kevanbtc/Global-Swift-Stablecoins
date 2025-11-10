// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DecentralizedStorage
 * @notice Integration with IPFS, Arweave, Filecoin, and other decentralized storage
 * @dev Handles file storage, retrieval, and content addressing
 */
contract DecentralizedStorage is Ownable, ReentrancyGuard {

    enum StorageProvider {
        IPFS,
        ARWEAVE,
        FILECOIN,
        SWARM,
        CRUST,
        PINATA,
        WEB3_STORAGE,
        NFT_STORAGE,
        S3_COMPATIBLE,
        CUSTOM
    }

    enum ContentType {
        DOCUMENT,
        IMAGE,
        VIDEO,
        AUDIO,
        CONTRACT_CODE,
        METADATA,
        CERTIFICATE,
        COMPLIANCE_DATA,
        FINANCIAL_REPORT,
        LEGAL_DOCUMENT,
        MEDICAL_RECORD,
        IDENTITY_DATA
    }

    enum StorageStatus {
        UPLOADING,
        STORED,
        PINNED,
        REPLICATED,
        RETRIEVING,
        AVAILABLE,
        EXPIRED,
        DELETED
    }

    struct StorageFile {
        bytes32 fileId;
        string cid; // Content Identifier (IPFS/Arweave)
        string url; // Direct access URL
        StorageProvider provider;
        ContentType contentType;
        address uploader;
        uint256 size; // bytes
        bytes32 checksum;
        StorageStatus status;
        uint256 uploadTimestamp;
        uint256 expiryTimestamp;
        uint256 accessCount;
        uint256 replicationFactor;
        mapping(address => bool) authorizedViewers;
        mapping(bytes32 => bytes32) metadata; // key => value
    }

    struct StorageRequest {
        bytes32 requestId;
        address requester;
        StorageProvider provider;
        ContentType contentType;
        uint256 maxSize;
        uint256 maxDuration;
        uint256 fee;
        bool fulfilled;
        bytes32 fileId;
    }

    struct ProviderConfig {
        StorageProvider provider;
        string apiEndpoint;
        string apiKey;
        uint256 rateLimit; // requests per minute
        uint256 storageFee; // wei per GB per month
        uint256 retrievalFee; // wei per GB
        bool isActive;
        uint256 totalFiles;
        uint256 totalStorage; // bytes
    }

    // Storage
    mapping(bytes32 => StorageFile) public storageFiles;
    mapping(bytes32 => StorageRequest) public storageRequests;
    mapping(StorageProvider => ProviderConfig) public providerConfigs;
    mapping(address => bytes32[]) public userFiles;
    mapping(address => bytes32[]) public userRequests;
    mapping(string => bytes32) public cidToFileId;

    // Global statistics
    uint256 public totalFiles;
    uint256 public totalStorage; // bytes
    uint256 public totalRequests;
    uint256 public totalAccesses;

    // Protocol parameters
    uint256 public baseStorageFee = 0.001 ether; // 0.001 ETH per GB per month
    uint256 public baseRetrievalFee = 0.0001 ether; // 0.0001 ETH per GB
    uint256 public maxFileSize = 1_000_000_000; // 1GB
    uint256 public defaultExpiry = 365 days;
    uint256 public replicationFactor = 3;

    // Events
    event FileUploaded(bytes32 indexed fileId, string cid, StorageProvider provider);
    event FileAccessed(bytes32 indexed fileId, address accessor);
    event StorageRequested(bytes32 indexed requestId, address requester, StorageProvider provider);
    event ProviderConfigured(StorageProvider provider, string apiEndpoint);

    modifier validFile(bytes32 _fileId) {
        require(storageFiles[_fileId].uploader != address(0), "File not found");
        _;
    }

    modifier authorizedViewer(bytes32 _fileId) {
        StorageFile storage file = storageFiles[_fileId];
        require(
            file.uploader == msg.sender ||
            file.authorizedViewers[msg.sender] ||
            msg.sender == owner(),
            "Not authorized to access file"
        );
        _;
    }

    modifier activeProvider(StorageProvider _provider) {
        require(providerConfigs[_provider].isActive, "Provider not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Configure storage provider
     */
    function configureProvider(
        StorageProvider _provider,
        string memory _apiEndpoint,
        string memory _apiKey,
        uint256 _rateLimit,
        uint256 _storageFee,
        uint256 _retrievalFee
    ) public onlyOwner {
        ProviderConfig storage config = providerConfigs[_provider];
        config.provider = _provider;
        config.apiEndpoint = _apiEndpoint;
        config.apiKey = _apiKey;
        config.rateLimit = _rateLimit;
        config.storageFee = _storageFee;
        config.retrievalFee = _retrievalFee;
        config.isActive = true;

        emit ProviderConfigured(_provider, _apiEndpoint);
    }

    /**
     * @notice Upload file to decentralized storage
     */
    function uploadFile(
        string memory _cid,
        StorageProvider _provider,
        ContentType _contentType,
        uint256 _size,
        bytes32 _checksum,
        uint256 _duration
    ) public payable activeProvider(_provider) returns (bytes32) {
        require(_size <= maxFileSize, "File too large");
        require(bytes(_cid).length > 0, "Invalid CID");
        require(cidToFileId[_cid] == bytes32(0), "CID already exists");

        // Calculate storage fee
        uint256 storageFee = calculateStorageFee(_provider, _size, _duration);
        require(msg.value >= storageFee, "Insufficient storage fee");

        bytes32 fileId = keccak256(abi.encodePacked(
            _cid,
            _provider,
            msg.sender,
            block.timestamp
        ));

        StorageFile storage file = storageFiles[fileId];
        file.fileId = fileId;
        file.cid = _cid;
        file.provider = _provider;
        file.contentType = _contentType;
        file.uploader = msg.sender;
        file.size = _size;
        file.checksum = _checksum;
        file.status = StorageStatus.STORED;
        file.uploadTimestamp = block.timestamp;
        file.expiryTimestamp = block.timestamp + (_duration > 0 ? _duration : defaultExpiry);
        file.replicationFactor = replicationFactor;

        cidToFileId[_cid] = fileId;
        userFiles[msg.sender].push(fileId);
        totalFiles++;
        totalStorage += _size;

        ProviderConfig storage config = providerConfigs[_provider];
        config.totalFiles++;
        config.totalStorage += _size;

        emit FileUploaded(fileId, _cid, _provider);
        return fileId;
    }

    /**
     * @notice Request storage allocation
     */
    function requestStorage(
        StorageProvider _provider,
        ContentType _contentType,
        uint256 _maxSize,
        uint256 _maxDuration
    ) public payable activeProvider(_provider) returns (bytes32) {
        require(_maxSize <= maxFileSize, "Size too large");

        uint256 fee = calculateStorageFee(_provider, _maxSize, _maxDuration);
        require(msg.value >= fee, "Insufficient fee");

        bytes32 requestId = keccak256(abi.encodePacked(
            msg.sender,
            _provider,
            _maxSize,
            block.timestamp
        ));

        StorageRequest storage request = storageRequests[requestId];
        request.requestId = requestId;
        request.requester = msg.sender;
        request.provider = _provider;
        request.contentType = _contentType;
        request.maxSize = _maxSize;
        request.maxDuration = _maxDuration;
        request.fee = fee;

        userRequests[msg.sender].push(requestId);
        totalRequests++;

        emit StorageRequested(requestId, msg.sender, _provider);
        return requestId;
    }

    /**
     * @notice Access file content
     */
    function accessFile(bytes32 _fileId) public payable validFile(_fileId)
        authorizedViewer(_fileId)
        returns (string memory cid, string memory url, bytes32 checksum)
    {
        StorageFile storage file = storageFiles[_fileId];
        require(file.status == StorageStatus.AVAILABLE || file.status == StorageStatus.STORED, "File not available");
        require(block.timestamp <= file.expiryTimestamp, "File expired");

        file.accessCount++;
        totalAccesses++;

        // Calculate retrieval fee if applicable
        if (file.accessCount > 10) { // Free first 10 accesses
            uint256 retrievalFee = calculateRetrievalFee(file.provider, file.size);
            require(msg.value >= retrievalFee, "Insufficient retrieval fee");
        }

        emit FileAccessed(_fileId, msg.sender);
        return (file.cid, file.url, file.checksum);
    }

    /**
     * @notice Grant access to file
     */
    function grantAccess(bytes32 _fileId, address _viewer) public validFile(_fileId) {
        StorageFile storage file = storageFiles[_fileId];
        require(file.uploader == msg.sender, "Not file owner");

        file.authorizedViewers[_viewer] = true;
    }

    /**
     * @notice Revoke access to file
     */
    function revokeAccess(bytes32 _fileId, address _viewer) public validFile(_fileId) {
        StorageFile storage file = storageFiles[_fileId];
        require(file.uploader == msg.sender, "Not file owner");

        file.authorizedViewers[_viewer] = false;
    }

    /**
     * @notice Update file metadata
     */
    function updateMetadata(bytes32 _fileId, bytes32 _key, bytes32 _value) public validFile(_fileId) {
        StorageFile storage file = storageFiles[_fileId];
        require(file.uploader == msg.sender, "Not file owner");

        file.metadata[_key] = _value;
    }

    /**
     * @notice Extend file storage duration
     */
    function extendStorage(bytes32 _fileId, uint256 _additionalDuration) public payable validFile(_fileId) {
        StorageFile storage file = storageFiles[_fileId];
        require(file.uploader == msg.sender, "Not file owner");

        uint256 extensionFee = calculateStorageFee(file.provider, file.size, _additionalDuration);
        require(msg.value >= extensionFee, "Insufficient extension fee");

        file.expiryTimestamp += _additionalDuration;
    }

    /**
     * @notice Delete file (mark as deleted)
     */
    function deleteFile(bytes32 _fileId) public validFile(_fileId) {
        StorageFile storage file = storageFiles[_fileId];
        require(file.uploader == msg.sender, "Not file owner");

        file.status = StorageStatus.DELETED;
        totalStorage -= file.size;

        ProviderConfig storage config = providerConfigs[file.provider];
        config.totalStorage -= file.size;
    }

    /**
     * @notice Fulfill storage request
     */
    function fulfillStorageRequest(bytes32 _requestId, bytes32 _fileId) public {
        StorageRequest storage request = storageRequests[_requestId];
        require(request.requester != address(0), "Request not found");
        require(!request.fulfilled, "Request already fulfilled");

        StorageFile storage file = storageFiles[_fileId];
        require(file.uploader == request.requester, "File not owned by requester");

        request.fulfilled = true;
        request.fileId = _fileId;
    }

    /**
     * @notice Get file details
     */
    function getFile(bytes32 _fileId) public view
        returns (
            string memory cid,
            StorageProvider provider,
            ContentType contentType,
            uint256 size,
            StorageStatus status,
            uint256 expiryTimestamp,
            uint256 accessCount
        )
    {
        StorageFile storage file = storageFiles[_fileId];
        return (
            file.cid,
            file.provider,
            file.contentType,
            file.size,
            file.status,
            file.expiryTimestamp,
            file.accessCount
        );
    }

    /**
     * @notice Get file metadata
     */
    function getFileMetadata(bytes32 _fileId, bytes32 _key) public view returns (bytes32) {
        return storageFiles[_fileId].metadata[_key];
    }

    /**
     * @notice Get provider configuration
     */
    function getProviderConfig(StorageProvider _provider) public view
        returns (
            string memory apiEndpoint,
            uint256 rateLimit,
            uint256 storageFee,
            uint256 retrievalFee,
            bool isActive,
            uint256 totalFiles,
            uint256 totalStorage
        )
    {
        ProviderConfig memory config = providerConfigs[_provider];
        return (
            config.apiEndpoint,
            config.rateLimit,
            config.storageFee,
            config.retrievalFee,
            config.isActive,
            config.totalFiles,
            config.totalStorage
        );
    }

    /**
     * @notice Get user files
     */
    function getUserFiles(address _user) public view returns (bytes32[] memory) {
        return userFiles[_user];
    }

    /**
     * @notice Check if viewer is authorized
     */
    function isAuthorizedViewer(bytes32 _fileId, address _viewer) public view returns (bool) {
        StorageFile storage file = storageFiles[_fileId];
        return file.uploader == _viewer || file.authorizedViewers[_viewer] || _viewer == owner();
    }

    /**
     * @notice Update protocol parameters
     */
    function updateProtocolParameters(
        uint256 _baseStorageFee,
        uint256 _baseRetrievalFee,
        uint256 _maxFileSize,
        uint256 _defaultExpiry,
        uint256 _replicationFactor
    ) public onlyOwner {
        baseStorageFee = _baseStorageFee;
        baseRetrievalFee = _baseRetrievalFee;
        maxFileSize = _maxFileSize;
        defaultExpiry = _defaultExpiry;
        replicationFactor = _replicationFactor;
    }

    /**
     * @notice Get global storage statistics
     */
    function getGlobalStatistics() public view
        returns (
            uint256 _totalFiles,
            uint256 _totalStorage,
            uint256 _totalRequests,
            uint256 _totalAccesses
        )
    {
        return (totalFiles, totalStorage, totalRequests, totalAccesses);
    }

    // Internal functions
    function calculateStorageFee(StorageProvider _provider, uint256 _size, uint256 _duration)
        internal
        view
        returns (uint256)
    {
        ProviderConfig memory config = providerConfigs[_provider];
        uint256 sizeInGB = (_size + 999999999) / 1000000000; // Round up to GB
        uint256 durationInMonths = (_duration + 2591999) / 2592000; // Round up to months

        uint256 providerFee = config.storageFee * sizeInGB * durationInMonths;
        uint256 protocolFee = baseStorageFee * sizeInGB * durationInMonths;

        return providerFee + protocolFee;
    }

    function calculateRetrievalFee(StorageProvider _provider, uint256 _size)
        internal
        view
        returns (uint256)
    {
        ProviderConfig memory config = providerConfigs[_provider];
        uint256 sizeInGB = (_size + 999999999) / 1000000000; // Round up to GB

        uint256 providerFee = config.retrievalFee * sizeInGB;
        uint256 protocolFee = baseRetrievalFee * sizeInGB;

        return providerFee + protocolFee;
    }
}
