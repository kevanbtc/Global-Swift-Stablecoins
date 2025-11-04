import hre from "hardhat";

/**
 * Minimal KMS-stub for development.
 * - If process.env.PRIVATE_KEY is set, uses that key.
 * - If KMS_MODE=stub and no PRIVATE_KEY, uses a deterministic dev key.
 */

const DEV_KEY = "0x59c6995e998f97a5a004497e5f1f0d2b8b7b5b6b8b8f6e7a8b9c0d1e2f3a4b5c"; // deterministic

export async function getAddress(): Promise<string> {
  const pk = process.env.PRIVATE_KEY ?? (process.env.KMS_MODE === "stub" ? DEV_KEY : undefined);
  if (!pk) throw new Error("KMS: no PRIVATE_KEY and not in stub mode");
  const w = new hre.ethers.Wallet(pk);
  return await w.getAddress();
}

export async function signTypedData(domain: any, types: any, value: any): Promise<string> {
  const pk = process.env.PRIVATE_KEY ?? (process.env.KMS_MODE === "stub" ? DEV_KEY : undefined);
  if (!pk) throw new Error("KMS: no PRIVATE_KEY and not in stub mode");
  const w = new hre.ethers.Wallet(pk);
  // ethers v6: wallet.signTypedData
  // In some runtimes _signTypedData is also available; try signTypedData first.
  // @ts-ignore
  if (typeof (w as any).signTypedData === "function") {
    // v6
    return await (w as any).signTypedData(domain, types, value);
  }
  // fallback to _signTypedData (v5 compatible)
  // @ts-ignore
  return await (w as any)._signTypedData(domain, types, value);
}
