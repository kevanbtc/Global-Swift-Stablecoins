// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../../contracts/oracle/AttestationOracle.sol";
import "../../../contracts/oracle/NAVEventOracleUpgradeable.sol";

/// Invariant scaffolds for oracle safety (staleness, bands, committees).
contract OracleInvariants is Test {
    AttestationOracle att;
    NAVEventOracleUpgradeable nav;

    function setUp() public {
        // Deploy minimal oracle instances and register them as fuzz targets
        att = new AttestationOracle(address(this));
        nav = new NAVEventOracleUpgradeable();
        nav.initialize(address(this), address(this));
        // mark targets for the invariant fuzzer
        targetContract(address(att));
        targetContract(address(nav));
    }
    // Prices/appraisals should respect staleness and quorum rules before use.
    function invariant_StalenessGuard() external view {
        // TODO: assert max age windows respected
    }

    // Circuit breakers should prevent out-of-band moves.
    function invariant_CircuitBreakers() external view {
        // TODO: assert banded changes; medianization where applicable
    }
}
