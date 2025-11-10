// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ChainInfrastructure} from "../core/ChainInfrastructure.sol";
import {BlockchainExplorer} from "../core/BlockchainExplorer.sol";

/**
 * @title UnykornExplorer
 * @notice Complete blockchain explorer for Unykorn Layer 1 with privacy controls
 * @dev Provides comprehensive blockchain data access with role-based permissions
 */
contract UnykornExplorer is Ownable, ReentrancyGuard {

    enum DataType {
        TRANSACTION,
        BLOCK,
        CONTRACT,
        TOKEN,
        ADDRESS,
        GOVERNANCE,
        COMPLIANCE,
        ORACLE
    }

    enum TimeRange {
        HOUR_1,
        HOUR_24,
        DAY_7,
        DAY_30,
        ALL_TIME
    }

    struct ExplorerQuery {
        bytes32 queryId;
        address requester;
        DataType dataType;
        bytes32[] filters;
        TimeRange timeRange;
        ChainInfrastructure.PrivacyLevel privacyLevel;
        uint256 timestamp;
        uint256 resultCount;
        bytes32 ipfsResultHash;
        bool isRealTime;
    }

    struct BlockData {
        uint256 blockNumber;
        bytes32 blockHash;
        address miner;
        uint256 timestamp;
        uint256 gasUsed;
        uint256 gasLimit;
        uint256 transactionCount;
        bytes32[] transactionHashes;
        ChainInfrastructure.PrivacyLevel privacyLevel;
    }

    struct TransactionData {
        bytes32 txHash;
        uint256 blockNumber;
        uint256 transactionIndex;
        address from;
        address to;
        uint256 value;
        bytes data;
        uint256 gasUsed;
        uint256 gasPrice;
        bool success;
        string methodName;
        bytes32[] eventLogs;
        ChainInfrastructure.PrivacyLevel privacyLevel;
        uint256 timestamp;
    }

    struct ContractData {
        address contractAddress;
        string name;
        string description;
        string version;
        address deployer;
        uint256 deploymentBlock;
        uint256 size; // bytecode size
        bytes32 codeHash;
        bool isVerified;
        string compilerVersion;
        string[] functions;
        mapping(string => bytes32) functionSelectors;
        ChainInfrastructure.PrivacyLevel privacyLevel;
        bytes32 ipfsMetadataHash;
    }

    struct TokenData {
        address tokenAddress;
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        uint256 holders;
        uint256 transfers24h;
        uint256 volume24h;
        address owner;
        bool isVerified;
        ChainInfrastructure.PrivacyLevel privacyLevel;
        bytes32 ipfsMetadataHash;
    }

    struct AddressData {
        address accountAddress;
        uint256 balance;
        uint256 transactionCount;
        uint256 firstSeenBlock;
        uint256 lastSeenBlock;
        bool isContract;
        string contractType;
        ChainInfrastructure.PrivacyLevel privacyLevel;
        bytes32[] associatedTokens;
        bytes32[] recentTransactions;
    }

    struct NetworkStats {
        uint256 totalBlocks;
        uint256 totalTransactions;
        uint256 totalContracts;
        uint256 totalTokens;
        uint256 activeAddresses;
        uint256 tps24h;
        uint256 gasUsed24h;
        uint256 marketCap;
        uint256 tvl;
        bytes32[] topTokens;
        bytes32[] recentBlocks;
    }

    // Core references
    ChainInfrastructure public chainInfra;
    BlockchainExplorer public blockExplorer;

    // Data storage
    mapping(bytes32 => ExplorerQuery) public queries;
    mapping(uint256 => BlockData) public blocks;
    mapping(bytes32 => TransactionData) public transactions;
    mapping(address => ContractData) public contracts;
    mapping(address => TokenData) public tokens;
    mapping(address => AddressData) public addresses;

    // Statistics
    NetworkStats public networkStats;
    bytes32[] public recentQueries;
    bytes32[] public verifiedContracts;
    bytes32[] public verifiedTokens;

    // Configuration
    uint256 public queryCacheTime = 300; // 5 minutes
    uint256 public maxQueryResults = 1000;
    uint256 public realTimeUpdateInterval = 12; // 12 seconds
    uint256 public analyticsUpdateInterval = 3600; // 1 hour

    // Access control
    mapping(address => bool) public authorizedIndexers;
    mapping(address => ChainInfrastructure.PrivacyLevel) public userAccessLevel;

    // Events
    event ContractVerified(address indexed contractAddress, string name, string version);
    event TokenVerified(address indexed tokenAddress, string name, string symbol);
    event QueryExecuted(bytes32 indexed queryId, address requester, DataType dataType);
    event BlockIndexed(uint256 indexed blockNumber, uint256 transactionCount);
    event TransactionIndexed(bytes32 indexed txHash, address indexed from, address indexed to);
    event NetworkStatsUpdated(uint256 totalBlocks, uint256 totalTransactions);

    modifier onlyAuthorizedIndexer() {
        require(authorizedIndexers[msg.sender] || msg.sender == owner(), "Not authorized indexer");
        _;
    }

    modifier validAccess(address _user, ChainInfrastructure.PrivacyLevel _requiredLevel) {
        require(uint256(userAccessLevel[_user]) >= uint256(_requiredLevel), "Insufficient access level");
        _;
    }

    constructor(address _chainInfra, address _blockExplorer) Ownable(msg.sender) {
        chainInfra = ChainInfrastructure(_chainInfra);
        blockExplorer = BlockchainExplorer(_blockExplorer);
        authorizedIndexers[msg.sender] = true;
        userAccessLevel[msg.sender] = ChainInfrastructure.PrivacyLevel.PRIVATE;
    }

    /**
     * @notice Execute comprehensive explorer query
     */
    function executeQuery(
        DataType _dataType,
        bytes32[] memory _filters,
        TimeRange _timeRange,
        ChainInfrastructure.PrivacyLevel _privacyLevel,
        bool _realTime
    ) public validAccess(msg.sender, _privacyLevel) returns (bytes32) {
        bytes32 queryId = keccak256(abi.encodePacked(
            msg.sender, _dataType, _filters.length, _timeRange, block.timestamp
        ));

        ExplorerQuery storage query = queries[queryId];
        query.queryId = queryId;
        query.requester = msg.sender;
        query.dataType = _dataType;
        query.filters = _filters;
        query.timeRange = _timeRange;
        query.privacyLevel = _privacyLevel;
        query.timestamp = block.timestamp;
        query.isRealTime = _realTime;

        // Execute query based on type
        if (_dataType == DataType.TRANSACTION) {
            query.resultCount = _executeTransactionQuery(_filters, _timeRange);
        } else if (_dataType == DataType.BLOCK) {
            query.resultCount = _executeBlockQuery(_filters, _timeRange);
        } else if (_dataType == DataType.CONTRACT) {
            query.resultCount = _executeContractQuery(_filters, _timeRange);
        } else if (_dataType == DataType.TOKEN) {
            query.resultCount = _executeTokenQuery(_filters, _timeRange);
        } else if (_dataType == DataType.ADDRESS) {
            query.resultCount = _executeAddressQuery(_filters, _timeRange);
        }

        // Generate IPFS result hash (simplified)
        query.ipfsResultHash = keccak256(abi.encodePacked(queryId, block.timestamp));

        recentQueries.push(queryId);
        if (recentQueries.length > 1000) {
            // Keep only recent 1000 queries
            for (uint256 i = 0; i < 100; i++) {
                recentQueries.pop();
            }
        }

        emit QueryExecuted(queryId, msg.sender, _dataType);
        return queryId;
    }

    /**
     * @notice Index a block with all transactions
     */
    function indexBlock(
        uint256 _blockNumber,
        bytes32 _blockHash,
        address _miner,
        uint256 _timestamp,
        uint256 _gasUsed,
        uint256 _gasLimit,
        bytes32[] memory _transactionHashes
    ) public onlyAuthorizedIndexer {
        BlockData storage blockData = blocks[_blockNumber];
        blockData.blockNumber = _blockNumber;
        blockData.blockHash = _blockHash;
        blockData.miner = _miner;
        blockData.timestamp = _timestamp;
        blockData.gasUsed = _gasUsed;
        blockData.gasLimit = _gasLimit;
        blockData.transactionHashes = _transactionHashes;
        blockData.transactionCount = _transactionHashes.length;
        blockData.privacyLevel = ChainInfrastructure.PrivacyLevel.PUBLIC;

        networkStats.totalBlocks++;
        networkStats.recentBlocks.push(bytes32(_blockNumber));

        if (networkStats.recentBlocks.length > 100) {
            // Keep only recent 100 blocks
            for (uint256 i = 0; i < 10; i++) {
                networkStats.recentBlocks.pop();
            }
        }

        emit BlockIndexed(_blockNumber, _transactionHashes.length);
    }

    /**
     * @notice Index a transaction
     */
    function indexTransaction(
        bytes32 _txHash,
        uint256 _blockNumber,
        uint256 _transactionIndex,
        address _from,
        address _to,
        uint256 _value,
        bytes memory _data,
        uint256 _gasUsed,
        uint256 _gasPrice,
        bool _success,
        string memory _methodName,
        bytes32[] memory _eventLogs
    ) public onlyAuthorizedIndexer {
        TransactionData storage txData = transactions[_txHash];
        txData.txHash = _txHash;
        txData.blockNumber = _blockNumber;
        txData.transactionIndex = _transactionIndex;
        txData.from = _from;
        txData.to = _to;
        txData.value = _value;
        txData.data = _data;
        txData.gasUsed = _gasUsed;
        txData.gasPrice = _gasPrice;
        txData.success = _success;
        txData.methodName = _methodName;
        txData.eventLogs = _eventLogs;
        txData.timestamp = block.timestamp;
        txData.privacyLevel = ChainInfrastructure.PrivacyLevel.PUBLIC;

        networkStats.totalTransactions++;

        // Update address data
        _updateAddressData(_from);
        if (_to != address(0)) {
            _updateAddressData(_to);
        }

        emit TransactionIndexed(_txHash, _from, _to);
    }

    /**
     * @notice Verify and index a contract
     */
    function verifyContract(
        address _contractAddress,
        string memory _name,
        string memory _description,
        string memory _version,
        string memory _compilerVersion,
        string[] memory _functions,
        bytes32 _ipfsMetadataHash
    ) public onlyAuthorizedIndexer {
        ContractData storage contractData = contracts[_contractAddress];
        contractData.contractAddress = _contractAddress;
        contractData.name = _name;
        contractData.description = _description;
        contractData.version = _version;
        contractData.compilerVersion = _compilerVersion;
        contractData.functions = _functions;
        contractData.isVerified = true;
        contractData.ipfsMetadataHash = _ipfsMetadataHash;
        contractData.privacyLevel = ChainInfrastructure.PrivacyLevel.PUBLIC;

        // Get deployment info
        contractData.size = _contractAddress.code.length;
        contractData.codeHash = keccak256(_contractAddress.code);

        // Store function selectors
        for (uint256 i = 0; i < _functions.length; i++) {
            contractData.functionSelectors[_functions[i]] = keccak256(abi.encodePacked(_functions[i]));
        }

        verifiedContracts.push(bytes32(uint256(uint160(_contractAddress))));
        networkStats.totalContracts++;

        emit ContractVerified(_contractAddress, _name, _version);
    }

    /**
     * @notice Verify and index a token
     */
    function verifyToken(
        address _tokenAddress,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalSupply,
        address _owner,
        bytes32 _ipfsMetadataHash
    ) public onlyAuthorizedIndexer {
        TokenData storage tokenData = tokens[_tokenAddress];
        tokenData.tokenAddress = _tokenAddress;
        tokenData.name = _name;
        tokenData.symbol = _symbol;
        tokenData.decimals = _decimals;
        tokenData.totalSupply = _totalSupply;
        tokenData.owner = _owner;
        tokenData.isVerified = true;
        tokenData.ipfsMetadataHash = _ipfsMetadataHash;
        tokenData.privacyLevel = ChainInfrastructure.PrivacyLevel.PUBLIC;

        verifiedTokens.push(bytes32(uint256(uint160(_tokenAddress))));
        networkStats.totalTokens++;
        networkStats.topTokens.push(bytes32(uint256(uint160(_tokenAddress))));

        emit TokenVerified(_tokenAddress, _name, _symbol);
    }

    /**
     * @notice Update network statistics
     */
    function updateNetworkStats(
        uint256 _tps24h,
        uint256 _gasUsed24h,
        uint256 _marketCap,
        uint256 _tvl,
        uint256 _activeAddresses
    ) public onlyAuthorizedIndexer {
        networkStats.tps24h = _tps24h;
        networkStats.gasUsed24h = _gasUsed24h;
        networkStats.marketCap = _marketCap;
        networkStats.tvl = _tvl;
        networkStats.activeAddresses = _activeAddresses;

        emit NetworkStatsUpdated(networkStats.totalBlocks, networkStats.totalTransactions);
    }

    /**
     * @notice Get block data
     */
    function getBlockData(uint256 _blockNumber) public view
        returns (
            bytes32 blockHash,
            address miner,
            uint256 timestamp,
            uint256 gasUsed,
            uint256 gasLimit,
            uint256 transactionCount,
            bytes32[] memory transactionHashes
        )
    {
        BlockData memory blockData = blocks[_blockNumber];
        return (
            blockData.blockHash,
            blockData.miner,
            blockData.timestamp,
            blockData.gasUsed,
            blockData.gasLimit,
            blockData.transactionCount,
            blockData.transactionHashes
        );
    }

    /**
     * @notice Get transaction data
     */
    function getTransactionData(bytes32 _txHash) public view
        returns (
            uint256 blockNumber,
            address from,
            address to,
            uint256 value,
            uint256 gasUsed,
            uint256 gasPrice,
            bool success,
            string memory methodName,
            ChainInfrastructure.PrivacyLevel privacyLevel
        )
    {
        TransactionData memory txData = transactions[_txHash];
        return (
            txData.blockNumber,
            txData.from,
            txData.to,
            txData.value,
            txData.gasUsed,
            txData.gasPrice,
            txData.success,
            txData.methodName,
            txData.privacyLevel
        );
    }

    /**
     * @notice Get contract data
     */
    function getContractData(address _contractAddress) public view
        returns (
            string memory name,
            string memory description,
            string memory version,
            address deployer,
            bool isVerified,
            string[] memory functions,
            ChainInfrastructure.PrivacyLevel privacyLevel
        )
    {
        ContractData storage contractData = contracts[_contractAddress];
        return (
            contractData.name,
            contractData.description,
            contractData.version,
            contractData.deployer,
            contractData.isVerified,
            contractData.functions,
            contractData.privacyLevel
        );
    }

    /**
     * @notice Get token data
     */
    function getTokenData(address _tokenAddress) public view
        returns (
            string memory name,
            string memory symbol,
            uint8 decimals,
            uint256 totalSupply,
            uint256 holders,
            uint256 transfers24h,
            uint256 volume24h,
            bool isVerified,
            ChainInfrastructure.PrivacyLevel privacyLevel
        )
    {
        TokenData memory tokenData = tokens[_tokenAddress];
        return (
            tokenData.name,
            tokenData.symbol,
            tokenData.decimals,
            tokenData.totalSupply,
            tokenData.holders,
            tokenData.transfers24h,
            tokenData.volume24h,
            tokenData.isVerified,
            tokenData.privacyLevel
        );
    }

    /**
     * @notice Get address data
     */
    function getAddressData(address _accountAddress) public view
        returns (
            uint256 balance,
            uint256 transactionCount,
            bool isContract,
            string memory contractType,
            ChainInfrastructure.PrivacyLevel privacyLevel,
            bytes32[] memory recentTransactions
        )
    {
        AddressData memory addressData = addresses[_accountAddress];
        return (
            addressData.balance,
            addressData.transactionCount,
            addressData.isContract,
            addressData.contractType,
            addressData.privacyLevel,
            addressData.recentTransactions
        );
    }

    /**
     * @notice Get network statistics
     */
    function getNetworkStats() public view
        returns (
            uint256 totalBlocks,
            uint256 totalTransactions,
            uint256 totalContracts,
            uint256 totalTokens,
            uint256 activeAddresses,
            uint256 tps24h,
            uint256 gasUsed24h,
            uint256 marketCap,
            uint256 tvl
        )
    {
        return (
            networkStats.totalBlocks,
            networkStats.totalTransactions,
            networkStats.totalContracts,
            networkStats.totalTokens,
            networkStats.activeAddresses,
            networkStats.tps24h,
            networkStats.gasUsed24h,
            networkStats.marketCap,
            networkStats.tvl
        );
    }

    /**
     * @notice Get recent blocks
     */
    function getRecentBlocks(uint256 _limit) public view
        returns (uint256[] memory blockNumbers, bytes32[] memory blockHashes, uint256[] memory timestamps)
    {
        uint256 count = _limit > networkStats.recentBlocks.length ? networkStats.recentBlocks.length : _limit;
        uint256[] memory numbers = new uint256[](count);
        bytes32[] memory hashes = new bytes32[](count);
        uint256[] memory times = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 blockNum = uint256(networkStats.recentBlocks[networkStats.recentBlocks.length - 1 - i]);
            numbers[i] = blockNum;
            hashes[i] = blocks[blockNum].blockHash;
            times[i] = blocks[blockNum].timestamp;
        }

        return (numbers, hashes, times);
    }

    /**
     * @notice Get top tokens
     */
    function getTopTokens(uint256 _limit) public view
        returns (address[] memory tokenAddresses, string[] memory names, string[] memory symbols)
    {
        uint256 count = _limit > networkStats.topTokens.length ? networkStats.topTokens.length : _limit;
        address[] memory addresses_ = new address[](count);
        string[] memory names_ = new string[](count);
        string[] memory symbols_ = new string[](count);

        for (uint256 i = 0; i < count; i++) {
            address tokenAddr = address(uint160(uint256(networkStats.topTokens[i])));
            addresses_[i] = tokenAddr;
            names_[i] = tokens[tokenAddr].name;
            symbols_[i] = tokens[tokenAddr].symbol;
        }

        return (addresses_, names_, symbols_);
    }

    /**
     * @notice Search contracts by name
     */
    function searchContracts(string memory _searchTerm, uint256 _limit) public view
        returns (address[] memory contractAddresses, string[] memory names)
    {
        // Simplified search - in production would use more sophisticated indexing
        address[] memory results = new address[](10);
        string[] memory resultNames = new string[](10);
        uint256 found = 0;

        for (uint256 i = 0; i < verifiedContracts.length && found < 10; i++) {
            address contractAddr = address(uint160(uint256(verifiedContracts[i])));
            ContractData storage contractData = contracts[contractAddr];

            // Simple string matching
            if (_containsString(contractData.name, _searchTerm)) {
                results[found] = contractAddr;
                resultNames[found] = contractData.name;
                found++;
            }
        }

        // Trim arrays to actual results
        address[] memory finalAddresses = new address[](found);
        string[] memory finalNames = new string[](found);

        for (uint256 i = 0; i < found; i++) {
            finalAddresses[i] = results[i];
            finalNames[i] = resultNames[i];
        }

        return (finalAddresses, finalNames);
    }

    /**
     * @notice Set user access level
     */
    function setUserAccessLevel(address _user, ChainInfrastructure.PrivacyLevel _level) public onlyOwner {
        userAccessLevel[_user] = _level;
    }

    /**
     * @notice Authorize indexer
     */
    function authorizeIndexer(address _indexer, bool _authorized) public onlyOwner {
        authorizedIndexers[_indexer] = _authorized;
    }

    /**
     * @notice Update configuration
     */
    function updateConfiguration(
        uint256 _queryCacheTime,
        uint256 _maxQueryResults,
        uint256 _realTimeUpdateInterval,
        uint256 _analyticsUpdateInterval
    ) public onlyOwner {
        queryCacheTime = _queryCacheTime;
        maxQueryResults = _maxQueryResults;
        realTimeUpdateInterval = _realTimeUpdateInterval;
        analyticsUpdateInterval = _analyticsUpdateInterval;
    }

    // Internal functions
    function _executeTransactionQuery(bytes32[] memory _filters, TimeRange _timeRange) internal pure returns (uint256) {
        // Simplified - would execute actual query logic
        return _filters.length * 10; // Mock result count
    }

    function _executeBlockQuery(bytes32[] memory _filters, TimeRange _timeRange) internal pure returns (uint256) {
        return _filters.length * 5; // Mock result count
    }

    function _executeContractQuery(bytes32[] memory _filters, TimeRange _timeRange) internal view returns (uint256) {
        return verifiedContracts.length; // Return verified contracts count
    }

    function _executeTokenQuery(bytes32[] memory _filters, TimeRange _timeRange) internal view returns (uint256) {
        return verifiedTokens.length; // Return verified tokens count
    }

    function _executeAddressQuery(bytes32[] memory _filters, TimeRange _timeRange) internal pure returns (uint256) {
        return _filters.length * 2; // Mock result count
    }

    function _updateAddressData(address _address) internal {
        AddressData storage addressData = addresses[_address];
        addressData.accountAddress = _address;
        addressData.transactionCount++;
        addressData.isContract = _address.code.length > 0;

        if (addressData.firstSeenBlock == 0) {
            addressData.firstSeenBlock = block.number;
        }
        addressData.lastSeenBlock = block.number;
        addressData.privacyLevel = ChainInfrastructure.PrivacyLevel.PUBLIC;
    }

    function _containsString(string memory _haystack, string memory _needle) internal pure returns (bool) {
        bytes memory haystack = bytes(_haystack);
        bytes memory needle = bytes(_needle);

        if (needle.length > haystack.length) {
            return false;
        }

        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }
        return false;
    }
}
