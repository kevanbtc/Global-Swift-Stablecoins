import { expect } from "chai";
import { ethers } from "hardhat";

describe("CCIPAttestationSender", function () {
  const CHAIN = 16015286601757825753n; // example selector (Ethereum Sepolia)

  async function deploy() {
    const [admin, attestor, receiver, other] = await ethers.getSigners();
    const Mock = await ethers.getContractFactory("MockRouterClient");
    const mock = await Mock.deploy();
    await mock.waitForDeployment();

    const Sender = await ethers.getContractFactory("CCIPAttestationSender");
    const sender = await Sender.deploy(await mock.getAddress());
    await sender.waitForDeployment();

    // roles
    await sender.grantRole(await sender.ATTESTOR_ROLE(), attestor.address);

    return { admin, attestor, receiver, other, mock, sender };
  }

  it("reverts when receiver not allowed", async () => {
    const { sender, attestor, receiver, mock } = await deploy();
    await sender.setSupportedChain(CHAIN, true);
    await mock.setFee(0);
    const s = (sender.connect(attestor) as any);
    await expect(
      s.sendAttestation(
        CHAIN,
        receiver.address,
        receiver.address,
        ethers.id("SCHEMA"),
        ethers.id("ATT1"),
        ethers.toUtf8Bytes("data")
      )
    ).to.be.revertedWith("receiver not allowed");
  });

  it("enforces rate limit", async () => {
    const { sender, attestor, receiver, mock } = await deploy();
    await sender.setSupportedChain(CHAIN, true);
    await sender.setAllowedReceiver(CHAIN, receiver.address, true);
    await sender.setRateLimit(CHAIN, 3600, 1); // 1 per hour
    await mock.setFee(0);

    const s = (sender.connect(attestor) as any);
    const tx1 = await s.sendAttestation(
      CHAIN,
      receiver.address,
      receiver.address,
      ethers.id("SCHEMA"),
      ethers.id("A1"),
      ethers.toUtf8Bytes("d1")
    );
    await tx1.wait();
    await expect(
      s.sendAttestation(
        CHAIN,
        receiver.address,
        receiver.address,
        ethers.id("SCHEMA"),
        ethers.id("A2"),
        ethers.toUtf8Bytes("d2")
      )
    ).to.be.revertedWith("rate limit");
  });

  it("requires sufficient fee and emits on success", async () => {
    const { sender, attestor, receiver, mock } = await deploy();
    await sender.setSupportedChain(CHAIN, true);
    await sender.setAllowedReceiver(CHAIN, receiver.address, true);
    await sender.setRateLimit(CHAIN, 0, 0); // off
    await mock.setFee(10n);

    const s = (sender.connect(attestor) as any);
    await expect(
      s.sendAttestation(
        CHAIN,
        receiver.address,
        receiver.address,
        ethers.id("SCHEMA"),
        ethers.id("A3"),
        ethers.toUtf8Bytes("d3"),
        { value: 5n }
      )
    ).to.be.revertedWith("insufficient fee");

    const tx = await s.sendAttestation(
      CHAIN,
      receiver.address,
      receiver.address,
      ethers.id("SCHEMA"),
      ethers.id("A3"),
      ethers.toUtf8Bytes("d3"),
      { value: 10n }
    );
    await expect(tx).to.emit(sender, "AttestationSent");
  });
});
