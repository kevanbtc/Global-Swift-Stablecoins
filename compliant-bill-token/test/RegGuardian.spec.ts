import { ethers } from "hardhat";
import { expect } from "chai";

describe("RegGuardian", function(){
  it("requires guardian approvals to flip op flags", async function(){
    const [admin, g1, g2] = await ethers.getSigners();
    const G = await ethers.getContractFactory("RegGuardian");
  const rg = await G.deploy(admin.address, [g1.address, g2.address], 2) as any;

    const MINT = ethers.id("MINT").slice(0,10) as any; // bytes4
    const tx = await rg.connect(admin).propose(MINT, true, 2);
    const rcpt = await tx.wait();
    const iface = (await ethers.getContractFactory("RegGuardian")).interface;
    let id: string | null = null;
    for (const log of rcpt!.logs) {
      try {
        const parsed = iface.parseLog(log);
        if (parsed?.name === "Proposed") { id = parsed.args[0]; break; }
      } catch {}
    }
    if (!id) throw new Error("no id");
    await rg.connect(g1).approve(id);
    await rg.connect(g2).approve(id);
    await rg.connect(admin).execute(id);
    expect(await rg.isPaused(MINT)).eq(true);
  });
});
