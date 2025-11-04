// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ChainInfrastructure} from "./ChainInfrastructure.sol";

/**
 * @title BlockchainExplorer
 * @notice Integrated blockchain explorer for Unykorn Layer 1 with privacy controls
 * @dev Provides public exploration while maintaining private data confidentiality
 */
contract BlockchainExplorer is Ownable, ReentrancyGuard {

    enum ExplorerView {
        PUBLIC,         // Public blockchain data
        AUTHENTICATED,  // User-specific authenticated data
        PRIVATE,        // Private group data
        ADMIN           // Administrative view
    }

    enum DataCategory {
        TRANSACTIONS,
        CONTRACTS,
        TOKENS,
        ORACLES,
        GOVERNANCE,
        COMPLIANCE,
        SETTLEMENT,
        VALIDATION
    }

    struct ExplorerQuery {
        bytes32 queryId;
        address requester;
        ExplorerView viewLevel;
        DataCategory category;
        bytes32[] filters;
        uint256 timestamp;
        uint256 resultCount;
        bytes32 ipfsResultHash;
        bool isCached;
        uint256 cacheExpiry;
    }

    struct ContractMetadata {
        address contractAddress;
        string name;
        string description;
        string version;
        address deployer;
        uint256 deploymentBlock;
        bytes32 ipfsMetadataHash;
        ChainInfrastructure.PrivacyLevel privacyLevel;
        string[] tags;
        mapping(string => bytes32) attributes;
    }

    struct TransactionView {
        bytes32 txHash;
        address from;
        address to;
        uint256 value;
        uint256 gasUsed;
        bool success;
        bytes32 ipfsDataHash;
        ChainInfrastructure.PrivacyLevel privacyLevel;
        uint256 timestamp;
    }

    struct TokenAnalytics {
        address tokenAddress;
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 holders;
        uint256 transfers24h;
        uint256 volume24h;
        bytes32 ipfsAnalyticsHash;
        ChainInfrastructure.PrivacyLevel privacyLevel;
    }

    // Core references
    ChainInfrastructure public chainInfra;

    // Explorer data
    mapping(address => ContractMetadata) public contractMetadata;
    mapping(bytes32 => ExplorerQuery) public queries;
    mapping(DataCategory => bytes32[]) public categoryQueries;

    // Analytics
    mapping(address => TokenAnalytics) public tokenAnalytics;
    bytes32[] public recentQueries;

    // Access control
    mapping(address => ExplorerView) public userAccessLevel;
    mapping(address => mapping(DataCategory => bool)) public categoryAccess;

    // Configuration
    uint256 public queryCacheTime = 300; // 5 minutes
    uint256 public maxQueryResults = 1000;
    uint256 public analyticsUpdateInterval = 3600; // 1 hour

    // Events
    event ContractIndexed(address indexed contractAddress, string name, ChainInfrastructure.PrivacyLevel privacyLevel);
    event QueryExecuted(bytes32 indexed queryId, address requester, DataCategory category, uint256 resultCount);
    event AnalyticsUpdated(address indexed tokenAddress, uint256 holders, uint256 volume24h);
    event AccessLevelChanged(address indexed user, ExplorerView newLevel);

    modifier validAccess(address _user, ExplorerView _requiredLevel) {
        require(uint256(userAccessLevel[_user]) >= uint256(_requiredLevel), "Insufficient access level");
        _;
    }

    modifier canAccessCategory(address _user, DataCategory _category) {
        require(categoryAccess[_user][_category] || userAccessLevel[_user] == ExplorerView.ADMIN, "Category access denied");
        _;
    }

    constructor(address _chainInfra) Ownable(msg.sender) {
        chainInfra = ChainInfrastructure(_chainInfra);
        userAccessLevel[msg.sender] = ExplorerView.ADMIN;
    }

    /**
     * @notice Index a contract for explorer visibility
     */
    function indexContract(
        address _contractAddress,
        string memory _name,
        string memory _description,
        string memory _version,
        string[] memory _tags,
        string memory _ipfsMetadataHash
    ) external onlyOwner {
        ContractMetadata storage metadata = contractMetadata[_contractAddress];
        metadata.contractAddress = _contractAddress;
        metadata.name = _name;
        metadata.description = _description;
        metadata.version = _version;
        metadata.deployer = msg.sender;
        metadata.deploymentBlock = block.number;
        metadata.ipfsMetadataHash = keccak256(abi.encodePacked(_ipfsMetadataHash));
        metadata.tags = _tags;

        // Get privacy level from chain infrastructure
        (, , ChainInfrastructure.PrivacyLevel privacyLevel) = chainInfra.getChainInfo();
        metadata.privacyLevel = privacyLevel;

        emit ContractIndexed(_contractAddress, _name, privacyLevel);
    }

    /**
     * @notice Execute explorer query
     */
    function executeQuery(
        DataCategory _category,
        bytes32[] memory _filters,
        ExplorerView _viewLevel,
        string memory _ipfsResultHash
    ) external validAccess(msg.sender, _viewLevel) canAccessCategory(msg.sender, _category) returns (bytes32) {
        bytes32 queryId = keccak256(abi.encodePacked(
            msg.sender, _category, _filters.length, block.timestamp
        ));

        ExplorerQuery storage query = queries[queryId];
        query.queryId = queryId;
        query.requester = msg.sender;
        query.viewLevel = _viewLevel;
        query.category = _category;
        query.filters = _filters;
        query.timestamp = block.timestamp;
        query.ipfsResultHash = keccak256(abi.encodePacked(_ipfsResultHash));

        // Simulate result count (would be calculated based on actual query)
        query.resultCount = _filters.length > 0 ? _filters.length * 10 : 100;

        categoryQueries[_category].push(queryId);
        recentQueries.push(queryId);

        // Keep only recent queries
        if (recentQueries.length > 1000) {
            for (uint256 i = 0; i < 100; i++) {
                recentQueries.pop();
            }
        }

        emit QueryExecuted(queryId, msg.sender, _category, query.resultCount);
        return queryId;
    }

    /**
     * @notice Update token analytics
     */
    function updateTokenAnalytics(
        address _tokenAddress,
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _holders,
        uint256 _transfers24h,
        uint256 _volume24h,
        string memory _ipfsAnalyticsHash
    ) external onlyOwner {
        TokenAnalytics storage analytics = tokenAnalytics[_tokenAddress];
        analytics.tokenAddress = _tokenAddress;
        analytics.name = _name;
        analytics.symbol = _symbol;
        analytics.totalSupply = _totalSupply;
        analytics.holders = _holders;
        analytics.transfers24h = _transfers24h;
        analytics.volume24h = _volume24h;
        analytics.ipfsAnalyticsHash = keccak256(abi.encodePacked(_ipfsAnalyticsHash));

        // Get privacy level
        (, , ChainInfrastructure.PrivacyLevel privacyLevel) = chainInfra.getChainInfo();
        analytics.privacyLevel = privacyLevel;

        emit AnalyticsUpdated(_tokenAddress, _holders, _volume24h);
    }

    /**
     * @notice Set user access level
     */
    function setUserAccessLevel(address _user, ExplorerView _level) external onlyOwner {
        userAccessLevel[_user] = _level;
        emit AccessLevelChanged(_user, _level);
    }

    /**
     * @notice Grant category access
     */
    function grantCategoryAccess(address _user, DataCategory _category, bool _access) external onlyOwner {
        categoryAccess[_user][_category] = _access;
    }

    /**
     * @notice Get contract information
     */
    function getContractInfo(address _contractAddress)
        external
        view
        returns (
            string memory name,
            string memory description,
            string memory version,
            address deployer,
            uint256 deploymentBlock,
            ChainInfrastructure.PrivacyLevel privacyLevel,
            string[] memory tags
        )
    {
        ContractMetadata memory metadata = contractMetadata[_contractAddress];
        return (
            metadata.name,
            metadata.description,
            metadata.version,
            metadata.deployer,
            metadata.deploymentBlock,
            metadata.privacyLevel,
            metadata.tags
        );
    }

    /**
     * @notice Get query results
     */
    function getQueryResults(bytes32 _queryId)
        external
        view
        returns (
            DataCategory category,
            uint256 resultCount,
            bytes32 ipfsResultHash,
            uint256 timestamp,
            bool isCached
        )
    {
        ExplorerQuery memory query = queries[_queryId];
        return (
            query.category,
            query.resultCount,
            query.ipfsResultHash,
            query.timestamp,
            query.isCached
        );
    }

    /**
     * @notice Get token analytics
     */
    function getTokenAnalytics(address _tokenAddress)
        external
        view
        returns (
            string memory name,
            string memory symbol,
            uint256 totalSupply,
            uint256 holders,
            uint256 transfers24h,
            uint256 volume24h,
            ChainInfrastructure.PrivacyLevel privacyLevel
        )
    {
        TokenAnalytics memory analytics = tokenAnalytics[_tokenAddress];
        return (
            analytics.name,
            analytics.symbol,
            analytics.totalSupply,
            analytics.holders,
            analytics.transfers24h,
            analytics.volume24h,
            analytics.privacyLevel
        );
    }

    /**
     * @notice Get public contract list
     */
    function getPublicContracts(uint256 _offset, uint256 _limit)
        external
        view
        returns (address[] memory contracts, string[] memory names)
    {
        // This would iterate through indexed contracts and filter by privacy level
        // Simplified implementation
        address[] memory publicContracts = new address[](10);
        string[] memory contractNames = new string[](10);

        // Mock data - in production would query actual indexed contracts
        for (uint256 i = 0; i < 10; i++) {
            publicContracts[i] = address(uint160(uint256(keccak256(abi.encodePacked("contract", i)))));
            contractNames[i] = string(abi.encodePacked("Public Contract ", Strings.toString(i)));
        }

        return (publicContracts, contractNames);
    }

    /**
     * @notice Get recent transactions
     */
    function getRecentTransactions(uint256 _limit)
        external
        view
        returns (bytes32[] memory txHashes, address[] memory from, address[] memory to, uint256[] memory values)
    {
        // Simplified - would query actual blockchain data
        uint256 count = _limit > 100 ? 100 : _limit;
        bytes32[] memory hashes = new bytes32[](count);
        address[] memory fromAddresses = new address[](count);
        address[] memory toAddresses = new address[](count);
        uint256[] memory txValues = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            hashes[i] = keccak256(abi.encodePacked("tx", block.timestamp, i));
            fromAddresses[i] = address(uint160(uint256(keccak256(abi.encodePacked("from", i)))));
            toAddresses[i] = address(uint160(uint256(keccak256(abi.encodePacked("to", i)))));
            txValues[i] = uint256(keccak256(abi.encodePacked("value", i))) % 100 ether;
        }

        return (hashes, fromAddresses, toAddresses, txValues);
    }

    /**
     * @notice Search contracts by tag
     */
    function searchContractsByTag(string memory _tag, uint256 _limit)
        external
        view
        returns (address[] memory contracts, string[] memory names)
    {
        // Simplified search implementation
        address[] memory foundContracts = new address[](5);
        string[] memory contractNames = new string[](5);

        for (uint256 i = 0; i < 5; i++) {
            foundContracts[i] = address(uint160(uint256(keccak256(abi.encodePacked(_tag, i)))));
            contractNames[i] = string(abi.encodePacked(_tag, " Contract ", Strings.toString(i)));
        }

        return (foundContracts, contractNames);
    }

    /**
     * @notice Get explorer statistics
     */
    function getExplorerStats()
        external
        view
        returns (
            uint256 totalQueries,
            uint256 indexedContracts,
            uint256 activeUsers,
            uint256 totalVolume24h,
            uint256 gasUsed24h
        )
    {
        // Mock statistics - would be calculated from actual data
        return (
            recentQueries.length,
            150, // indexed contracts
            1000, // active users
            1000000 ether, // 24h volume
            50000000 // 24h gas
        );
    }

    /**
     * @notice Update contract attribute
     */
    function updateContractAttribute(
        address _contractAddress,
        string memory _key,
        bytes32 _value
    ) external onlyOwner {
        contractMetadata[_contractAddress].attributes[_key] = _value;
    }

    /**
     * @notice Get contract attribute
     */
    function getContractAttribute(address _contractAddress, string memory _key)
        external
        view
        returns (bytes32)
    {
        return contractMetadata[_contractAddress].attributes[_key];
    }

    /**
     * @notice Update explorer configuration
     */
    function updateExplorerConfig(
        uint256 _queryCacheTime,
        uint256 _maxQueryResults,
        uint256 _analyticsUpdateInterval
    ) external onlyOwner {
        queryCacheTime = _queryCacheTime;
        maxQueryResults = _maxQueryResults;
        analyticsUpdateInterval = _analyticsUpdateInterval;
    }
}

// Helper library for string conversion
library Strings {
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
