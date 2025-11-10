export async function fetchCryptoPricesFromCoinGecko(ids: string[]): Promise<Record<string, number>> {
  // Base URL for the CoinGecko API
  const baseUrl = 'https://api.coingecko.com/api/v3';
  
  // Convert array of ids to comma-separated string
  const idsParam = ids.join(',');
  
  try {
    const response = await fetch(
      `${baseUrl}/simple/price?ids=${idsParam}&vs_currencies=usd`,
      {
        headers: {
          'Accept': 'application/json'
        }
      }
    );
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    const data = await response.json();
    
    // Transform the response to match our expected format
    const prices: Record<string, number> = {};
    for (const id of ids) {
      if (data[id]) {
        prices[id] = data[id].usd;
      }
    }
    
    return prices;
  } catch (error) {
    console.error('Error fetching crypto prices:', error);
    return {};
  }
}
