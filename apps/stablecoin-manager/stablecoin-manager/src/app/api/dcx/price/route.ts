import { NextResponse } from 'next/server';
import { fetchCryptoPricesFromCoinGecko } from '@/lib/live-data.service';

export async function GET() {
  // CoinGecko IDs for major stablecoins
  const ids = ['usd-coin', 'tether', 'dai', 'frax', 'first-digital-usd'];
  const data = await fetchCryptoPricesFromCoinGecko(ids);
  
  return NextResponse.json({ data, ts: Date.now() });
}
