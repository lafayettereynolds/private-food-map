import { describe, expect, it } from 'vitest'
import { calculateVisitPayment, resolveVisitActualSpend, resolveVisitPaymentEdit, summarizeVisitSpend, visitReferencePrice } from './visitSpend'
import { restaurantCity } from './restaurantCity'

describe('single amount, automatic payment and independent dining reference', () => {
  it.each([
    ['aa', 200, 4, 50, 50], ['my_treat', 200, 4, 200, 50],
    ['treated', 200, 4, 0, 50], ['separate', 50, 4, 50, 50],
    ['other', 60, 4, 60, 60], [null, 50, 1, 50, 50],
  ] as const)('%s: amount %s / %s people produces personal %s and reference %s', (mode, amount, partySize, actual, reference) => {
    const payment = calculateVisitPayment(amount, mode, partySize)
    const visit = { ...payment, paymentMode: mode, partySize }
    expect(payment.myActualSpend).toBe(actual)
    expect(resolveVisitActualSpend(visit)).toBe(actual)
    expect(visitReferencePrice(visit)).toBe(reference)
    expect(summarizeVisitSpend([visit]).total).toBe(actual)
  })
  it('recalculates when amount, mode or party size changes, without stale explicit input', () => {
    const initial = { totalPrice: 175, myActualSpend: 301, paymentMode: 'aa' as const, partySize: 4 }
    expect(resolveVisitPaymentEdit(175, 'aa', 4, initial).myActualSpend).toBe(301)
    expect(resolveVisitPaymentEdit(200, 'aa', 4, initial).myActualSpend).toBe(50)
    expect(resolveVisitPaymentEdit(175, 'aa', 5, initial).myActualSpend).toBe(35)
    expect(resolveVisitPaymentEdit(175, 'treated', 4, initial).myActualSpend).toBe(0)
    expect(calculateVisitPayment(100, 'aa', 3).myActualSpend).toBe(33.33)
  })
  it('recovers omitted iOS fields but never treats unknown group payments as all paid or AA', () => {
    expect(resolveVisitActualSpend({ totalPrice: 17, partySize: 1 })).toBe(17)
    expect(resolveVisitActualSpend({ totalPrice: 200, partySize: 4 })).toBeNull()
    expect(resolveVisitActualSpend({ totalPrice: 200, partySize: 4, paymentMode: 'separate' })).toBeNull()
    expect(calculateVisitPayment(null, 'aa', 4).myActualSpend).toBeNull()
    expect(calculateVisitPayment(null, 'treated', 4).myActualSpend).toBe(0)
    expect(calculateVisitPayment(Number.NaN, 'separate', 4).myActualSpend).toBeNull()
    expect(calculateVisitPayment(100, 'aa', 0).myActualSpend).toBeNull()
  })
  it('sums personal payments, not reference prices', () => {
    const records = ['aa', 'my_treat', 'treated'].map(mode => ({
      ...calculateVisitPayment(200, mode as 'aa', 4), paymentMode: mode as 'aa', partySize: 4,
    }))
    expect(records.map(visitReferencePrice)).toEqual([50, 50, 50])
    expect(summarizeVisitSpend(records)).toEqual({ total: 250, recordedVisitCount: 3, unrecordedVisitCount: 0 })
  })
  it('uses only explicit city/address evidence', () => {
    expect(restaurantCity('', '中国浙江省杭州市滨江区江南大道')).toBe('杭州市')
    expect(restaurantCity('上海市', '浙江省杭州市')).toBe('上海市')
    expect(restaurantCity('', '北京市东城区')).toBe('北京市')
    expect(restaurantCity('', '杭州路 18 号')).toBe('')
  })
})
