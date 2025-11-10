import { Client, Wallet, IssuedCurrencyAmount, AccountInfoResponse, BookOffersResponse, dropsToXrp, AccountLinesResponse, BookOfferCurrency } from "xrpl";
import { getRlusdConfig, RlusdConfig } from "./rlusd-integration";

/**
 * @notice Fetches the balance of a specific issued currency for an XRPL account.
 * @param client The XRPL client instance.
 * @param account The XRPL account address.
 * @param currency The currency code (e.g., "RLUSD").
 * @param issuer The issuer address of the currency.
 * @returns The balance as a string, or "0" if not found.
 */
export async function getIssuedCurrencyBalance(
  client: Client,
  account: string,
  currency: string,
  issuer: string
): Promise<string> {
  try {
    const accountLines: AccountLinesResponse = await client.request({
      command: "account_lines",
      account: account,
      ledger_index: "current",
    });

    if (accountLines.result && accountLines.result.lines) {
      const issuedBalance = accountLines.result.lines.find(
        (line) =>
          line.currency === currency && line.account === issuer
      );
      return issuedBalance ? issuedBalance.balance : "0";
    }
    return "0";
  } catch (error) {
    console.error(`Error fetching ${currency} balance for ${account}:`, error);
    return "0";
  }
}

/**
 * @notice Fetches all balances for an XRPL account, including XRP and issued currencies.
 * @param client The XRPL client instance.
 * @param account The XRPL account address.
 * @returns An object containing all balances.
 */
export async function getAllXrplBalances(
  client: Client,
  account: string
): Promise<Record<string, string>> {
  const balances: Record<string, string> = {};
  try {
    // Get XRP balance
    const accountInfo: AccountInfoResponse = await client.request({
      command: "account_info",
      account: account,
      ledger_index: "current",
    });
    balances["XRP"] = dropsToXrp(accountInfo.result.account_data.Balance);

    // Get issued currency balances (trustlines)
    const accountLines = await client.request({
      command: "account_lines",
      account: account,
      ledger_index: "current",
    });

    if (accountLines.result && accountLines.result.lines) {
      for (const line of accountLines.result.lines) {
        balances[`${line.currency}.${line.account}`] = line.balance;
      }
    }

    // Get RLUSD balance specifically
    const rlusdConfig = getRlusdConfig("mainnet"); // Assuming mainnet for operational use
    const rlusdBalance = await getIssuedCurrencyBalance(
      client,
      account,
      rlusdConfig.currency,
      rlusdConfig.issuer
    );
    balances[`${rlusdConfig.currency}.${rlusdConfig.issuer}`] = rlusdBalance;

  } catch (error) {
    console.error(`Error fetching all XRPL balances for ${account}:`, error);
  }
  return balances;
}

/**
 * @notice Lists available DEX pairs on the XRPL for a given asset.
 * @param client The XRPL client instance.
 * @param takerGets The asset the taker wants to buy (e.g., {currency: "RLUSD", issuer: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"} or "XRP").
 * @param takerPays The asset the taker wants to sell (e.g., {currency: "USD", issuer: "rvYAfWj5gh67oV6fW32ZzP3Aw4Eubs59B"} or "XRP").
 * @returns An array of available offers.
 */
export async function listXrplDexPairs(
  client: Client,
  takerGets: BookOfferCurrency,
  takerPays: BookOfferCurrency
): Promise<any[]> {
  try {
    const offers: BookOffersResponse = await client.request({
      command: "book_offers",
      taker_gets: takerGets,
      taker_pays: takerPays,
      ledger_index: "current",
    });
    return offers.result.offers || [];
  } catch (error) {
    console.error("Error listing XRPL DEX pairs:", error);
    return [];
  }
}
