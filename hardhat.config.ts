import { HardhatUserConfig, task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
// Note: '@nomiclabs/hardhat-ethers' is deprecated in newer setups and
// the project uses '@nomicfoundation/hardhat-toolbox' which bundles the
// foundation 'ethers' plugin. Removed the old '@nomiclabs' import to
// avoid module resolution errors when the package is not installed.
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-deploy";
import "hardhat-tracer";

// Load tasks
import "./tasks/submit-attestation";
import "./tasks/rail-ccip";
import "./tasks/rail-cctp";
import "./tasks/router-set";
import "./tasks/stable-seed";
import "./tasks/stable-seed-bulk";
import "./tasks/rail-eip712";
import "./tasks/rail-prepare";

interface TaskArgs {
  // Add any specific task arguments here
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 500
          },
          viaIR: true
        }
      }
    ]
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 30000000,
      forking: {
        url: process.env.MAINNET_RPC || "",
        enabled: false
      }
    },
    besu: {
      url: process.env.BESU_RPC || "http://localhost:8545",
      chainId: 1337,
      gasPrice: 20000000000,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
    },
    besu_testnet: {
      url: process.env.BESU_TESTNET_RPC || "https://besu-testnet.example.com",
      chainId: 1338,
      gasPrice: 20000000000,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
    excludeContracts: ["mock/", "test/"]
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 100000
  }
};

// Test task definitions
task("test:sequencer", "Run sequencer network tests")
  .setAction(async (taskArgs: TaskArgs, hre: HardhatRuntimeEnvironment) => {
    await hre.run("test", { grep: "Sequencer" });
  });

task("test:performance", "Run performance benchmark tests")
  .setAction(async (taskArgs: TaskArgs, hre: HardhatRuntimeEnvironment) => {
    await hre.run("test", { grep: "Performance" });
  });

task("test:integration", "Run multi-chain integration tests")
  .setAction(async (taskArgs: TaskArgs, hre: HardhatRuntimeEnvironment) => {
    await hre.run("test", { grep: "Integration" });
  });

task("test:all", "Run all tests")
  .setAction(async (taskArgs: TaskArgs, hre: HardhatRuntimeEnvironment) => {
    await hre.run("test");
  });

export default config;
