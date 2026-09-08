import { apiURL } from '../config/apiEnvironment'
import { localTestHeaders } from '../config/appEnvironment'
import { TasteMapPlatformError } from '../platform/TasteMapPlatform'
import type { UserProfile } from '../types/domain'

export interface PublicListPage {
  apiVersion: 1
  list: {
    id: string; title: string; description: string; visibility: 'private' | 'friends' | 'public'
    isRanked: boolean; restaurantCount: number; updatedAt: string
    owner: { userId: string; displayName: string; avatarPresetId: UserProfile['avatarPresetId'] }
  }
  items: Array<{
    id: string; position: number; note: string
    restaurant: {
      globalKey: string; restaurantId: string; name: string; address: string; city: string
      latitude: number; longitude: number; markerEmoji: string
      markerPhotoId?: string | null; merchantImageUrl?: string | null
    }
  }>
  nextCursor: string | null
  generatedAt: string
}

/** Existing authenticated API boundary, never a client-supplied owner identity. */
export async function requestRestaurantListAPI<T>(path: string, body?: unknown, options: { signal?: AbortSignal; headers?: Record<string, string> } = {}): Promise<T> {
  const response = await fetch(apiURL(path), {
    method: body === undefined ? 'GET' : 'POST', credentials: 'same-origin',
    signal: options.signal,
    headers: { Accept: 'application/json', ...localTestHeaders(), ...options.headers, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  })
  const value = await response.json().catch(() => null)
  if (!response.ok) throw new TasteMapPlatformError(
    typeof value?.error === 'string' ? value.error : '食单服务暂时不可用。',
    [401, 403, 404].includes(response.status) ? 'list_unavailable' : 'list_request_failed', true,
  )
  return value as T
}
