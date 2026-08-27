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

export async function updateDiningCompanionProfile(companion: DiningCompanion, ownerUserId: string, input: {
  displayName: string
  privateAvatarData: string | null
  relationshipLabel: string | null
}) {
  if (companion.ownerUserId !== ownerUserId) throw new Error('只能修改自己的饭搭子')
  const displayName = input.displayName.trim()
  if (!displayName) throw new Error('饭搭子名字不能为空')
  const now = new Date().toISOString()
  const existing = await db.diningCompanions.get(companion.id)
  const updated: DiningCompanion = {
    ...(existing ?? companion),
    ownerUserId,
    displayName,
    privateAvatarData: input.privateAvatarData,
    relationshipLabel: input.relationshipLabel?.trim() || null,
    createdAt: existing?.createdAt || companion.createdAt || now,
    updatedAt: now,
    deletedAt: null,
  }
  await db.transaction('rw', db.diningCompanions, db.visits, async () => {
    await db.diningCompanions.put(updated)
    if (displayName !== companion.displayName) {
      const oldName = normalize(companion.displayName)
      const relatedVisits = await db.visits.where('userId').equals(ownerUserId).filter((visit) => !visit.deletedAt && (
        visit.companionIds.includes(companion.id) || visit.companions.some((name) => normalize(name) === oldName)
      )).toArray()
      await Promise.all(relatedVisits.map((visit) => db.visits.put({
        ...visit,
        companionIds: visit.companionIds.includes(companion.id) ? visit.companionIds : [...visit.companionIds, companion.id],
        companions: visit.companions.map((name) => normalize(name) === oldName ? displayName : name),
        updatedAt: now,
      })))
    }
  })
  return updated
}

function normalize(value: string) {
  return value.trim().toLocaleLowerCase('zh-CN')
}
