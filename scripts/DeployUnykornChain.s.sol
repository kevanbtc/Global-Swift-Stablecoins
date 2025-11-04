// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import all core contracts
import {SystemBootstrap} from "../contracts/core/SystemBootstrap.sol";
import {UnykornDNACore} from "../contracts/core/UnykornDNACore.sol";
import {DNASequencer} from "../contracts/core/DNASequencer.sol";
import {LifeLineOrchestrator} from "../contracts/core/LifeLineOrchestrator.sol";
import {ChainInfrastructure} from "../contracts/core/ChainInfrastructure.sol";
import {BlockchainExplorer} from "../contracts/core/BlockchainExplorer.sol";
import {DemoOrchestrator} from "../contracts/core/DemoOrchestrator.sol";

// Import validation contracts
import {SystemStateMachines} from "../contracts/validation/SystemStateMachines.sol";
import {AlgorithmicVerification} from "../contracts/validation/AlgorithmicVerification.sol";
import {ThirdPartyValidation} from "../contracts/validation/ThirdPartyValidation.sol";

// Import procedure contracts
import {ImplementationProcedures} from "../contracts/procedures/ImplementationProcedures.sol";
import {OperationalProtocols} from "../contracts/procedures/OperationalProtocols.sol";

// Import governance contracts
import {PolicyRoles} from "../contracts/governance/PolicyRoles.sol";
import {MultiSigWallet} from "../contracts/governance/MultiSigWallet.sol";
import {TimelockDeployer} from "../contracts/governance/TimelockDeployer.sol";

// Import compliance contracts
import {ComplianceRegistryUpgradeable} from "../contracts/compliance/ComplianceRegistryUpgradeable.sol";
import {TravelRuleEngine} from "../contracts/compliance/TravelRuleEngine.sol";
import {AdvancedSanctionsEngine} from "../contracts/compliance/AdvancedSanctionsEngine.sol";
import {KYCRegistry} from "../contracts/compliance/KYCRegistry.sol";

// Import settlement contracts
import {SettlementHub2PC} from "../contracts/settlement/SettlementHub2PC.sol";
import {SrCompliantDvP} from "../contracts/settlement/SrCompliantDvP.sol";
import {AtomicCrossAssetSettlement} from "../contracts/settlement/AtomicCrossAssetSettlement.sol";
import {StablecoinRouter} from "../contracts/settlement/stable/StablecoinRouter.sol";

// Import oracle contracts
import {DecentralizedOracleNetwork} from "../contracts/oracle/DecentralizedOracleNetwork.sol";
import {OracleCommittee} from "../contracts/oracle/OracleCommittee.sol";
import {AttestationOracle} from "../contracts/oracle/AttestationOracle.sol";

// Import token contracts
import {RebasedBillToken} from "../contracts/token/RebasedBillToken.sol";
import {RWASecurityToken} from "../contracts/token/RWASecurityToken.sol";
import {WrappedShares4626} from "../contracts/token/WrappedShares4626.sol";

// Import RWA contracts
import {GoldRWAToken} from "../contracts/rwa/GoldRWAToken.sol";
import {NaturalResourceRightsToken} from "../contracts/rwa/NaturalResourceRightsToken.sol";
import {ReserveManager} from "../contracts/reserves/ReserveManager.sol";

// Import DeFi contracts
import {InstitutionalDeFiHub} from "../contracts/defi/InstitutionalDeFiHub.sol";
import {InstitutionalLendingProtocol} from "../contracts/defi/InstitutionalLendingProtocol.sol";
import {GlobalDEX} from "../contracts/trading/GlobalDEX.sol";

// Import security contracts
import {QuantumResistantCryptography} from "../contracts/security/QuantumResistantCryptography.sol";
import {AIEnhancedSecurity} from "../contracts/security/AIEnhancedSecurity.sol";
import {DecentralizedIdentity} from "../contracts/security/DecentralizedIdentity.sol";

// Import global contracts
import {GlobalInfrastructureCodex} from "../contracts/global/GlobalInfrastructureCodex.sol";
import {GlobalFinancialInstitutions} from "../contracts/global/GlobalFinancialInstitutions.sol";
import {StakeholderRegistry} from "../contracts/stakeholders/StakeholderRegistry.sol";

// Import AI contracts
import {AIAgentSwarm} from "../contracts/ai/AIAgentSwarm.sol";
import {QuantumGovernance} from "../contracts/quantum/QuantumGovernance.sol";

// Import utility contracts
import {UniversalDeployer} from "../contracts/infrastructure/UniversalDeployer.sol";
import {MasterRegistry} from "../contracts/registry/MasterRegistry.sol";

contract DeployUnykornChain is Script {
    // Deployment configuration - Real Unykorn L1 funded accounts
    address public constant DEPLOYER = 0xdd2f1e6e4b28d1766f482b22e8a405423f1eddfd; // Real funded account from genesis
    address public constant DEPLOYER_ALT = 0x8626f6940e2eb28930efb4cef49b2d1f2c9c1199; // Alternative funded account
    address public constant IPFS_PINNER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address public constant AI_COORDINATOR = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    // Chain configuration
    uint256 public constant CHAIN_ID = 7777;
    string public constant CHAIN_NAME = "Unykorn L1";
    bool public constant PRIVACY_ENABLED = true;

    // Deployed contract addresses
    SystemBootstrap public bootstrap;
    UnykornDNACore public dnaCore;
    DNASequencer public dnaSequencer;
    LifeLineOrchestrator public lifelineOrchestrator;
    ChainInfrastructure public chainInfra;
    BlockchainExplorer public explorer;
    DemoOrchestrator public demoOrchestrator;

    // Validation contracts
    SystemStateMachines public stateMachines;
    AlgorithmicVerification public algorithmicVerification;
    ThirdPartyValidation public thirdPartyValidation;

    // Procedure contracts
    ImplementationProcedures public implementationProcedures;
    OperationalProtocols public operationalProtocols;

    // Core infrastructure contracts
    MasterRegistry public masterRegistry;
    UniversalDeployer public universalDeployer;
    PolicyRoles public policyRoles;
    MultiSigWallet public multiSigWallet;

    // Compliance contracts
    ComplianceRegistryUpgradeable public complianceRegistry;
    TravelRuleEngine public travelRuleEngine;
    AdvancedSanctionsEngine public sanctionsEngine;
    KYCRegistry public kycRegistry;

    // Settlement contracts
    SettlementHub2PC public settlementHub;
    SrCompliantDvP public srCompliantDvp;
    AtomicCrossAssetSettlement public atomicSettlement;
    StablecoinRouter public stablecoinRouter;

    // Oracle contracts
    DecentralizedOracleNetwork public oracleNetwork;
    OracleCommittee public oracleCommittee;
    AttestationOracle public attestationOracle;

    // Token contracts
    RebasedBillToken public rebasedBillToken;
    RWASecurityToken public rwaSecurityToken;
    WrappedShares4626 public wrappedShares;

    // RWA contracts
    GoldRWAToken public goldRwaToken;
    NaturalResourceRightsToken public naturalResourceToken;
    ReserveManager public reserveManager;

    // DeFi contracts
    InstitutionalDeFiHub public defiHub;
    InstitutionalLendingProtocol public lendingProtocol;
    GlobalDEX public globalDex;

    // Security contracts
    QuantumResistantCryptography public quantumCrypto;
    AIEnhancedSecurity public aiSecurity;
    DecentralizedIdentity public decentralizedIdentity;

    // Global contracts
    GlobalInfrastructureCodex public infrastructureCodex;
    GlobalFinancialInstitutions public financialInstitutions;
    StakeholderRegistry public stakeholderRegistry;

    // AI contracts
    AIAgentSwarm public aiAgentSwarm;
    QuantumGovernance public quantumGovernance;

    function run() external {
        vm.startBroadcast();

        console.log("Starting Unykorn Layer 1 deployment...");
        console.log("Chain ID:", CHAIN_ID);
        console.log("Chain Name:", CHAIN_NAME);

        // Phase 1: Deploy core infrastructure
        deployCoreInfrastructure();

        // Phase 2: Deploy validation systems
        deployValidationSystems();

        // Phase 3: Deploy procedure systems
        deployProcedureSystems();

        // Phase 4: Deploy governance systems
        deployGovernanceSystems();

        // Phase 5: Deploy compliance systems
        deployComplianceSystems();

        // Phase 6: Deploy settlement systems
        deploySettlementSystems();

        // Phase 7: Deploy oracle systems
        deployOracleSystems();

        // Phase 8: Deploy token systems
        deployTokenSystems();

        // Phase 9: Deploy RWA systems
        deployRWASystems();

        // Phase 10: Deploy DeFi systems
        deployDeFiSystems();

        // Phase 11: Deploy security systems
        deploySecuritySystems();

        // Phase 12: Deploy global systems
        deployGlobalSystems();

        // Phase 13: Deploy AI systems
        deployAISystems();

        // Phase 14: Initialize DNA system
        initializeDNASystem();

        // Phase 15: Launch chain infrastructure
        launchChainInfrastructure();

        // Phase 16: Finalize deployment
        finalizeDeployment();

        vm.stopBroadcast();

        console.log("Unykorn Layer 1 deployment completed successfully!");
        logDeploymentSummary();
    }

    function deployCoreInfrastructure() internal {
        console.log("Phase 1: Deploying core infrastructure...");

        // Deploy master registry first
        masterRegistry = new MasterRegistry();
        console.log("MasterRegistry deployed at:", address(masterRegistry));

        // Deploy universal deployer
        universalDeployer = new UniversalDeployer();
        console.log("UniversalDeployer deployed at:", address(universalDeployer));

        // Deploy system bootstrap
        bootstrap = new SystemBootstrap(IPFS_PINNER, AI_COORDINATOR);
        console.log("SystemBootstrap deployed at:", address(bootstrap));

        // Deploy DNA core
        dnaCore = new UnykornDNACore();
        console.log("UnykornDNACore deployed at:", address(dnaCore));

        // Deploy DNA sequencer
        dnaSequencer = new DNASequencer(address(dnaCore));
        console.log("DNASequencer deployed at:", address(dnaSequencer));

        // Deploy lifeline orchestrator
        lifelineOrchestrator = new LifeLineOrchestrator(
            address(dnaCore),
            address(dnaSequencer)
        );
        console.log("LifeLineOrchestrator deployed at:", address(lifelineOrchestrator));

        // Deploy chain infrastructure
        chainInfra = new ChainInfrastructure(
            CHAIN_ID,
            CHAIN_NAME,
            ChainInfrastructure.ChainMode.HYBRID,
            PRIVACY_ENABLED
        );
        console.log("ChainInfrastructure deployed at:", address(chainInfra));

        // Deploy blockchain explorer
        explorer = new BlockchainExplorer(address(chainInfra));
        console.log("BlockchainExplorer deployed at:", address(explorer));

        // Deploy demo orchestrator
        demoOrchestrator = new DemoOrchestrator(
            address(bootstrap),
            address(dnaCore),
            address(dnaSequencer),
            address(lifelineOrchestrator),
            IPFS_PINNER
        );
        console.log("DemoOrchestrator deployed at:", address(demoOrchestrator));
    }

    function deployValidationSystems() internal {
        console.log("Phase 2: Deploying validation systems...");

        stateMachines = new SystemStateMachines();
        console.log("SystemStateMachines deployed at:", address(stateMachines));

        algorithmicVerification = new AlgorithmicVerification();
        console.log("AlgorithmicVerification deployed at:", address(algorithmicVerification));

        thirdPartyValidation = new ThirdPartyValidation();
        console.log("ThirdPartyValidation deployed at:", address(thirdPartyValidation));
    }

    function deployProcedureSystems() internal {
        console.log("Phase 3: Deploying procedure systems...");

        implementationProcedures = new ImplementationProcedures();
        console.log("ImplementationProcedures deployed at:", address(implementationProcedures));

        operationalProtocols = new OperationalProtocols();
        console.log("OperationalProtocols deployed at:", address(operationalProtocols));
    }

    function deployGovernanceSystems() internal {
        console.log("Phase 4: Deploying governance systems...");

        policyRoles = new PolicyRoles();
        console.log("PolicyRoles deployed at:", address(policyRoles));

        address[] memory owners = new address[](3);
        owners[0] = DEPLOYER;
        owners[1] = DEPLOYER_ALT;
        owners[2] = AI_COORDINATOR;

        multiSigWallet = new MultiSigWallet(owners, 2);
        console.log("MultiSigWallet deployed at:", address(multiSigWallet));

        timelockDeployer = new TimelockDeployer();
        console.log("TimelockDeployer deployed at:", address(timelockDeployer));
    }

    function deployComplianceSystems() internal {
        console.log("Phase 5: Deploying compliance systems...");

        complianceRegistry = new ComplianceRegistryUpgradeable();
        complianceRegistry.initialize(address(multiSigWallet));
        console.log("ComplianceRegistryUpgradeable deployed at:", address(complianceRegistry));

        travelRuleEngine = new TravelRuleEngine(address(complianceRegistry));
        console.log("TravelRuleEngine deployed at:", address(travelRuleEngine));

        sanctionsEngine = new AdvancedSanctionsEngine(address(complianceRegistry));
        console.log("AdvancedSanctionsEngine deployed at:", address(sanctionsEngine));

        kycRegistry = new KYCRegistry(address(complianceRegistry));
        console.log("KYCRegistry deployed at:", address(kycRegistry));
    }

    function deploySettlementSystems() internal {
        console.log("Phase 6: Deploying settlement systems...");

        settlementHub = new SettlementHub2PC();
        console.log("SettlementHub2PC deployed at:", address(settlementHub));

        srCompliantDvp = new SrCompliantDvP(address(settlementHub));
        console.log("SrCompliantDvP deployed at:", address(srCompliantDvp));

        atomicSettlement = new AtomicCrossAssetSettlement(address(settlementHub));
        console.log("AtomicCrossAssetSettlement deployed at:", address(atomicSettlement));

        stablecoinRouter = new StablecoinRouter();
        console.log("StablecoinRouter deployed at:", address(stablecoinRouter));
    }

    function deployOracleSystems() internal {
        console.log("Phase 7: Deploying oracle systems...");

        oracleNetwork = new DecentralizedOracleNetwork();
        console.log("DecentralizedOracleNetwork deployed at:", address(oracleNetwork));

        oracleCommittee = new OracleCommittee(address(oracleNetwork));
        console.log("OracleCommittee deployed at:", address(oracleCommittee));

        attestationOracle = new AttestationOracle(address(oracleNetwork));
        console.log("AttestationOracle deployed at:", address(attestationOracle));
    }

    function deployTokenSystems() internal {
        console.log("Phase 8: Deploying token systems...");

        rebasedBillToken = new RebasedBillToken(
            "Unykorn USD",
            "uUSD",
            address(complianceRegistry),
            address(reserveManager)
        );
        console.log("RebasedBillToken deployed at:", address(rebasedBillToken));

        rwaSecurityToken = new RWASecurityToken(
            "RWA Security Token",
            "RWA",
            address(complianceRegistry)
        );
        console.log("RWASecurityToken deployed at:", address(rwaSecurityToken));

        wrappedShares = new WrappedShares4626(
            address(rebasedBillToken),
            "Wrapped Shares",
            "wSHARES"
        );
        console.log("WrappedShares4626 deployed at:", address(wrappedShares));
    }

    function deployRWASystems() internal {
        console.log("Phase 9: Deploying RWA systems...");

        goldRwaToken = new GoldRWAToken(
            "Gold RWA Token",
            "GLD",
            address(complianceRegistry)
        );
        console.log("GoldRWAToken deployed at:", address(goldRwaToken));

        naturalResourceToken = new NaturalResourceRightsToken(
            "Natural Resource Token",
            "NRT",
            address(complianceRegistry)
        );
        console.log("NaturalResourceRightsToken deployed at:", address(naturalResourceToken));

        reserveManager = new ReserveManager(address(complianceRegistry));
        console.log("ReserveManager deployed at:", address(reserveManager));
    }

    function deployDeFiSystems() internal {
        console.log("Phase 10: Deploying DeFi systems...");

        defiHub = new InstitutionalDeFiHub();
        console.log("InstitutionalDeFiHub deployed at:", address(defiHub));

        lendingProtocol = new InstitutionalLendingProtocol(address(defiHub));
        console.log("InstitutionalLendingProtocol deployed at:", address(lendingProtocol));

        globalDex = new GlobalDEX(address(complianceRegistry));
        console.log("GlobalDEX deployed at:", address(globalDex));
    }

    function deploySecuritySystems() internal {
        console.log("Phase 11: Deploying security systems...");

        quantumCrypto = new QuantumResistantCryptography();
        console.log("QuantumResistantCryptography deployed at:", address(quantumCrypto));

        aiSecurity = new AIEnhancedSecurity(address(quantumCrypto));
        console.log("AIEnhancedSecurity deployed at:", address(aiSecurity));

        decentralizedIdentity = new DecentralizedIdentity(address(complianceRegistry));
        console.log("DecentralizedIdentity deployed at:", address(decentralizedIdentity));
    }

    function deployGlobalSystems() internal {
        console.log("Phase 12: Deploying global systems...");

        infrastructureCodex = new GlobalInfrastructureCodex();
        console.log("GlobalInfrastructureCodex deployed at:", address(infrastructureCodex));

        financialInstitutions = new GlobalFinancialInstitutions();
        console.log("GlobalFinancialInstitutions deployed at:", address(financialInstitutions));

        stakeholderRegistry = new StakeholderRegistry();
        console.log("StakeholderRegistry deployed at:", address(stakeholderRegistry));
    }

    function deployAISystems() internal {
        console.log("Phase 13: Deploying AI systems...");

        aiAgentSwarm = new AIAgentSwarm(address(aiSecurity));
        console.log("AIAgentSwarm deployed at:", address(aiAgentSwarm));

        quantumGovernance = new QuantumGovernance(address(quantumCrypto));
        console.log("QuantumGovernance deployed at:", address(quantumGovernance));
    }

    function initializeDNASystem() internal {
        console.log("Phase 14: Initializing DNA system...");

        // Start bootstrap process
        bootstrap.startBootstrap();

        // Execute bootstrap phases
        bootstrap.executePhase(SystemBootstrap.BootstrapPhase.DNA_CORE_DEPLOYMENT);
        bootstrap.executePhase(SystemBootstrap.BootstrapPhase.CHROMOSOME_INITIALIZATION);
        bootstrap.executePhase(SystemBootstrap.BootstrapPhase.GENE_POPULATION);
        bootstrap.executePhase(SystemBootstrap.BootstrapPhase.SEQUENCER_SETUP);
        bootstrap.executePhase(SystemBootstrap.BootstrapPhase.LIFELINE_ACTIVATION);
        bootstrap.executePhase(SystemBootstrap.BootstrapPhase.AI_INTEGRATION);
        bootstrap.executePhase(SystemBootstrap.BootstrapPhase.SYSTEM_VALIDATION);

        // Complete bootstrap
        bootstrap.completeBootstrap("QmGenomeHash123456789");
    }

    function launchChainInfrastructure() internal {
        console.log("Phase 15: Launching chain infrastructure...");

        // Launch the chain
        chainInfra.launchChain(
            address(dnaCore),
            "Genesis data for Unykorn L1",
            "http://localhost:3000"
        );

        // Set up privacy groups
        chainInfra.createPrivacyGroup(
            "Institutional Group",
            ChainInfrastructure.PrivacyLevel.PRIVATE,
            new address[](0), // Will be populated later
            "QmPrivacyGroupHash123"
        );

        // Index contracts in explorer
        indexContractsInExplorer();
    }

    function indexContractsInExplorer() internal {
        // Index core contracts
        explorer.indexContract(
            address(dnaCore),
            "Unykorn DNA Core",
            "Central DNA helix managing all system genes",
            "1.0.0",
            stringToArray("dna,core,system"),
            "QmDNACoreMetadata123"
        );

        explorer.indexContract(
            address(chainInfra),
            "Chain Infrastructure",
            "Blockchain infrastructure management",
            "1.0.0",
            stringToArray("infrastructure,chain,privacy"),
            "QmChainInfraMetadata123"
        );

        // Index token contracts
        explorer.indexContract(
            address(rebasedBillToken),
            "Unykorn USD",
            "Regulatory compliant stablecoin",
            "1.0.0",
            stringToArray("stablecoin,token,regulatory"),
            "QmUSDMetadata123"
        );

        // Set contract privacy levels
        chainInfra.setContractPrivacy(address(dnaCore), ChainInfrastructure.PrivacyLevel.RESTRICTED);
        chainInfra.setContractPrivacy(address(rebasedBillToken), ChainInfrastructure.PrivacyLevel.PUBLIC);
        chainInfra.setContractPrivacy(address(complianceRegistry), ChainInfrastructure.PrivacyLevel.PRIVATE);
    }

    function finalizeDeployment() internal {
        console.log("Phase 16: Finalizing deployment...");

        // Register all contracts in master registry
        registerContractsInMasterRegistry();

        // Set up AI authorizations
        dnaCore.setAISwarmCoordinator(AI_COORDINATOR);
        dnaSequencer.setAISwarmCoordinator(AI_COORDINATOR);
        lifelineOrchestrator.setPrimaryAIController(AI_COORDINATOR);

        // Authorize AI agents
        explorer.authorizeAIAgent(AI_COORDINATOR, true);
        demoOrchestrator.authorizeAIAgent(AI_COORDINATOR, true);

        // Initialize demo templates
        initializeDemoTemplates();
    }

    function registerContractsInMasterRegistry() internal {
        masterRegistry.registerContract("SystemBootstrap", address(bootstrap));
        masterRegistry.registerContract("UnykornDNACore", address(dnaCore));
        masterRegistry.registerContract("DNASequencer", address(dnaSequencer));
        masterRegistry.registerContract("LifeLineOrchestrator", address(lifelineOrchestrator));
        masterRegistry.registerContract("ChainInfrastructure", address(chainInfra));
        masterRegistry.registerContract("BlockchainExplorer", address(explorer));
        masterRegistry.registerContract("ComplianceRegistry", address(complianceRegistry));
        masterRegistry.registerContract("RebasedBillToken", address(rebasedBillToken));
        masterRegistry.registerContract("ReserveManager", address(reserveManager));
        masterRegistry.registerContract("AIAgentSwarm", address(aiAgentSwarm));
    }

    function initializeDemoTemplates() internal {
        // Demo templates are initialized in the DemoOrchestrator constructor
        // Additional templates can be added here if needed
    }

    function logDeploymentSummary() internal view {
        console.log("\n=== UNYKORN LAYER 1 DEPLOYMENT SUMMARY ===");
        console.log("Chain ID:", CHAIN_ID);
        console.log("Chain Name:", CHAIN_NAME);
        console.log("Genesis Validator:", DEPLOYER);
        console.log("Alternative Deployer:", DEPLOYER_ALT);
        console.log("IPFS Pinner:", IPFS_PINNER);
        console.log("AI Coordinator:", AI_COORDINATOR);
        console.log("\nCore Contracts:");
        console.log("- DNA Core:", address(dnaCore));
        console.log("- DNA Sequencer:", address(dnaSequencer));
        console.log("- Lifeline Orchestrator:", address(lifelineOrchestrator));
        console.log("- Chain Infrastructure:", address(chainInfra));
        console.log("- Blockchain Explorer:", address(explorer));
        console.log("\nToken Contracts:");
        console.log("- uUSD Token:", address(rebasedBillToken));
        console.log("- RWA Token:", address(rwaSecurityToken));
        console.log("- Gold RWA:", address(goldRwaToken));
        console.log("\nCompliance Contracts:");
        console.log("- Compliance Registry:", address(complianceRegistry));
        console.log("- Travel Rule Engine:", address(travelRuleEngine));
        console.log("- Sanctions Engine:", address(sanctionsEngine));
        console.log("\nDeFi Contracts:");
        console.log("- DeFi Hub:", address(defiHub));
        console.log("- Lending Protocol:", address(lendingProtocol));
        console.log("- Global DEX:", address(globalDex));
        console.log("\nSecurity Contracts:");
        console.log("- Quantum Crypto:", address(quantumCrypto));
        console.log("- AI Security:", address(aiSecurity));
        console.log("- Decentralized Identity:", address(decentralizedIdentity));
        console.log("\nAI Contracts:");
        console.log("- AI Agent Swarm:", address(aiAgentSwarm));
        console.log("- Quantum Governance:", address(quantumGovernance));
        console.log("\n=== DEPLOYMENT COMPLETE ===");
    }

    function stringToArray(string memory str) internal pure returns (string[] memory) {
        string[] memory arr = new string[](1);
        arr[0] = str;
        return arr;
    }
}
