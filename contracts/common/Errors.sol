// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @notice Canonical minimal error library for the treasury platform
library Errors {
    error Unauthorized();
    error NotAuthorized();
    error InvalidParam();
    error NotReady();
    error Expired();
    error Stale();
    error Paused();
    error Replay();
    error Signature();
    error Sanctioned();
    error JurisdictionBlocked();
    // Additional platform-wide errors used across modules
    error Frozen();
    error InvestorClassBlocked();
    error LockupActive();
    error PositionCapExceeded();
    error GlobalPause();
    error CourtOrderActive();
    error ConcentrationBreach();
    error AttestationInvalid();
    error UnsafeUpgrade();
}
