import { db } from './appDb'
import type { DiningCompanion } from '../types/domain'

export async function ensureDiningCompanions(names: string[]) {
  const normalized = [...new Set(names.map((name) => name.trim()).filter(Boolean))]
  if (!normalized.length) return []
  const existing = await db.diningCompanions.where('ownerUserId').equals('owner').filter((item) => !item.deletedAt).toArray()
  const byName = new Map(existing.map((item) => [normalize(item.displayName), item]))
  const now = new Date().toISOString()
  const created: DiningCompanion[] = []
  normalized.forEach((displayName) => {
    if (byName.has(normalize(displayName))) return
    const companion: DiningCompanion = {
      id: createCompanionId(displayName),
      ownerUserId: 'owner',
      displayName,
      linkedUserId: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    }
    byName.set(normalize(displayName), companion)
    created.push(companion)
  })
  if (created.length) await db.diningCompanions.bulkPut(created)
  return normalized.map((name) => byName.get(normalize(name)) as DiningCompanion)
}

export function createCompanionId(name: string) {
  return `companion:owner:${encodeURIComponent(normalize(name))}`
}

function normalize(value: string) {
  return value.trim().toLocaleLowerCase('zh-CN')
}
