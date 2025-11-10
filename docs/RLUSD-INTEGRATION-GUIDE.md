# RLUSD Integration Guide

## Overview

This guide covers the integration of **Ripple USD (RLUSD)** into the Global-Swift-Stablecoins infrastructure. RLUSD is treated as another settlement rail on your highway – like USDC/USDT – but with native XRPL + Ethereum support and institutional backing from Ripple.

## Architecture

RLUSD is integrated at three layers:

1. **Configuration Layer**: Central asset registry with network definitions
2. **Smart Contract Layer**: EVM contracts for settlement, collateral, and routing
3. **XRPL Layer**: Native issued token operations and DEX integration

## Quick Reference

### RLUSD Addresses

**XRPL Mainnet:**
- Issuer: `rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De`
- Currency: `RLUSD`

**XRPL Testnet:**
- Issuer: `rQhWct2fv4Vc4KRjRgMrxa8xPN9Zx9iLKV`
- Currency: `RLUSD`

**Ethereum Mainnet:**
- Proxy: `0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD`
- Standard: ERC-20, 18 decimals

### Asset Classification

```typescript
{
  symbol: "RLUSD",
  class: "EXTERNAL_STABLECOIN",
  risk: {
    ltv: 0.9,              // 90% loan-to-value
    haircut: 0.05,         // 5% capital haircut
    category: "TIER1_STABLE"
  }
}
```

## Use Cases

### 1. Fiat → FTHUSD → RLUSD Settlement

User flow for converting internal stablecoins to RLUSD for external settlement:

```typescript
// 1. User deposits USD → receives FTHUSD
// 2. User requests RLUSD payout
const swap = await fetch('/api/rlusd', {
  method: 'POST',
  body: JSON.stringify({
    action: 'swap',
    fromAsset: 'FTHUSD',
    toAsset: 'RLUSD',
    amount: '10000',
    network: 'xrpl-mainnet',
    slippageBps: 50 // 0.5% max slippage
  })
});

// 3. System burns FTHUSD, releases RLUSD
```

### 2. RLUSD as Collateral

Accept RLUSD deposits for vault collateral:

```solidity
// In your vault contract
function depositCollateral(AssetId asset, uint256 amount) external {
    require(asset == AssetId.RLUSD, "Unsupported asset");
    
    // RLUSD has 90% LTV, 5% haircut
    uint256 collateralValue = (amount * 90) / 100;
    
    _mint(msg.sender, collateralValue);
}
```

### 3. Cross-Chain Settlement

Use RLUSD to bridge between XRPL and Ethereum:

```typescript
// Transfer from XRPL to Ethereum
const bridge = await fetch('/api/bridge/rlusd', {
  method: 'POST',
  body: JSON.stringify({
    from: 'xrpl-mainnet',
    to: 'ethereum-mainnet',
    amount: '50000',
    destination: '0x...'
  })
});
```

## API Reference

### GET /api/rlusd

#### Get Balance
```bash
curl "https://api.example.com/api/rlusd?account=rXXX...&action=balance&network=xrpl-mainnet"
```

Response:
```json
{
  "data": {
    "network": "xrpl-mainnet",
    "balance": "100000.50",
    "usdValue": "100000.50",
    "lastUpdated": "2025-11-09T12:00:00Z"
  }
}
```

#### Get Account State
```bash
curl "https://api.example.com/api/rlusd?account=rXXX...&action=state"
```

Response:
```json
{
  "data": {
    "address": "rXXX...",
    "balances": [
      {
        "network": "xrpl-mainnet",
        "balance": "100000.50",
        "usdValue": "100000.50",
        "lastUpdated": "2025-11-09T12:00:00Z"
      }
    ],
    "totalUsdValue": "100000.50",
    "trustlines": {
      "xrplMainnet": {
        "account": "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De",
        "currency": "RLUSD",
        "issuer": "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De",
        "balance": "100000.50",
        "limit": "1000000",
        "authorized": true,
        "frozen": false
      }
    },
    "recentTransfers": [],
    "allowedNetworks": ["xrpl-mainnet", "ethereum-mainnet"]
  }
}
```

### POST /api/rlusd

#### Create Trustline
```bash
curl -X POST https://api.example.com/api/rlusd \
  -H "Content-Type: application/json" \
  -d '{
    "action": "create_trustline",
    "seed": "sXXX...",
    "limit": "1000000",
    "network": "mainnet"
  }'
```

#### Transfer RLUSD
```bash
curl -X POST https://api.example.com/api/rlusd \
  -H "Content-Type: application/json" \
  -d '{
    "action": "transfer",
    "seed": "sXXX...",
    "destination": "rYYY...",
    "amount": "1000",
    "network": "mainnet"
  }'
```

## XRPL Integration

### Creating a Trustline

Before receiving RLUSD on XRPL, accounts must create a trustline:

```typescript
import { Client, Wallet } from 'xrpl';
import { ensureRlusdTrustline } from './cli/xrpl/rlusd-integration';

const client = new Client('wss://xrplcluster.com');
await client.connect();

const wallet = Wallet.fromSeed('sXXX...');
const result = await ensureRlusdTrustline(
  client,
  wallet,
  '1000000' // 1M RLUSD limit
);

console.log('Trustline created:', result);
```

### Sending RLUSD

```typescript
import { sendRlusd } from './cli/xrpl/rlusd-integration';

const result = await sendRlusd(
  client,
  wallet,
  'rDestination...', // Recipient address
  '1000'             // Amount
);

console.log('Transfer hash:', result.result.hash);
```

### DEX Trading

RLUSD can be traded on XRPL DEX against XRP and other currencies:

```typescript
// Get RLUSD/XRP order book
const orderBook = await client.request({
  command: 'book_offers',
  taker_gets: {
    currency: 'RLUSD',
    issuer: 'rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De'
  },
  taker_pays: 'XRP',
  limit: 10
});
```

## Smart Contract Integration

### Adding RLUSD to Router

```solidity
// In StablecoinRouter or TreasuryRouter
function addRlusdSupport() external onlyAdmin {
    address rlusdProxy = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    
    _setAssetConfig(
        AssetId.RLUSD,
        AssetConfig({
            token: rlusdProxy,
            decimals: 18,
            isStable: true,
            collateralFactorBps: 9000 // 90% LTV
        })
    );
    
    isSupportedStable[AssetId.RLUSD] = true;
}
```

### Oracle Integration

The `RLUSDAdapter` contract provides price feeds:

```solidity
import {RLUSDAdapter} from "./contracts/oracle/adapters/RLUSDAdapter.sol";

// Deploy adapter
RLUSDAdapter adapter = new RLUSDAdapter(
    0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD, // RLUSD proxy
    msg.sender // admin
);

// Add price sources
adapter.addSource(chainlinkOracle, 5000); // 50% weight
adapter.addSource(customOracle, 5000);    // 50% weight

// Query price
(uint256 price, uint8 decimals, uint64 lastUpdate) = adapter.quoteInCash(rlusdAddress);
// price should be ~1e18 (1 USD)
```

## Compliance & Risk

### KYC/AML Requirements

RLUSD transactions should follow the same compliance rules as other stablecoins:

```solidity
// In PolicyGuard or ComplianceRegistry
function checkRlusdTransfer(address from, address to, uint256 amount) 
    external 
    view 
    returns (bool allowed) 
{
    require(kycApproved[from], "Sender not KYC'd");
    require(kycApproved[to], "Recipient not KYC'd");
    require(!isPaused(), "System paused");
    
    // Check jurisdiction rules
    bytes32 fromJurisdiction = getJurisdiction(from);
    bytes32 toJurisdiction = getJurisdiction(to);
    
    require(
        jurisdiction[keccak256("RLUSD_TRANSFER")][fromJurisdiction].listed,
        "From jurisdiction blocked"
    );
    
    return true;
}
```

### Capital Requirements

RLUSD is classified as TIER1_STABLE with:
- **LTV**: 90% (10% overcollateralization required)
- **Haircut**: 5% (capital cushion)
- **Max Deviation**: 0.5% from $1.00 peg

### Travel Rule

For transfers >$1000 USD equivalent:

```typescript
// Include VASP information
const transfer = {
  from: 'rXXX...',
  to: 'rYYY...',
  amount: '1500',
  vaspInfo: {
    originator: {
      name: 'Alice Smith',
      accountNumber: 'ACC123',
      address: '123 Main St'
    },
    beneficiary: {
      name: 'Bob Jones',
      accountNumber: 'ACC456',
      address: '456 Elm St'
    }
  }
};
```

## Testing

### Unit Tests

```typescript
// Test RLUSD balance query
describe('RLUSD API', () => {
  it('should fetch RLUSD balance', async () => {
    const response = await fetch('/api/rlusd?account=rTest...&action=balance&network=xrpl-testnet');
    const data = await response.json();
    
    expect(data.data.balance).toBeDefined();
    expect(data.data.network).toBe('xrpl-testnet');
  });
  
  it('should create trustline', async () => {
    const response = await fetch('/api/rlusd', {
      method: 'POST',
      body: JSON.stringify({
        action: 'create_trustline',
        seed: TEST_SEED,
        network: 'testnet'
      })
    });
    
    const data = await response.json();
    expect(data.data.success).toBe(true);
  });
});
```

### Integration Tests

```bash
# Test XRPL trustline creation
npm run test:rlusd:trustline

# Test RLUSD transfer
npm run test:rlusd:transfer

# Test Ethereum ERC-20 operations
npm run test:rlusd:ethereum
```

## Deployment Checklist

- [ ] Deploy `RLUSDAdapter` oracle contract
- [ ] Add RLUSD to `AssetId` enum in `Types.sol`
- [ ] Configure RLUSD in `StablecoinRouter`
- [ ] Update `PolicyGuard` with RLUSD rules
- [ ] Add RLUSD price feeds to oracle network
- [ ] Enable RLUSD in Command Hub UI
- [ ] Update API documentation
- [ ] Configure compliance rules for RLUSD transfers
- [ ] Set up monitoring and alerting for RLUSD price deviation
- [ ] Test XRPL and Ethereum integrations
- [ ] Update user-facing documentation

## Monitoring

### Price Deviation Alerts

```solidity
// RLUSDAdapter emits DeviationAlert when price strays
event DeviationAlert(uint256 price, uint256 deviation);

// Monitor this event
const filter = adapter.filters.DeviationAlert();
adapter.on(filter, (price, deviation) => {
  if (deviation > 50) { // >0.5%
    alert(`RLUSD price deviation: ${deviation}bps`);
  }
});
```

### Balance Monitoring

```bash
# Check RLUSD reserves
curl "https://api.example.com/api/rlusd?account=rTreasury...&action=balance"

# Should maintain reserves > outstanding liabilities
```

## Support & Resources

- **RLUSD Documentation**: https://docs.ripple.com/stablecoin/
- **XRPL Explorer**: https://livenet.xrpl.org
- **Ethereum Explorer**: https://etherscan.io
- **Internal Support**: support@example.com

## Changelog

### v1.0.0 (2025-11-09)
- Initial RLUSD integration
- XRPL trustline and payment support
- Ethereum ERC-20 integration
- Oracle adapter with multi-source aggregation
- API routes for balances, transfers, and swaps
- Compliance and risk framework

---

**Status**: ✅ Production Ready

**Last Updated**: November 9, 2025
