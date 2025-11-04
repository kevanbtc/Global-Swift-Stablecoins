/* eslint-disable no-console */
import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const admin    = process.env.RPR_ADMIN    || deployer.address;
  const governor = process.env.RPR_GOVERNOR || deployer.address;
  const reporter = process.env.RPR_REPORTER || deployer.address;
  const auditor  = process.env.RPR_AUDITOR  || deployer.address;

  const Factory = await ethers.getContractFactory("ReserveProofRegistry");
  const proxy = await upgrades.deployProxy(Factory, [admin, governor], {
    kind: "uups",
    initializer: "initialize",
  });
  await proxy.waitForDeployment();

  const addr = await proxy.getAddress();
  console.log("ReserveProofRegistry proxy:", addr);

  // grant roles
  const GOVERNOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GOVERNOR_ROLE"));
  const REPORTER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("REPORTER_ROLE"));
  const AUDITOR_ROLE  = ethers.keccak256(ethers.toUtf8Bytes("AUDITOR_ROLE"));

  const tx1 = await proxy.grantRole(REPORTER_ROLE, reporter);
  await tx1.wait();
  console.log("Granted REPORTER_ROLE to", reporter);

  const tx2 = await proxy.grantRole(AUDITOR_ROLE, auditor);
  await tx2.wait();
  console.log("Granted AUDITOR_ROLE to", auditor);

  // (optional) pin auditor to a specific reserveId
  if (process.env.RPR_PIN_RESERVE && process.env.RPR_PIN_AUDITOR) {
    const t = await proxy.pinAuditor(process.env.RPR_PIN_RESERVE as `0x${string}`, process.env.RPR_PIN_AUDITOR);
    await t.wait();
    console.log("Pinned auditor", process.env.RPR_PIN_AUDITOR, "to reserve", process.env.RPR_PIN_RESERVE);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
