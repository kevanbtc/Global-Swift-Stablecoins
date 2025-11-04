import { ethers } from "hardhat";
import { expect } from "chai";

describe("CollateralizedStablecoin", function(){
  it("lists collateral, mints within safety, blocks unsafe", async function(){
    const [admin, user, keeper] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("CollateralizedStablecoin");
  const stable = await Token.deploy(admin.address) as any;

    const Oracle = await ethers.getContractFactory("PriceOracleMock");
    const oracle = await Oracle.deploy(); await oracle.waitForDeployment();
    // Set price = $100 per collateral unit (1e18)
    await oracle.set(ethers.ZeroAddress, ethers.parseUnits("100", 18));

    await stable.listCollateral(ethers.ZeroAddress, { listed:true, debtCeiling: ethers.parseUnits("1000000",18), liqRatioBps: 15000, stabilityFeeBps: 0, penaltyBps: 500, oracle: await oracle.getAddress() });

    // add 10 units collateral -> value = $1000
    await stable.connect(user).addCollateral(ethers.ZeroAddress, ethers.parseUnits("10", 18));
    // can mint up to value / liqRatio = 1000 / 1.5 = 666.66
    await stable.connect(user).mint(ethers.ZeroAddress, ethers.parseUnits("600",18));
    await expect(stable.connect(user).mint(ethers.ZeroAddress, ethers.parseUnits("100",18))).to.be.reverted;
  });
});
