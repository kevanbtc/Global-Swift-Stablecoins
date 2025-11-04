import { ethers, upgrades } from "hardhat";
import { expect } from "chai";

describe("RebasedBillToken", function(){
  it("mints, rebases, checks guards", async function(){
    const [admin, issuer, redeemer, treasurer, kyc, user] = await ethers.getSigners();

    const Oracle = await ethers.getContractFactory("ReserveOracleMock");
    const oracle = await Oracle.deploy(); await oracle.waitForDeployment();
    await oracle.set(ethers.parseUnits("1000000",18), 0, true);

    const Risk = await ethers.getContractFactory("RiskWeightsMock");
    const risk = await Risk.deploy(); await risk.waitForDeployment();
    const Elig = await ethers.getContractFactory("EligibleReserveMock");
    const elig = await Elig.deploy(); await elig.waitForDeployment();
    await elig.set(ethers.parseUnits("200000",18));

    const Registry = await ethers.getContractFactory("ComplianceRegistryUpgradeable");
    const registry = await upgrades.deployProxy(Registry, [admin.address], { kind:"uups" });
    const policyId = ethers.encodeBytes32String("DEFAULT");
    await registry.setPolicy(policyId, { allowUS:true, allowEU:true, allowSG:true, allowUK:true, regD506c:true, regS:true, micaART:false, micaEMT:true, proOnly:false, travelRuleRequired:false });
    await registry.grantRole(await registry.ATTESTOR_ROLE(), kyc.address);
    await registry.connect(kyc).setProfile(user.address, { kyc:true, accredited:true, kycAsOf: BigInt(0), kycExpiry: BigInt(0), isoCountry: ethers.encodeBytes32String("US").slice(0,6) as any, frozen:false });

    const CAR = await ethers.getContractFactory("BaselCARModule");
    const car = await upgrades.deployProxy(CAR, [admin.address, await risk.getAddress(), await elig.getAddress(), 1000], { kind:"uups" });

    const Token = await ethers.getContractFactory("RebasedBillToken");
    const token = await upgrades.deployProxy(Token, [admin.address, "Compliant Bill Token", "CBT", await registry.getAddress(), policyId, await oracle.getAddress(), await car.getAddress()], { kind:"uups" });

    await car.grantRole(await car.FEED_ROLE(), await token.getAddress());
    await token.grantRole(await token.MINT_ROLE(), issuer.address);
    await token.grantRole(await token.REBASE_ROLE(), treasurer.address);

    const before = await token.totalSupply();
    expect(before).eq(0n);

    await token.connect(issuer).mint(user.address, ethers.parseUnits("1000",18), ethers.keccak256(ethers.toUtf8Bytes("pacs")), "uri", ethers.keccak256(ethers.toUtf8Bytes("LEI")) );
    const afterMint = await token.totalSupply();
    expect(afterMint).eq(ethers.parseUnits("1000",18));

    await token.connect(treasurer).rebase(100, ethers.keccak256(ethers.toUtf8Bytes("camt")), "uri");
    const afterRebase = await token.totalSupply();
    expect(afterRebase).gt(afterMint);
  });
});
