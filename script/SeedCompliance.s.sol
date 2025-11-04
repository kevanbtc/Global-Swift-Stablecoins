// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {AccessRegistryUpgradeable} from "../contracts/compliance/AccessRegistryUpgradeable.sol";

contract SeedCompliance is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address admin = vm.addr(pk);
        address governor = vm.envAddress("GOVERNOR");

        vm.startBroadcast(pk);
        AccessRegistryUpgradeable reg = new AccessRegistryUpgradeable();
        reg.initialize(admin, governor, "TBAC");

        // example allow US (840), block nothing initially
        reg.setJurisdictionBlocked(0, false);

        console2.log("TBAC deployed", address(reg));
        vm.stopBroadcast();
    }
}
