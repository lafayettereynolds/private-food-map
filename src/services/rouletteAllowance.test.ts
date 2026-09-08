import { describe, expect, it } from 'vitest'
import { consumeRouletteAllowance } from './rouletteAllowance'
describe('daily roulette allowance', () => {
  it('persists one draw per local day and account, while premium stays unlimited', () => {
    const data = new Map<string, string>()
    const storage = { getItem: (key: string) => data.get(key) ?? null, setItem: (key: string, value: string) => { data.set(key, value) } }
    const day = new Date(2026, 8, 8, 23, 59)
    expect(consumeRouletteAllowance(storage, 'a', false, day)).toBe(true)
    expect(consumeRouletteAllowance(storage, 'a', false, day)).toBe(false)
    expect(consumeRouletteAllowance(storage, 'b', false, day)).toBe(true)
    expect(consumeRouletteAllowance(storage, 'a', true, day)).toBe(true)
    expect(consumeRouletteAllowance(storage, 'a', false, new Date(2026, 8, 9))).toBe(true)
    expect(consumeRouletteAllowance(storage, 'a', false, new Date(2026, 8, 9))).toBe(false)
  })
  it('fails closed when the allowance cannot be persisted', () => {
    expect(consumeRouletteAllowance({ getItem: () => null, setItem: () => { throw Error('storage') } }, 'a', false)).toBe(false)
  })
})
