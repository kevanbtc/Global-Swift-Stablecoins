import { ethers, upgrades } from "hardhat";
import { expect } from "chai";

describe("AssetReferencedBasketUpgradeable", function(){
  it("mints with weight NAV floor", async function(){
    const [admin, cashier, user] = await ethers.getSigners();
    const Oracle = await ethers.getContractFactory("PriceOracleMock");
    const oracle = await Oracle.deploy(); await oracle.waitForDeployment();
    await oracle.set(ethers.ZeroAddress, ethers.parseUnits("1",18));

    const Token = await ethers.getContractFactory("AssetReferencedBasketUpgradeable");
  const token = await upgrades.deployProxy(Token, [admin.address, "ART Basket", "ARTB", 10000], { kind:"uups" }) as any;
    await token.grantRole(await token.CASHIER_ROLE(), cashier.address);
    // set single component 100% weight priced at $1
    await token.resetComponents([{ asset: ethers.ZeroAddress, weightBps: 10000, oracle: await oracle.getAddress() }]);

    await token.connect(cashier).mint(user.address, ethers.parseUnits("100",18), ethers.keccak256(ethers.toUtf8Bytes("pacs")), "uri", ethers.keccak256(ethers.toUtf8Bytes("LEI")));
    expect(await token.totalSupply()).eq(ethers.parseUnits("100",18));
  });
});
