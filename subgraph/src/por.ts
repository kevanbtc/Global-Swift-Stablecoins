import { Published } from "../generated/ProofOfReserveEmitter/ProofOfReserveEmitter"
import { PoRRound } from "../generated/schema"

export function handlePublished(e: Published): void {
  const id = e.transaction.hash.toHex() + "-" + e.logIndex.toString()
  const r = new PoRRound(id)
  r.epoch = e.params.epoch
  r.totalAssets1e18 = e.params.totalAssets1e18
  r.cash1e18 = e.params.cash1e18
  r.tBills1e18 = e.params.tBills1e18
  r.documentsCid = e.params.documentsCid
  r.tx = e.transaction.hash
  r.ts = e.block.timestamp
  r.save()
}
