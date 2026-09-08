/** Private, append-only sync. These are exclusion facts, not a replaceable
 * snapshot or public recommendation telemetry. Pulling/acknowledging an event
 * never creates a second intent vote. No restore/undismiss operation in V1. */
export const RECOMMENDATION_PREFERENCES_API_VERSION = 1 as const
export const RECOMMENDATION_PREFERENCES_MAX_EVENTS = 100
export const RECOMMENDATION_PREFERENCES_MAX_ALIASES = 32
export const RECOMMENDATION_PREFERENCES_MAX_BODY_BYTES = 131_072

export type RecommendationPreferenceEventSourceV1 = 'explicit_dismissal' | 'legacy_exclusion' | 'legacy_intent'
export interface RecommendationPreferenceIntentV1 {
  classifierVersion: 1
  brandID: 'kfc' | 'mcdonalds' | 'juewei' | null
  context: 'everyday_fast_food' | 'snack_takeaway' | null
}
export interface RecommendationPreferenceEventV1 {
  /** Generated and persisted once before sending; retries retain this ID. */
  eventID: string
  /** Only trusted stable local/provider/global IDs, never names/rounded locations.
   * Opaque local IDs remain unresolved until an authoritative alias is known. */
  aliases: string[]
  source: RecommendationPreferenceEventSourceV1
  /** Client history only, never conflict ordering. Unknown legacy time is null. */
  occurredAt: string | null
  intent: RecommendationPreferenceIntentV1 | null
}
export interface RecommendationPreferenceStoredEventV1 extends RecommendationPreferenceEventV1 {
  revision: number
  receivedAt: string
}
export interface RecommendationPreferencesPushRequestV1 {
  apiVersion: 1
  events: RecommendationPreferenceEventV1[]
}
export interface RecommendationPreferencesPushResponseV1 {
  apiVersion: 1
  ownerID: string
  /** Ack only these event IDs. This is not a pull checkpoint. */
  receipts: Array<{ eventID: string; revision: number }>
}
export interface RecommendationPreferencesPullResponseV1 {
  apiVersion: 1
  ownerID: string
  events: RecommendationPreferenceStoredEventV1[]
  /** Owner-bound opaque checkpoint, valid even on an empty page. Save only in
   * the transaction that merges this page with local AND pending events. */
  cursor: string
  hasMore: boolean
}

export class RecommendationPreferenceValidationError extends Error {
  constructor(readonly field: string) {
    super(`Invalid recommendation preference: ${field}`)
    this.name = 'RecommendationPreferenceValidationError'
  }
}
const fail = (field: string): never => { throw new RecommendationPreferenceValidationError(field) }
function record(value: unknown, keys: readonly string[], field: string): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fail(field)
  if (Object.keys(value).some(key => !keys.includes(key))) return fail(field)
  return value as Record<string, unknown>
}

/** Deterministic canonical representation is also the idempotency payload.
 * Legacy exact exclusions cannot acquire retroactive learning or timestamps. */
export function normalizeRecommendationPreferenceEventV1(value: unknown): RecommendationPreferenceEventV1 {
  const raw = record(value, ['eventID', 'aliases', 'source', 'occurredAt', 'intent'], 'event')
  if (typeof raw.eventID !== 'string' || !/^[A-Za-z0-9:_-]{1,128}$/.test(raw.eventID)) return fail('eventID')
  if (!Array.isArray(raw.aliases) || !raw.aliases.length || raw.aliases.length > RECOMMENDATION_PREFERENCES_MAX_ALIASES) return fail('aliases')
  const aliases = [...new Set(raw.aliases.map((id: unknown) => {
    if (typeof id !== 'string' || id.length > 256 || !id.trim() || /\s|[\u0000-\u001f\u007f]/u.test(id.trim())) return fail('aliases')
    return id.trim().toLowerCase()
  }))].sort()
  if (raw.source !== 'explicit_dismissal' && raw.source !== 'legacy_exclusion' && raw.source !== 'legacy_intent') return fail('source')
  let occurredAt: string | null = null
  if (raw.occurredAt !== null) {
    if (typeof raw.occurredAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(raw.occurredAt)
      || !Number.isFinite(Date.parse(raw.occurredAt))) return fail('occurredAt')
    occurredAt = new Date(raw.occurredAt).toISOString()
    if (occurredAt.slice(0, 19) !== raw.occurredAt.slice(0, 19)) return fail('occurredAt')
  }
  if (raw.source === 'explicit_dismissal' && !occurredAt) return fail('occurredAt')
  if (raw.source === 'legacy_exclusion' && (raw.intent !== null || occurredAt !== null)) return fail('legacy_exclusion')
  let intent: RecommendationPreferenceIntentV1 | null = null
  if (raw.intent !== null) {
    const item = record(raw.intent, ['classifierVersion', 'brandID', 'context'], 'intent')
    if (item.classifierVersion !== 1) return fail('intent.classifierVersion')
    if (item.brandID !== null && item.brandID !== 'kfc' && item.brandID !== 'mcdonalds' && item.brandID !== 'juewei') return fail('intent.brandID')
    if (item.context !== null && item.context !== 'everyday_fast_food' && item.context !== 'snack_takeaway') return fail('intent.context')
    if (item.brandID && item.context !== (item.brandID === 'juewei' ? 'snack_takeaway' : 'everyday_fast_food')) return fail('intent.context')
    intent = { classifierVersion: 1, brandID: item.brandID, context: item.context }
  }
  if (raw.source === 'legacy_intent' && !intent) return fail('intent')
  return { eventID: raw.eventID, aliases, source: raw.source, occurredAt, intent }
}

export function normalizeRecommendationPreferencesPushV1(value: unknown): RecommendationPreferencesPushRequestV1 {
  const raw = record(value, ['apiVersion', 'events'], 'request')
  if (raw.apiVersion !== 1) return fail('apiVersion')
  if (!Array.isArray(raw.events) || !raw.events.length || raw.events.length > RECOMMENDATION_PREFERENCES_MAX_EVENTS) return fail('events')
  const events = raw.events.map(normalizeRecommendationPreferenceEventV1)
  if (new Set(events.map(event => event.eventID)).size !== events.length) return fail('events.duplicateID')
  return { apiVersion: 1, events }
}
