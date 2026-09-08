import { describe, expect, it } from 'vitest'
import { resolveRecordedMoney } from './legacyMoney'

describe('approved historical currency compatibility', () => {
  it('treats historical amounts as CNY, including a recorded zero', () => {
    expect(resolveRecordedMoney(100)).toEqual({ value: 100, currency: 'CNY' })
    expect(resolveRecordedMoney(0, null)).toEqual({ value: 0, currency: 'CNY' })
  })
  it('does not overwrite an explicit currency or fabricate missing money', () => {
    expect(resolveRecordedMoney(100, 'USD')).toEqual({ value: 100, currency: 'USD' })
    for (const value of [null, undefined, NaN, Infinity, -1]) expect(resolveRecordedMoney(value)).toBeNull()
    expect(resolveRecordedMoney(100, '')).toBeNull()
  })
})
