// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import the proof contracts
import {DeploymentProofNFT} from "../contracts/nft/DeploymentProofNFT.sol";
import {ContractAccessFee} from "../contracts/fees/ContractAccessFee.sol";

/**
 * @title DeployProofSystem
 * @notice Deploys the NFT proof and fee collection system for Unykorn L1
 */
contract DeployProofSystem is Script {
    // Configuration
    uint256 constant CHAIN_ID = 7777;
    address constant DEPLOYER = 0xdd2f1e6e4b28d1766f482b22e8a405423f1eddfd; // Real funded account

    // UNYETH token address (to be deployed separately or use native)
    address constant UNYETH_TOKEN = address(0); // Use address(0) for native ETH initially

    function run() external {
        vm.startBroadcast();

        console.log("=== DEPLOYING UNYKORN L1 PROOF SYSTEM ===");
        console.log("Chain ID:", CHAIN_ID);
        console.log("Deployer:", DEPLOYER);

        // Deploy Deployment Proof NFT
        console.log("\nDeploying DeploymentProofNFT...");
        DeploymentProofNFT proofNFT = new DeploymentProofNFT();
        console.log("DeploymentProofNFT deployed at:", address(proofNFT));

        // Deploy Contract Access Fee system
        console.log("\nDeploying ContractAccessFee...");
        ContractAccessFee accessFee = new ContractAccessFee(UNYETH_TOKEN);
        console.log("ContractAccessFee deployed at:", address(accessFee));

        // Setup roles and initial configuration
        console.log("\nSetting up roles...");

        // Grant deployer role to the DEPLOYER address
        proofNFT.grantRole(proofNFT.DEPLOYER_ROLE(), DEPLOYER);
        proofNFT.grantRole(proofNFT.VERIFIER_ROLE(), DEPLOYER);

        accessFee.grantRole(accessFee.FEE_SETTER_ROLE(), DEPLOYER);
        accessFee.grantRole(accessFee.COLLECTOR_ROLE(), DEPLOYER);

        console.log("Roles granted to deployer:", DEPLOYER);

        // Register some core contracts for fee collection (example)
        console.log("\nRegistering example contracts for fee collection...");

        // Register the proof NFT itself
        accessFee.registerContract(address(proofNFT), DEPLOYER);
        accessFee.setContractFees(address(proofNFT), 0.001 ether, 0.0001 ether); // Small fees

        // Register the access fee contract
        accessFee.registerContract(address(accessFee), DEPLOYER);
        accessFee.setContractFees(address(accessFee), 0.001 ether, 0.0001 ether);

        console.log("Example contracts registered with fees");

        console.log("\n=== PROOF SYSTEM DEPLOYMENT COMPLETE ===");
        console.log("DeploymentProofNFT:", address(proofNFT));
        console.log("ContractAccessFee:", address(accessFee));
        console.log("UNYETH Token:", UNYETH_TOKEN == address(0) ? "Native ETH" : "ERC20 Token");

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Deploy UNYETH token if using ERC20 fees");
        console.log("2. Update UNYETH_TOKEN constant in this script");
        console.log("3. Register additional contracts for fee collection");
        console.log("4. Mint deployment proofs for deployed contracts");
        console.log("5. Set up automated verification processes");

        vm.stopBroadcast();
    }
}
