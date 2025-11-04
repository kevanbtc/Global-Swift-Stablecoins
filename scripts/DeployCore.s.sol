// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {PolicyGuard} from "../contracts/policy/PolicyGuard.sol";
import {AttestationRegistry} from "../contracts/attest/AttestationRegistry.sol";
import {OracleCommittee} from "../contracts/oracle/OracleCommittee.sol";
import {ReserveVault} from "../contracts/reserves/ReserveVault.sol";

contract DeployCore is Script {
    function run() external {
        address governor = vm.envAddress("GOVERNOR");
        address guardian = vm.envAddress("GUARDIAN");
        address cashToken = vm.envAddress("CASH_TOKEN"); // optional or 0x0
        uint8   cashDec   = uint8(vm.envUint("CASH_DECIMALS")); // e.g., 6

        vm.startBroadcast();

        PolicyGuard guard = new PolicyGuard();
        guard.initialize(governor, guardian);

        AttestationRegistry attest = new AttestationRegistry();
        attest.initialize(governor);

        OracleCommittee oracle = new OracleCommittee();
        oracle.initialize(governor, /*minSigners*/2, /*maxAgeSec*/ 24 hours);

        ReserveVault vault = new ReserveVault();
        vault.initialize(governor, guardian, address(guard), address(oracle), cashToken, cashDec);

        vm.stopBroadcast();

        console2.log("PolicyGuard   :", address(guard));
        console2.log("AttestRegistry:", address(attest));
        console2.log("OracleCommittee:", address(oracle));
        console2.log("ReserveVault  :", address(vault));
    }
}
