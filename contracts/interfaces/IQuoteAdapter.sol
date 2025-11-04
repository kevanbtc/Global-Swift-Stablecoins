// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice External quoting adapter (e.g., Chainlink/CCIP/Pyth/OFF-CHAIN signer)
///         Used to sanity-check price/px-to-NAV and slippage for deposits/withdrawals.
interface IQuoteAdapter {
    /// @dev return quote for vault or asset expressed in cash units (1eX) and lastUpdate ts
    function quoteInCash(address instrument) external view returns (uint256 price, uint8 decimals, uint64 lastUpdate);
    /// @dev return true if quote freshness is acceptable
    function isFresh(address instrument, uint64 maxAgeSec) external view returns (bool);
}
