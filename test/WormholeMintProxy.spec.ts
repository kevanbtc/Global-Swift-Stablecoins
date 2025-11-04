import { ethers } from "hardhat";
import { expect } from "chai";

describe("WormholeMintProxy", () => {
  it("enforces BRIDGE_ROLE and forwards mint", async () => {
    const [admin, bridge, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockMintableERC20");
    const t = await Token.deploy("Mock", "MOCK");
    await t.waitForDeployment();

    const Proxy = await ethers.getContractFactory("WormholeMintProxy");
    const p = await Proxy.deploy(admin.address);
    await p.waitForDeployment();

    // Without BRIDGE_ROLE -> revert
    await expect((p as any).connect(bridge).mint(t.target, user.address, ethers.parseUnits("10", 18))).to.be
      .reverted;

    // Grant BRIDGE_ROLE
    await (await (p as any).setBridge(bridge.address)).wait();

    // Forward mint
    await (await (p as any).connect(bridge).mint(t.target, user.address, ethers.parseUnits("10", 18))).wait();
    const bal = await (t as any).balanceOf(user.address);
    expect(bal).to.eq(ethers.parseUnits("10", 18));
  });
});
