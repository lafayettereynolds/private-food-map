/** Reuse accepted GPS briefly; refresh expired GPS instead of silently losing
 * nearby ranking after the user spends time typing. Provider refresh remains
 * bounded, and failure leaves the city search usable without an invented fix. */
export async function resolveRestaurantSearchLocation<T extends { acquiredAt: number }>(
  accepted: T | null,
  refresh: () => Promise<T>,
  now: () => number = Date.now,
): Promise<T | null> {
  if (!accepted) return null
  const fresh = (value: T) => now() - value.acquiredAt >= 0 && now() - value.acquiredAt <= 15_000
  if (fresh(accepted)) return accepted
  try {
    const updated = await refresh()
    return fresh(updated) ? updated : null
  } catch {
    return null
  }
}
