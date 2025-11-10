// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ISO20022EventEmitter
/// @notice Emits canonical events for off-chain ISO 20022 gateways to consume and translate into XML messages.
contract ISO20022EventEmitter is AccessControl {
    bytes32 public constant ROLE_PUBLISHER = keccak256("ROLE_PUBLISHER");
    bytes32 public constant ROLE_ADMIN     = keccak256("ROLE_ADMIN");

    event Pacs008Payment(
        bytes32 indexed correlationId,
        address indexed payer,
        address indexed payee,
        uint256 amount,         // in minor units (e.g., cents)
        string  ccy,            // "USD"
        string  debtorIban,     // optional
        string  creditorIban,   // optional
        string  purpose,        // ISO purpose code or free text
        uint64  valueDate,      // yyyy-mm-dd as unix (00:00 UTC)
        uint64  createdAt
    );

    event Camt053Statement(
        bytes32 indexed correlationId,
        string  accountRef,
        int256  bookingAmount,  // signed
        string  ccy,
        string  txnRef,
        string  narrative,
        uint64  bookingDate,
        uint64  createdAt
    );

    event Sese023SecuritiesSettlement(
        bytes32 indexed correlationId,
        string  isinOrCusip,
        string  side,           // "BUY"/"SELL"
        uint256 quantity,
        uint256 priceMinor,     // minor units
        string  ccy,
        string  accountRef,
        uint64  settlementDate,
        uint64  createdAt
    );

    constructor(address admin) {
        _grantRole(ROLE_ADMIN, admin);
        _grantRole(ROLE_PUBLISHER, admin);
    }

    function publishPacs008(
        bytes32 correlationId,
        address payer,
        address payee,
        uint256 amountMinor,
        string calldata ccy,
        string calldata debtorIban,
        string calldata creditorIban,
        string calldata purpose,
        uint64  valueDate
    ) public onlyRole(ROLE_PUBLISHER) {
        emit Pacs008Payment(
            correlationId, payer, payee, amountMinor, ccy, debtorIban, creditorIban, purpose, valueDate, uint64(block.timestamp)
        );
    }

    function publishCamt053(
        bytes32 correlationId,
        string calldata accountRef,
        int256 bookingAmountMinor,
        string calldata ccy,
        string calldata txnRef,
        string calldata narrative,
        uint64  bookingDate
    ) public onlyRole(ROLE_PUBLISHER) {
        emit Camt053Statement(
            correlationId, accountRef, bookingAmountMinor, ccy, txnRef, narrative, bookingDate, uint64(block.timestamp)
        );
    }

    function publishSese023(
        bytes32 correlationId,
        string calldata isinOrCusip,
        string calldata side,
        uint256 quantity,
        uint256 priceMinor,
        string calldata ccy,
        string calldata accountRef,
        uint64  settlementDate
    ) public onlyRole(ROLE_PUBLISHER) {
        emit Sese023SecuritiesSettlement(
            correlationId, isinOrCusip, side, quantity, priceMinor, ccy, accountRef, settlementDate, uint64(block.timestamp)
        );
    }
}
