import { expandRecommendationAliases, recommendationIdentityKey } from './recommendationExclusions'

export type RecommendationContext = 'everyday_fast_food' | 'snack_takeaway'
export type RecommendationBrand = 'kfc' | 'mcdonalds' | 'juewei'
export interface RecommendationIntentFeedback {
  brandIDs: string[]
  contextCounts: Partial<Record<RecommendationContext, number>>
}
export interface RecommendationIntentMetadata { name: string; tags: readonly string[] }
export interface RecommendationIntentEntry {
  aliases: string[]
  brandID: RecommendationBrand | null
  context: RecommendationContext | null
}
export interface RecommendationPreferences {
  ownerID: string | null
  excludedIDs: string[]
  /** Optional for older Native hosts. A missing value never fabricates learning. */
  intentFeedback?: RecommendationIntentFeedback
}

const normalize = (value: string) => value.normalize('NFKC').toLowerCase().trim().replace(/’/g, "'")
const brands: readonly [RecommendationBrand, RegExp, RecommendationContext][] = [
  ['kfc', /^(?:肯德基|kfc)(?=$|[\s()·-])/, 'everyday_fast_food'],
  ['mcdonalds', /^(?:麦当劳|mcdonald'?s)(?=$|[\s()·-])/, 'everyday_fast_food'],
  ['juewei', /^绝味鸭脖(?=$|[\s()·-])/, 'snack_takeaway'],
]

/** Dining intent, not cuisine affinity. Unknown names, ordinary 小吃/快餐 tags,
 * low prices and locations are deliberately insufficient classification evidence. */
export function recommendationIntent(metadata: RecommendationIntentMetadata) {
  const name = normalize(metadata.name)
  for (const [brandID, pattern, context] of brands) if (pattern.test(name)) return { brandID, context }
  const tags = new Set(metadata.tags.map(normalize))
  const fast = tags.has('everyday_fast_food') || tags.has('日常快餐')
  const snack = tags.has('snack_takeaway') || tags.has('小吃外带')
  return { brandID: null, context: fast !== snack ? fast ? 'everyday_fast_food' : 'snack_takeaway' : null } as const
}

export function mergeRecommendationIntentEntries(entries: readonly RecommendationIntentEntry[], groups: readonly (readonly string[])[]) {
  const merged: RecommendationIntentEntry[] = []
  for (const entry of entries) {
    const aliases = expandRecommendationAliases(entry.aliases, [...groups, ...entries.map(value => value.aliases)])
    if (!aliases.length || merged.some(value => value.aliases.some(id => aliases.includes(id)))) continue
    merged.push({ ...entry, aliases })
  }
  return merged
}

export function summarizeRecommendationIntent(entries: readonly RecommendationIntentEntry[]): RecommendationIntentFeedback {
  const brandIDs = new Set<string>()
  const contextCounts: RecommendationIntentFeedback['contextCounts'] = {}
  for (const entry of entries) {
    if (entry.brandID) brandIDs.add(entry.brandID)
    if (entry.context) contextCounts[entry.context] = (contextCounts[entry.context] ?? 0) + 1
  }
  return { brandIDs: [...brandIDs].sort(), contextCounts }
}

export function recommendationIsDismissed(restaurant: RecommendationIntentMetadata & { id: string }, preferences: Pick<RecommendationPreferences, 'excludedIDs' | 'intentFeedback'>) {
  if (preferences.excludedIDs.includes(recommendationIdentityKey(restaurant.id))) return true
  const { brandID } = recommendationIntent(restaurant)
  return Boolean(brandID && preferences.intentFeedback?.brandIDs.includes(brandID))
}

/** Applies only to the canonical For You snapshot (also projected to Map).
 * Two distinct dismissed restaurants provide a weak scene signal. Preserve all
 * non-brand candidates, public scores, reasons and taste/probability values. */
export function applyRecommendationIntent<T extends { restaurant: RecommendationIntentMetadata & { id: string }; rank: number }>(
  items: readonly T[], preferences: Pick<RecommendationPreferences, 'excludedIDs' | 'intentFeedback'>,
): T[] {
  const penalty = (item: T) => {
    const context = recommendationIntent(item.restaurant).context
    return context && (preferences.intentFeedback?.contextCounts[context] ?? 0) >= 2 ? 1 : 0
  }
  const retained = items.filter(item => !recommendationIsDismissed(item.restaurant, preferences))
  // Re-rank copies only when scene feedback actually changes order. These ranks
  // are presentation order, not new ratings or calibrated likelihood values.
  const ranked = retained.map((item, index) => ({ item, index }))
    .sort((a, b) => penalty(a.item) - penalty(b.item) || a.item.rank - b.item.rank || a.index - b.index)
  const changed = ranked.some((value, index) => value.item !== retained[index])
  return ranked.map(({ item }, index) => changed ? { ...item, rank: index + 1 } : item)
}

/** One atomic owner-scoped v2 record. Legacy v1 exclusions are retained but never
 * turned into inferred feedback after the fact. No Restaurant/Visit is mutated. */
export function browserRecommendationPreferences(
  storage: { getItem(key: string): string | null; setItem(key: string, value: string): void }, ownerID: string,
  groups: readonly (readonly string[])[], adding?: { aliases: string[]; metadata: RecommendationIntentMetadata },
): RecommendationPreferences {
  if (!ownerID.trim()) throw new Error('请先登录后再保存推荐偏好。')
  const prefix = `tastemap:recommendation-exclusions:`
  const suffix = encodeURIComponent(ownerID)
  const legacy: unknown = JSON.parse(storage.getItem(`${prefix}v1:${suffix}`) ?? '[]')
  const raw: unknown = JSON.parse(storage.getItem(`${prefix}v2:${suffix}`) ?? '{"excludedIDs":[],"entries":[]}')
  const strings = (value: unknown): value is string[] => Array.isArray(value) && value.every(id => typeof id === 'string')
  if (!strings(legacy) || !raw || typeof raw !== 'object' || !('excludedIDs' in raw) || !strings(raw.excludedIDs)
    || !('entries' in raw) || !Array.isArray(raw.entries) || !raw.entries.every(validEntry)) throw new Error('推荐偏好读取失败，请重试。')
  const entries = [...raw.entries] as RecommendationIntentEntry[]
  const priorExclusions = new Set(expandRecommendationAliases([...legacy, ...raw.excludedIDs], groups))
  if (adding && !expandRecommendationAliases(adding.aliases, groups).some(id => priorExclusions.has(id))) {
    entries.push({ aliases: adding.aliases, ...recommendationIntent(adding.metadata) })
  }
  const merged = mergeRecommendationIntentEntries(entries, groups)
  const excludedIDs = expandRecommendationAliases([...legacy, ...raw.excludedIDs, ...(adding?.aliases ?? [])], groups)
  if (adding || JSON.stringify(merged) !== JSON.stringify(raw.entries) || JSON.stringify(excludedIDs) !== JSON.stringify(raw.excludedIDs)) {
    storage.setItem(`${prefix}v2:${suffix}`, JSON.stringify({ excludedIDs, entries: merged }))
  }
  return { ownerID, excludedIDs, intentFeedback: summarizeRecommendationIntent(merged) }
}

function validEntry(value: unknown): value is RecommendationIntentEntry {
  if (!value || typeof value !== 'object') return false
  const entry = value as RecommendationIntentEntry
  return Array.isArray(entry.aliases) && entry.aliases.every(id => typeof id === 'string')
    && (entry.brandID === null || brands.some(([brand]) => brand === entry.brandID))
    && (entry.context === null || entry.context === 'everyday_fast_food' || entry.context === 'snack_takeaway')
}
