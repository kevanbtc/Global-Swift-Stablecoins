import { ethers } from "hardhat";
async function main(){
  const tokenAddr = process.env.TOKEN!; const token = await ethers.getContractAt("RebasedBillToken", tokenAddr);
  const treasurer = (await ethers.getSigners())[3];
  await token.connect(treasurer).rebase(25, ethers.keccak256(ethers.toUtf8Bytes("camt.053 demo")), "ipfs://camt053.json"); // +0.25%
  console.log("Rebased +25 bps");
}
main().catch((e)=>{console.error(e); process.exit(1)});
