import { describe, expect, it, vi } from 'vitest'
import { resolveRestaurantSearchLocation } from './restaurantSearchLocation'

describe('Text search GPS refresh', () => {
  it('refreshes a previously accepted 30-second-old fix and uses the new coordinates', async () => {
    const accepted = { acquiredAt: 1_000, latitude: 30.27, longitude: 120.15 }
    const updated = { acquiredAt: 31_000, latitude: 30.28, longitude: 120.16 }
    const refresh = vi.fn(async () => updated)
    expect(await resolveRestaurantSearchLocation(accepted, refresh, () => 31_000)).toEqual(updated)
    expect(refresh).toHaveBeenCalledTimes(1)
  })

  it('keeps city search available on refresh failure or stale replacement without reusing the stale origin', async () => {
    const accepted = { acquiredAt: 1_000 }
    expect(await resolveRestaurantSearchLocation(accepted, async () => { throw new Error('GPS unavailable') }, () => 31_000)).toBeNull()
    expect(await resolveRestaurantSearchLocation(accepted, async () => accepted, () => 31_000)).toBeNull()
  })

  it('does not request first-time permission for city-only search and reuses a fresh accepted fix', async () => {
    const updated = { acquiredAt: 30_000 }
    const refresh = vi.fn(async () => updated)
    expect(await resolveRestaurantSearchLocation(null, refresh, () => 31_000)).toBeNull()
    expect(await resolveRestaurantSearchLocation(updated, refresh, () => 31_000)).toEqual(updated)
    expect(refresh).not.toHaveBeenCalled()
  })
})
