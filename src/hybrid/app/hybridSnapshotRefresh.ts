import type { TasteMapHybridContentSnapshotDTO, TasteMapPlatform, TasteMapProfileDashboardViewModel } from '../../platform/TasteMapPlatform'
import { discoveryRefreshMessage } from './discoveryRefreshState'

/** Owner records and network-backed content settle independently. */
export async function refreshHybridSnapshots(
  platform: Pick<TasteMapPlatform, 'profile' | 'content'>,
  callbacks: {
    isCurrent: () => boolean
    onProfile: (profile: TasteMapProfileDashboardViewModel) => void
    onContent: (content: TasteMapHybridContentSnapshotDTO) => void
  },
  timeoutMS = 15_000,
  options: { forceRefresh?: boolean } = {},
) {
  let contentMessage: string | null = null
  const publish = <T>(request: Promise<T>, accept: (value: T) => void) =>
    boundedSnapshotRead(request, timeoutMS).then((value) => {
      if (callbacks.isCurrent()) accept(value)
    })
  const results = await Promise.allSettled([
    publish(Promise.resolve().then(() => platform.profile.getCurrent()), callbacks.onProfile),
    publish(Promise.resolve().then(() => platform.content.snapshot(options)), (content) => {
      contentMessage = discoveryRefreshMessage(content)
      callbacks.onContent(content)
    }),
  ])
  return {
    failed: results.some((result) => result.status === 'rejected') || contentMessage !== null,
    contentFailed: results[1].status === 'rejected',
    message: contentMessage,
  }
}

export function boundedSnapshotRead<T>(request: Promise<T>, timeoutMS = 15_000): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('内容刷新超时，请重试。')), timeoutMS)
    request.then(resolve, reject).finally(() => clearTimeout(timeout))
  })
}
