import { task } from "hardhat/config";
import fs from "fs";

task("upgrade:validate", "Checks storage layout diffs")
  .addParam("contract", "Fully qualified name, e.g. contracts/ReserveVault.sol:ReserveVault")
  .setAction(async (args, hre) => {
    const layout = await hre.storageLayout.export();
    fs.writeFileSync(`out/storage-layout.json`, JSON.stringify(layout, null, 2));
    console.log("✔ Wrote out/storage-layout.json");
    // Optionally compare against baseline under version control:
    // failing on incompatible diffs can be implemented here.
  });
