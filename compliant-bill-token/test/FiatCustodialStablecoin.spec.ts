import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
// Using 'any' casting for deployProxy return to call typed methods without waiting for typechain names

describe("FiatCustodialStablecoinUpgradeable", function(){
  it("mints/burns with compliance & reserve guard", async function(){
    const [admin, cashier, kyc, user] = await ethers.getSigners();

    const Oracle = await ethers.getContractFactory("ReserveOracleMock");
    const oracle = await Oracle.deploy(); await oracle.waitForDeployment();
    await oracle.set(ethers.parseUnits("1000000", 18), 0, true);

  const Registry = await ethers.getContractFactory("ComplianceRegistryUpgradeable");
  const registry = (await upgrades.deployProxy(Registry, [admin.address], { kind: "uups" })) as any;
    const policyId = ethers.encodeBytes32String("DEFAULT");
    await registry.setPolicy(policyId, { allowUS:true, allowEU:true, allowSG:true, allowUK:true, regD506c:true, regS:true, micaART:false, micaEMT:true, proOnly:false, travelRuleRequired:false });
    await registry.grantRole(await registry.ATTESTOR_ROLE(), kyc.address);
    await registry.connect(kyc).setProfile(user.address, { kyc:true, accredited:true, kycAsOf: 0n, kycExpiry: 0n, isoCountry: ethers.encodeBytes32String("US").slice(0,6) as any, frozen:false });

  const Token = await ethers.getContractFactory("FiatCustodialStablecoinUpgradeable");
  const token = (await upgrades.deployProxy(Token, [admin.address, "Fiat Stable", "fUSD", await registry.getAddress(), policyId, await oracle.getAddress(), 10000], { kind:"uups" })) as any;
    await token.grantRole(await token.CASHIER_ROLE(), cashier.address);

    await token.connect(cashier).mint(user.address, ethers.parseUnits("1000",18), ethers.keccak256(ethers.toUtf8Bytes("pacs")), "uri", ethers.keccak256(ethers.toUtf8Bytes("LEI")) );
    expect(await token.totalSupply()).eq(ethers.parseUnits("1000",18));

    await token.connect(cashier).burn(user.address, ethers.parseUnits("200",18), ethers.keccak256(ethers.toUtf8Bytes("pacs")), "uri", ethers.keccak256(ethers.toUtf8Bytes("LEI")) );
    expect(await token.totalSupply()).eq(ethers.parseUnits("800",18));
  });
});
