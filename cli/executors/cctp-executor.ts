/*
  CCTP Executor (skeleton)
  - Watches for prepared transfers on CCTPExternalRail and marks them released/refunded based on external signals.

  Env:
  - RAIL_ADDRESS: address of CCTPExternalRail
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

  const rail = await hre.ethers.getContractAt("CCTPExternalRail", addr);
  const iface = rail.interface;
  const ev = iface.getEvent("RailPrepared");
  const preparedTopic = ev ? ev.topicHash : undefined;
  if (!preparedTopic) throw new Error("Event RailPrepared not found on CCTPExternalRail ABI");
  const provider = hre.ethers.provider;

  const current = await provider.getBlockNumber();
  let lastBlock: number = fromBlock ? Number(fromBlock) : Math.max(0, current - 1000);
  console.log(`[cctp-executor] watching ${addr}, starting at block ${lastBlock}`);

  setInterval(async () => {
    try {
  const latest: number = await provider.getBlockNumber();
  if (latest <= lastBlock) return;
  const logs = await provider.getLogs({ address: addr, fromBlock: lastBlock + 1, toBlock: latest, topics: [preparedTopic] });
      for (const log of logs) {
        const parsed = iface.parseLog(log);
        if (!parsed) continue;
        const [id, from, to, asset, amount] = parsed.args as any[];
        console.log(`[cctp-executor] prepared id=${id} from=${from} to=${to} asset=${asset} amount=${amount}`);
        try {
          const transfer = { id, asset, from, to, amount, metadata: "0x" };
          const ok = await verifyAttestation("CCTP", id, transfer);
          if (!ok) {
            console.log(`[cctp-executor] attestation verification failed for ${id}, skipping`);
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
          console.warn(`[cctp-executor] mark failed for ${id}:`, e?.message ?? e);
        }
      }
      lastBlock = latest;
    } catch (e:any) {
      console.warn("[cctp-executor] poll error:", e?.message ?? e);
    }
  }, interval);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
