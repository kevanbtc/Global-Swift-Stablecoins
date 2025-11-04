// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {RailRegistry} from "contracts/settlement/rails/RailRegistry.sol";
import {ERC20Rail} from "contracts/settlement/rails/ERC20Rail.sol";
import {NativeRail} from "contracts/settlement/rails/NativeRail.sol";
import {ExternalRail} from "contracts/settlement/rails/ExternalRail.sol";
import {SettlementHub2PC} from "contracts/settlement/SettlementHub2PC.sol";
import {KYCRegistry} from "contracts/compliance/KYCRegistry.sol";
import {SanctionsOracleDenylist} from "contracts/compliance/SanctionsOracleDenylist.sol";
import {ComplianceModuleRBAC} from "contracts/compliance/ComplianceModuleRBAC.sol";
import {Iso20022Bridge} from "contracts/iso20022/Iso20022Bridge.sol";

contract DeploySettlement is Script {
    function run() external {
        vm.startBroadcast();
        address admin = msg.sender;

        // Compliance suite
        KYCRegistry kyc = new KYCRegistry(admin);
        SanctionsOracleDenylist so = new SanctionsOracleDenylist(admin);
        ComplianceModuleRBAC cm = new ComplianceModuleRBAC(admin, address(kyc), address(so));

        // ISO binding
        Iso20022Bridge iso = new Iso20022Bridge(admin);

        // Rails and registry
        RailRegistry registry = new RailRegistry(admin);
        ERC20Rail r20 = new ERC20Rail(admin);
        NativeRail rnat = new NativeRail(admin);
        ExternalRail rx = new ExternalRail(admin, admin); // set executor later if distinct
        registry.set(keccak256("RAIL_ERC20"), address(r20));
        registry.set(keccak256("RAIL_NATIVE"), address(rnat));
        registry.set(keccak256("RAIL_EXTERNAL"), address(rx));

        // Hub
        SettlementHub2PC hub = new SettlementHub2PC(admin, address(registry));

        // Silence warnings about unused vars in Script context
        hub; cm; iso;

        vm.stopBroadcast();
    }
}
