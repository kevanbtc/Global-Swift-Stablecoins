import { ethers } from "hardhat";
import { expect } from "chai";

describe("CcipDistributor", () => {
  it("enforces allow-list and fee sufficiency, then sends via router", async () => {
    const [admin] = await ethers.getSigners();

    // Deploy router mock and set a fee
    const Router = await ethers.getContractFactory("MockRouterClient");
    const router = await Router.deploy();
    await router.waitForDeployment();
    await (await (router as any).setFee(ethers.parseUnits("0.001", 18))).wait();

    // Deploy distributor
    const D = await ethers.getContractFactory("CcipDistributor");
    const d = await D.deploy(router.target, admin.address);
    await d.waitForDeployment();

  const CHAIN = 42n; // dummy selector
  const recv = admin.address; // any valid address

    // Not supported chain -> revert
    await expect((d as any).send(CHAIN, recv, "0x")).to.be.revertedWith("chain");

    // Allow chain, but not receiver -> revert
    await (await (d as any).setSupportedChain(CHAIN, true)).wait();
    await expect((d as any).send(CHAIN, recv, "0x")).to.be.revertedWith("recv");

    // Allow receiver; insufficient fee -> revert
    await (await (d as any).setAllowedReceiver(CHAIN, recv, true)).wait();
    await expect((d as any).send(CHAIN, recv, "0x", { value: 0 })).to.be.revertedWith("fee");

    // Provide fee and succeed
    const fee = ethers.parseUnits("0.001", 18);
    const tx = await (d as any).send(CHAIN, recv, ethers.toUtf8Bytes("hello"), { value: fee });
    const rc = await tx.wait();
    const ev = rc?.logs?.find((l: any) => l.fragment?.name === "Sent");
    expect(ev).to.not.be.undefined;
  });
});
