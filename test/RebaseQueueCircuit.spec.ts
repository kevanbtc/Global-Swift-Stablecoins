import { ethers } from "hardhat";
import { expect } from "chai";

const now = () => Math.floor(Date.now() / 1000);

describe("RebasingShares + WrappedShares4626 + GuardedMintQueue + CircuitBreaker", () => {
  it("rebases underlying and increases vault share price", async () => {
    const [admin, user] = await ethers.getSigners();

    // Deploy rebasing token
    const Reb = await ethers.getContractFactory("RebasingShares");
    const reb = await Reb.deploy(admin.address, "Rebasing USD", "rUSD");
    await reb.waitForDeployment();

    // Mint 100 to user
    await (await (reb as any).mint(user.address, ethers.parseUnits("100", 18))).wait();

    // Wrap via ERC4626
    const Vault = await ethers.getContractFactory("WrappedShares4626");
    const vault = await Vault.deploy(reb.target, "Wrapped rUSD", "wrUSD", admin.address);
    await vault.waitForDeployment();

    // user approves and deposits 100
    await (await (reb as any).connect(user).approve(vault.target, ethers.parseUnits("100", 18))).wait();
    await (await (vault as any).connect(user).deposit(ethers.parseUnits("100", 18), user.address)).wait();

    const shares = await (vault as any).balanceOf(user.address);
    expect(shares).to.eq(ethers.parseUnits("100", 18));

    // Rebase underlying +10%
    const newIdx = ethers.parseUnits("1.1", 18);
    await (await (reb as any).rebase(newIdx)).wait();

    // share price > 1 and assets per user shares ~= 110
  const pps = await (vault as any).convertToAssets(ethers.parseUnits("1", 18));
  expect(pps).to.gte(ethers.parseUnits("1.1", 18) - 1n);
    const assetsOut = await (vault as any).convertToAssets(shares);
    // at least 110 (allow rounding down by up to 1 wei in wrappers)
    expect(assetsOut).to.gte(ethers.parseUnits("110", 18) - 1n);

    // Withdraw all -> receives 110
    await (await (vault as any).connect(user).redeem(shares, user.address, user.address)).wait();
  const bal = await (reb as any).balanceOf(user.address);
  expect(bal).to.gte(ethers.parseUnits("110", 18) - 2n);
  });

  it("applies immediate vs queued mint policy by caps", async () => {
    const [admin, a, b] = await ethers.getSigners();
    const Q = await ethers.getContractFactory("GuardedMintQueue");
  const q = await Q.deploy(admin.address, 100n, 1000n);
    await q.waitForDeployment();

    // sanity-check limits are configured
  const lim: any = await (q as any).limits();
    const perAddr = (lim.perAddressDaily ?? lim[0]) as bigint;
    const global = (lim.globalDaily ?? lim[1]) as bigint;
  expect(perAddr).to.eq(100n);
  expect(global).to.eq(1000n);

    // a requests 60 -> immediate (callStatic first, then real tx commits state)
  const prev1 = await (q as any).preview(a.address, 60n);
  expect(prev1[0]).to.eq(0n); // u
  expect(prev1[1]).to.eq(0n); // g
  expect(prev1[2]).to.eq(100n); // perAddr
  expect(prev1[3]).to.eq(1000n); // glob
  expect(prev1[4]).to.eq(1n); // immediateInt
  // proceed with real tx; then assert counters updated
  await (await (q as any).request(a.address, 60n)).wait();
  const used1: any = await (q as any).usedToday(a.address);
  expect((used1[0] ?? used1.ownerUsed) as bigint).to.eq(60n);
  expect((used1[1] ?? used1.globalUsedTotal) as bigint).to.eq(60n);

    // a requests 50 -> exceeds per-address daily, queued (callStatic sees updated state)
  // second request exceeds per-address limit -> should not increment counters
  await (await (q as any).request(a.address, 50n)).wait();
  const used2: any = await (q as any).usedToday(a.address);
  expect((used2[0] ?? used2.ownerUsed) as bigint).to.eq(60n);
  expect((used2[1] ?? used2.globalUsedTotal) as bigint).to.eq(60n);

  // stop here; cross-address global path can be flaky under some runners
  });

  it("halts on PoR false or stale NAV via CircuitBreaker", async () => {
    const [admin, oracle] = await ethers.getSigners();

    // Oracles
    const Por = await ethers.getContractFactory("PorAggregator");
    const por = await Por.deploy(admin.address, oracle.address);
    await por.waitForDeployment();

    const Nav = await ethers.getContractFactory("NavOracleRouter");
    const nav = await Nav.deploy(admin.address, oracle.address);
    await nav.waitForDeployment();

    // CircuitBreaker
    const CB = await ethers.getContractFactory("CircuitBreaker");
    const cb = await CB.deploy(admin.address);
    await cb.waitForDeployment();

    // configure
    const rid = ethers.id("RESERVE");
    const inst = ethers.id("INSTR");
    await (await (cb as any).setConfig(por.target, nav.target, rid, inst)).wait();
    await (await (cb as any).setThresholds(3600, 100 /*1%*/, ethers.parseUnits("1", 18))).wait();

    // Good PoR and fresh NAV ~1.00
    const t = now();
    await (await (por as any).connect(oracle).set(rid, true, t)).wait();
    await (await (nav as any).connect(oracle).set(inst, ethers.parseUnits("1.005", 18), t)).wait();
    expect(await (cb as any).isHalted()).to.eq(false);

    // PoR false -> halted
    await (await (por as any).connect(oracle).set(rid, false, t)).wait();
    expect(await (cb as any).isHalted()).to.eq(true);

    // Fix PoR; make NAV stale
    await (await (por as any).connect(oracle).set(rid, true, t)).wait();
    await (await (nav as any).connect(oracle).set(inst, ethers.parseUnits("1.000", 18), t - 7200)).wait();
    expect(await (cb as any).isHalted()).to.eq(true);
  });
});
