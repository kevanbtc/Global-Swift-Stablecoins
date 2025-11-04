// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/oracle/AttestationOracle.sol";
import "../../contracts/oracle/NAVEventOracleUpgradeable.sol";

/// Invariant scaffolds for oracle safety (staleness, bands, committees).
contract OracleInvariants is Test {
    // Intentionally not deploying heavy graphs yet; wire up stubs first.

    // Prices/appraisals should respect staleness and quorum rules before use.
    function invariant_StalenessGuard() external view {
        // TODO: assert max age windows respected
    }

    // Circuit breakers should prevent out-of-band moves.
    function invariant_CircuitBreakers() external view {
        // TODO: assert banded changes; medianization where applicable
    }
}
