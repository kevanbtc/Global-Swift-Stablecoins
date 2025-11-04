// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/mica/ReserveManagerUpgradeable.sol";
import "../contracts/compliance/ComplianceRegistryUpgradeable.sol";
import "../contracts/compliance/PolicyEngineUpgradeable.sol";
import "../contracts/token/InstitutionalEMTUpgradeable.sol";

contract Invariants is Test {
    ReserveManagerUpgradeable rm;
    ComplianceRegistryUpgradeable reg;
    PolicyEngineUpgradeable pol;
    InstitutionalEMTUpgradeable token;

    address admin = address(this);
    address gov   = address(0xBEEF);

    function setUp() public {
        rm = new ReserveManagerUpgradeable(); rm.initialize(admin, gov);
        reg = new ComplianceRegistryUpgradeable(); reg.initialize(admin, gov);
        pol = new PolicyEngineUpgradeable(); pol.initialize(admin, gov, address(reg), address(0));
        token = new InstitutionalEMTUpgradeable(); token.initialize(admin, gov, "USDU", "USDU", address(pol));
    }

    function test_set_and_cover() public {
        vm.prank(gov); rm.setLimit(ReserveManagerUpgradeable.Bucket.T_BILLS, 10_000);
        uint256[5] memory by = [uint256(90e6), 5e6, 3e6, 2e6, 0];
        vm.prank(gov); rm.grantRole(rm.ATTESTOR_ROLE(), address(this));
        rm.attest(100e6, by, uint64(block.timestamp), keccak256("cid"));
        assertEq(rm.coverageBps(100e6), 10_000);
    }
}
