// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {InstitutionalEMTUpgradeable} from "../contracts/token/InstitutionalEMTUpgradeable.sol";
import {ComplianceRegistryUpgradeable} from "../contracts/compliance/ComplianceRegistryUpgradeable.sol";
import {PolicyEngineUpgradeable} from "../contracts/compliance/PolicyEngineUpgradeable.sol";
import {CourtOrderRegistryUpgradeable} from "../contracts/controller/CourtOrderRegistryUpgradeable.sol";
import {ReserveManagerUpgradeable} from "../contracts/mica/ReserveManagerUpgradeable.sol";
import {NAVEventOracleUpgradeable} from "../contracts/oracle/NAVEventOracleUpgradeable.sol";
import {MerkleStreamDistributorUpgradeable} from "../contracts/distribution/MerkleStreamDistributorUpgradeable.sol";

contract Deploy_Prod is Script {
    function run() external {
        address admin    = vm.envAddress("ADMIN");
        address governor = vm.envAddress("GOVERNOR");

        vm.startBroadcast();

        // Core registries
        ComplianceRegistryUpgradeable reg = new ComplianceRegistryUpgradeable();
    reg.initialize(admin);

        CourtOrderRegistryUpgradeable court = new CourtOrderRegistryUpgradeable();
    court.initialize(admin, governor);

        // Policy
        PolicyEngineUpgradeable policy = new PolicyEngineUpgradeable();
        policy.initialize(admin, governor, address(reg), address(court));

        // Token
        InstitutionalEMTUpgradeable emt = new InstitutionalEMTUpgradeable();
        emt.initialize(admin, governor, "Unykorn USD", "USDU", address(policy));

        // Reserves & NAV
        ReserveManagerUpgradeable rm = new ReserveManagerUpgradeable();
        rm.initialize(admin, governor);

        NAVEventOracleUpgradeable nav = new NAVEventOracleUpgradeable();
        nav.initialize(admin, governor);

        // Distributor
        MerkleStreamDistributorUpgradeable dist = new MerkleStreamDistributorUpgradeable();
        dist.initialize(admin, governor);

        vm.stopBroadcast();

        console2.log("ComplianceRegistry:", address(reg));
        console2.log("CourtOrderRegistry:", address(court));
        console2.log("PolicyEngine:", address(policy));
        console2.log("EMT:", address(emt));
        console2.log("ReserveManager:", address(rm));
        console2.log("NAVOracle:", address(nav));
        console2.log("Distributor:", address(dist));
    }
}
