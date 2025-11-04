import { ethers } from "hardhat";
import { id, isHexString, ZeroAddress } from "ethers";
import * as fs from "fs";
import * as path from "path";

type RoleMapping = {
  // e.g. "GOVERNOR_ROLE", "DEFAULT_ADMIN_ROLE", or hex bytes32 like 0x...
  role: string;
  // address to grant the role to (e.g., timelock address)
  to: string;
  // optional address to revoke from (e.g., deployer EOA or old admin)
  revokeFrom?: string;
};

type TargetConfig = {
  // Contract name as compiled by Hardhat (e.g., "StableUSD", "ReserveProofRegistry")
  name: string;
  // Deployed address to wire
  address: string;
  // Role actions to perform on this target
  roles: RoleMapping[];
};

type TimelockConfig = {
  minDelay: number | string;
  proposers: string[];
  executors: string[];
  admin?: string; // optional override admin; defaults to deployer
};

type GuardianConfig = {
  admin: string; // admin for RegGuardian
  guardians: string[]; // guardian signers
  threshold: number; // required approvals for an op-code
};

type GovernanceConfig = {
  // If provided, we deploy an OZ TimelockController and use it for grants.
  timelock?: TimelockConfig;
  // If provided, we deploy RegGuardian from compliant-bill-token and log its address.
  guardian?: GuardianConfig;
  // Per-contract wiring
  targets?: TargetConfig[];
};

async function resolveRole(contract: any, role: string): Promise<string> {
  // If hex bytes32 provided, accept it directly
  if (isHexString(role) && role.length === 66) return role.toLowerCase();

  // Try reading a constant getter from the contract (e.g., DEFAULT_ADMIN_ROLE())
  try {
    if (typeof contract[role] === "function") {
      const val: string = await contract[role]();
      if (isHexString(val) && val.length === 66) return val.toLowerCase();
    }
  } catch {
    // fall through
  }

  // Fallback to keccak256 of the role string (typical OZ pattern)
  return id(role);
}

async function main() {
  const network = await ethers.provider.getNetwork();
  const [deployer] = await ethers.getSigners();

  // Load config file (by default scripts/config/governance.json)
  const configPath = process.env.GOV_CONFIG_PATH || path.join(__dirname, "config", "governance.json");
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config file not found at ${configPath}. Copy governance.example.json to governance.json and edit.`);
  }
  const cfg: GovernanceConfig = JSON.parse(fs.readFileSync(configPath, "utf8"));

  console.log(`\nGovernance wiring starting...`);
  console.log(`Network: chainId=${network.chainId}`);
  console.log(`Deployer: ${deployer.address}`);

  let timelockAddress: string | undefined;
  if (cfg.timelock) {
    const admin = cfg.timelock.admin && cfg.timelock.admin !== "" ? cfg.timelock.admin : deployer.address;
    console.log(`\nDeploying TimelockController...`);
    const Timelock = await ethers.getContractFactory("TimelockController");
    const tl = await Timelock.deploy(
      cfg.timelock.minDelay,
      cfg.timelock.proposers ?? [],
      cfg.timelock.executors ?? [],
      admin
    );
    await tl.waitForDeployment();
    timelockAddress = await tl.getAddress();
    console.log(`TimelockController deployed at: ${timelockAddress}`);
  }

  let guardianAddress: string | undefined;
  if (cfg.guardian) {
    console.log(`\nDeploying RegGuardian...`);
    try {
      const RegGuardian = await ethers.getContractFactory("RegGuardian");
      const g = await RegGuardian.deploy(cfg.guardian.admin, cfg.guardian.guardians, cfg.guardian.threshold);
      await g.waitForDeployment();
      guardianAddress = await g.getAddress();
      console.log(`RegGuardian deployed at: ${guardianAddress}`);
    } catch (e) {
      console.warn(
        "Could not locate RegGuardian artifact. Ensure 'compliant-bill-token/contracts' is included in Hardhat sources or deploy RegGuardian separately.",
        e
      );
    }
  }

  if (cfg.targets && cfg.targets.length > 0) {
    console.log(`\nWiring roles across ${cfg.targets.length} target contract(s)...`);
    for (const t of cfg.targets) {
      console.log(`\n> Target ${t.name} @ ${t.address}`);
      const c = await ethers.getContractAt(t.name, t.address);

      for (const r of t.roles) {
        const toAddr =
          r.to === "<TIMELOCK>"
            ? timelockAddress
            : r.to === "<GUARDIAN>"
            ? guardianAddress
            : r.to;

        if (!toAddr || toAddr === ZeroAddress) {
          throw new Error(`Resolved 'to' address is empty for role ${r.role} on ${t.name}`);
        }

        const roleId = await resolveRole(c, r.role);

        // Grant role
        const hasAlready: boolean = await c.hasRole(roleId, toAddr);
        if (!hasAlready) {
          const tx = await c.grantRole(roleId, toAddr);
          console.log(`  grantRole(${r.role} -> ${toAddr}) tx=${tx.hash}`);
          await tx.wait();
        } else {
          console.log(`  grantRole(${r.role} -> ${toAddr}) skipped (already set)`);
        }

        // Optional revoke
        if (r.revokeFrom && r.revokeFrom !== "") {
          const had: boolean = await c.hasRole(roleId, r.revokeFrom);
          if (had) {
            const txr = await c.revokeRole(roleId, r.revokeFrom);
            console.log(`  revokeRole(${r.role} from ${r.revokeFrom}) tx=${txr.hash}`);
            await txr.wait();
          } else {
            console.log(`  revokeRole(${r.role} from ${r.revokeFrom}) skipped (not set)`);
          }
        }
      }
    }
  } else {
    console.log("\nNo targets specified in config; nothing to wire.");
  }

  console.log("\nGovernance wiring complete. Summary:")
  if (timelockAddress) console.log(`  TimelockController: ${timelockAddress}`);
  if (guardianAddress) console.log(`  RegGuardian:       ${guardianAddress}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
