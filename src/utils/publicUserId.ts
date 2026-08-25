const PUBLIC_ID_BASE = 100_000_000_000n
const PUBLIC_ID_RANGE = 900_000_000_000n

/**
 * Creates a stable, numeric-only public identifier without exposing the
 * internal account key used by local/cloud persistence.
 */
export function publicUserId(internalId: string) {
  let hash = 14_695_981_039_346_656_037n
  for (const character of internalId) {
    hash ^= BigInt(character.codePointAt(0) ?? 0)
    hash = BigInt.asUintN(64, hash * 1_099_511_628_211n)
  }
  return String(PUBLIC_ID_BASE + (hash % PUBLIC_ID_RANGE))
}
