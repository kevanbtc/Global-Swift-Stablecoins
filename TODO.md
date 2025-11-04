# Update Unykorn L1 Configuration to Real Values

## Information Gathered
- Real chain ID: 7777
- Real RPC URL: http://localhost:8545
- Real network name: Unykorn L1
- Real currency: Unykorn Ether (UNYETH)
- Funded dev accounts: 0xdd2f1e6e4b28d1766f482b22e8a405423f1eddfd, 0x8626f6940e2eb28930efb4cef49b2d1f2c9c1199
- Remove fake URLs like https://rpc.unykorn.layer1.network

## Plan
1. Update scripts/DeploymentSummary.s.sol
   - Change chain name to "Unykorn L1"
   - Change currency to "Unykorn Ether (UNYETH)"
   - Change RPC to "http://localhost:8545"
   - Remove fake URLs (explorer, websocket, IPFS)

2. Update scripts/DeployUnykornChain.s.sol
   - Change CHAIN_ID to 7777
   - Change CHAIN_NAME to "Unykorn L1"
   - Update explorer URL to remove fake domain

3. Update scripts/DeployExplorer.s.sol
   - Remove fake URLs for explorer, API, websocket

4. Update foundry.toml
   - Change chain_id to 7777
   - Change eth_rpc_url to "http://localhost:8545"

5. Update hardhat.config.ts
   - Change chainId to 7777
   - Change url to "http://localhost:8545"

## Dependent Files to be edited
- scripts/DeploymentSummary.s.sol
- scripts/DeployUnykornChain.s.sol
- scripts/DeployExplorer.s.sol
- foundry.toml
- hardhat.config.ts

## Followup steps
- Verify configurations are updated correctly
- Test deployment scripts with real chain ID and RPC
- Update any environment variables or deployment guides
