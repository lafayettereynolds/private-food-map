/** Product decision, 2026-09-07: all historical amounts without a currency
 * are CNY. This is an explicit compatibility policy, never a city inference.
 * Missing/invalid amounts stay unknown; an explicit currency is preserved. */
export const LEGACY_AMOUNT_CURRENCY = 'CNY' as const

export function resolveRecordedMoney(value: number | null | undefined, currency?: string | null) {
  if (value == null || !Number.isFinite(value) || value < 0) return null
  const resolvedCurrency = currency == null ? LEGACY_AMOUNT_CURRENCY : currency
  if (!/^[A-Z]{3}$/.test(resolvedCurrency)) return null
  return { value, currency: resolvedCurrency }
}
