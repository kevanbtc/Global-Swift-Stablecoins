import { ethers } from "hardhat";

async function main() {
  const tokenAddr = process.env.TOKEN!; const registryAddr = process.env.REGISTRY!; const beneficiary = (await ethers.getSigners())[2].address;
  const token = await ethers.getContractAt("RebasedBillToken", tokenAddr);
  const registry = await ethers.getContractAt("ComplianceRegistryUpgradeable", registryAddr);

  const policyId = ethers.encodeBytes32String(process.env.POLICY_ID || "DEFAULT");
  const kyc = (await ethers.getSigners())[4];
  await registry.connect(kyc).setProfile(beneficiary, { kyc:true, accredited:true, kycAsOf: BigInt(Math.floor(Date.now()/1000)), kycExpiry: BigInt(Math.floor(Date.now()/1000)+31536000), isoCountry: ethers.encodeBytes32String("US").slice(0,6) as any, frozen:false });

  const issuer = (await ethers.getSigners())[1];
  const amt = ethers.parseUnits("1000000", 18); // $1m
  await token.connect(issuer).mint(beneficiary, amt, ethers.keccak256(ethers.toUtf8Bytes("pacs.009 demo")), "ipfs://pacs009.json", ethers.keccak256(ethers.toUtf8Bytes("LEI-DEMO")));
  console.log("Minted $1m to", beneficiary);
}
main().catch((e)=>{console.error(e); process.exit(1)});
