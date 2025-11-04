/* eslint-disable no-console */
import { task } from "hardhat/config";
import { ethers } from "hardhat";

type Hex = `0x${string}`;

task("rpr:submit", "Submit an EIP-712 ReserveAttestation")
  .addParam("registry", "ReserveProofRegistry proxy address")
  .addParam("reserve", "bytes32 reserveId")
  .addParam("auditor", "auditor address")
  .addParam("start", "start timestamp (uint64)")
  .addParam("end", "end timestamp (uint64)")
  .addParam("valid", "validUntil timestamp (uint64)")
  .addParam("assets", "totalAssets (uint256)")
  .addParam("liabs", "totalLiabilities (uint256)")
  .addParam("cid", "bytes32 IPFS digest")
  .addParam("nonce", "uint64 next nonce")
  .addOptionalParam("auditorPk", "auditor private key (hex) to sign")
  .setAction(async (args, hre) => {
    const [reporter] = await hre.ethers.getSigners();

    const registry = await hre.ethers.getContractAt("ReserveProofRegistry", args.registry);

    const chainId = (await hre.ethers.provider.getNetwork()).chainId;
    const domain = {
      name: "ReserveProofRegistry",
      version: "1",
      chainId,
      verifyingContract: args.registry as string
    };

    const types = {
      ReserveAttestation: [
        { name: "reserveId", type: "bytes32" },
        { name: "auditor", type: "address" },
        { name: "start", type: "uint64" },
        { name: "end", type: "uint64" },
        { name: "validUntil", type: "uint64" },
        { name: "totalAssets", type: "uint256" },
        { name: "totalLiabilities", type: "uint256" },
        { name: "cid", type: "bytes32" },
        { name: "nonce", type: "uint64" },
      ]
    };

    const att = {
      reserveId: args.reserve as Hex,
      auditor: args.auditor as string,
      start: BigInt(args.start),
      end: BigInt(args.end),
      validUntil: BigInt(args.valid),
      totalAssets: BigInt(args.assets),
      totalLiabilities: BigInt(args.liabs),
      cid: args.cid as Hex,
      nonce: BigInt(args.nonce),
    };

    // sign as auditor
    let signature: Hex;
    if (args.auditorPk) {
      const wallet = new hre.ethers.Wallet(args.auditorPk as string, hre.ethers.provider);
      signature = await wallet.signTypedData(domain, types, att) as Hex;
      if ((await wallet.getAddress()).toLowerCase() !== (args.auditor as string).toLowerCase()) {
        throw new Error("auditorPk does not match auditor address");
      }
    } else {
      // use reporter to sign if you want to simulate (only for testing)
      signature = await reporter.signTypedData(domain, types, att) as Hex;
    }

    // submit
    const tx = await registry.connect(reporter).submitReserveAttestation(att, signature);
    const rc = await tx.wait();
    console.log("Submitted. gasUsed:", rc?.gasUsed?.toString());
  });
