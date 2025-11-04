/**
 * Minimal attestation verifier used by executors in CI/dev.
 * Behavior:
 * - If SKIP_ATTESTATION=1 => returns true (dev convenience)
 * - If ALLOWLIST_IDS contains the transfer id (comma-separated), returns true
 * - Otherwise returns false (requires real verifier implementation)
 */

export async function verifyAttestation(railName: string, id: string, transfer: any): Promise<boolean> {
  if (process.env.SKIP_ATTESTATION === "1") return true;
  const allow = process.env.ALLOWLIST_IDS ?? "";
  if (!allow) return false;
  const arr = allow.split(",").map(s => s.trim().toLowerCase()).filter(Boolean);
  if (arr.includes(id.toLowerCase())) return true;
  return false;
}
