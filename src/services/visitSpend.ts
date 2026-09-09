import type { PaymentMode, Visit } from '../types/domain'

type VisitSpendSource = Partial<Pick<Visit, 'deletedAt' | 'myActualSpend' | 'partySize' | 'paymentMode' | 'totalPrice'>>

export interface VisitSpendSummary {
  total: number
  recordedVisitCount: number
  unrecordedVisitCount: number
}

function validMoney(value: number | null | undefined) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
}

function currency(value: number) {
  return Math.round(value * 100) / 100
}

/** Read-only history label; omitted Native optional fields equal explicit null. */
export function visitSpendLabel(visit: VisitSpendSource & { pricePerPerson?: number | null }) {
  const actual = resolveVisitActualSpend(visit)
  const total = validMoney(visit.totalPrice)
  const reference = validMoney(visit.pricePerPerson)
  if (actual !== null) {
    return `我的消费 ¥${actual}${total !== null && total !== actual ? ` · 整桌 ¥${total}` : ''}`
  }
  return total !== null
    ? `整桌 ¥${total}${reference !== null ? ` · ¥${reference}/人` : ''}`
    : '未记价格'
}

/**
 * Returns what this user actually paid for one Visit.
 *
 * Explicit `myActualSpend` is always authoritative. The remaining branches
 * recover records written by the old Hybrid one-price form, but only when the
 * selected payment mode makes the user's share deterministic.
 */
export function resolveVisitActualSpend(visit: VisitSpendSource): number | null {
  if (visit.deletedAt) return null
  const explicit = validMoney(visit.myActualSpend)
  if (explicit !== null) return currency(explicit)

  const paymentMode = visit.paymentMode == null || (typeof visit.paymentMode === 'string' && visit.paymentMode.trim() === '')
    ? null
    : visit.paymentMode
  if (paymentMode === 'treated') return 0
  const total = validMoney(visit.totalPrice)
  if (total === null) return null

  switch (paymentMode) {
    case null:
      // Missing Codable keys and explicit null are equivalent. An old group
      // record without a payment choice is not evidence that the owner paid all.
      return visit.partySize === 1 ? currency(total) : null
    case 'my_treat':
      return currency(total)
    case 'aa': {
      const partySize = visit.partySize
      return Number.isInteger(partySize) && (partySize ?? 0) > 0
        ? currency(total / (partySize as number))
        : null
    }
    case 'separate':
    case 'other':
      return null
    default:
      return null
  }
}

/** One editable amount; personal modes never masquerade as a table total. */
export function calculateVisitPayment(amount: number | null, paymentMode: PaymentMode | null, partySize: number) {
  const personal = paymentMode === 'separate' || paymentMode === 'other'
  const totalPrice = personal ? null : validMoney(amount)
  const myActualSpend = personal ? validMoney(amount) : resolveVisitActualSpend({ totalPrice, paymentMode, partySize })
  return { totalPrice, myActualSpend: myActualSpend === null ? null : currency(myActualSpend) }
}

/** Dining-cost reference is not personal expenditure (e.g. a guest pays zero). */
export function visitReferencePrice(visit: VisitSpendSource): number | null {
  const total = validMoney(visit.totalPrice)
  if (total !== null && Number.isInteger(visit.partySize) && (visit.partySize ?? 0) > 0) return Math.round(total / visit.partySize!)
  if (visit.paymentMode === 'separate' || visit.paymentMode === 'other') {
    const own = validMoney(visit.myActualSpend)
    return own === null ? null : Math.round(own)
  }
  return null
}

export function visitPaymentInputAmount(visit: VisitSpendSource): number | null {
  if (visit.paymentMode === 'separate' || visit.paymentMode === 'other') return validMoney(visit.myActualSpend)
  const total = validMoney(visit.totalPrice)
  if (total !== null) return total
  const actual = validMoney(visit.myActualSpend)
  if (actual === null) return null
  return visit.paymentMode === 'aa' && Number.isInteger(visit.partySize) && (visit.partySize ?? 0) > 0
    ? currency(actual * visit.partySize!) : actual
}

/** Editing notes/photos must not rewrite an explicitly recorded historic amount. */
export function resolveVisitPaymentEdit(amount: number | null, paymentMode: PaymentMode | null, partySize: number, initial?: VisitSpendSource) {
  if (initial && amount === visitPaymentInputAmount(initial)
    && paymentMode === (initial.paymentMode ?? null) && partySize === (initial.partySize ?? 1)) {
    return { totalPrice: initial.totalPrice ?? null, myActualSpend: initial.myActualSpend ?? null }
  }
  return calculateVisitPayment(amount, paymentMode, partySize)
}

export function summarizeVisitSpend(visits: VisitSpendSource[]): VisitSpendSummary {
  let total = 0
  let recordedVisitCount = 0
  let activeVisitCount = 0
  for (const visit of visits) {
    if (visit.deletedAt) continue
    activeVisitCount += 1
    const value = resolveVisitActualSpend(visit)
    const normalizedValue = validMoney(value)
    if (normalizedValue === null) continue
    recordedVisitCount += 1
    total += normalizedValue
  }
  return {
    total: currency(total),
    recordedVisitCount,
    unrecordedVisitCount: activeVisitCount - recordedVisitCount,
  }
}

export function inferredActualSpend(
  totalPrice: number | null,
  myActualSpend: number | null,
  paymentMode: PaymentMode | null,
  partySize: number,
) {
  return resolveVisitActualSpend({
    deletedAt: null,
    totalPrice,
    myActualSpend,
    paymentMode,
    partySize,
  })
}
