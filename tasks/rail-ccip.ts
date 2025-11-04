/* eslint-disable no-console */
import { task } from "hardhat/config";

type Hex = `0x${string}`;

function parseBytes(input: string): Hex {
  if (input.startsWith("0x")) return input as Hex;
  return ("0x" + Buffer.from(input, "utf8").toString("hex")) as Hex;
}

task("rail:ccip:release", "Mark a CCIPRail transfer as released (executor only)")
  .addParam("contract", "CCIPRail address")
  .addParam("asset", "asset address (0x0 for native)")
  .addParam("from", "from address")
  .addParam("to", "to address")
  .addParam("amount", "amount (uint256)")
  .addOptionalParam("meta", "metadata bytes (hex or utf8)")
  .setAction(async (args, hre) => {
    const rail = await hre.ethers.getContractAt("CCIPRail", args.contract);
    const t = {
      asset: args.asset as string,
      from: args.from as string,
      to: args.to as string,
      amount: BigInt(args.amount),
      metadata: parseBytes((args.meta as string) ?? "0x")
    };
    const id = await rail.transferId(t);
    const tx = await rail.markReleased(id, t);
    const rc = await tx.wait();
    console.log("✔ CCIP released. gasUsed:", rc?.gasUsed?.toString());
  });

task("rail:ccip:refund", "Mark a CCIPRail transfer as refunded (executor only)")
  .addParam("contract", "CCIPRail address")
  .addParam("asset", "asset address (0x0 for native)")
  .addParam("from", "from address")
  .addParam("to", "to address")
  .addParam("amount", "amount (uint256)")
  .addOptionalParam("meta", "metadata bytes (hex or utf8)")
  .setAction(async (args, hre) => {
    const rail = await hre.ethers.getContractAt("CCIPRail", args.contract);
    const t = {
      asset: args.asset as string,
      from: args.from as string,
      to: args.to as string,
      amount: BigInt(args.amount),
      metadata: parseBytes((args.meta as string) ?? "0x")
    };
    const id = await rail.transferId(t);
    const tx = await rail.markRefunded(id, t);
    const rc = await tx.wait();
    console.log("✔ CCIP refunded. gasUsed:", rc?.gasUsed?.toString());
  });
