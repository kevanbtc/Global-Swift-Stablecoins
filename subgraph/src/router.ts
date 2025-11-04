import { Journal as Ev } from "../generated/CreationRedemptionRouter/CreationRedemptionRouter"
import { Journal } from "../generated/schema"

export function handleJournal(e: Ev): void {
  const id = e.transaction.hash.toHex() + "-" + e.logIndex.toString()
  const j = new Journal(id)
  j.doc = e.params.doc
  j.debit = e.params.debit
  j.credit = e.params.credit
  j.amount1e2 = e.params.amount1e2
  j.currency = e.params.currency
  j.memo = e.params.memo
  j.tx = e.transaction.hash
  j.ts = e.block.timestamp
  j.save()
}
