import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
// Load tasks
import "./tasks/submit-attestation";
import "./tasks/rail-ccip";
import "./tasks/rail-cctp";
import "./tasks/router-set";
import "./tasks/stable-seed";
import "./tasks/stable-seed-bulk";
import "./tasks/rail-eip712";
import "./tasks/rail-prepare";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 500 },
      viaIR: true
    }
  },
  networks: {
    // fill in your RPCs
    besu: {
      url: "http://localhost:8545",
      chainId: 1337,
      gasPrice: 20000000000, // 20 gwei
      accounts: [], // Add private keys for Besu deployment
    },
    besu_testnet: {
      url: "https://besu-testnet.example.com", // Placeholder
      chainId: 1338,
      gasPrice: 20000000000,
      accounts: [],
    },
  }
};

export default config;
