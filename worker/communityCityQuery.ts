/** Query-only comparison; never changes stored Restaurant.city or visibility. */
export function communityCityKey(value: string): string {
  const city = value.normalize('NFKC').trim()
  return (city.length > 2 && city.endsWith('市') ? city.slice(0, -1) : city).toLowerCase()
}

export const communityRestaurantCitySQL = `LOWER(CASE
  WHEN LENGTH(TRIM(r.city)) > 2 AND SUBSTR(TRIM(r.city), -1) = '市'
  THEN SUBSTR(TRIM(r.city), 1, LENGTH(TRIM(r.city)) - 1)
  ELSE TRIM(r.city) END)`

export interface CommunityFeedCursorScope { viewerId: string; scope: string; city: string; query?: string }

export function encodeCommunityFeedCursor(eventAt: string, id: string, snapshot: number, query: CommunityFeedCursorScope): string {
  const bytes = new TextEncoder().encode(JSON.stringify([eventAt, id, snapshot, query.viewerId, query.scope, query.city, query.query ?? '']))
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

/** Reject unbound legacy/profile cursors; refresh restarts from a new first page. */
export function decodeCommunityFeedCursor(raw: string | null, query: CommunityFeedCursorScope) {
  if (!raw) return { eventAt: '9999-12-31T23:59:59.999Z', id: '', snapshot: null as number | null }
  if (raw.length > 4096) throw new Error('Invalid community feed cursor')
  const bytes = Uint8Array.from(atob(raw.replaceAll('-', '+').replaceAll('_', '/')), (character) => character.charCodeAt(0))
  const value: unknown = JSON.parse(new TextDecoder().decode(bytes))
  if (!Array.isArray(value) || value.length !== 7 || typeof value[0] !== 'string' || !Number.isFinite(Date.parse(value[0]))
    || typeof value[1] !== 'string' || !value[1] || typeof value[2] !== 'number' || !Number.isFinite(new Date(value[2]).getTime())
    || value[3] !== query.viewerId || value[4] !== query.scope || value[5] !== query.city
    || value[6] !== (query.query ?? '')) {
    throw new Error('Invalid community feed cursor')
  }
  return { eventAt: value[0], id: value[1], snapshot: value[2] }
}
