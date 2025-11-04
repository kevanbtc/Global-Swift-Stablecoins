import { ethers, upgrades } from "hardhat";
import { expect } from "chai";

describe("MultiIssuerStablecoinUpgradeable", function(){
  it("enforces issuer quotas and daily caps", async function(){
    const [admin, bankA, user] = await ethers.getSigners();

    const Registry = await ethers.getContractFactory("ComplianceRegistryUpgradeable");
    const registry = await upgrades.deployProxy(Registry, [admin.address], { kind:"uups" }) as any;
    const policyId = ethers.encodeBytes32String("DEFAULT");
    await registry.setPolicy(policyId, { allowUS:true, allowEU:true, allowSG:true, allowUK:true, regD506c:true, regS:true, micaART:false, micaEMT:true, proOnly:false, travelRuleRequired:false });
    await registry.setAllowlist(user.address, true);

    const Token = await ethers.getContractFactory("MultiIssuerStablecoinUpgradeable");
    const token = await upgrades.deployProxy(Token, [admin.address, "BankNet USD", "bUSD", await registry.getAddress(), policyId], { kind:"uups" }) as any;
    await token.grantRole(await token.ISSUER_ROLE(), bankA.address);
    await token.setLimits(bankA.address, ethers.parseUnits("1000",18), ethers.parseUnits("600",18));

    await token.connect(bankA).mint(user.address, ethers.parseUnits("500",18));
    await expect(token.connect(bankA).mint(user.address, ethers.parseUnits("200",18))).to.be.reverted; // day cap
  });
});
