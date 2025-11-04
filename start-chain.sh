#!/bin/bash

# Unykorn L1 Chain Startup Script
# This script starts the Besu QBFT network for Unykorn L1

echo "=== Starting Unykorn L1 Chain ==="
echo "Chain ID: 7777"
echo "Consensus: QBFT"
echo "Block Time: 2 seconds"
echo "RPC: http://localhost:8545"
echo "WebSocket: ws://localhost:8546"
echo ""

# Create data directory if it doesn't exist
mkdir -p ./data

# Start Besu with QBFT consensus
besu \
  --config-file=besu-config.toml \
  --genesis-file=genesis.json \
  --node-private-key-file=node.key \
  --logging=INFO \
  --miner-enabled \
  --miner-coinbase=0xdd2f1e6e4b28d1766f482b22e8a405423f1eddfd

echo ""
echo "Chain started successfully!"
echo "RPC available at: http://localhost:8545"
echo "WebSocket available at: ws://localhost:8546"
echo "Metrics available at: http://localhost:9545"
