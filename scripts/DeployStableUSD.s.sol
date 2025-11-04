// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {StableUSD} from "../contracts/stable/StableUSD.sol";

contract DeployStableUSD is Script {
    function run() external {
        address governor = vm.envAddress("GOVERNOR");
        address guardian = vm.envAddress("GUARDIAN");
        address guard    = vm.envAddress("POLICY_GUARD");
        address attest   = vm.envAddress("ATTEST_REG");
        address vault    = vm.envAddress("RESERVE_VAULT");

        vm.startBroadcast();

        StableUSD s = new StableUSD();
        s.initialize(governor, guardian, "Unykorn USD", "uUSD");
        s.bind(guard, attest, vault);

        vm.stopBroadcast();

        console2.log("StableUSD:", address(s));
    }
}
