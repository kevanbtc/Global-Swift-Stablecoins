const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe.skip("Regulatory Compliant Token", function () {
  let registry;
  let car;
  let token;
  let owner;
  let user1;
  let user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy ComplianceRegistry
    const Registry = await ethers.getContractFactory("ComplianceRegistryUpgradeable");
    registry = await upgrades.deployProxy(Registry, [owner.address], { kind: "uups" });

    // Deploy BaselCARModule with mock addresses
    const CAR = await ethers.getContractFactory("BaselCARModule");
    car = await upgrades.deployProxy(CAR, [
      owner.address,
      ethers.ZeroAddress,  // mock risk weights
      ethers.ZeroAddress,  // mock eligible reserve
      1000  // 10% CAR
    ], { kind: "uups" });

    // Deploy RebasedBillToken
    const Token = await ethers.getContractFactory("RebasedBillToken");
    token = await upgrades.deployProxy(Token, [
      owner.address,
      "Test Token",
      "TEST",
      await registry.getAddress(),
      ethers.encodeBytes32String("DEFAULT"),
      ethers.ZeroAddress,  // mock reserve oracle
      await car.getAddress()
    ], { kind: "uups" });

    // Set up roles
    const ATTESTOR_ROLE = await registry.ATTESTOR_ROLE();
    const FEED_ROLE = await car.FEED_ROLE();
    const MINT_ROLE = await token.MINT_ROLE();

    await registry.grantRole(ATTESTOR_ROLE, owner.address);
    await car.grantRole(FEED_ROLE, await token.getAddress());
    await token.grantRole(MINT_ROLE, owner.address);
  });

  describe("Basic Setup", function () {
    it("Should have correct initial state", async function () {
      expect(await token.name()).to.equal("Test Token");
      expect(await token.symbol()).to.equal("TEST");
      expect(await token.totalSupply()).to.equal(0);
    });

    it("Should properly set up compliance registry", async function () {
      const policy = {
        allowUS: true,
        allowEU: true,
        allowSG: false,
        allowUK: true,
        regD506c: true,
        regS: true,
        micaART: false,
        micaEMT: true,
        proOnly: true,
        travelRuleRequired: false
      };

      await registry.setPolicy(ethers.encodeBytes32String("DEFAULT"), policy);
      expect(await registry.policies(ethers.encodeBytes32String("DEFAULT"))).to.deep.equal(
        Object.values(policy)
      );
    });

    it("Should allow KYC profile setup", async function () {
      const profile = {
        kyc: true,
        accredited: true,
        kycAsOf: Math.floor(Date.now() / 1000),
        kycExpiry: Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60,
        isoCountry: ethers.encodeBytes2("US"),
        frozen: false
      };

      await registry.setProfile(user1.address, profile);
      const storedProfile = await registry.profiles(user1.address);
      expect(storedProfile.kyc).to.equal(profile.kyc);
      expect(storedProfile.accredited).to.equal(profile.accredited);
      expect(storedProfile.isoCountry).to.equal(profile.isoCountry);
    });
  });

  describe("Token Operations", function () {
    beforeEach(async function () {
      // Set up a basic policy and KYC profiles
      const policy = {
        allowUS: true,
        allowEU: true,
        allowSG: true,
        allowUK: true,
        regD506c: false,
        regS: false,
        micaART: false,
        micaEMT: false,
        proOnly: false,
        travelRuleRequired: false
      };

      const profile = {
        kyc: true,
        accredited: true,
        kycAsOf: Math.floor(Date.now() / 1000),
        kycExpiry: Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60,
        isoCountry: ethers.encodeBytes2("US"),
        frozen: false
      };

      await registry.setPolicy(ethers.encodeBytes32String("DEFAULT"), policy);
      await registry.setProfile(user1.address, profile);
      await registry.setProfile(user2.address, profile);
    });

    it("Should allow minting to KYC'd address", async function () {
      await token.mint(
        user1.address,
        ethers.parseEther("100"),
        ethers.randomBytes(32),
        "ipfs://test",
        ethers.encodeBytes32String("LEI001")
      );

      expect(await token.balanceOf(user1.address)).to.equal(ethers.parseEther("100"));
    });

    it("Should allow transfers between KYC'd addresses", async function () {
      // Mint initial tokens
      await token.mint(
        user1.address,
        ethers.parseEther("100"),
        ethers.randomBytes(32),
        "ipfs://test",
        ethers.encodeBytes32String("LEI001")
      );

      // Connect as user1 and transfer to user2
      await token.connect(user1).transfer(user2.address, ethers.parseEther("50"));

      expect(await token.balanceOf(user1.address)).to.equal(ethers.parseEther("50"));
      expect(await token.balanceOf(user2.address)).to.equal(ethers.parseEther("50"));
    });

    it("Should prevent transfers to/from non-KYC'd addresses", async function () {
      // Mint initial tokens
      await token.mint(
        user1.address,
        ethers.parseEther("100"),
        ethers.randomBytes(32),
        "ipfs://test",
        ethers.encodeBytes32String("LEI001")
      );

      // Remove KYC from user2
      const profile = {
        kyc: false,
        accredited: true,
        kycAsOf: Math.floor(Date.now() / 1000),
        kycExpiry: Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60,
        isoCountry: ethers.encodeBytes2("US"),
        frozen: false
      };
      await registry.setProfile(user2.address, profile);

      // Try to transfer to non-KYC'd address
      await expect(
        token.connect(user1).transfer(user2.address, ethers.parseEther("50"))
      ).to.be.revertedWith("to blocked");
    });
  });
});
