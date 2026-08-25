import { db } from './appDb'
import type { RestaurantListCollection, RestaurantListItem, Visibility } from '../types/domain'
import { enqueueSyncOperation } from '../services/syncQueue'
import { requestCloudSync } from '../services/syncEvents'

export interface RestaurantListInput {
  title: string
  description?: string
  visibility?: Visibility
  isRanked?: boolean
  coverMode?: RestaurantListCollection['coverMode']
  customCoverImageData?: string | null
  customCoverPhotoId?: string | null
}

export async function createRestaurantList(input: RestaurantListInput) {
  const now = new Date().toISOString()
  const item: RestaurantListCollection = {
    id: crypto.randomUUID(), userId: 'owner', title: input.title.trim(), description: input.description?.trim() ?? '',
    visibility: input.visibility ?? 'private', isRanked: input.isRanked ?? false, coverMode: input.coverMode ?? 'automatic',
    customCoverImageData: input.customCoverImageData ?? null, customCoverPhotoId: input.customCoverPhotoId ?? null,
    createdAt: now, updatedAt: now, deletedAt: null,
  }
  if (!item.title) throw new Error('食单名称不能为空。')
  await db.restaurantLists.put(item)
  await enqueueSyncOperation('restaurantList', item.id, now)
  requestCloudSync()
  return item
}

export async function updateRestaurantList(id: string, changes: Partial<RestaurantListInput>) {
  const current = await db.restaurantLists.get(id)
  if (!current || current.deletedAt) throw new Error('没有找到这个食单。')
  const updatedAt = new Date().toISOString()
  const updated: RestaurantListCollection = {
    ...current,
    ...(changes.title !== undefined ? { title: changes.title.trim() } : {}),
    ...(changes.description !== undefined ? { description: changes.description.trim() } : {}),
    ...(changes.visibility !== undefined ? { visibility: changes.visibility } : {}),
    ...(changes.isRanked !== undefined ? { isRanked: changes.isRanked } : {}),
    ...(changes.coverMode !== undefined ? { coverMode: changes.coverMode } : {}),
    ...(changes.customCoverImageData !== undefined ? { customCoverImageData: changes.customCoverImageData } : {}),
    ...(changes.customCoverPhotoId !== undefined ? { customCoverPhotoId: changes.customCoverPhotoId } : {}),
    updatedAt,
  }
  if (!updated.title) throw new Error('食单名称不能为空。')
  await db.restaurantLists.put(updated)
  await enqueueSyncOperation('restaurantList', id, updatedAt)
  requestCloudSync()
  return updated
}

export async function deleteRestaurantList(id: string) {
  const now = new Date().toISOString()
  const list = await db.restaurantLists.get(id)
  if (!list) return
  const items = await db.restaurantListItems.where('listId').equals(id).toArray()
  await db.transaction('rw', [db.restaurantLists, db.restaurantListItems, db.syncQueue], async () => {
    await db.restaurantLists.put({ ...list, deletedAt: now, updatedAt: now })
    for (const item of items) {
      await db.restaurantListItems.put({ ...item, deletedAt: now, updatedAt: now })
      await enqueueSyncOperation('restaurantListItem', item.id, now, 'delete')
    }
    await enqueueSyncOperation('restaurantList', id, now, 'delete')
  })
  requestCloudSync()
}

export async function addRestaurantToList(listId: string, restaurantId: string, note = '') {
  const activeItems = (await db.restaurantListItems.where('listId').equals(listId).toArray()).filter((item) => !item.deletedAt)
  const duplicate = activeItems.find((item) => item.restaurantId === restaurantId)
  if (duplicate) return duplicate
  const now = new Date().toISOString()
  const item: RestaurantListItem = {
    id: crypto.randomUUID(), listId, restaurantId, position: activeItems.reduce((max, value) => Math.max(max, value.position), -1) + 1,
    note: note.trim(), createdAt: now, updatedAt: now, deletedAt: null,
  }
  await db.restaurantListItems.put(item)
  await enqueueSyncOperation('restaurantListItem', item.id, now)
  requestCloudSync()
  return item
}

export async function removeRestaurantFromList(itemId: string) {
  const item = await db.restaurantListItems.get(itemId)
  if (!item || item.deletedAt) return
  const now = new Date().toISOString()
  await db.restaurantListItems.put({ ...item, deletedAt: now, updatedAt: now })
  await enqueueSyncOperation('restaurantListItem', item.id, now, 'delete')
  requestCloudSync()
}

export async function updateRestaurantListItem(itemId: string, changes: Pick<Partial<RestaurantListItem>, 'note' | 'position'>) {
  const item = await db.restaurantListItems.get(itemId)
  if (!item || item.deletedAt) throw new Error('没有找到这条食单记录。')
  const updatedAt = new Date().toISOString()
  const updated = { ...item, ...changes, note: changes.note?.trim() ?? item.note, updatedAt }
  await db.restaurantListItems.put(updated)
  await enqueueSyncOperation('restaurantListItem', item.id, updatedAt)
  requestCloudSync()
  return updated
}

export async function reorderRestaurantListItems(listId: string, orderedIds: string[]) {
  const now = new Date().toISOString()
  const items = await db.restaurantListItems.where('listId').equals(listId).toArray()
  const byId = new Map(items.map((item) => [item.id, item]))
  await db.transaction('rw', [db.restaurantListItems, db.syncQueue], async () => {
    for (const [position, id] of orderedIds.entries()) {
      const item = byId.get(id)
      if (!item || item.deletedAt) continue
      await db.restaurantListItems.put({ ...item, position, updatedAt: now })
      await enqueueSyncOperation('restaurantListItem', id, now)
    }
  })
  requestCloudSync()
}
