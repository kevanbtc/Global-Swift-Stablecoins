# Compliant Bill Token — Hardhat Scaffold (UUPS + Basel + ISO 20022)

This is a drop‑in Hardhat project you can run end‑to‑end: compile, test, and deploy a rebasing, KYC‑gated, Basel‑guarded bill token with ISO 20022 audit events.

## Quickstart

```bash
# install dev deps (Node 18+)
npm i -D hardhat @nomicfoundation/hardhat-toolbox \
  @openzeppelin/contracts-upgradeable @openzeppelin/hardhat-upgrades \
  typescript ts-node dotenv

# compile
npx hardhat compile

# test
npx hardhat test

# local deploy
npx hardhat run scripts/01_deploy.ts --network hardhat
```

See `scripts/` for role grants and demo flows.