/* eslint-disable no-console */
import { task } from "hardhat/config";

// Local Hex type
// eslint-disable-next-line @typescript-eslint/ban-types
type LocalHex = `0x${string}` | string;

function parseBytes(input: string): LocalHex {
  if (!input) return "0x";
  if (input.startsWith("0x")) return input as LocalHex;
  return ("0x" + Buffer.from(input, "utf8").toString("hex")) as LocalHex;
}

async function signReceipt(hre: any, railAddr: string, id: string, released: boolean, settledAt: bigint) {
  const [signer] = await hre.ethers.getSigners();
  const net = await hre.ethers.provider.getNetwork();
  const domain = {
    name: "ExternalRailEIP712",
    version: "1",
    chainId: Number(net.chainId),
    verifyingContract: railAddr
  };
  const types = {
    Receipt: [
      { name: "id", type: "bytes32" },
      { name: "released", type: "bool" },
      { name: "settledAt", type: "uint64" }
    ]
  };
  const value = { id, released, settledAt: Number(settledAt) };
  // ethers v6 signer has signTypedData(domain, types, value)
  const sig = await signer.signTypedData(domain, types, value);
  return sig as string;
}

function buildTransfer(args: any) {
  return {
    asset: args.asset as string,
    from: args.from as string,
    to: args.to as string,
    amount: BigInt(args.amount),
    metadata: parseBytes((args.meta as string) ?? "0x")
  };
}

// Release
task("rail:eip712:release", "Mark an ExternalRailEIP712 transfer as released using a typed-data receipt")
  .addParam("contract", "ExternalRailEIP712 address")
  .addParam("asset", "asset address (0x0 for native)")
  .addParam("from", "from address")
  .addParam("to", "to address")
  .addParam("amount", "amount (uint256)")
  .addOptionalParam("meta", "metadata bytes (hex or utf8)")
  .addOptionalParam("settledAt", "unix seconds for settlement (default: now)")
  .setAction(async (args, hre) => {
    const rail = await hre.ethers.getContractAt("ExternalRailEIP712", args.contract);
    const t = buildTransfer(args);
    const id: string = await rail.transferId(t);
    const settledAt = args.settledAt ? BigInt(args.settledAt) : BigInt(Math.floor(Date.now() / 1000));
    const sig = await signReceipt(hre, rail.target as string, id, true, settledAt);
    const tx = await rail.markWithReceipt(t, true, settledAt, sig);
    const rc = await tx.wait();
    console.log("✔ EIP-712 released. id:", id, "gasUsed:", rc?.gasUsed?.toString());
  });

// Refund
task("rail:eip712:refund", "Mark an ExternalRailEIP712 transfer as refunded using a typed-data receipt")
  .addParam("contract", "ExternalRailEIP712 address")
  .addParam("asset", "asset address (0x0 for native)")
  .addParam("from", "from address")
  .addParam("to", "to address")
  .addParam("amount", "amount (uint256)")
  .addOptionalParam("meta", "metadata bytes (hex or utf8)")
  .addOptionalParam("settledAt", "unix seconds for settlement (default: now)")
  .setAction(async (args, hre) => {
    const rail = await hre.ethers.getContractAt("ExternalRailEIP712", args.contract);
    const t = buildTransfer(args);
    const id: string = await rail.transferId(t);
    const settledAt = args.settledAt ? BigInt(args.settledAt) : BigInt(Math.floor(Date.now() / 1000));
    const sig = await signReceipt(hre, rail.target as string, id, false, settledAt);
    const tx = await rail.markWithReceipt(t, false, settledAt, sig);
    const rc = await tx.wait();
    console.log("✔ EIP-712 refunded. id:", id, "gasUsed:", rc?.gasUsed?.toString());
  });
