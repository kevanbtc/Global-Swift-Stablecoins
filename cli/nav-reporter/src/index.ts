/* eslint-disable no-console */
import { Command } from "commander";
import { JsonRpcProvider, Wallet, Contract, ethers } from "ethers";
import fs from "node:fs";

const ABI = [
  "function submitReserveAttestation((bytes32,address,uint64,uint64,uint64,uint256,uint256,bytes32,uint64),bytes) external",
  "function domainSeparator() external view returns (bytes32)"
];

type Hex = `0x${string}`;

interface Att {
  reserveId: Hex;
  auditor: string;
  start: bigint;
  end: bigint;
  validUntil: bigint;
  totalAssets: bigint;
  totalLiabilities: bigint;
  cid: Hex;
  nonce: bigint;
}

const program = new Command();

program
  .name("nav-reporter")
  .description("Submit reserve attestations with EIP-712 signatures")
  .option("--rpc <url>", "RPC URL", "http://localhost:8545")
  .option("--contract <addr>", "ReserveProofRegistry proxy address")
  .option("--reporterPk <hex>", "Reporter private key")
  .option("--auditorPk <hex>", "Auditor private key (signer)")
  .option("--json <path>", "Path to attestation JSON")
  .option("--reserve <hex>", "ReserveId")
  .option("--auditor <addr>", "Auditor address")
  .option("--start <ts>", "start ts")
  .option("--end <ts>", "end ts")
  .option("--valid <ts>", "validUntil ts")
  .option("--assets <num>", "totalAssets")
  .option("--liabs <num>", "totalLiabilities")
  .option("--cid <hex>", "IPFS digest")
  .option("--nonce <n>", "nonce")
  .parse(process.argv);

(async () => {
  const opts = program.opts();
  const provider = new JsonRpcProvider(opts.rpc);
  const reporter = new Wallet(opts.reporterPk, provider);
  const auditor  = new Wallet(opts.auditorPk, provider);

  const chainId = (await provider.getNetwork()).chainId;
  const contract = new Contract(opts.contract, ABI, reporter);

  let att: Att;
  if (opts.json) {
    att = JSON.parse(fs.readFileSync(opts.json, "utf8"));
    // coerce BigInt
    att.start = BigInt(att.start); att.end = BigInt(att.end); att.validUntil = BigInt(att.validUntil);
    att.totalAssets = BigInt(att.totalAssets); att.totalLiabilities = BigInt(att.totalLiabilities);
    att.nonce = BigInt(att.nonce);
  } else {
    att = {
      reserveId: opts.reserve,
      auditor: opts.auditor,
      start: BigInt(opts.start),
      end: BigInt(opts.end),
      validUntil: BigInt(opts.valid),
      totalAssets: BigInt(opts.assets),
      totalLiabilities: BigInt(opts.liabs),
      cid: opts.cid,
      nonce: BigInt(opts.nonce),
    };
  }

  const domain = {
    name: "ReserveProofRegistry",
    version: "1",
    chainId,
    verifyingContract: opts.contract,
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
    ],
  };

  // ensure signer matches att.auditor
  const signerAddr = await auditor.getAddress();
  if (signerAddr.toLowerCase() !== att.auditor.toLowerCase()) {
    throw new Error(`auditorPk address ${signerAddr} does not match att.auditor ${att.auditor}`);
  }

  const signature = await auditor.signTypedData(domain, types, att);
  const tx = await contract.submitReserveAttestation(att, signature);
  const rc = await tx.wait();
  console.log("Submitted attestation. tx:", rc?.hash);
})();
