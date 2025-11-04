import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 }
    }
  },
  networks: {
    hardhat: {},
    sepolia: {
      url: process.env.RPC_SEPOLIA || "",
      accounts: process.env.DEPLOYER_KEY ? [process.env.DEPLOYER_KEY] : []
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_KEY || ""
  }
};
export default config;
