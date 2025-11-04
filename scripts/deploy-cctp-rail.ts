/*
 Deploy a CCTPExternalRail using the first signer as both admin and executor.
 Logs the deployed address.
*/

import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("deployer:", deployer.address);
  const F = await ethers.getContractFactory("CCTPExternalRail");
  const rail = await F.deploy(deployer.address, deployer.address, 0);
  await rail.waitForDeployment();
  console.log("CCTPExternalRail:", rail.target);
}

main().catch((e) => { console.error(e); process.exit(1); });
