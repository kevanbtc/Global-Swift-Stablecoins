/*
  EIP-712 Receipt Signer (minimal HTTP)
  - Exposes /sign to produce a signature for ExternalRailEIP712. Optionally submit on chain.

  Env:
  - RAIL_ADDRESS: ExternalRailEIP712 address (used when submitting)
  - PORT: HTTP port (default 8787)
  - SUBMIT: if set to "1", also call markWithReceipt after signing
  - PRIVATE_KEY: hex private key for the signer (required)
  - RPC_URL: optional custom RPC (defaults to Hardhat provider)
*/

import http from "http";
import hre from "hardhat";
import { signTypedData, getAddress } from "./kmssigner";

function bad(res: http.ServerResponse, code: number, msg: string) {
  res.statusCode = code; res.setHeader("content-type", "application/json");
  res.end(JSON.stringify({ error: msg }));
}

async function start() {
  const PORT = Number(process.env.PORT ?? 8787);
  const SUBMIT = process.env.SUBMIT === "1";
  const RAIL = process.env.RAIL_ADDRESS;
  // KMS-based signer: requires PRIVATE_KEY or KMS_MODE=stub that the kmssigner module handles.
  // For SUBMIT behavior, a SUBMIT_KEY (private key) must be provided to send the on-chain tx.
  const SUBMIT_KEY = process.env.SUBMIT_KEY;
  const server = http.createServer(async (req, res) => {
    if (req.method !== "POST" || req.url !== "/sign") return bad(res, 404, "not found");

    try {
      const body = await new Promise<string>((resolve) => {
        let data = ""; req.on("data", (c) => data += c); req.on("end", () => resolve(data));
      });
  const { id, released, settledAt } = JSON.parse(body || "{}");
  if (!id || typeof released !== "boolean" || !settledAt) return bad(res, 400, "id,released,settledAt required");

      // Sign typed data for ExternalRailEIP712
      const net = await hre.ethers.provider.getNetwork();
      const domain = {
        name: "ExternalRailEIP712",
        version: "1",
        chainId: Number(net.chainId),
        verifyingContract: RAIL ?? hre.ethers.ZeroAddress,
      } as const;
      const types: Record<string, Array<{ name: string; type: string }>> = { Receipt: [
        { name: "id", type: "bytes32" },
        { name: "released", type: "bool" },
        { name: "settledAt", type: "uint64" }
      ] };
  const value = { id, released, settledAt: Number(settledAt) };
  const sig = await signTypedData(domain, types, value);

      let txHash: string | undefined;
      if (SUBMIT) {
        if (!RAIL) return bad(res, 400, "RAIL_ADDRESS required when SUBMIT=1");
        // SUBMIT requires a submission signer. We prefer explicit SUBMIT_KEY for security.
        if (!SUBMIT_KEY) return bad(res, 400, "SUBMIT_KEY required to submit on-chain");
        const submitWallet = new hre.ethers.Wallet(SUBMIT_KEY, hre.ethers.provider);
        const rail = await hre.ethers.getContractAt("ExternalRailEIP712", RAIL, submitWallet);
        // Caller must POST the full Transfer if they want us to submit on-chain.
        // Try to parse transfer from body (if provided there may be more fields); we reuse id/released/settledAt.
        const parsed = JSON.parse(body || "{}");
        const t = parsed.transfer ?? { id, asset: hre.ethers.ZeroAddress, from: submitWallet.address, to: submitWallet.address, amount: 0, metadata: "0x" };
        const tx = await rail.markWithReceipt(t, released, Number(settledAt), sig);
        const r = await tx.wait();
        txHash = r.transactionHash;
      }

      res.statusCode = 200; res.setHeader("content-type", "application/json");
      res.end(JSON.stringify({ signature: sig, submitted: !!txHash, txHash }));
    } catch (e:any) {
      console.error(e);
      return bad(res, 500, e?.message ?? String(e));
    }
  });

  server.listen(PORT, () => {
    console.log(`[eip712-signer] listening on :${PORT} submit=${SUBMIT} rail=${RAIL ?? "(none)"}`);
  });
}

start().catch((e) => { console.error(e); process.exit(1); });
