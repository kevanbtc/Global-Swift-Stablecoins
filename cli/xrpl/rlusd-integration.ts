import { Client, Wallet, Transaction } from "xrpl";

export interface RlusdConfig {
  currency: string;
  issuer: string;
}

export const RLUSD_XRPL_MAINNET: RlusdConfig = {
  currency: "RLUSD",
  issuer: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"
};

export const RLUSD_XRPL_TESTNET: RlusdConfig = {
  currency: "RLUSD",
  issuer: "rQhWct2fv4Vc4KRjRgMrxa8xPN9Zx9iLKV"
};

export function getRlusdConfig(network: "mainnet" | "testnet"): RlusdConfig {
  return network === "mainnet" ? RLUSD_XRPL_MAINNET : RLUSD_XRPL_TESTNET;
}

/**
 * @notice Ensures a trustline exists for RLUSD on the XRPL for a given wallet.
 * @param client The XRPL client instance.
 * @param wallet The wallet to create the trustline for.
 * @param limit The limit for the trustline (default: "1000000" for 1M RLUSD).
 * @returns The result of the TrustSet transaction.
 */
export async function ensureRlusdTrustline(
  client: Client,
  wallet: Wallet,
  limit: string = "1000000" // 1M RLUSD
) {
  const rlusdConfig = getRlusdConfig("mainnet"); // Assuming mainnet for operational use
  const tx: Transaction = {
    TransactionType: "TrustSet",
    Account: wallet.address,
    LimitAmount: {
      currency: rlusdConfig.currency,
      issuer: rlusdConfig.issuer,
      value: limit
    }
  };

  const prepared = await client.autofill(tx);
  const signed = wallet.sign(prepared);
  const result = await client.submitAndWait(signed.tx_blob);
  return result;
}

/**
 * @notice Sends RLUSD from one XRPL address to another.
 * @param client The XRPL client instance.
 * @param wallet The sending wallet.
 * @param destination The recipient address.
 * @param amount The amount of RLUSD to send.
 * @returns The result of the Payment transaction.
 */
export async function sendRlusd(
  client: Client,
  wallet: Wallet,
  destination: string,
  amount: string
) {
  const rlusdConfig = getRlusdConfig("mainnet"); // Assuming mainnet for operational use
  const tx: Transaction = {
    TransactionType: "Payment",
    Account: wallet.address,
    Destination: destination,
    Amount: {
      currency: rlusdConfig.currency,
      issuer: rlusdConfig.issuer,
      value: amount
    }
  };

  const prepared = await client.autofill(tx);
  const signed = wallet.sign(prepared);
  const result = await client.submitAndWait(signed.tx_blob);
  return result;
}
