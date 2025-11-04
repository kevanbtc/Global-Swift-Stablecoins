import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv"; dotenv.config();

async function main() {
  const [admin] = await ethers.getSigners();
  const policyId = ethers.encodeBytes32String(process.env.POLICY_ID || "DEFAULT");

  // mocks (replace with production feeds/contracts in live env)
  const Oracle = await ethers.getContractFactory("ReserveOracleMock");
  const oracle = await Oracle.deploy(); await oracle.waitForDeployment();
  await oracle.set(ethers.parseUnits("100000000", 18), 0, true); // NAV=$100m

  const Risk = await ethers.getContractFactory("RiskWeightsMock");
  const risk = await Risk.deploy(); await risk.waitForDeployment();
  const Elig = await ethers.getContractFactory("EligibleReserveMock");
  const elig = await Elig.deploy(); await elig.waitForDeployment();
  await elig.set(ethers.parseUnits("12000000", 18)); // eligible=$12m

  const Registry = await ethers.getContractFactory("ComplianceRegistryUpgradeable");
  const registry = await upgrades.deployProxy(Registry, [admin.address], { kind: "uups" });
  await registry.waitForDeployment();
  await registry.setPolicy(policyId, { allowUS:true, allowEU:true, allowSG:true, allowUK:true, regD506c:true, regS:true, micaART:false, micaEMT:true, proOnly:true, travelRuleRequired:false });

  const CAR = await ethers.getContractFactory("BaselCARModule");
  const car = await upgrades.deployProxy(CAR, [admin.address, await risk.getAddress(), await elig.getAddress(), 1000], { kind: "uups" }); // 10% floor
  await car.waitForDeployment();

  const Token = await ethers.getContractFactory("RebasedBillToken");
  const token = await upgrades.deployProxy(Token, [admin.address, "Compliant Bill Token", "CBT", await registry.getAddress(), policyId, await oracle.getAddress(), await car.getAddress()], { kind: "uups" });
  await token.waitForDeployment();

  console.log("Registry:", await registry.getAddress());
  console.log("CAR:", await car.getAddress());
  console.log("Oracle:", await oracle.getAddress());
  console.log("Token:", await token.getAddress());

  // wire FEED role so token can push liabilities
  await car.grantRole(await car.FEED_ROLE(), await token.getAddress());
}

main().catch((e) => { console.error(e); process.exit(1); });
