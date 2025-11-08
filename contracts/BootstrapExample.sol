// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PolicyRoles} from "./governance/PolicyRoles.sol";
import {IComplianceRegistry} from "./interfaces/IComplianceRegistry.sol";
import {IAttestationOracle} from "./interfaces/IAttestationOracle.sol";
import {IProofOfReserves} from "./interfaces/IProofOfReserves.sol";
import {ComplianceRegistryUpgradeable} from "./compliance/ComplianceRegistryUpgradeable.sol";
import {AttestationOracle} from "./oracle/AttestationOracle.sol";
import {ReserveManager} from "./reserves/ReserveManager.sol";
import {RWAVaultNFT} from "./rwa/RWAVaultNFT.sol";
import {RWASecurityToken} from "./token/RWASecurityToken.sol";
import {SuretyBondNFT} from "./surety/SuretyBondNFT.sol";
import {SBLC721} from "./surety/SBLC721.sol";
import {InsurancePolicyNFT} from "./insurance/InsurancePolicyNFT.sol";

/// @title BootstrapExample
/// @notice One-shot deployer wiring all singletons with roles and initial configs
contract BootstrapExample {
    address public immutable admin;
    IComplianceRegistry public compliance;
    IAttestationOracle public oracle;
    IProofOfReserves public reserves;
    RWAVaultNFT public vault;
    RWASecurityToken public security;
    SuretyBondNFT public surety;
    SBLC721 public sblc;
    InsurancePolicyNFT public insurance;

    constructor(address _admin) {
        require(_admin != address(0), "admin=0");
        admin = _admin;
    }

    function deployAll() public {
        require(msg.sender == admin, "only admin");
        require(address(compliance) == address(0), "already deployed");

        // 1. Core contracts
        compliance = IComplianceRegistry(address(new ComplianceRegistryUpgradeable()));
        ComplianceRegistryUpgradeable(address(compliance)).initialize(admin);

        oracle = IAttestationOracle(address(new AttestationOracle(admin)));
        reserves = IProofOfReserves(address(new ReserveManager(admin, oracle)));

        // 2. RWA contracts
        vault = new RWAVaultNFT(admin);
        security = new RWASecurityToken(
            "RWA Security",
            "RWA-SEC",
            admin,
            compliance,
            keccak256("DEFAULT_PARTITION")
        );

        // 3. Instrument contracts
        surety = new SuretyBondNFT(admin);
        sblc = new SBLC721(admin);
        insurance = new InsurancePolicyNFT(admin);
    }

    // Example configuration helpers
    function configureExample() public {
        require(msg.sender == admin, "only admin");
        require(address(compliance) != address(0), "not deployed");

        // Example: set up a reserve with quorum
        bytes32 reserveId = keccak256("EXAMPLE_RESERVE");
        address[] memory signers = new address[](3);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        signers[2] = address(0x3);
        AttestationOracle(address(oracle)).setQuorum(reserveId, 2, signers);

        // Example: register reserve with custodian
        address[] memory assets = new address[](1);
        assets[0] = address(security); // the security token itself as reserve
        ReserveManager(address(reserves)).registerReserve(reserveId, address(0x123), assets);

        // Example: KYC a test address (construct Profile struct per current registry schema)
        ComplianceRegistryUpgradeable.Profile memory prof = ComplianceRegistryUpgradeable.Profile({
            kyc: true,
            accredited: false,
            kycAsOf: uint64(block.timestamp),
            kycExpiry: 0,
            isoCountry: "US",
            frozen: false
        });
        ComplianceRegistryUpgradeable(address(compliance)).setProfile(address(0x456), prof);
    }
}
