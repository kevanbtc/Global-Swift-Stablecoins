// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import explorer contracts
import {UnukornExplorer} from "../contracts/explorer/UnukornExplorer.sol";
import {ChainInfrastructure} from "../contracts/core/ChainInfrastructure.sol";
import {BlockchainExplorer} from "../contracts/core/BlockchainExplorer.sol";

contract DeployExplorer is Script {

    // Deployed contract addresses (from previous deployment)
    address public constant CHAIN_INFRA = 0x4567890123456789012345678901234567890123;
    address public constant BLOCK_EXPLORER = 0x5678901234567890123456789012345678901234;

    // New deployment addresses
    UnukornExplorer public unykornExplorer;

    function run() external {
        vm.startBroadcast();

        console.log("========================================");
        console.log("DEPLOYING UNYKORN EXPLORER");
        console.log("========================================");
        console.log("");

        console.log("Chain Infrastructure:", CHAIN_INFRA);
        console.log("Blockchain Explorer:", BLOCK_EXPLORER);
        console.log("");

        // Deploy Unykorn Explorer
        console.log("Deploying UnykornExplorer...");
        unykornExplorer = new UnukornExplorer(CHAIN_INFRA, BLOCK_EXPLORER);
        console.log("UnukornExplorer deployed at:", address(unykornExplorer));
        console.log("");

        // Initialize explorer with sample data
        console.log("Initializing explorer with sample data...");

        // Index sample contracts
        _indexSampleContracts();

        // Index sample tokens
        _indexSampleTokens();

        // Update network stats
        _updateNetworkStats();

        console.log("Explorer initialization complete!");
        console.log("");

        console.log("========================================");
        console.log("EXPLORER DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("Unykorn Explorer:", address(unykornExplorer));
        console.log("Chain Infrastructure:", CHAIN_INFRA);
        console.log("Blockchain Explorer:", BLOCK_EXPLORER);
        console.log("");
        console.log("Features:");
        console.log("- Real-time blockchain data");
        console.log("- Privacy-aware access control");
        console.log("- Contract verification");
        console.log("- Token analytics");
        console.log("- Network statistics");
        console.log("- Advanced search capabilities");
        console.log("");

        console.log("Access URLs:");
        console.log("- Explorer: https://explorer.unykorn.layer1.network");
        console.log("- API: https://api.unykorn.layer1.network");
        console.log("- WebSocket: wss://ws.unykorn.layer1.network");
        console.log("");

        console.log("========================================");
        console.log("EXPLORER READY FOR USE");
        console.log("========================================");

        vm.stopBroadcast();
    }

    function _indexSampleContracts() internal {
        console.log("Indexing sample contracts...");

        // Index DNA Core
        string[] memory dnaFunctions = new string[](10);
        dnaFunctions[0] = "initializeNucleus";
        dnaFunctions[1] = "addChromosome";
        dnaFunctions[2] = "activateGene";
        dnaFunctions[3] = "getNucleusStatus";
        dnaFunctions[4] = "setAISwarmCoordinator";
        dnaFunctions[5] = "emergencyShutdown";
        dnaFunctions[6] = "emergencyRestart";
        dnaFunctions[7] = "updateGenomeHash";
        dnaFunctions[8] = "getChromosome";
        dnaFunctions[9] = "getGene";

        unykornExplorer.verifyContract(
            0x1234567890123456789012345678901234567890,
            "Unykorn DNA Core",
            "Central DNA helix managing all system genes and chromosomes",
            "1.0.0",
            "0.8.24",
            dnaFunctions,
            keccak256(abi.encodePacked("DNA Core metadata"))
        );

        // Index Compliance Registry
        string[] memory complianceFunctions = new string[](8);
        complianceFunctions[0] = "setPolicy";
        complianceFunctions[1] = "setProfile";
        complianceFunctions[2] = "getProfile";
        complianceFunctions[3] = "isUserCompliant";
        complianceFunctions[4] = "addJurisdiction";
        complianceFunctions[5] = "updateProfile";
        complianceFunctions[6] = "freezeProfile";
        complianceFunctions[7] = "getComplianceStatus";

        unykornExplorer.verifyContract(
            0x8901234567890123456789012345678901234567,
            "Compliance Registry",
            "Regulatory compliance and KYC management system",
            "1.0.0",
            "0.8.24",
            complianceFunctions,
            keccak256(abi.encodePacked("Compliance Registry metadata"))
        );

        // Index Stablecoin
        string[] memory tokenFunctions = new string[](12);
        tokenFunctions[0] = "mint";
        tokenFunctions[1] = "burn";
        tokenFunctions[2] = "transfer";
        tokenFunctions[3] = "transferFrom";
        tokenFunctions[4] = "approve";
        tokenFunctions[5] = "allowance";
        tokenFunctions[6] = "balanceOf";
        tokenFunctions[7] = "totalSupply";
        tokenFunctions[8] = "rebase";
        tokenFunctions[9] = "getRebaseInfo";
        tokenFunctions[10] = "setRebaseRate";
        tokenFunctions[11] = "emergencyPause";

        unykornExplorer.verifyContract(
            0x234567890123456789012345678901234567890B,
            "Unykorn USD",
            "Regulatory compliant stablecoin backed by RWA",
            "1.0.0",
            "0.8.24",
            tokenFunctions,
            keccak256(abi.encodePacked("uUSD metadata"))
        );

        console.log("Sample contracts indexed successfully");
    }

    function _indexSampleTokens() internal {
        console.log("Indexing sample tokens...");

        // Index uUSD
        unykornExplorer.verifyToken(
            0x234567890123456789012345678901234567890B,
            "Unykorn USD",
            "uUSD",
            18,
            1000000000000000000000000, // 1M tokens
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // Deployer
            keccak256(abi.encodePacked("uUSD token metadata"))
        );

        // Index Gold RWA
        unykornExplorer.verifyToken(
            0x456789012345678901234567890123456789012D,
            "Gold RWA Token",
            "GLD",
            18,
            100000000000000000000000, // 100K tokens
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            keccak256(abi.encodePacked("Gold RWA metadata"))
        );

        // Index Natural Resource Token
        unykornExplorer.verifyToken(
            0x567890123456789012345678901234567890123E,
            "Natural Resource Token",
            "NRT",
            18,
            50000000000000000000000, // 50K tokens
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            keccak256(abi.encodePacked("Natural Resource metadata"))
        );

        console.log("Sample tokens indexed successfully");
    }

    function _updateNetworkStats() internal {
        console.log("Updating network statistics...");

        unykornExplorer.updateNetworkStats(
            1250,      // TPS 24h
            50000000,  // Gas used 24h
            500000000, // Market cap ($500M)
            24000000,  // TVL ($24M)
            50000      // Active addresses
        );

        console.log("Network statistics updated");
    }
}
