/* eslint-disable no-console */
import { task } from "hardhat/config";

type Hex = `0x${string}`;

function parseBytes(input: string): Hex {
  if (input.startsWith("0x")) return input as Hex;
  return ("0x" + Buffer.from(input, "utf8").toString("hex")) as Hex;
}

task("rail:cctp:release", "Mark a CCTPExternalRail transfer as released (executor only)")
  .addParam("contract", "CCTPExternalRail address")
  .addParam("asset", "asset address (0x0 for native)")
  .addParam("from", "from address")
  .addParam("to", "to address")
  .addParam("amount", "amount (uint256)")
  .addOptionalParam("meta", "metadata bytes (hex or utf8)")
  .setAction(async (args, hre) => {
    const rail = await hre.ethers.getContractAt("CCTPExternalRail", args.contract);
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
    console.log("✔ CCTP released. gasUsed:", rc?.gasUsed?.toString());
  });

task("rail:cctp:refund", "Mark a CCTPExternalRail transfer as refunded (executor only)")
  .addParam("contract", "CCTPExternalRail address")
  .addParam("asset", "asset address (0x0 for native)")
  .addParam("from", "from address")
  .addParam("to", "to address")
  .addParam("amount", "amount (uint256)")
  .addOptionalParam("meta", "metadata bytes (hex or utf8)")
  .setAction(async (args, hre) => {
    const rail = await hre.ethers.getContractAt("CCTPExternalRail", args.contract);
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
    console.log("✔ CCTP refunded. gasUsed:", rc?.gasUsed?.toString());
  });
