const { expect } = require("chai");
const { ethers } = require("hardhat");

describe.skip("MerkleCouponDistributor", function () {
  let MerkleCouponDistributor;
  let distributor;
  let owner;
  let addr1;
  let addr2;
  let mockCompliance;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy mock compliance
    const MockCompliance = await ethers.getContractFactory("MockComplianceRegistry");
    mockCompliance = await MockCompliance.deploy();
  await mockCompliance.waitForDeployment();

    // Deploy distributor
    MerkleCouponDistributor = await ethers.getContractFactory("MerkleCouponDistributor");
    distributor = await MerkleCouponDistributor.deploy(owner.address, mockCompliance.address);
  await distributor.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await distributor.hasRole(await distributor.ROLE_ADMIN(), owner.address)).to.equal(true);
    });

    it("Should set the right compliance registry", async function () {
      expect(await distributor.compliance()).to.equal(mockCompliance.address);
    });
  });

  describe("Distribution Creation", function () {
    it("Should allow manager to create distribution", async function () {
      const mockERC20Address = "0x0000000000000000000000000000000000000001";
  const partition = ethers.encodeBytes32String("TEST_PARTITION");
  const merkleRoot = ethers.keccak256(ethers.toUtf8Bytes("test"));
  const totalAmount = ethers.parseUnits("1000", 18);
      const deadline = Math.floor(Date.now() / 1000) + 86400; // 24 hours from now

      await expect(distributor.createDistribution(
        mockERC20Address,
        partition,
        merkleRoot,
        totalAmount,
        deadline,
        "ipfs://test",
        ethers.ZeroAddress
      )).to.emit(distributor, "DistributionCreated");
    });
  });
});
