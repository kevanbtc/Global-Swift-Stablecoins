# Stablecoin Executors & Tasks

This repo ships with simple Hardhat tasks to simulate off-chain executors for cross-chain rails and to set router defaults.

Tasks:

- `rail:cctp:release` / `rail:cctp:refund`
  - Marks a `CCTPExternalRail` transfer as released/refunded. Uses the rail’s `transferId(Transfer)` to compute the id then calls `markReleased/markRefunded` as the active signer (must be the configured executor).
- `rail:ccip:release` / `rail:ccip:refund`
  - Same as above for `CCIPRail`.
- `rail:eip712:release` / `rail:eip712:refund`
  - For `ExternalRailEIP712`. Computes the transfer id on-chain, signs an EIP-712 Receipt (id, released, settledAt) with the active signer, and calls `markWithReceipt`. The signer must be allowlisted via `setSigner`.
- `router:set`
  - Sets the default rail key for a token in `StablecoinRouter`.

Usage examples (parameters abbreviated):

```sh
# CCTP released as executor signer
npx hardhat rail:cctp:release \
  --contract 0xCCTP... \
  --asset 0xA... \
  --from 0xF... \
  --to 0xT... \
  --amount 1000000 \
  --meta 0x

# CCIP refund
npx hardhat rail:ccip:refund \
  --contract 0xCCIP... \
  --asset 0x0000000000000000000000000000000000000000 \
  --from 0xF... --to 0xT... --amount 123 --meta "note"

# EIP-712 External rail: release (signs typed data with active signer)
npx hardhat rail:eip712:release \
  --contract 0xX712... \
  --asset 0xA... \
  --from 0xF... \
  --to 0xT... \
  --amount 1000 \
  --meta "memo" \
  --settled-at 1699999999

# Router: token -> rail key mapping
npx hardhat router:set \
  --router 0xRouter... \
  --token 0xToken... \
  --railkey 0x...bytes32
```

Notes:

- For executor tasks, run with a signer that matches the rail’s `executor` address (set by the admin). Otherwise the call will revert.
- The `Transfer` struct is assembled from CLI params; the id is derived by calling `transferId` on the rail to avoid off-chain encoding errors.
- These tasks are meant for development and operator testing. In production, run a service that watches source-chain events (e.g., CCTP burns, CCIP deliveries), verifies attestations/proofs, and then calls the appropriate `mark*` function.
- For `ExternalRailEIP712`, ensure the signing account is allowlisted via `setSigner(s, true)`. The domain used is `{ name: "ExternalRailEIP712", version: "1", chainId, verifyingContract }`.
