import { describe, expect, it } from 'vitest'
import type { TasteMapLocationDTO } from '../platform/TasteMapPlatform'
import { MapLocationDeliveryGate } from './mapLocationLifecycle'

const now = Date.parse('2026-09-06T00:00:00Z')
const fix = (timestamp = now, overrides: Partial<TasteMapLocationDTO> = {}): TasteMapLocationDTO => ({
  latitude: 1, longitude: 1, timestamp: new Date(timestamp).toISOString(), horizontalAccuracy: 12,
  accuracyMode: 'full', authorizationStatus: 'allowed', ...overrides,
})

describe('Map GPS UI delivery lifecycle', () => {
  it('accepts only the current request after a foreground refresh', () => {
    const gate = new MapLocationDeliveryGate()
    const old = gate.begin(now)
    const current = gate.begin(now + 30_000)
    expect(gate.accept(fix(now + 30_000), old, now + 30_000)).toBe(false)
    expect(gate.accept(fix(now + 30_000), current, now + 30_000)).toBe(true)
  })

  it('invalidates a departed owner/page request without cancelling another sensor consumer', () => {
    const gate = new MapLocationDeliveryGate()
    const request = gate.begin(now)
    gate.invalidate(now + 2_000)
    expect(gate.isCurrent(request)).toBe(false)
    expect(gate.accept(fix(now + 2_000), request, now + 2_000)).toBe(false)
  })

  it('rejects cached events from before the resumed request even if they are under 15 seconds old', () => {
    const gate = new MapLocationDeliveryGate()
    gate.begin(now)
    expect(gate.accept(fix(now - 5_000), undefined, now)).toBe(false)
    expect(gate.accept(fix(now - 500), undefined, now)).toBe(true)
  })

  it('rejects expired, future, invalid, denied and low-accuracy deliveries', () => {
    for (const value of [fix(now - 20_000), fix(now + 6_000), fix(now, { latitude: NaN }),
      fix(now, { longitude: 181 }), fix(now, { horizontalAccuracy: 101 }),
      fix(now, { horizontalAccuracy: -1 }), fix(now, { authorizationStatus: 'denied' })]) {
      const gate = new MapLocationDeliveryGate()
      const request = gate.begin(now)
      expect(gate.accept(value, request, now)).toBe(false)
    }
  })

  it('allows honestly labelled reduced accuracy only within the Native policy limit', () => {
    const gate = new MapLocationDeliveryGate()
    const request = gate.begin(now)
    expect(gate.accept(fix(now, { accuracyMode: 'reduced', horizontalAccuracy: 5_000 }), request, now)).toBe(true)
    expect(gate.accept(fix(now, { accuracyMode: 'reduced', horizontalAccuracy: 10_001 }), request, now)).toBe(false)
  })

  it('does not replace a newer accepted event with a late earlier event', () => {
    const gate = new MapLocationDeliveryGate()
    gate.begin(now)
    expect(gate.accept(fix(now + 2_000), undefined, now + 3_000)).toBe(true)
    expect(gate.accept(fix(now + 1_000), undefined, now + 3_000)).toBe(false)
  })
})
