import { ethers, upgrades } from "hardhat";
export async function deployMocks() {
  const [deployer] = await ethers.getSigners();
  const Oracle = await ethers.getContractFactory("ReserveOracleMock");
  const oracle = await Oracle.deploy();
  const Risk = await ethers.getContractFactory("RiskWeightsMock");
  const risk = await Risk.deploy();
  const Elig = await ethers.getContractFactory("EligibleReserveMock");
  const elig = await Elig.deploy();
  const TR = await ethers.getContractFactory("TravelRuleMock");
  const tr = await TR.deploy();
  await oracle.waitForDeployment(); await risk.waitForDeployment(); await elig.waitForDeployment(); await tr.waitForDeployment();
  return { deployer, oracle, risk, elig, tr };
}
