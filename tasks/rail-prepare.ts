/* eslint-disable no-console */
import { task } from "hardhat/config";

function parseBytes(input: string): `0x${string}` {
  if (!input) return "0x" as const;
  if (input.startsWith("0x")) return input as `0x${string}`;
  return ("0x" + Buffer.from(input, "utf8").toString("hex")) as `0x${string}`;
}

task("rail:prepare", "Prepare a transfer on any IRail (generic ABI)")
  .addParam("contract", "IRail contract address")
  .addParam("asset", "asset address (0x0 for native)")
  .addOptionalParam("from", "from address (defaults to signer)")
  .addParam("to", "to address")
  .addParam("amount", "amount (uint256)")
  .addOptionalParam("meta", "metadata bytes (hex or utf8)")
  .setAction(async (args, hre) => {
    const [signer] = await hre.ethers.getSigners();
    const abi = [
      "function transferId((address asset,address from,address to,uint256 amount,bytes metadata) t) view returns (bytes32)",
      "function prepare((address asset,address from,address to,uint256 amount,bytes metadata) t) payable"
    ];
    const rail = new hre.ethers.Contract(args.contract, abi, signer);
    const from = (args.from as string) ?? signer.address;
    const t = {
      asset: args.asset as string,
      from,
      to: args.to as string,
      amount: BigInt(args.amount),
      metadata: parseBytes((args.meta as string) ?? "0x")
    };
    const id = await rail.transferId(t);
    const tx = await rail.prepare(t);
    const rc = await tx.wait();
    console.log("✔ prepared id:", id, "gasUsed:", rc?.gasUsed?.toString());
  });
