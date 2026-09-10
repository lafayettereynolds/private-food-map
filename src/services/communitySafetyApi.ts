import { apiURL } from '../config/apiEnvironment'
import { localTestHeaders } from '../config/appEnvironment'
import type { UGCSafetyTarget, UGCSafetyCapabilities, ModerationReasonV1 } from '../contracts/releaseSafetyV1'

async function request<T>(path: string, method = 'GET', body?: unknown): Promise<T> {
  const response = await fetch(apiURL(path), {
    method, credentials: 'same-origin',
    headers: { Accept: 'application/json', ...localTestHeaders(), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  })
  const result = await response.json().catch(() => null)
  if (!response.ok) throw new Error(typeof result?.error === 'string' ? result.error : '安全操作未完成，请重试。')
  return result as T
}

export const browserCommunitySafety = {
  safety: (target: UGCSafetyTarget) => request<UGCSafetyCapabilities>(`/api/v1/community/safety?${new URLSearchParams({ type: target.type, id: target.id })}`),
  report: (target: UGCSafetyTarget, reason: ModerationReasonV1, details: string, requestID: string) => request('/api/v1/community/reports', 'POST', {
    apiVersion: 1, requestId: requestID, contentType: target.type, contentId: target.id, reason, details,
  }),
  block: async (target: UGCSafetyTarget) => {
    const capability = await browserCommunitySafety.safety(target)
    if (!capability.canBlock) throw new Error('不能屏蔽此用户。')
    return request(`/api/v1/community/blocks/${encodeURIComponent(capability.ownerID)}`, 'PUT')
  },
  deleteComment: async (target: UGCSafetyTarget) => {
    if (target.type !== 'comment') throw new Error('只能删除自己的评论。')
    return request(`/api/v1/community/comments/${encodeURIComponent(target.id)}`, 'DELETE')
  },
}
