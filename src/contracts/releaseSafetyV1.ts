export const RELEASE_SAFETY_API_VERSION = 1 as const

export type AccountDeletionStatusV1 =
  | 'previewed'
  | 'confirmed'
  | 'deleting_data'
  | 'deleting_objects'
  | 'completed'
  | 'failed'

export interface AccountDeletionPreviewV1 {
  apiVersion: 1
  userId: string
  requiresFreshAuthentication: true
  pendingMutationCount: number
  entityCounts: Record<string, number>
  photoObjectCount: number
}

export interface AccountDeletionConfirmRequestV1 {
  apiVersion: 1
  requestId: string
  statusToken: string
  confirmation: 'DELETE'
}

export interface AccountDeletionJobV1 {
  apiVersion: 1
  jobId: string
  status: AccountDeletionStatusV1
  requestedAt: string
  updatedAt: string
  completedAt: string | null
  retryable: boolean
  errorCode: string | null
}

export type ModerationContentTypeV1 = 'visit' | 'comment' | 'user'
export type ModerationReasonV1 =
  | 'spam' | 'harassment' | 'hate' | 'sexual' | 'violence' | 'privacy' | 'other'

export interface ContentReportRequestV1 {
  apiVersion: 1
  requestId: string
  contentType: ModerationContentTypeV1
  contentId: string
  reason: ModerationReasonV1
  details?: string
}

export interface ContentReportResponseV1 {
  apiVersion: 1
  reportId: string
  status: 'pending'
  duplicate: boolean
}

export interface UserBlockMutationV1 {
  apiVersion: 1
  blockedUserId: string
  blocked: boolean
  duplicate: boolean
}
