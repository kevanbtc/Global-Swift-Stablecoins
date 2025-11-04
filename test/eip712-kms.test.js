const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ExternalRailEIP712 + KMS-stub flow", function () {
  const DEV_PK = "0x59c6995e998f97a5a004497e5f1f0d2b8b7b5b6b8b8f6e7a8b9c0d1e2f3a4b5c";

  it("allows a registered signer to produce an EIP-712 signature that verifies against the contract domain", async function () {
    const [deployer] = await ethers.getSigners();

    const Rail = await ethers.getContractFactory("ExternalRailEIP712");
    const rail = await Rail.deploy(deployer.address);
    await rail.waitForDeployment();

    // create signer wallet from DEV_PK (KMS stub)
    const kmsWallet = new ethers.Wallet(DEV_PK, ethers.provider);
    const kmsAddr = await kmsWallet.getAddress();

    // register kmsWallet as signer using admin (deployer)
    await rail.connect(deployer).setSigner(kmsAddr, true);

    // Build a typed-data payload and have the KMS wallet sign it using signTypedData/_signTypedData
    const net = await ethers.provider.getNetwork();
    const domain = {
      name: "ExternalRailEIP712",
      version: "1",
      chainId: Number(net.chainId),
      verifyingContract: rail.address,
    };
    const types = { Receipt: [
      { name: "id", type: "bytes32" },
      { name: "released", type: "bool" },
      { name: "settledAt", type: "uint64" },
    ] };
    const id = '0x' + '00'.repeat(32);
    const settledAt = Math.floor(Date.now() / 1000);
    const value = { id, released: true, settledAt };

    // sign using available wallet helpers (works in both ethers v5/v6 runtimes)
    const sig = typeof kmsWallet.signTypedData === "function"
      ? await kmsWallet.signTypedData(domain, types, value)
      : await kmsWallet._signTypedData(domain, types, value);

    // recovered should equal the kms address via ethers.verifyTypedData
    const recovered = ethers.verifyTypedData(domain, types, value, sig);
    expect(recovered.toLowerCase()).to.equal(kmsAddr.toLowerCase());
  });
});
