import { NextResponse } from 'next/server';
import { Client } from 'xrpl';
import { getAllXrplBalances, listXrplDexPairs } from '../../../../../../../cli/xrpl/xrpl-balance-checker';
import { getRlusdConfig } from '../../../../../../../cli/xrpl/rlusd-integration';
import { BookOfferCurrency } from 'xrpl';

const XRPL_NODE = process.env.XRPL_NODE || 'wss://s.altnet.rippletest.net:51233'; // Use testnet for development

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const account = searchParams.get('account');
  const action = searchParams.get('action');

  if (!account) {
    return NextResponse.json({ error: 'Account address is required' }, { status: 400 });
  }

  const client = new Client(XRPL_NODE);
  await client.connect();

  try {
    if (action === 'balances') {
      const balances = await getAllXrplBalances(client, account);
      return NextResponse.json({ data: balances });
    } else if (action === 'dex_pairs') {
      const takerGetsCurrency = searchParams.get('takerGetsCurrency');
      const takerGetsIssuer = searchParams.get('takerGetsIssuer');
      const takerPaysCurrency = searchParams.get('takerPaysCurrency');
      const takerPaysIssuer = searchParams.get('takerPaysIssuer');

      let takerGets: BookOfferCurrency;
      if (takerGetsCurrency === 'XRP') {
        takerGets = 'XRP';
      } else if (takerGetsCurrency && takerGetsIssuer) {
        takerGets = { currency: takerGetsCurrency, issuer: takerGetsIssuer } as BookOfferCurrency;
      } else {
        return NextResponse.json({ error: 'Invalid takerGets parameters for DEX pairs' }, { status: 400 });
      }

      let takerPays: BookOfferCurrency;
      if (takerPaysCurrency === 'XRP') {
        takerPays = 'XRP';
      } else if (takerPaysCurrency && takerPaysIssuer) {
        takerPays = { currency: takerPaysCurrency, issuer: takerPaysIssuer } as BookOfferCurrency;
      } else {
        return NextResponse.json({ error: 'Invalid takerPays parameters for DEX pairs' }, { status: 400 });
      }

      const dexPairs = await listXrplDexPairs(client, takerGets, takerPays);
      return NextResponse.json({ data: dexPairs });
    } else {
      return NextResponse.json({ error: 'Invalid action specified' }, { status: 400 });
    }
  } catch (error: any) {
    console.error('XRPL API error:', error);
    return NextResponse.json({ error: error.message || 'Internal server error' }, { status: 500 });
  } finally {
    await client.disconnect();
  }
}
