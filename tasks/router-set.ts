/* eslint-disable no-console */
import { task } from "hardhat/config";

task("router:set", "Set default rail for a token in StablecoinRouter")
  .addParam("router", "StablecoinRouter address")
  .addParam("token", "Token address")
  .addParam("railkey", "Rail key (bytes32 hex)")
  .setAction(async (args, hre) => {
    const router = await hre.ethers.getContractAt("StablecoinRouter", args.router);
    const tx = await router.setDefaultRail(args.token as string, args.railkey as string);
    const rc = await tx.wait();
    console.log("✔ Router updated. gasUsed:", rc?.gasUsed?.toString());
  });
