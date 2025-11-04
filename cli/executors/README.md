# Off-chain Executors (skeletons)

Minimal executor/signer processes for development. These are not production-grade services, but are enough to exercise the rails locally and in testnets.

Common requirements:

- Node 18+
- tsx (already in devDependencies)
- Hardhat configured network and account as needed

## CCIP executor

Watches `CCIPRail` for `RailPrepared` events and marks release/refund using the active signer.

Env:

- `RAIL_ADDRESS` (required) — CCIPRail address
- `ACTION` — `release` | `refund` (default `release`)
- `INTERVAL_MS` — poll interval (default 5000)
- `FROM_BLOCK` — optional start block

Run (PowerShell):

```powershell
$env:RAIL_ADDRESS="0xCCIP..."; $env:ACTION="release"; npm run exec:ccip
```

## CCTP executor

Watches `CCTPExternalRail` for `RailPrepared` events and marks release/refund using the active signer.

Env:

- `RAIL_ADDRESS` (required) — CCTPExternalRail address
- `ACTION` — `release` | `refund` (default `release`)
- `INTERVAL_MS` — poll interval (default 5000)
- `FROM_BLOCK` — optional start block

Run (PowerShell):

```powershell
$env:RAIL_ADDRESS="0xCCTP..."; $env:ACTION="refund"; npm run exec:cctp
```

## EIP-712 signer (ExternalRailEIP712)

Exposes a `/sign` HTTP endpoint producing EIP-712 Receipt signatures; optionally submits on-chain.

Env:

- `PRIVATE_KEY` (required) — signer private key
- `RAIL_ADDRESS` — ExternalRailEIP712 address (required if `SUBMIT=1`)
- `SUBMIT` — set to `1` to also submit on-chain
- `PORT` — HTTP port (default 8787)

Run (PowerShell):

```powershell
$env:PRIVATE_KEY="0xabc..."; $env:RAIL_ADDRESS="0xX712..."; npm run exec:eip712
# POST sample
Invoke-RestMethod -Uri http://localhost:8787/sign -Method Post -Body '{"id":"0x...","released":true,"settledAt":1699999999}' -ContentType 'application/json'
```

Notes:

- In production, replace polling with robust event ingestion (webhooks/queues), failure retries, metrics, and secure key management (HSM/KMS). Add source-chain attestation verification (Circle CCTP, CCIP) before calling `mark*`.
- For ExternalRailEIP712, ensure the signer is allowlisted via `setSigner` on the rail.
