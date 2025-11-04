// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IQuoteAdapter} from "../../interfaces/IQuoteAdapter.sol";

/// @title HybridQuoteAdapter
/// @notice Tries primary adapter, then secondary adapter. Both must implement IQuoteAdapter.
///         Useful to chain Chainlink -> Pyth fallback, or vice versa.
contract HybridQuoteAdapter is IQuoteAdapter, AccessControl {
    bytes32 public constant ADMIN = keccak256("ADMIN");

    IQuoteAdapter public primary;
    IQuoteAdapter public secondary;

    event PrimarySet(address adapter);
    event SecondarySet(address adapter);

    constructor(address governor, address _primary, address _secondary) {
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(ADMIN, governor);
        primary = IQuoteAdapter(_primary);
        secondary = IQuoteAdapter(_secondary);
        emit PrimarySet(_primary);
        emit SecondarySet(_secondary);
    }

    function setPrimary(address a) external onlyRole(ADMIN) { primary = IQuoteAdapter(a); emit PrimarySet(a); }
    function setSecondary(address a) external onlyRole(ADMIN) { secondary = IQuoteAdapter(a); emit SecondarySet(a); }

    function quoteInCash(address instrument) external view returns (uint256 price, uint8 decimals, uint64 lastUpdate) {
        // try primary
        try primary.quoteInCash(instrument) returns (uint256 p, uint8 d, uint64 t) {
            if (p > 0) return (p, d, t);
        } catch {}
        // fallback
        try secondary.quoteInCash(instrument) returns (uint256 p2, uint8 d2, uint64 t2) {
            if (p2 > 0) return (p2, d2, t2);
        } catch {}
        revert("no_quote");
    }

    function isFresh(address instrument, uint64 maxAgeSec) external view returns (bool) {
        bool f1 = false;
        bool f2 = false;
        try primary.isFresh(instrument, maxAgeSec) returns (bool ok) { f1 = ok; } catch {}
        try secondary.isFresh(instrument, maxAgeSec) returns (bool ok2) { f2 = ok2; } catch {}
        return f1 || f2;
    }
}
