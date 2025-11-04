# Unykorn L1 Chain - Getting Started

## Overview
Unykorn L1 is a Besu-based blockchain network using QBFT consensus with chain ID 7777. This network serves as the foundation for the Unykorn ecosystem, providing a secure and scalable Layer 1 solution for decentralized finance and compliance.

## Network Specifications
- **Chain ID**: 7777
- **Consensus**: QBFT (IBFT 2.0)
- **Block Time**: 2 seconds
- **Native Currency**: Unykorn Ether (UNYETH)
- **RPC URL**: http://localhost:8545
- **WebSocket**: ws://localhost:8546
- **Genesis Validators**: 2 pre-configured validators

## Pre-funded Accounts
The genesis block includes two pre-funded developer accounts:
- `0xdd2f1e6e4b28d1766f482b22e8a405423f1eddfd` - 900 UNYETH
- `0x8626f6940e2eb28930efb4cef49b2d1f2c9c1199` - 900 UNYETH

## Quick Start

### 1. Prerequisites
- Java 11 or higher
- Besu client installed
- Node.js and npm (for deployment scripts)

### 2. Start the Chain
```bash
# Make the startup script executable (if needed)
chmod +x start-chain.sh

# Start the Unykorn L1 network
./start-chain.sh
```

The chain will start with:
- RPC endpoint: http://localhost:8545
- WebSocket endpoint: ws://localhost:8546
- Metrics endpoint: http://localhost:9545

### 3. Verify Chain Status
```bash
# Check if RPC is responding
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

### 4. Deploy Proof System
```bash
# Deploy NFT and fee collection contracts
forge script scripts/DeployProofSystem.s.sol \
  --rpc-url http://localhost:8545 \
  --chain-id 7777 \
  --broadcast \
  --private-key <your-private-key>
```

### 5. Deploy Core Contracts
```bash
# Deploy the full Unykorn ecosystem
forge script scripts/DeployUnykornChain.s.sol \
  --rpc-url http://localhost:8545 \
  --chain-id 7777 \
  --broadcast \
  --private-key <your-private-key>
```

## Configuration Files

### besu-config.toml
Main Besu configuration file with QBFT settings, RPC endpoints, and network parameters.

### genesis.json
Genesis block configuration with:
- Chain ID 7777
- QBFT consensus parameters
- Pre-funded accounts
- Validator addresses

### foundry.toml & hardhat.config.ts
Development tool configurations pointing to the local Unykorn L1 network.

## Development Tools

### Foundry
```bash
# Use the configured profile
forge script YourScript.s.sol --profile besu
```

### Hardhat
```bash
# Use the configured network
npx hardhat run scripts/deploy.js --network besu
```

## Monitoring

### Chain Metrics
- **RPC Health**: http://localhost:8545
- **WebSocket Health**: ws://localhost:8546
- **Besu Metrics**: http://localhost:9545

### Key Metrics to Monitor
- Block production (should be ~2 seconds)
- Validator participation
- Network peers
- Gas usage

## Troubleshooting

### Common Issues

1. **RPC Connection Refused**
   - Ensure Besu is running: `ps aux | grep besu`
   - Check logs: `tail -f data/logs/besu.log`
   - Verify port 8545 is not blocked

2. **Genesis Loading Issues**
   - Ensure `genesis.json` is valid JSON
   - Check file permissions
   - Verify Besu can read the genesis file

3. **Validator Issues**
   - Ensure validator private keys are accessible
   - Check validator addresses match genesis configuration
   - Verify QBFT configuration

### Logs and Debugging
```bash
# View Besu logs
tail -f data/logs/besu.log

# Check data directory
ls -la data/

# Verify genesis block
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0", false],"id":1}' \
  http://localhost:8545
```

## Security Notes

- This is a development network with pre-funded accounts
- Private keys for genesis accounts should be secured
- RPC endpoints are open for development - consider authentication for production
- Regular backups of the data directory are recommended

## Next Steps

1. **Deploy Contracts**: Use the deployment scripts to deploy your smart contracts
2. **Test Transactions**: Send test transactions using the pre-funded accounts
3. **Monitor Performance**: Track block times and network health
4. **Scale Up**: Add more validators for production readiness
5. **Integrate**: Connect your dApps and services to the RPC endpoint

## Support

For issues or questions:
- Check the Besu documentation: https://besu.hyperledger.org/
- Review QBFT consensus documentation
- Check network logs for detailed error messages
