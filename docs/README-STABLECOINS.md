# Stablecoin routing and PoR guard

This folder introduces minimal building blocks to support “all-stablecoins, all-rails” without breaking existing flows.

Components:

- `StablecoinRegistry.sol` — registry of third‑party stablecoin metadata and preferred rails (default, CCTP, CCIP). Stores a `reserveId`, optional PoR adapter, and rail keys (for `RailRegistry`).
- `IReleaseGuard.sol` — small interface for release guards used by rails.
- `PoRGuard.sol` — checks an `IProofOfReserves` adapter for a token+amount using `StablecoinRegistry` metadata. If no adapter is set, it does not block.
- `StablecoinAwareERC20Rail.sol` — ERC20 escrow rail that consults a `IReleaseGuard` before releasing. Useful to enforce PoR or other policy rules.
- `CCTPExternalRail.sol` — specialized external rail for Circle CCTP legs. Uses an authorized `executor` to mark release/refund after off‑chain settlement; distinct transferId salt.
- `CCIPRail.sol` — executor‑marked external rail for CCIP legs. Mirrors `ExternalRail` with a distinct transferId salt.
- `ExternalRailEIP712.sol` — external rail that requires an EIP‑712 signed receipt from an approved signer to mark release/refund (bank/shared‑ledger path). Includes a `hashReceipt` helper for tests/services.
- `StablecoinRouter.sol` — convenience router that forwards `prepare` to a configured rail per token via the on‑chain `RailRegistry`.

Notes:

- All rails implement the shared `IRail` interface and are designed to work with the existing `RailRegistry` and `SettlementHub2PC`.
- These contracts are intentionally lean stubs to keep CI green and make it easy to iterate. You can extend them with richer validation (EIP‑712 receipts, attestation checks, CCIP/CCTP listeners) as you wire real executors.
- The PoR guard uses `IProofOfReserves.checkRedeem(reserveId, amount)` as a conservative outbound check. If no adapter is configured, releases are permitted.

Wiring tips:

- Deploy `StablecoinRegistry` and set metadata for the tokens you plan to support.
- Deploy a `PoRGuard` pointing at the registry (optional) and pass it into `StablecoinAwareERC20Rail`.
- Register rails in `RailRegistry` (e.g., keys like `keccak256("ERC20_RAIL")`, `keccak256("USDC_CCTP")`, `keccak256("CCIP_RAIL")`).
- Use `StablecoinRouter` to route same‑chain ERC‑20 prepares for third‑party tokens while the hub continues to orchestrate two‑leg atomic deals.

Try it (Foundry):

- Deploy infra: run the script `script/DeployStablecoinInfra.s.sol` with your deployer key to stand up registry, guard, rails, router, and register standard keys.
- Run tests: the Foundry suite includes `foundry/test/stable/StableRails.t.sol` which validates PoR‑guarded denial, router prepare routing, and CCTP/CCIP executor marking.
  It also includes `foundry/test/stable/ExternalRailEIP712.t.sol` to validate EIP‑712 receipts.
