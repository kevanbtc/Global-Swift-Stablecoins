import { ethers } from "hardhat";
import { expect } from "chai";

const now = () => Math.floor(Date.now() / 1000);

describe("Oracles & Disclosure", () => {
  it("sets/gets PoR and NAV, and stores disclosures", async () => {
    const [admin, oracle, auditor] = await ethers.getSigners();

    // Deploy PoR aggregator
    const Por = await ethers.getContractFactory("PorAggregator");
    const por = await Por.deploy(admin.address, oracle.address);
    await por.waitForDeployment();

    // Deploy NAV router
    const Nav = await ethers.getContractFactory("NavOracleRouter");
    const nav = await Nav.deploy(admin.address, oracle.address);
    await nav.waitForDeployment();

    // Deploy Disclosure registry
    const Disc = await ethers.getContractFactory("DisclosureRegistry");
    const disc = await Disc.deploy(admin.address);
    await disc.waitForDeployment();

    // Grant auditor role on disclosure registry (read canonical id from contract)
    const ROLE_AUDITOR = await (disc as any).ROLE_AUDITOR_ID();
    await (await (disc as any).grantRole(ROLE_AUDITOR, auditor.address)).wait();

    // Update PoR
    const rid = ethers.id("US_TBILL_RESERVE");
    const asOf = now();
  await (await (por as any).connect(oracle).set(rid, true, asOf)).wait();

    const porRes = await por.get(rid);
    expect(porRes[0]).to.eq(true);
    expect(porRes[1]).to.eq(asOf);

    // Update NAV
    const inst = ethers.id("TBILL_SHARES");
    const navAsOf = asOf + 60;
    const navVal = ethers.parseUnits("1.000123", 18);
  await (await (nav as any).connect(oracle).set(inst, navVal, navAsOf)).wait();

    const navRes = await nav.get(inst);
    expect(navRes[0]).to.eq(navVal);
    expect(navRes[1]).to.eq(navAsOf);

    // Post a disclosure as auditor
    const docType = ethers.id("CUSTODIAN_ATTESTATION");
    const uri = "ipfs://bafy…custodian-proof";
  await (await (disc as any).connect(auditor).set(admin.address, inst, docType, uri, navAsOf)).wait();

    const k = await disc.keyOf(admin.address, inst, docType);
    const doc = await disc.get(k);
    expect(doc[0]).to.eq(uri);
    expect(doc[1]).to.eq(navAsOf);
  });
});
