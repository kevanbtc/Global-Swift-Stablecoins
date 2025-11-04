import { ethers } from "hardhat";

async function main() {
  const tokenAddr = process.env.TOKEN!; // export TOKEN=0x...
  const registryAddr = process.env.REGISTRY!; // export REGISTRY=0x...

  const [admin, issuer, redeemer, treasurer, kyc] = await ethers.getSigners();
  const token = await ethers.getContractAt("RebasedBillToken", tokenAddr);
  const registry = await ethers.getContractAt("ComplianceRegistryUpgradeable", registryAddr);

  await token.grantRole(await token.MINT_ROLE(), issuer.address);
  await token.grantRole(await token.BURN_ROLE(), redeemer.address);
  await token.grantRole(await token.REBASE_ROLE(), treasurer.address);

  await registry.grantRole(await registry.ATTESTOR_ROLE(), kyc.address);
  console.log("Roles granted.");
}

main().catch((e)=>{console.error(e); process.exit(1)});
