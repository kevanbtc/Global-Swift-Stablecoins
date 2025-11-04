# API Documentation

## Core APIs

### Settlement API

```typescript
interface ISettlement {
    function settleTransaction(
        bytes32 txId,
        address[] parties,
        uint256[] amounts
    ) external returns (bool);
    
    function getSettlementStatus(
        bytes32 txId
    ) external view returns (SettlementStatus);
}
```

### ISO20022 Messaging API

```typescript
interface IISO20022 {
    function sendMessage(
        bytes32 messageId,
        string messageType,
        bytes payload
    ) external returns (bool);
    
    function receiveMessage(
        bytes32 messageId
    ) external view returns (Message);
}
```

### Oracle Network API

```typescript
interface IOracleNetwork {
    function submitPrice(
        bytes32 assetId,
        uint256 price,
        uint256 timestamp
    ) external returns (bool);
    
    function getLatestPrice(
        bytes32 assetId
    ) external view returns (PriceData);
}
```

### Compliance API

```typescript
interface ICompliance {
    function checkCompliance(
        address account,
        bytes32 txId
    ) external view returns (bool);
    
    function getComplianceStatus(
        address account
    ) external view returns (ComplianceStatus);
}
```

## Integration Examples

### Settlement Integration

```typescript
// Initialize settlement
const settlement = await Settlement.at(settlementAddress);

// Prepare settlement data
const txId = web3.utils.sha3('transaction-1');
const parties = [party1, party2];
const amounts = [amount1, amount2];

// Execute settlement
const result = await settlement.settleTransaction(
    txId,
    parties,
    amounts
);
```

### ISO20022 Integration

```typescript
// Initialize messaging
const iso20022 = await ISO20022.at(messagingAddress);

// Prepare message
const messageId = web3.utils.sha3('message-1');
const messageType = 'pacs.008.001.08';
const payload = encode(messageData);

// Send message
const result = await iso20022.sendMessage(
    messageId,
    messageType,
    payload
);
```

## REST API Endpoints

### Transaction API

```
POST /api/v1/transactions
GET /api/v1/transactions/{txId}
GET /api/v1/transactions/status/{txId}
```

### Asset Management API

```
POST /api/v1/assets
GET /api/v1/assets/{assetId}
PUT /api/v1/assets/{assetId}/price
```

### Compliance API

```
POST /api/v1/compliance/check
GET /api/v1/compliance/status/{accountId}
PUT /api/v1/compliance/update/{accountId}
```

## WebSocket API

### Price Feed Subscription

```typescript
// Subscribe to price updates
ws.subscribe('prices', {
    assets: ['BTC', 'ETH'],
    interval: '1m'
});

// Handle price updates
ws.on('price', (data) => {
    console.log('New price:', data);
});
```

### Settlement Notifications

```typescript
// Subscribe to settlement events
ws.subscribe('settlements', {
    accounts: [account1, account2]
});

// Handle settlement updates
ws.on('settlement', (data) => {
    console.log('Settlement update:', data);
});
```

## Error Handling

### Error Codes

```typescript
enum ErrorCode {
    INVALID_INPUT = 'E001',
    INSUFFICIENT_FUNDS = 'E002',
    UNAUTHORIZED = 'E003',
    COMPLIANCE_FAILED = 'E004',
    SETTLEMENT_FAILED = 'E005'
}
```

### Error Responses

```json
{
    "error": {
        "code": "E001",
        "message": "Invalid input parameters",
        "details": {
            "field": "amount",
            "reason": "Must be greater than 0"
        }
    }
}
```

## Rate Limits

| Endpoint | Rate Limit |
|----------|------------|
| /api/v1/transactions | 100/minute |
| /api/v1/assets | 200/minute |
| /api/v1/compliance | 50/minute |

## Authentication

### JWT Authentication

```typescript
// Request headers
{
    "Authorization": "Bearer <jwt_token>",
    "x-api-key": "<api_key>"
}
```

### API Key Generation

```typescript
// Generate API key
POST /api/v1/keys/generate
{
    "permissions": ["read", "write"],
    "expiry": "30d"
}
```

## SDK Examples

### JavaScript/TypeScript SDK

```typescript
import { UnykornSDK } from '@unykorn/sdk';

// Initialize SDK
const sdk = new UnykornSDK({
    apiKey: 'your-api-key',
    environment: 'production'
});

// Execute settlement
const settlement = await sdk.settlement.execute({
    txId: 'transaction-1',
    parties: [party1, party2],
    amounts: [amount1, amount2]
});
```

### Python SDK

```python
from unykorn_sdk import UnykornSDK

# Initialize SDK
sdk = UnykornSDK(
    api_key='your-api-key',
    environment='production'
)

# Execute settlement
settlement = sdk.settlement.execute(
    tx_id='transaction-1',
    parties=[party1, party2],
    amounts=[amount1, amount2]
)
```

## Best Practices

1. Always use SSL/TLS for API connections
2. Implement proper error handling
3. Use rate limiting in your applications
4. Keep API keys secure
5. Monitor API usage and errors

## Support

- API Support: api-support@unykorn.network
- Documentation: https://docs.unykorn.network
- SDK Repository: https://github.com/unykorn/sdk