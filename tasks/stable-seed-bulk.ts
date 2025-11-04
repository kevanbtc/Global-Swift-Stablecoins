/* eslint-disable no-console */
import { task } from "hardhat/config";
import fs from "fs";

type StableDef = {
  token: string;
  supported: boolean;
  reserveId: string; // hex bytes32
  por: string; // contract address or 0x0
  minbps: number;
  defaultkey: string; // bytes32 or human name
  cctpkey?: string;
  ccipkey?: string;
};

function normalizeKey(hre: any, key: string): string {
  // if looks like 0x... assume already bytes32
  if (!key) return hre.ethers.constants.HashZero;
  if (key.startsWith("0x") && key.length === 66) return key;
  // otherwise compute keccak256 of utf8 bytes
  return hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes(key));
}

task("stable:seed:bulk", "Seed many stablecoins from a JSON file")
  .addParam("registry", "StablecoinRegistry address")
  .addParam("file", "Path to JSON file with stable coin defs")
  .setAction(async (args, hre) => {
    const path = args.file as string;
    if (!fs.existsSync(path)) throw new Error(`file not found: ${path}`);
    const raw = fs.readFileSync(path, { encoding: "utf8" });
    let list: StableDef[];
    try {
      list = JSON.parse(raw) as StableDef[];
    } catch (e) {
      throw new Error("failed parsing JSON: " + (e as Error).message);
    }

    const reg = await hre.ethers.getContractAt("StablecoinRegistry", args.registry as string);

    for (const s of list) {
      console.log(`-> Seeding ${s.token} supported=${s.supported} reserve=${s.reserveId}`);
      const defaultKey = normalizeKey(hre, s.defaultkey);
      const cctpKey = normalizeKey(hre, s.cctpkey ?? "");
      const ccipKey = normalizeKey(hre, s.ccipkey ?? "");

      const tx = await reg.setStablecoin(
        s.token,
        Boolean(s.supported),
        s.reserveId,
        s.por ?? "0x0000000000000000000000000000000000000000",
        Number(s.minbps ?? 0),
        defaultKey,
        cctpKey,
        ccipKey
      );
      const rc = await tx.wait();
      console.log(`✔ seeded ${s.token} gas:${rc?.gasUsed?.toString()}`);
    }
    console.log("Done.");
  });
