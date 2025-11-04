const { ethers, upgrades } = require("hardhat");

async function main() {
  // Deploy the ComplianceRegistry
  const Registry = await ethers.getContractFactory("ComplianceRegistryUpgradeable");
  const [admin] = await ethers.getSigners();
  console.log("Deploying ComplianceRegistry...");
  const registry = await upgrades.deployProxy(Registry, [admin.address], { kind: "uups" });
  await registry.waitForDeployment();
  console.log("ComplianceRegistry deployed to:", await registry.getAddress());

  // Deploy the BaselCARModule
  const CAR = await ethers.getContractFactory("BaselCARModule");
  console.log("Deploying BaselCARModule...");
  // Replace these with actual oracle addresses
  const riskWeightsAddr = "0x0000000000000000000000000000000000000000";
  const eligibleReserveAddr = "0x0000000000000000000000000000000000000000";
  const minCARbps = 1000; // 10%
  const car = await upgrades.deployProxy(CAR, [
    admin.address,
    riskWeightsAddr,
    eligibleReserveAddr,
    minCARbps
  ], { kind: "uups" });
  await car.waitForDeployment();
  console.log("BaselCARModule deployed to:", await car.getAddress());

  // Deploy the RebasedBillToken
  const Token = await ethers.getContractFactory("RebasedBillToken");
  console.log("Deploying RebasedBillToken...");
  // Replace with actual oracle address
  const reserveOracleAddr = "0x0000000000000000000000000000000000000000";
  const token = await upgrades.deployProxy(Token, [
    admin.address,
    "Compliant Bill Token",
    "CBT",
    await registry.getAddress(),
    ethers.encodeBytes32String("DEFAULT"),
    reserveOracleAddr,
    await car.getAddress()
  ], { kind: "uups" });
  await token.waitForDeployment();
  console.log("RebasedBillToken deployed to:", await token.getAddress());

  // Setup roles
  console.log("Setting up roles...");
  const ATTESTOR_ROLE = await registry.ATTESTOR_ROLE();
  const FEED_ROLE = await car.FEED_ROLE();
  const MINT_ROLE = await token.MINT_ROLE();
  const BURN_ROLE = await token.BURN_ROLE();
  const REBASE_ROLE = await token.REBASE_ROLE();

  // Grant roles (replace with actual addresses)
  const kycAttestor = "0x0000000000000000000000000000000000000000";
  const issuer = "0x0000000000000000000000000000000000000000";
  const redeemer = "0x0000000000000000000000000000000000000000";
  const treasurer = "0x0000000000000000000000000000000000000000";

  await registry.grantRole(ATTESTOR_ROLE, kycAttestor);
  await car.grantRole(FEED_ROLE, await token.getAddress());
  await token.grantRole(MINT_ROLE, issuer);
  await token.grantRole(BURN_ROLE, redeemer);
  await token.grantRole(REBASE_ROLE, treasurer);

  console.log("Deployment and setup complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
