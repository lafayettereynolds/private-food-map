import type { TasteMapHybridContentSnapshotDTO } from '../../platform/TasteMapPlatform'

const labels = { for_you: '为你推荐', similar_taste: '同味之选', trending: '趋势' } as const

/** A successful local snapshot can still contain a failed remote refresh.
 * Legacy payloads omit metadata; absence never proves remote freshness. */
export function discoveryRefreshMessage(content: TasteMapHybridContentSnapshotDTO): string | null {
  const statuses = content.discovery?.refreshStatus
  if (!statuses) return null
  const messages = Object.entries(labels).flatMap(([key, label]) => {
    const status = statuses[key as keyof typeof labels]
    if (!status?.issue || status.state === 'restricted') return []
    const suffix = status.state === 'cached' ? '正在显示上次缓存。' : ''
    return [`${label}：${status.issue.message}${suffix}`]
  })
  if (!messages.length) return null
  return messages.length === 1 ? messages[0] : '部分发现内容暂未更新，已保留可用缓存，请稍后重试。'
}
