// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IQuoteAdapter} from "../../interfaces/IQuoteAdapter.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

/// @title ChainlinkQuoteAdapter
/// @notice Returns USD quotes for registered instruments via Chainlink Aggregators.
///         Normalizes to 18 decimals. Freshness checking by timestamp.
contract ChainlinkQuoteAdapter is IQuoteAdapter, AccessControl {
    bytes32 public constant ADMIN = keccak256("ADMIN");

    struct Feed {
        address aggregator;
        uint64 maxAgeSec; // advisory default freshness for this instrument
    }

    // instrument => feed
    mapping(address => Feed) public feeds;

    event FeedSet(address indexed instrument, address aggregator, uint64 maxAgeSec);

    constructor(address governor) {
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(ADMIN, governor);
    }

    function setFeed(address instrument, address aggregator, uint64 maxAgeSec) external onlyRole(ADMIN) {
        require(instrument != address(0) && aggregator != address(0), "bad_addr");
        feeds[instrument] = Feed(aggregator, maxAgeSec);
        emit FeedSet(instrument, aggregator, maxAgeSec);
    }

    /// @inheritdoc IQuoteAdapter
    function quoteInCash(address instrument) external view returns (uint256 price, uint8 decimals, uint64 lastUpdate) {
        Feed memory f = feeds[instrument];
        require(f.aggregator != address(0), "no_feed");

        ( , int256 ans, , uint256 updatedAt, ) = AggregatorV3Interface(f.aggregator).latestRoundData();
        require(ans > 0, "bad_answer");

        uint8 d = AggregatorV3Interface(f.aggregator).decimals();
        // normalize to 18
        if (d <= 18) {
            price = uint256(ans) * (10 ** (18 - d));
            decimals = 18;
        } else {
            // extremely rare; downscale
            price = uint256(ans) / (10 ** (d - 18));
            decimals = 18;
        }
        lastUpdate = uint64(updatedAt);
    }

    /// @inheritdoc IQuoteAdapter
    function isFresh(address instrument, uint64 maxAgeSec) external view returns (bool) {
        Feed memory f = feeds[instrument];
        require(f.aggregator != address(0), "no_feed");
        ( , , , uint256 updatedAt, ) = AggregatorV3Interface(f.aggregator).latestRoundData();
        uint64 age = uint64(block.timestamp) - uint64(updatedAt);
        uint64 limit = (maxAgeSec > 0) ? maxAgeSec : f.maxAgeSec;
        return limit == 0 ? true : age <= limit;
    }
}
