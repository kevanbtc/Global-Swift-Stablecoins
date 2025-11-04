/* eslint-disable no-console */
import { task } from "hardhat/config";

task("stable:seed", "Seed StablecoinRegistry for a token")
  .addParam("registry", "StablecoinRegistry address")
  .addParam("token", "token address")
  .addParam("supported", "true/false")
  .addParam("reserveId", "bytes32 reserve id (hex)")
  .addParam("por", "IProofOfReserves contract address (0x0 if none)")
  .addParam("minbps", "min reserve ratio bps (uint16)")
  .addParam("defaultkey", "bytes32 rail key for same-chain default")
  .addOptionalParam("cctpkey", "bytes32 rail key for CCTP")
  .addOptionalParam("ccipkey", "bytes32 rail key for CCIP")
  .setAction(async (args, hre) => {
    const reg = await hre.ethers.getContractAt("StablecoinRegistry", args.registry as string);
    const tx = await reg.setStablecoin(
      args.token as string,
      (args.supported as string).toLowerCase() === "true",
      args.reserveId as string,
      args.por as string,
      Number(args.minbps),
      args.defaultkey as string,
      (args.cctpkey as string) ?? "0x0000000000000000000000000000000000000000000000000000000000000000",
      (args.ccipkey as string) ?? "0x0000000000000000000000000000000000000000000000000000000000000000"
    );
    const rc = await tx.wait();
    console.log("✔ Seeded token. gasUsed:", rc?.gasUsed?.toString());
  });
