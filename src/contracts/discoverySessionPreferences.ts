/** Ephemeral query preferences. Never write these into the long-term profile. */
export interface DiscoverySessionPreferences {
  exploration: 'familiar' | 'balanced' | 'adventurous'
  budget: { minimum: number; maximumExclusive: number | null; currency: string } | null
  occasion: 'any' | 'solo' | 'two' | 'group'
  nearby: boolean
  reference: { latitude: number; longitude: number; source: 'device_location' | 'user_selected_point' } | null
}
export const DEFAULT_DISCOVERY_SESSION_PREFERENCES: DiscoverySessionPreferences = {
  exploration: 'balanced', budget: null, occasion: 'any', nearby: false, reference: null,
}
export const DISCOVERY_EXPLORATION_PAGE_LIMIT = { familiar: 0, balanced: 4, adventurous: 8 } as const

export function normalizeDiscoverySessionPreferences(raw: unknown = {}): DiscoverySessionPreferences {
  const fail = (): never => { throw new Error('invalid_discovery_session_preferences') }
  const object = (value: unknown, keys: string[]) => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return fail()
    if (Object.keys(value).some(key => !keys.includes(key))) return fail()
    return value as Record<string, unknown>
  }
  const data = object(raw, ['exploration', 'budget', 'occasion', 'nearby', 'reference'])
  const exploration = data.exploration ?? 'balanced'
  const occasion = data.occasion ?? 'any'
  if (!['familiar', 'balanced', 'adventurous'].includes(exploration as string) || !['any', 'solo', 'two', 'group'].includes(occasion as string)) return fail()
  if (data.nearby != null && typeof data.nearby !== 'boolean') return fail()
  let budget: DiscoverySessionPreferences['budget'] = null
  if (data.budget != null) {
    const b = object(data.budget, ['minimum', 'maximumExclusive', 'currency'])
    if (typeof b.minimum !== 'number' || !Number.isFinite(b.minimum) || b.minimum < 0
      || (b.maximumExclusive !== null && (typeof b.maximumExclusive !== 'number' || !Number.isFinite(b.maximumExclusive) || b.maximumExclusive <= b.minimum))
      || typeof b.currency !== 'string' || !/^[A-Z]{3}$/.test(b.currency)) return fail()
    budget = b as unknown as NonNullable<DiscoverySessionPreferences['budget']>
  }
  let reference: DiscoverySessionPreferences['reference'] = null
  if (data.reference != null) {
    const r = object(data.reference, ['latitude', 'longitude', 'source'])
    if (typeof r.latitude !== 'number' || !Number.isFinite(r.latitude) || Math.abs(r.latitude) > 90
      || typeof r.longitude !== 'number' || !Number.isFinite(r.longitude) || Math.abs(r.longitude) > 180
      || !['device_location', 'user_selected_point'].includes(r.source as string)) return fail()
    reference = r as unknown as NonNullable<DiscoverySessionPreferences['reference']>
  }
  if (data.nearby === true && !reference) return fail()
  return { exploration: exploration as DiscoverySessionPreferences['exploration'], occasion: occasion as DiscoverySessionPreferences['occasion'], budget, nearby: data.nearby === true, reference }
}

/** A small positive tie-break contribution only; unknown data is never removed. */
export function discoverySessionPreferenceBonus(facts: {
  reliablePrice?: { value: number; currency: string } | null
  verifiedOccasions?: readonly ('solo' | 'two' | 'group')[]
  distanceMeters?: number | null
}, preferences: DiscoverySessionPreferences): number {
  let bonus = 0
  const price = facts.reliablePrice
  if (preferences.budget && price && Number.isFinite(price.value) && price.value >= 0
    && price.currency === preferences.budget.currency
    && price.value >= preferences.budget.minimum
    && (preferences.budget.maximumExclusive === null || price.value < preferences.budget.maximumExclusive)) bonus += .08
  if (preferences.occasion !== 'any' && facts.verifiedOccasions?.includes(preferences.occasion)) bonus += .05
  if (preferences.nearby && preferences.reference && facts.distanceMeters != null && Number.isFinite(facts.distanceMeters) && facts.distanceMeters >= 0) bonus += .05 / (1 + facts.distanceMeters / 1000)
  return bonus
}

/** Reorder the qualified full candidate set before assigning pagination ranks.
 * Deferred exploration is carried into subsequent pages, never duplicated. */
export function discoveryExplorationPages<T>(items: readonly T[], isExploration: (item: T) => boolean, pageSize: number, preferences: DiscoverySessionPreferences): T[][] {
  if (!Number.isSafeInteger(pageSize) || pageSize < 1) throw new Error('invalid_page_size')
  const cap = Math.min(pageSize, DISCOVERY_EXPLORATION_PAGE_LIMIT[preferences.exploration])
  let remaining = items.filter(item => cap > 0 || !isExploration(item))
  const pages: T[][] = []
  while (remaining.length) {
    let exploration = 0; let used = 0
    const page: T[] = []
    const deferred: T[] = []
    for (const item of remaining) {
      const exploratory = isExploration(item)
      if (used < pageSize && (!exploratory || exploration < cap)) {
        page.push(item); used += 1; if (exploratory) exploration += 1
      } else deferred.push(item)
    }
    remaining = deferred
    pages.push(page)
  }
  return pages
}
