import { db } from './appDb'
import { IS_DEVELOPMENT, LOCAL_TEST_ACCOUNT, LOCAL_TEST_VIEWER_ID } from '../config/appEnvironment'
import type { Friendship, MembershipTier, SharedMeal, SharedMealParticipant, UserProfile, Visit } from '../types/domain'
import { requestCloudSync } from '../services/syncEvents'
import { syncQueueId } from '../types/sync'

export const CURRENT_USER_ID = LOCAL_TEST_VIEWER_ID

export async function ensureCurrentUser() {
  const existing = await db.users.get(CURRENT_USER_ID)
  const expectedTier: MembershipTier = IS_DEVELOPMENT && LOCAL_TEST_ACCOUNT === 'premium' ? 'member' : 'free'
  if (existing) {
    if (IS_DEVELOPMENT && existing.membershipTier !== expectedTier) {
      const updated = { ...existing, membershipTier: expectedTier, updatedAt: new Date().toISOString() }
      await db.users.put(updated)
    await synchronizeFootprintVisibility(updated)
      return updated
    }
    return existing
  }
  const now = new Date().toISOString()
  const user: UserProfile = {
    id: CURRENT_USER_ID,
    nickname: LOCAL_TEST_ACCOUNT === 'free' ? '非会员测试账号' : 'Taste Map 用户',
    email: null,
    bio: LOCAL_TEST_ACCOUNT === 'free' ? '喜欢日料、火锅和安静的小店。' : '',
    city: LOCAL_TEST_ACCOUNT === 'free' ? '杭州市' : '',
    avatarImageData: null,
    avatarPhotoId: null,
    avatarPresetId: 'polar-bear',
    membershipTier: expectedTier,
    mapSharingEnabled: false,
    mapVisibility: 'private',
    authProvider: 'local',
    authSubject: null,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  }
  await db.users.put(user)
  return user
}

export async function synchronizeFootprintVisibility(user: UserProfile) {
  const visibility = user.mapSharingEnabled ? user.mapVisibility : 'private'
  const visits = await db.visits.filter(visit => !visit.deletedAt && (visit.userId === user.id || visit.userId === 'owner')).toArray()
  for (const visit of visits) {
    if (visit.visibility === visibility) continue
    const updatedAt = new Date().toISOString()
    await db.visits.update(visit.id, { visibility, updatedAt })
    await db.syncQueue.put({ id: syncQueueId('visit', visit.id), entityType: 'visit', entityId: visit.id, updatedAt })
  }
  const visitIDs = new Set(visits.map(visit => visit.id))
  const photos = await db.photos.filter(photo => !photo.deletedAt && (photo.userId === user.id || photo.userId === 'owner') && photo.visitId != null && visitIDs.has(photo.visitId)).toArray()
  for (const photo of photos) {
    if (photo.visibility === visibility) continue
    const updatedAt = new Date().toISOString()
    await db.photos.update(photo.id, { visibility, updatedAt })
  }

}

export async function updateCurrentUserProfile(changes: Pick<UserProfile, 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId'> & Partial<Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>>) {
  const current = await ensureCurrentUser()
  const updated: UserProfile = {
    ...current,
    ...changes,
    nickname: changes.nickname.trim() || 'Taste Map 用户',
    bio: changes.bio.trim(),
    city: changes.city.trim(),
    avatarImageData: current.membershipTier === 'member' ? changes.avatarImageData : current.avatarImageData,
    avatarPhotoId: current.membershipTier === 'member' ? changes.avatarPhotoId : current.avatarPhotoId,
    mapVisibility: changes.mapSharingEnabled === false ? 'private' : (changes.mapVisibility ?? current.mapVisibility),
    updatedAt: new Date().toISOString(),
    deletedAt: null,
  }
  await db.transaction('rw', db.users, db.visits, db.photos, db.syncQueue, async () => {
    await db.users.put(updated)
    await synchronizeFootprintVisibility(updated)
    await db.syncQueue.put({ id: syncQueueId('user', updated.id), entityType: 'user', entityId: updated.id, updatedAt: updated.updatedAt })
  })
  requestCloudSync()
  return updated
}

export async function updateCurrentUserMapPrivacy(changes: Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>) {
  const current = await ensureCurrentUser()
  const updated: UserProfile = {
    ...current,
    ...changes,
    mapVisibility: changes.mapSharingEnabled ? changes.mapVisibility : 'private',
    updatedAt: new Date().toISOString(),
    deletedAt: null,
  }
  await db.transaction('rw', db.users, db.visits, db.photos, db.syncQueue, async () => {
    await db.users.put(updated)
    await synchronizeFootprintVisibility(updated)
    await db.syncQueue.put({ id: syncQueueId('user', updated.id), entityType: 'user', entityId: updated.id, updatedAt: updated.updatedAt })
  })
  requestCloudSync()
  return updated
}

export async function createSharedMealInvitations(visit: Visit, participantUserIds: string[]) {
  const participants = [...new Set(participantUserIds.filter((id) => id && id !== visit.userId))]
  if (!participants.length) return null
  const now = new Date().toISOString()
  const mealId = createId()
  const meal: SharedMeal = {
    id: mealId,
    restaurantId: visit.restaurantId,
    createdByUserId: visit.userId,
    occurredAt: visit.visitedAt,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  }
  const rows: SharedMealParticipant[] = [
    {
      id: `${mealId}:${visit.userId}`,
      sharedMealId: mealId,
      userId: visit.userId,
      visitId: visit.id,
      status: 'accepted',
      createdAt: now,
      updatedAt: now,
    },
    ...participants.map((userId) => ({
      id: `${mealId}:${userId}`,
      sharedMealId: mealId,
      userId,
      visitId: null,
      status: 'pending' as const,
      createdAt: now,
      updatedAt: now,
    })),
  ]
  await db.transaction('rw', db.visits, db.sharedMeals, db.sharedMealParticipants, async () => {
    await db.sharedMeals.put(meal)
    await db.sharedMealParticipants.bulkPut(rows)
    await db.visits.update(visit.id, { sharedMealId: mealId, updatedAt: now })
  })
  requestCloudSync()
  return meal
}

export async function setSharedMealInvitationStatus(participantId: string, status: SharedMealParticipant['status'], visitId: string | null = null) {
  const now = new Date().toISOString()
  await db.transaction('rw', db.sharedMealParticipants, db.visits, async () => {
    const participant = await db.sharedMealParticipants.get(participantId)
    if (!participant) return
    await db.sharedMealParticipants.update(participantId, { status, visitId, updatedAt: now })
    if (visitId && status === 'accepted') {
      await db.visits.update(visitId, { sharedMealId: participant.sharedMealId, updatedAt: now })
    }
  })
  requestCloudSync()
}

export async function upsertFriendship(friendship: Friendship) {
  await db.friendships.put(friendship)
  requestCloudSync()
}

function createId() {
  return 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`
}
