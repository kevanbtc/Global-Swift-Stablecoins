import { Sealed } from "../generated/NavQuorumOracle/NavQuorumOracle"
import { NavPoint } from "../generated/schema"

export function handleSealed(e: Sealed): void {
  const id = e.transaction.hash.toHex() + "-" + e.logIndex.toString()
  const np = new NavPoint(id)
  np.instrument = e.params.instrument
  np.nav1e18 = e.params.point.nav1e18
  np.asOf = e.params.point.asOf
  np.epoch = e.params.point.epoch
  np.reserveHash = e.params.point.reserveHash
  np.tx = e.transaction.hash
  np.ts = e.block.timestamp
  np.save()
}
