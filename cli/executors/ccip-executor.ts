/*
  CCIP Executor (skeleton)
  - Watches for prepared transfers on CCIPRail and marks them released/refunded based on external signals.
  - For development, this polls events and uses a simple heuristic on metadata.

  Env:
  - RAIL_ADDRESS: address of CCIPRail
  - INTERVAL_MS: poll interval (default 5000)
  - ACTION: "release" | "refund" (dev shortcut)
  - FROM_BLOCK: optional start block
*/

import hre from "hardhat";
import { verifyAttestation } from "./attestationVerifier";

async function main() {
  const addr = process.env.RAIL_ADDRESS;
  if (!addr) throw new Error("RAIL_ADDRESS not set");
  if (!hre.ethers.isAddress(addr)) throw new Error(`Invalid RAIL_ADDRESS: ${addr}`);
  const interval = Number(process.env.INTERVAL_MS ?? 5000);
  const action = (process.env.ACTION ?? "release").toLowerCase();
  const fromBlock = process.env.FROM_BLOCK ? BigInt(process.env.FROM_BLOCK) : undefined;

  const rail = await hre.ethers.getContractAt("CCIPRail", addr);
  const iface = rail.interface;
  const preparedFrag = iface.getEvent("RailPrepared");
  const preparedTopic = preparedFrag ? preparedFrag.topicHash : undefined;
  if (!preparedTopic) throw new Error("Event RailPrepared not found on CCIPRail ABI");
  const provider = hre.ethers.provider;

  // Use numbers for block tags to avoid BigInt issues with some providers
  const current = await provider.getBlockNumber();
  let lastBlock: number = fromBlock ? Number(fromBlock) : Math.max(0, current - 1000);
  console.log(`[ccip-executor] watching ${addr}, starting at block ${lastBlock}`);

  setInterval(async () => {
    try {
      const latest: number = await provider.getBlockNumber();
      if (latest <= lastBlock) return;
      const logs = await provider.getLogs({
        address: addr,
        fromBlock: lastBlock + 1,
        toBlock: latest,
        topics: [preparedTopic]
      });
      for (const log of logs) {
  const parsed = iface.parseLog(log);
  if (!parsed) continue;
  const [id, from, to, asset, amount] = parsed.args as any[];
        console.log(`[ccip-executor] prepared id=${id} from=${from} to=${to} asset=${asset} amount=${amount}`);
        try {
          const transfer = { id, asset, from, to, amount, metadata: "0x" };
          const ok = await verifyAttestation("CCIP", id, transfer);
          if (!ok) {
            console.log(`[ccip-executor] attestation verification failed for ${id}, skipping`);
            continue;
          }
          if (action === "refund") {
            const tx = await rail.markRefunded(id, transfer);
            await tx.wait();
            console.log(`↩ refunded ${id}`);
          } else {
            const tx = await rail.markReleased(id, transfer);
            await tx.wait();
            console.log(`→ released ${id}`);
          }
        } catch (e:any) {
          console.warn(`[ccip-executor] mark failed for ${id}:`, e?.message ?? e);
        }
      }
  lastBlock = latest;
    } catch (e:any) {
      console.warn("[ccip-executor] poll error:", e?.message ?? e);
    }
  }, interval);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
