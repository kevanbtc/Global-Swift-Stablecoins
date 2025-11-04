// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library StableErrors {
    error NotAuthorized();
    error Paused();
    error ComplianceBlocked();
    error ReserveRatioBreach();
    error StaleOracle();
    error CollateralTypeNotFound();
    error SafeCheckFailed();
    error InsufficientBalance();
}
