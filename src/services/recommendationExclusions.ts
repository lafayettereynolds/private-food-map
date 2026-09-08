/** Only stable identities match. Names/rounded coordinates must not hide another branch. */
export function recommendationIdentityKey(id: string): string {
  return id.trim().toLowerCase()
}

export function excludeRecommendationIDs<T extends { restaurant: { id: string } }>(items: readonly T[], ids: readonly string[]): T[] {
  const excluded = new Set(ids.map(recommendationIdentityKey))
  return items.filter(item => !excluded.has(recommendationIdentityKey(item.restaurant.id)))
}

export function saveBrowserRecommendationExclusion(storage: { getItem(key: string): string | null; setItem(key: string, value: string): void }, ownerID: string, aliases: string[] = []): string[] {
  if (!ownerID.trim()) throw new Error('请先登录后再保存推荐偏好。')
  const key = `tastemap:recommendation-exclusions:v1:${encodeURIComponent(ownerID)}`
  const raw: unknown = JSON.parse(storage.getItem(key) ?? '[]')
  if (!Array.isArray(raw) || raw.some(id => typeof id !== 'string')) throw new Error('推荐偏好读取失败，请重试。')
  const ids = [...new Set([...raw, ...aliases].map(recommendationIdentityKey).filter(Boolean))].sort()
  if (aliases.length) storage.setItem(key, JSON.stringify(ids))
  return ids
}

export function expandRecommendationAliases(ids: readonly string[], groups: readonly (readonly string[])[]): string[] {
  const result = new Set(ids.map(recommendationIdentityKey))
  let previous: number
  do {
    previous = result.size
    for (const group of groups) {
      const keys = group.map(recommendationIdentityKey)
      if (keys.some(key => result.has(key))) keys.forEach(key => result.add(key))
    }
  } while (previous !== result.size)
  return [...result].filter(Boolean).sort()
}
