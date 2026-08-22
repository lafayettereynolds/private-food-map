import { db } from './appDb'
import type { Friendship, SharedMeal, SharedMealParticipant, UserProfile, Visit } from '../types/domain'
import { requestCloudSync } from '../services/syncEvents'

export const CURRENT_USER_ID = 'owner'

export async function ensureCurrentUser() {
  const existing = await db.users.get(CURRENT_USER_ID)
  if (existing) return existing
  const now = new Date().toISOString()
  const user: UserProfile = {
    id: CURRENT_USER_ID,
    nickname: 'Taste Map 用户',
    email: null,
    bio: '',
    city: '',
    avatarImageData: null,
    avatarPhotoId: null,
    avatarPresetId: 'polar-bear',
    membershipTier: 'free',
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

export async function updateCurrentUserProfile(changes: Pick<UserProfile, 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId'>) {
  const current = await ensureCurrentUser()
  const updated: UserProfile = {
    ...current,
    ...changes,
    nickname: changes.nickname.trim() || 'Taste Map 用户',
    bio: changes.bio.trim(),
    city: changes.city.trim(),
    avatarImageData: current.membershipTier === 'member' ? changes.avatarImageData : null,
    avatarPhotoId: current.membershipTier === 'member' ? changes.avatarPhotoId : null,
    updatedAt: new Date().toISOString(),
    deletedAt: null,
  }
  await db.users.put(updated)
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
  await db.users.put(updated)
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
